# Linux Bluetooth Troubleshooting Guide

This repository contains documentation and tools for diagnosing and fixing common Bluetooth adapter issues on Linux (such as Arch Linux, Manjaro, or Debian/Ubuntu). 

---

## Unified Diagnostic Flow

When Bluetooth is not working (e.g., your mouse connects but doesn't move, or the Bluetooth controller cannot be turned on), follow these steps to identify your adapter and find the right fix:

### Step 1: Identify your Bluetooth Controller (USB ID)
Run the following command to find your Bluetooth USB interface:
```bash
lsusb | grep -i -E "blue|wireless|bt"
```
*   **If you see `MediaTek Inc.` (e.g., ID `0e8d:7902`):** Go to [Case 2: MediaTek MT7902 (rfkill Soft-Block)](#case-2-mediatek-mt7902-rfkill-soft-block).
*   **If you see `Qualcomm` or `Atheros` (e.g., ID `13d3:3503`):** Go to [Case 1: Qualcomm QCA9377 (BLE Connection Bug)](#case-1-qualcomm-qca9377-ble-connection-bug).

### Step 2: Check Adapter Status and Kernel Logs
Run these diagnostic commands to see how the adapter is behaving:
```bash
# Check if blocked by the OS
rfkill list

# Check the system service status
systemctl status bluetooth

# Inspect Bluetooth kernel logs for general issues
sudo dmesg | grep -i -E "blue|hci0|btusb|btqca" | tail -n 30

# Inspect the system journal specifically for Bluetooth daemon errors
sudo journalctl -b -u bluetooth | grep -i -E "error|fail|unlikely" | tail -n 20
```

---

## Case 1: Qualcomm QCA9377 (BLE Connection Bug)

### 1. Symptoms
* Your Bluetooth mouse (e.g., Logitech MX Master 2S, which utilizes BLE exclusively) successfully pairs and connects, but the pointer does not move. After a short period, the connection drops.
* Kernel logs (`dmesg`) spam the following error every ~16 seconds:
  ```
  Bluetooth: hci0: unexpected event for opcode 0x2005
  ```
  *(Opcode `0x2005` corresponds to `LE Set Scan Parameters`, indicating BLE scanning is broken at the hardware/HCI level).*

### 2. How to Identify
* Run `lsusb` and look for Qualcomm Atheros (typically ID `13d3:3503` or similar OEM variants).
* Run `sudo dmesg | grep -i btqca`. If no output is returned, **no Qualcomm firmware initialization ever occurred**, and the driver is loaded as generic class-matched Bluetooth.

### 3. Root Cause
The QCA9377 adapter binds to the generic `btusb` driver via class matching (as a generic USB Bluetooth device) rather than as a named Qualcomm device because these specific OEM USB IDs are missing from the driver's hardcoded QCA Rome whitelist. 
Without this whitelist mapping, `btusb` never triggers the `btqca` firmware loader. The device operates on its raw, buggy ROM firmware which crashes during BLE scanning.

> **Note on Standard Fixes:** Dynamically registering the ID with `new_id` (`echo "13d3 3503..." > .../new_id`) fails because the USB dynamic ID sysfs handler cannot parse private configuration structures, and the Qualcomm Rome entry table is private in `btusb.c`.

### 4. How to Recover: Surgical Binary Patching
Since we cannot dynamically inject the ID, we **binary-patch the active `btusb.ko` module** to replace an unused Qualcomm Rome device ID with your card's device ID.

The provided script `patch-btusb.sh` automates this entire process:
1. Locates the active kernel's `btusb.ko.zst` file.
2. Creates a secure backup (`btusb.ko.zst.bak`).
3. Decompresses the module, uses Python to do an in-place binary search-and-replace for QCA Rome reference ID candidates, and writes the patched binary.
4. Strips the signature block using `strip --strip-debug` so the kernel loads the unsigned patched module (bypassing signature mismatch).
5. Compresses the module back and overwrites the system driver.
6. Reloads the driver to immediately apply the fix.

#### Execution
Configure your target VID and PID in `patch-btusb.sh` if they differ from the QCA9377 default (`13d3:3503`), then run:
```bash
chmod +x patch-btusb.sh
sudo ./patch-btusb.sh
```

---

## Case 2: MediaTek MT7902 (rfkill Soft-Block)

### 1. Symptoms
* The system Bluetooth service fails to start, or fails to power on your controller.
* System logs (`journalctl`) show:
  ```
  bluetoothd: Failed to set default system config for hci0
  bluetoothd: Failed to set mode: Failed (0x03)
  ```
* You cannot discover or connect to any Bluetooth devices.

### 2. How to Identify
* Run `lsusb` and look for MediaTek (typically ID `0e8d:7902` Wireless_Device).
* Inspect `dmesg` to verify firmware initialized properly:
  ```
  Bluetooth: hci0: HW/SW Version: 0x008a008a, Build Time: 20250826211444
  Bluetooth: hci0: Device setup in 204496 usecs
  ```
  If firmware logs are present, the driver and card are fully functional.

### 3. Root Cause
The MediaTek MT7902 Bluetooth card is natively supported by modern Linux kernels and handles firmware setup correctly. However, the system's software/hardware RF switch (`rfkill`) has **soft-blocked** the adapter, causing the system service `bluetoothd` to log `Failed (0x03)` when trying to change its power state.

### 4. How to Recover: rfkill Unblocking
No binary patching or custom drivers are required. You only need to clear the soft-block.

#### Execution
1. Check the block status of your adapter:
   ```bash
   rfkill list
   ```
   If `hci0: Bluetooth` shows `Soft blocked: yes`, proceed.
2. Unblock the Bluetooth subsystem:
   ```bash
   sudo rfkill unblock bluetooth
   ```
3. Restart or re-trigger the Bluetooth daemon:
   ```bash
   sudo systemctl restart bluetooth
   ```
4. Confirm `rfkill list` now shows `Soft blocked: no` and that you can scan/connect to devices.

---

## Case 3: Bluetooth LE (GATT) Connection/Reconnection Failure

### 1. Symptoms
* A Bluetooth Low Energy (BLE) device (such as a modern BLE mouse or keyboard) successfully connects, but the **cursor/pointer does not move** and the keyboard inputs are not registered.
* Within 10 to 30 seconds, the device **automatically disconnects** and disappears from the paired devices list.
* **Side Effect:** During pairing or connection attempts, random nearby BLE devices (showing raw MAC addresses or temporary name fragments like `ty`) briefly appear in your Bluetooth manager GUI and then disappear.
* System logs (`journalctl -u bluetooth`) are filled with the following errors from `bluetoothd`:
  ```text
  bluetoothd: profiles/deviceinfo/deviceinfo.c:read_pnpid_cb() Error reading PNP_ID value: Request attribute has encountered an unlikely error
  bluetoothd: profiles/input/hog-lib.c:info_read_cb() HID Information read failed: Request attribute has encountered an unlikely error
  bluetoothd: profiles/input/hog-lib.c:report_read_cb() Error reading Report value: Request attribute has encountered an unlikely error
  ```

### 2. How to Identify
* Run the following command to check if your Bluetooth daemon is failing to communicate over GATT with your BLE mouse/keyboard:
  ```bash
  sudo journalctl -b -u bluetooth | grep -i "unlikely error"
  ```
  If you see `Request attribute has encountered an unlikely error` from `hog-lib.c` (HID over GATT) or `deviceinfo.c`, you are experiencing this issue.

### 3. Root Cause
The "Unlikely Error" (ATT/GATT Protocol Error `0x0E`) occurs when `bluetoothd` tries to read or write specific device characteristics (like PNP IDs, battery levels, or HID reports), but the connection state is unauthenticated, keys are out-of-sync, or the device's firmware rejects the request.
This is typically caused by:
1. **Stale Pairing Keys / GATT Cache:** A mismatch between the pairing keys or cached GATT service attributes stored in `/var/lib/bluetooth/` and those on the mouse itself (often occurring after re-pairing, dual-booting, or firmware updates).
2. **Aggressive USB Autosuspend / Power Management:** The kernel powers down the Bluetooth adapter or transitions the BLE connection to an idle state before the GATT discovery handshake is complete.

---

### 4. How to Recover

Follow these steps in order to clear the stale state and establish a healthy BLE connection:

#### Method A: The "Clean Slate" Pairing (Most Effective)
Often, standard GUI unpairing does not clear the filesystem cache, leading to persistent key mismatches. Purging the GATT cache and pairing via the CLI is the most reliable fix.

1. **Check for `bluetoothctl`:**
   If `bluetoothctl` is missing on your system, install it using your package manager:
   * **Arch Linux / Manjaro:** `sudo pacman -S bluez-utils`
   * **Debian / Ubuntu / Pop!_OS:** `sudo apt install bluez`

2. **Open the interactive CLI:**
   ```bash
   bluetoothctl
   ```

3. **List paired devices:**
   Find your mouse's MAC address (e.g., `XX:XX:XX:XX:XX:XX`):
   ```text
   [bluetooth]# devices
   ```
   *Note: If `devices` returns empty, the device is completely forgotten and you can jump straight to Step 5.*

4. **Remove and disconnect the device (if listed):**
   ```text
   [bluetooth]# remove XX:XX:XX:XX:XX:XX
   [bluetooth]# disconnect XX:XX:XX:XX:XX:XX
   ```

5. **Put your mouse/keyboard into pairing mode:**
   Hold down the connection/channel button on the bottom of your device until its LED flashes rapidly.

6. **Pair, trust, and connect manually:**
   ```text
   [bluetooth]# scan on
   # Wait for your device to appear in the list with its MAC address
   [bluetooth]# pair XX:XX:XX:XX:XX:XX
   [bluetooth]# trust XX:XX:XX:XX:XX:XX
   [bluetooth]# connect XX:XX:XX:XX:XX:XX
   ```
   *Verification: Upon successful pairing and connection, you should see your terminal output populate with discovered services (e.g., `[NEW] Primary Service`, `[NEW] Characteristic`). If these resolve without "unlikely error" logs in the background, your device is fully operational.*

7. **Stop scanning:**
   ```text
   [bluetooth]# scan off
   ```

#### Method B: Manually Purging the GATT Cache
If the issue persists, you can force the Bluetooth daemon to perform a full, fresh GATT database discovery by deleting the stored attribute cache.

1. Stop the Bluetooth service:
   ```bash
   sudo systemctl stop bluetooth
   ```
2. Locate and remove the cached databases (replace `AA:AA:AA:AA:AA:AA` with your adapter's local MAC address):
   ```bash
   # Delete the cached attribute mappings
   sudo rm -rf /var/lib/bluetooth/AA:AA:AA:AA:AA:AA/cache/
   ```
3. Restart the Bluetooth service:
   ```bash
   sudo systemctl start bluetooth
   ```

#### Method C: Adjusting `main.conf` Workarounds
For persistent connection dropouts on BLE mice, you can disable GATT caching or enable automatic repairing by editing `/etc/bluetooth/main.conf`:

1. Open the configuration file:
   ```bash
   sudo nano /etc/bluetooth/main.conf
   ```
2. Under the `[General]` section, make sure the following options are set:
   ```ini
   [General]
   JustWorksRepairing = always
   FastConnectable = true
   ```
3. Under the `[GATT]` section, you can optionally disable caching if the mouse firmware has buggy attribute maps:
   ```ini
   [GATT]
   Cache = no
   ```
4. Save the file and restart Bluetooth:
   ```bash
   sudo systemctl restart bluetooth
   ```

---

## Useful Commands Cheat Sheet

| Command | Purpose |
| :--- | :--- |
| `lsusb \| grep -i bluetooth` | Identify Bluetooth adapter vendor and product IDs |
| `rfkill list` | Check if wireless devices are soft/hard blocked |
| `sudo rfkill unblock bluetooth` | Lift all software blocks on Bluetooth adapters |
| `systemctl status bluetooth` | View current state and errors of the Bluetooth service |
| `sudo journalctl -b -u bluetooth` | View logs for the Bluetooth service since last boot |
| `sudo dmesg \| grep -i -E 'blue\|bt'` | View kernel ring buffer messages related to Bluetooth |

---

## Contributing Upstream

If you have a missing Qualcomm adapter ID, submit the following patch to the Linux Bluetooth subsystem mailing list `linux-bluetooth@vger.kernel.org` to have it whitelisted natively in future Linux releases:

```diff
diff --git a/drivers/bluetooth/btusb.c b/drivers/bluetooth/btusb.c
index 281896d8..8e8f8cf1 100644
--- a/drivers/bluetooth/btusb.c
+++ b/drivers/bluetooth/btusb.c
@@ -489,6 +489,7 @@ static const struct usb_device_id blacklist_table[] = {
 	{ USB_DEVICE(0x0cf3, 0xe300), .driver_info = BTUSB_QCA_ROME |
 						     BTUSB_WIDEBAND_SPEECH },
+	{ USB_DEVICE(0x13d3, 0x3503), .driver_info = BTUSB_QCA_ROME |
+						     BTUSB_WIDEBAND_SPEECH },
 	{ USB_DEVICE(0x0cf3, 0xe360), .driver_info = BTUSB_QCA_ROME |
 						     BTUSB_WIDEBAND_SPEECH },
```

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
