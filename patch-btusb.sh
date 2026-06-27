#!/bin/bash
# patch-btusb.sh - Automates binary patching of btusb module for QCA9377 (13d3:3503)
# Saves backup, patches clean source, strips signature, compresses, and reloads.

set -e

# Target device to inject (Qualcomm QCA9377)
NEW_VID="13d3"
NEW_PID="3503"

# Kernel module path
KERNEL_VER=$(uname -r)
MODULE_DIR="/lib/modules/${KERNEL_VER}/kernel/drivers/bluetooth"
MODULE_FILE="${MODULE_DIR}/btusb.ko.zst"
BACKUP_FILE="${MODULE_FILE}.bak"

if [ ! -f "$MODULE_FILE" ]; then
    echo "Error: Module file not found: $MODULE_FILE"
    exit 1
fi

echo "Working on kernel: ${KERNEL_VER}"

# Create backup of the original module if not already present
if [ ! -f "$BACKUP_FILE" ]; then
    echo "Creating backup of original module to ${BACKUP_FILE}..."
    sudo cp "$MODULE_FILE" "$BACKUP_FILE"
fi

# Always patch from the clean backup to support running repeatedly
echo "Decompressing clean module source..."
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

zstd -d "$BACKUP_FILE" -o "${TMP_DIR}/btusb.ko"

echo "Surgically patching binary..."
python3 -c "
import sys

new_vid = int('$NEW_VID', 16)
new_pid = int('$NEW_PID', 16)

# Standard QCA Rome IDs to search for in blacklist_table
candidates = [
    (0x0cf3, 0xe300),  # QCA6174 (e.g. Dell XPS)
    (0x0cf3, 0xe301),
    (0x0cf3, 0xe360),
    (0x0cf3, 0xe007),
]

with open('${TMP_DIR}/btusb.ko', 'r+b') as f:
    data = f.read()
    
    patched = False
    for ref_vid, ref_pid in candidates:
        # Match flags for USB_DEVICE_ID_MATCH_DEVICE is 0x0003
        # pattern is match_flags (2 bytes) + idVendor (2 bytes) + idProduct (2 bytes) in little-endian
        old_pattern = b'\x03\x00' + ref_vid.to_bytes(2, 'little') + ref_pid.to_bytes(2, 'little')
        
        count = data.count(old_pattern)
        if count == 1:
            idx = data.find(old_pattern)
            
            # Read the 32-byte struct to verify driver_info is 0x204000 (ROME | WBS)
            f.seek(idx)
            struct_bytes = f.read(32)
            driver_info = int.from_bytes(struct_bytes[24:32], 'little')
            
            # 0x204000 = BTUSB_QCA_ROME | BTUSB_WIDEBAND_SPEECH
            if driver_info == 0x204000:
                print(f'Found target reference {ref_vid:04x}:{ref_pid:04x} at index {idx} with QCA Rome flags.')
                
                # Write the new VID and PID
                new_struct = bytearray(struct_bytes)
                new_struct[2:4] = new_vid.to_bytes(2, 'little')
                new_struct[4:6] = new_pid.to_bytes(2, 'little')
                
                f.seek(idx)
                f.write(new_struct)
                patched = True
                print(f'Successfully replaced with {new_vid:04x}:{new_pid:04x}!')
                break
            else:
                print(f'Found {ref_vid:04x}:{ref_pid:04x} but driver_info ({hex(driver_info)}) did not match QCA Rome.')
                
    if not patched:
        print('Error: Could not find any suitable Qualcomm Rome reference ID to patch.')
        sys.exit(1)
"

echo "Stripping debug symbols and signature block..."
strip --strip-debug "${TMP_DIR}/btusb.ko"

echo "Re-compressing module..."
zstd -f -z "${TMP_DIR}/btusb.ko" -o "${TMP_DIR}/btusb.ko.zst"

echo "Overwriting system module..."
sudo cp "${TMP_DIR}/btusb.ko.zst" "$MODULE_FILE"

echo "Reloading btusb driver..."
if lsmod | grep -q "^btusb"; then
    sudo rmmod btusb
fi
sudo modprobe btusb

echo "Success! Qualcomm Rome driver successfully patched and loaded."
sudo dmesg | grep -i -E 'btusb|btqca|hci0|firmware|qca' | tail -n 15
