# Sanitized Diagnostics for IMC Networks QCA9377 (`13d3:3503`)

This file stores sanitized diagnostics for the affected Bluetooth controller so future maintainer requests can be answered from the repository without exposing personal data.

## Sanitization Notes

- Only the relevant Bluetooth device block is included.
- Email headers, account names, hostnames, serial numbers, and unrelated USB devices are omitted.
- Commands are recorded exactly so the same data can be recollected later.

## Symptom Summary

- Adapter: IMC Networks Qualcomm Atheros QCA9377 Bluetooth controller
- USB ID: `13d3:3503`
- Failure mode: BLE scanning fails unless the device is handled as QCA Rome
- Observed kernel symptom: `Bluetooth: hci0: unexpected event for opcode 0x2005`

## Collected Descriptor Data

### `/sys/kernel/debug/usb/devices`

```text
P:  Vendor=13d3 ProdID=3503 Rev= 0.01
C:* #Ifs= 2 Cfg#= 1 Atr=e0 MxPwr=100mA
I:* If#= 0 Alt= 0 #EPs= 3 Cls=e0(wlcon) Sub=01 Prot=01 Driver=btusb
E:  Ad=81(I) Atr=03(Int.) MxPS=  16 Ivl=1ms
E:  Ad=82(I) Atr=02(Bulk) MxPS=  64 Ivl=0ms
E:  Ad=02(O) Atr=02(Bulk) MxPS=  64 Ivl=0ms
I:* If#= 1 Alt= 0 #EPs= 2 Cls=e0(wlcon) Sub=01 Prot=01 Driver=btusb
E:  Ad=83(I) Atr=01(Isoc) MxPS=   0 Ivl=1ms
E:  Ad=03(O) Atr=01(Isoc) MxPS=   0 Ivl=1ms
I:  If#= 1 Alt= 1 #EPs= 2 Cls=e0(wlcon) Sub=01 Prot=01 Driver=btusb
E:  Ad=83(I) Atr=01(Isoc) MxPS=   9 Ivl=1ms
E:  Ad=03(O) Atr=01(Isoc) MxPS=   9 Ivl=1ms
I:  If#= 1 Alt= 2 #EPs= 2 Cls=e0(wlcon) Sub=01 Prot=01 Driver=btusb
E:  Ad=83(I) Atr=01(Isoc) MxPS=  17 Ivl=1ms
E:  Ad=03(O) Atr=01(Isoc) MxPS=  17 Ivl=1ms
I:  If#= 1 Alt= 3 #EPs= 2 Cls=e0(wlcon) Sub=01 Prot=01 Driver=btusb
E:  Ad=83(I) Atr=01(Isoc) MxPS=  25 Ivl=1ms
E:  Ad=03(O) Atr=01(Isoc) MxPS=  25 Ivl=1ms
I:  If#= 1 Alt= 4 #EPs= 2 Cls=e0(wlcon) Sub=01 Prot=01 Driver=btusb
E:  Ad=83(I) Atr=01(Isoc) MxPS=  33 Ivl=1ms
E:  Ad=03(O) Atr=01(Isoc) MxPS=  33 Ivl=1ms
I:  If#= 1 Alt= 5 #EPs= 2 Cls=e0(wlcon) Sub=01 Prot=01 Driver=btusb
E:  Ad=83(I) Atr=01(Isoc) MxPS=  49 Ivl=1ms
E:  Ad=03(O) Atr=01(Isoc) MxPS=  49 Ivl=1ms
```

### `usb-devices`

```text
P:  Vendor=13d3 ProdID=3503 Rev=00.01
C:  #Ifs= 2 Cfg#= 1 Atr=e0 MxPwr=100mA
I:  If#= 0 Alt= 0 #EPs= 3 Cls=e0(wlcon) Sub=01 Prot=01 Driver=btusb
E:  Ad=02(O) Atr=02(Bulk) MxPS=  64 Ivl=0ms
E:  Ad=81(I) Atr=03(Int.) MxPS=  16 Ivl=1ms
E:  Ad=82(I) Atr=02(Bulk) MxPS=  64 Ivl=0ms
I:  If#= 1 Alt= 0 #EPs= 2 Cls=e0(wlcon) Sub=01 Prot=01 Driver=btusb
E:  Ad=03(O) Atr=01(Isoc) MxPS=   0 Ivl=1ms
E:  Ad=83(I) Atr=01(Isoc) MxPS=   0 Ivl=1ms
```

### `lsusb -v` Summary

```text
Bus 001 Device 004: ID 13d3:3503 IMC Networks
Negotiated speed: Full Speed (12Mbps)
bDeviceClass          224 Wireless
bDeviceSubClass         1 Radio Frequency
bDeviceProtocol         1 Bluetooth
bNumConfigurations      1

Configuration 1:
  bNumInterfaces          2
  bmAttributes         0xe0  (Self Powered, Remote Wakeup)
  MaxPower              100mA

Interface 0:
  Class/Subclass/Protocol: e0/01/01
  Endpoints:
    0x81 interrupt IN, 16 bytes
    0x82 bulk IN, 64 bytes
    0x02 bulk OUT, 64 bytes

Interface 1:
  Class/Subclass/Protocol: e0/01/01
  Alternate settings observed:
    alt 0: isoc IN/OUT, 0 bytes
    alt 1: isoc IN/OUT, 9 bytes
    alt 2: isoc IN/OUT, 17 bytes
    alt 3: isoc IN/OUT, 25 bytes
    alt 4: isoc IN/OUT, 33 bytes
    alt 5: isoc IN/OUT, 49 bytes
```

### `lsusb -t` Relevant Topology

```text
/:  Bus 001.Port 001: Dev 001, Class=root_hub, Driver=xhci_hcd/9p, 480M
    |__ Port 007: Dev 004, If 0, Class=Wireless, Driver=btusb, 12M
    |__ Port 007: Dev 004, If 1, Class=Wireless, Driver=btusb, 12M
```

## Collection Procedure

Run the following commands and record only the block for `13d3:3503`:

```bash
# 1. Mount debugfs if it is not already mounted.
sudo mount -t debugfs none /sys/kernel/debug

# 2. Capture the exact maintainer-requested debugfs descriptor block.
sudo sed -n '/Vendor=13d3 ProdID=3503/,+25p' /sys/kernel/debug/usb/devices

# 3. Capture the equivalent normalized USB descriptor view.
usb-devices | sed -n '/Vendor=13d3 ProdID=3503/,+20p'

# 4. Capture the verbose descriptor dump for the device only.
lsusb -d 13d3:3503 -v 2>/dev/null | sed -n '1,220p'

# 5. Capture the active USB topology to show the binding to btusb.
lsusb -t | sed -n '1,120p'
```

## What to Avoid Committing

- Full email messages with raw headers
- Full `dmesg` output if it contains unrelated hardware or identifying details
- USB dumps for unrelated devices
- Host-specific serial numbers or other string descriptors, if any appear on future hardware

## Extending This File

If maintainers request more data later, add a new subsection with:

1. The exact request
2. The command used to gather the data
3. The sanitized output
4. Any redactions performed
