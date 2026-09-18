#!/bin/bash
# scripts/build_nethunter_module.sh
# Usage: ./build_nethunter_module.sh <path_to_ko_files> <device_name>

KO_DIR=$1
DEVICE_NAME=${2:-"Generic"}
MODULE_DIR="ksu_nethunter_module"

echo ">>> Constructing Minimalist NetHunter KernelSU Module for $DEVICE_NAME..."

# 1. Clean and prepare module directory
rm -rf "$MODULE_DIR"
mkdir -p "$MODULE_DIR"

# 2. Copy compiled drivers directly into the module root
echo "  -> Injecting compiled drivers..."
cp "$KO_DIR"/*.ko "$MODULE_DIR/" 2>/dev/null || true

# 3. Generate module.prop
cat << EOF > "$MODULE_DIR/module.prop"
id=nethunter-drivers-${DEVICE_NAME,,}
name=NetHunter Surgical Wireless Drivers ($DEVICE_NAME)
version=v2.1-surgical
versionCode=3
author=Shoey
description=Minimalist systemless NetHunter drivers (Realtek 88XXau) with Action Button control.
EOF

# 4. Generate service.sh (Disabled autoload)
cat << 'EOF' > "$MODULE_DIR/service.sh"
#!/system/bin/sh
MODDIR=${0%/*}
# Auto-load disabled. The Action button is in full control.
EOF

# 5. Generate action.sh (The Silent, Bottom-Up Spines-First Topology)
cat << 'EOF' > "$MODULE_DIR/action.sh"
#!/system/bin/sh
MODDIR=${0%/*}

if ip link show 2>/dev/null | grep -qE "(wlan1|wlan2|wlan3).*UP"; then
    echo "NetHunter stack being de-activated..."
    ip link set wlan1 down 2>/dev/null
    ip link set wlan2 down 2>/dev/null
    ip link set wlan3 down 2>/dev/null
    sleep 1
    echo "[SUCCESS!] Interfaces dropped. Modules kept in memory to prevent kernel panic."
else
    echo "NetHunter stack being activated..."

    # 1. INDEPENDENT HOOKS & SUBSYSTEMS
    insmod "$MODDIR/rfkill.ko" 2>/dev/null

    # 2. THE WIRELESS SPINE (Strict bottom-up order)
    insmod "$MODDIR/cfg80211.ko" 2>/dev/null
    insmod "$MODDIR/mac80211.ko" 2>/dev/null
    
    # 3. WI-FI ADAPTERS
    insmod "$MODDIR/88XXau.ko" 2>/dev/null

    sleep 1
    ip link set wlan1 up 2>/dev/null
    echo "[SUCCESS!] Stack armed silently."
fi
EOF

# 6. Generate customize.sh
cat << EOF > "$MODULE_DIR/customize.sh"
#!/system/bin/sh
ui_print "- Installing Surgical NetHunter Driver Stack..."
ui_print "- Device: $DEVICE_NAME"
ui_print "- Setting permissions..."
set_perm_recursive "\$MODPATH" 0 0 0755 0644
set_perm "\$MODPATH/action.sh" 0 0 0755
set_perm "\$MODPATH/service.sh" 0 0 0755
ui_print "- Ready for OTG injection."
EOF

chmod +x "$MODULE_DIR"/*.sh

echo ">>> Surgical KernelSU Module structure complete!"
