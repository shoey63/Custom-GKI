#!/bin/bash
KO_DIR=$1
DEVICE_NAME=${2:-"Generic"}
MODULE_DIR="ksu_nethunter_module"

echo ">>> Constructing Minimalist NetHunter KernelSU Module for $DEVICE_NAME..."
rm -rf "$MODULE_DIR"
mkdir -p "$MODULE_DIR/system/vendor/firmware/mediatek"

cp "$KO_DIR"/*.ko "$MODULE_DIR/" 2>/dev/null || true
wget -q -O "$MODULE_DIR/system/vendor/firmware/mediatek/mt7662u_rom_patch.bin" "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mediatek/mt7662u_rom_patch.bin"
wget -q -O "$MODULE_DIR/system/vendor/firmware/mediatek/mt7662u.bin" "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mediatek/mt7662u.bin"

cat << INNER_EOF > "$MODULE_DIR/module.prop"
id=nethunter-drivers-${DEVICE_NAME,,}
name=NetHunter Surgical Wireless Drivers ($DEVICE_NAME)
version=v3.0-mediatek
versionCode=4
author=Shoey
description=Minimalist systemless NetHunter drivers (MediaTek MT7612U ALFA AWUS036ACM)
INNER_EOF

cat << 'INNER_EOF' > "$MODULE_DIR/service.sh"
#!/system/bin/sh
MODDIR=${0%/*}
INNER_EOF

echo "Generating action.sh..."
cat << 'INNER_EOF' > "$MODULE_DIR/action.sh"
#!/system/bin/sh
MODDIR=${0%/*}

if ! lsmod | grep -q "mt76x2u"; then
    echo "Activating ALFA drivers..."
    # insmod REQUIRES actual filenames on disk (hyphens)
    insmod "$MODDIR/mt76.ko"
    insmod "$MODDIR/mt76-usb.ko"
    insmod "$MODDIR/mt76x02-lib.ko"
    insmod "$MODDIR/mt76x02-usb.ko"
    insmod "$MODDIR/mt76x2-common.ko"
    insmod "$MODDIR/mt76x2u.ko"
    
    if lsmod | grep -q "mt76x2u"; then
        echo "[SUCCESS] Drivers injected."
    else
        echo "[ERROR] Kernel rejected the modules! Check dmesg."
    fi
else
    echo "Deactivating ALFA drivers..."
    # rmmod REQUIRES module names in memory (underscores)
    rmmod mt76x2u
    rmmod mt76x2_common
    rmmod mt76x02_usb
    rmmod mt76x02_lib
    rmmod mt76_usb
    rmmod mt76
    echo "[SUCCESS] Drivers unloaded."
fi
INNER_EOF

cat << INNER_EOF > "$MODULE_DIR/customize.sh"
#!/system/bin/sh
ui_print "- Installing Surgical NetHunter Driver Stack..."
ui_print "- Device: $DEVICE_NAME"
set_perm_recursive "\$MODPATH" 0 0 0755 0644
set_perm "\$MODPATH/action.sh" 0 0 0755
set_perm "\$MODPATH/service.sh" 0 0 0755
INNER_EOF

chmod +x "$MODULE_DIR"/*.sh
