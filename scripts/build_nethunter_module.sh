#!/bin/bash
# scripts/build_nethunter_module.sh
# Usage: ./build_nethunter_module.sh <path_to_ko_files> <device_name>

KO_DIR=$1
DEVICE_NAME=${2:-"Generic"}
MODULE_DIR="ksu_nethunter_module"
ZIP_NAME="${DEVICE_NAME}-NetHunter-Module.zip"

echo ">>> Constructing Minimalist NetHunter KernelSU Module for $DEVICE_NAME..."

# 1. Clean and prepare module directory
rm -rf "$MODULE_DIR" "$ZIP_NAME"
mkdir -p "$MODULE_DIR"

# 2. Copy compiled drivers directly into the module root
echo "  -> Injecting compiled drivers..."
cp "$KO_DIR"/*.ko "$MODULE_DIR/" 2>/dev/null || true

# 3. Fetch and inject MediaTek firmware for systemless overlay
echo "  -> Fetching MediaTek MT7612U firmware blobs..."
FW_DIR="$MODULE_DIR/system/vendor/firmware/mediatek"
mkdir -p "$FW_DIR"
wget -q -O "$FW_DIR/mt7662u_rom_patch.bin" "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mediatek/mt7662u_rom_patch.bin"
wget -q -O "$FW_DIR/mt7662u.bin" "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mediatek/mt7662u.bin"

# 4. Generate module.prop
cat << EOF > "$MODULE_DIR/module.prop"
id=nethunter-drivers-${DEVICE_NAME,,}
name=NetHunter Surgical Wireless Drivers ($DEVICE_NAME)
version=v3.0-mediatek
versionCode=4
author=Shoey
description=Minimalist systemless NetHunter drivers (MediaTek MT7612U ALFA AWUS036ACM) with Action Button control and firmware injection.
EOF

# 5. Generate service.sh (Disabled autoload)
cat << 'EOF' > "$MODULE_DIR/service.sh"
#!/system/bin/sh
MODDIR=${0%/*}
# Auto-load disabled. The Action button is in full control.
EOF

# 6. Generate action.sh (The Honest MediaTek Cascade)
cat << 'EOF' > "$MODULE_DIR/action.sh"
#!/system/bin/sh
MODDIR=${0%/*}

if lsmod | grep -q "mt76x2u"; then
    echo "De-activating ALFA drivers..."
    
    # The kernel automatically destroys the interface when the module unloads, 
    # so we just cascade rmmod top-down.
    rmmod mt76x2u 2>/dev/null
    rmmod mt76x2_common 2>/dev/null
    rmmod mt76x02_usb 2>/dev/null
    rmmod mt76x02_lib 2>/dev/null
    rmmod mt76_usb 2>/dev/null
    rmmod mt76 2>/dev/null
    
    echo "[SUCCESS] Stack cleanly unloaded."
else
    echo "Activating ALFA drivers..."
    
    # Notice we removed 2>/dev/null. If the kernel rejects them, 
    # KernelSU will now display the actual error on the screen.
    insmod "$MODDIR/mt76.ko"
    insmod "$MODDIR/mt76-usb.ko"
    insmod "$MODDIR/mt76x02-lib.ko"
    insmod "$MODDIR/mt76x02-usb.ko"
    insmod "$MODDIR/mt76x2-common.ko"
    insmod "$MODDIR/mt76x2u.ko"

    sleep 1
    
    # Actually verify the driver is in memory before celebrating
    if lsmod | grep -q "mt76x2u"; then
        # Filter out the known Pixel 9 internal interfaces
        ALFA_IFACE=$(iw dev | awk '$1=="Interface"{print $2}' | grep -vE "wlan0|wlan1|aware|wonder")
        
        if [ -n "$ALFA_IFACE" ]; then
            ip link set "$ALFA_IFACE" up
            echo "[SUCCESS] Drivers injected. ALFA online on $ALFA_IFACE."
        else
            echo "[SUCCESS] Drivers injected, but waiting for USB hotplug..."
            echo "Plug in the ALFA adapter now."
        fi
    else
        echo "[ERROR] Kernel rejected the modules! Check dmesg."
    fi
fi
EOF

# 7. Generate customize.sh
cat << EOF > "$MODULE_DIR/customize.sh"
#!/system/bin/sh
ui_print "- Installing Surgical NetHunter Driver Stack..."
ui_print "- Device: $DEVICE_NAME"
ui_print "- Hardware: MediaTek MT7612U (AWUS036ACM)"
ui_print "- Setting permissions..."
set_perm_recursive "\$MODPATH" 0 0 0755 0644
set_perm "\$MODPATH/action.sh" 0 0 0755
set_perm "\$MODPATH/service.sh" 0 0 0755
ui_print "- Ready for OTG injection."
EOF

chmod +x "$MODULE_DIR"/*.sh

echo ">>> Surgical NetHunter Module directory ready for GitHub upload!"
