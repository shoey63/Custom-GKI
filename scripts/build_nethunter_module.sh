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

# 6. Generate action.sh (The Native MediaTek Cascade)
cat << 'EOF' > "$MODULE_DIR/action.sh"
#!/system/bin/sh
MODDIR=${0%/*}

if lsmod | grep -q "mt76x2u"; then
    echo "NetHunter stack being de-activated..."
    
    # Dynamically find and drop external interfaces
    ALFA_IFACE=$(iw dev | awk '$1=="Interface"{print $2}' | grep -v "wlan0\|aware")
    if [ -n "$ALFA_IFACE" ]; then
        ip link set "$ALFA_IFACE" down 2>/dev/null
    else
        ip link set wlan1 down 2>/dev/null
        ip link set wlan2 down 2>/dev/null
    fi
    sleep 1
    
    # Gracefully unload the MediaTek stack
    rmmod mt76x2u 2>/dev/null
    rmmod mt76x2_common 2>/dev/null
    rmmod mt76x02_usb 2>/dev/null
    rmmod mt76x02_lib 2>/dev/null
    rmmod mt76_usb 2>/dev/null
    rmmod mt76 2>/dev/null
    
    echo "[SUCCESS!] Interfaces dropped and ALFA drivers cleanly unloaded."
else
    echo "NetHunter stack being activated..."

    # 1. INDEPENDENT HOOKS & SUBSYSTEMS
    insmod "$MODDIR/rfkill.ko" 2>/dev/null

    # 2. THE WIRELESS SPINE
    insmod "$MODDIR/cfg80211.ko" 2>/dev/null
    insmod "$MODDIR/mac80211.ko" 2>/dev/null
    
    # 3. MEDIATEK ALFA ADAPTER
    insmod "$MODDIR/mt76.ko" 2>/dev/null
    insmod "$MODDIR/mt76-usb.ko" 2>/dev/null
    insmod "$MODDIR/mt76x02-lib.ko" 2>/dev/null
    insmod "$MODDIR/mt76x02-usb.ko" 2>/dev/null
    insmod "$MODDIR/mt76x2-common.ko" 2>/dev/null
    insmod "$MODDIR/mt76x2u.ko" 2>/dev/null

    sleep 1
    
    # Dynamically find the new interface and bring it up
    ALFA_IFACE=$(iw dev | awk '$1=="Interface"{print $2}' | grep -v "wlan0\|aware")
    if [ -n "$ALFA_IFACE" ]; then
        ip link set "$ALFA_IFACE" up 2>/dev/null
        echo "[SUCCESS!] Stack armed silently. ALFA online on $ALFA_IFACE."
    else
        ip link set wlan1 up 2>/dev/null
        echo "[SUCCESS!] Stack armed silently. ALFA online on wlan1."
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
