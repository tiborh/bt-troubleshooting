# Bluetooth Mouse Troubleshooting on Linux (Qualcomm QCA9377 BLE Fix)

This repository contains documentation and a self-healing automation script to fix Bluetooth Low Energy (BLE) scanning issues on Qualcomm Atheros QCA9377 Bluetooth adapters under Linux (such as Arch Linux, Manjaro, or Debian/Ubuntu).

## The Symptom

Your Bluetooth mouse (e.g., Logitech MX Master 2S, which utilizes BLE exclusively) successfully pairs and connects, but the pointer does not move. After a short period, the connection drops.

Kernel logs (`dmesg`) spam the following error every ~16 seconds:
```
[  401.775514] Bluetooth: hci0: unexpected event for opcode 0x2005
```
*   **Opcode `0x2005`** corresponds to `LE Set Scan Parameters`. This indicates that BLE scanning is broken at the hardware/HCI level.
*   The driver is loaded as generic Bluetooth, but **no Qualcomm firmware initialization (`btqca`) ever occurred**.

---

## The Root Cause

The Qualcomm QCA9377 Bluetooth adapter (USB Vendor/Product ID `13d3:3503` or similar OEM variants) binds to the generic `btusb` driver via **class matching** (as a generic USB Bluetooth device) rather than as a named Qualcomm device. 

Because of this, `btusb` never triggers the `btqca` firmware loading path. The device operates on its raw ROM firmware, which has a bug that crashes BLE scanning (`opcode 0x2005`). 

This is not a kernel regression—these specific USB IDs were simply never added to the driver's hardcoded QCA Rome whitelist.

---

## Why Standard Dynamic ID Bindings (`new_id`) Fail

A common troubleshooting suggestion online is to register the device ID dynamically with the driver via sysfs:
```bash
# This is a standard recommendation that DOES NOT WORK for QCA devices:
echo "13d3 3503 0 0 0 0 0x00040000" > /sys/bus/usb/drivers/btusb/new_id
```

This fails for two reasons:
1. **SSCANF Limitations**: The USB dynamic ID sysfs handler in `drivers/usb/core/driver.c` only parses up to 5 fields (Vendor, Product, bInterfaceClass, refVendor, refProduct). It has no 7-field or 12-field parser to map the 12th field (`driver_info`) directly from userspace.
2. **Qualcomm is Private**: To set configuration flags dynamically, you must pass a reference device (`refVendor` and `refProduct`) to copy flags from. However, the parser only searches the driver's public device table (`btusb_table[]`). In `btusb.c`, all Qualcomm Rome entries are kept inside a private structure (`blacklist_table[]`). Thus, writing a reference device like `0cf3 e300` fails with `No such device` (ENODEV).

---

## The Solution: Surgical Binary Patching

Since we cannot use the sysfs `new_id` interface to dynamically assign the QCA Rome driver flags, the most robust and elegant solution is to **binary-patch the active `btusb.ko` module** to replace a statically compiled, unused Qualcomm Rome device ID with your card's device ID.

### 1. Locate and Patch the Device ID Table
In 64-bit Linux, the size of a `usb_device_id` struct is exactly 32 bytes:
```c
struct usb_device_id {
    __u16 match_flags;      // 2 bytes
    __u16 idVendor;         // 2 bytes
    __u16 idProduct;        // 2 bytes
    ... [padding/class] ... // 18 bytes
    kernel_ulong_t drv_info;// 8 bytes (BTUSB_QCA_ROME | BTUSB_WIDEBAND_SPEECH = 0x204000)
};
```
The standard Atheros/Qualcomm Rome ID is `0cf3:e300` which maps to:
- Hex: `03 00 f3 0c 00 e3 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 40 20 00 00 00 00 00` (32 bytes)

By searching the compiled `btusb.ko` binary for this pattern and replacing `0cf3` (`f3 0c`) and `e300` (`00 e3`) with your native adapter ID (e.g., `13d3:3503`), we statically register your device in the driver's blacklist table.

### 2. Bypass Module Signature Check
The running kernel enforces module signatures (`CONFIG_MODULE_SIG=y`). Binary patching the module breaks its signature, causing `modprobe` to fail with `Key was rejected by service`.

However, on most systems, strict signature enforcement is disabled (`# CONFIG_MODULE_SIG_FORCE is not set`). This means the kernel will load completely unsigned modules.
* Running **`strip --strip-debug`** on the patched `.ko` file strips all debug symbols and automatically chops off the appended signature block.
* This leaves a perfectly clean, unsigned module that the kernel loads without any errors.

---

## Automated Patch Script

The provided script `patch-btusb.sh` automates this entire process:
1. Finds the active running kernel and locates the `btusb.ko.zst` file.
2. Creates a secure backup (`btusb.ko.zst.bak`).
3. Decompress the backup, uses Python to do an in-place binary search-and-replace for QCA Rome reference ID candidates, and writes the patched binary.
4. Strips the signature block using `strip --strip-debug`.
5. Compresses the module back to `.zst` format and overwrites the system driver.
6. Reloads the module to immediately apply the fix.

### Usage

1. Clone this repository.
2. Configure your target VID and PID in `patch-btusb.sh` if they differ from the QCA9377 default (`13d3:3503`).
3. Make the script executable and run with `sudo`:
   ```bash
   chmod +x patch-btusb.sh
   sudo ./patch-btusb.sh
   ```

### Survival Across Kernel Updates
Since system package managers (like `pacman` or `apt`) will overwrite `btusb.ko.zst` during kernel updates, keep this script in your home directory or `/usr/local/bin/`. After any kernel update, simply run the script once to re-apply the patch.

---

## Contributing Upstream

The permanent fix is to submit a patch to the Linux Bluetooth subsystem mailing list: `linux-bluetooth@vger.kernel.org`. 

If your adapter ID is missing, submit the following patch to the maintainers to have it whitelisted natively in future Linux releases:

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
