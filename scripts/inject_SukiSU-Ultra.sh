#!/usr/bin/env bash
# scripts/inject_SukiSU-Ultra.sh

echo ">>> Executing Unified Integration Module for SukiSU-Ultra..."

echo ">>> 1. Cloning target branch (${KSU_VARIANT_REF}) from ${KSU_VARIANT_REPO_URL}..."
git clone -b "${KSU_VARIANT_REF}" "${KSU_VARIANT_REPO_URL}" "${MANAGER_DIR}"

ln -sfn "../${MANAGER_DIR}" "common/${MANAGER_DIR}"
cd common
bash "${MANAGER_DIR}/kernel/setup.sh" "${KSU_VARIANT_REF}"
cd ..

cd "${MANAGER_DIR}"

if [ "${USE_DYNAMIC_TRANSPLANT}" == "true" ]; then
    echo ">>> 2. Dynamic mode active: Checking for YAML-provided Upstream Hash..."
    if [ -n "${UPSTREAM_HASH}" ]; then
        echo "  -> Anchoring clone to exact YAML hash: ${UPSTREAM_HASH:0:7}"
        git reset --hard "${UPSTREAM_HASH}"
    else
        echo "  -> [WARNING] No UPSTREAM_HASH found in environment! Defaulting to HEAD."
        UPSTREAM_HASH=$(git rev-parse HEAD)
    fi

    echo ">>> 3. Fetching 'builtin' branch for SuSFS VFS code transplant..."
    git fetch origin builtin:builtin

    echo ">>> 4. Structuring 'builtin' branch for clean diffing..."
    git checkout builtin
    rm -rf uapi
    mv kernel/include/uapi uapi 2>/dev/null || true
    cd kernel/include
    ln -s ../../uapi uapi
    cd ../..
    
    # KEEP THIS: The genius hack that forces the amalgamation build
    mv kernel/Makefile kernel/Kbuild 2>/dev/null || true
    
    git add uapi kernel/
    git config user.email "github-actions[bot]@users.noreply.github.com"
    git config user.name "github-actions[bot]"
    git commit -m "chore: structure prep for diff"

    echo ">>> 5. Generating filtered SuSFS port patch..."
    git checkout "${KSU_VARIANT_REF}"
    
    # We DO NOT exclude Kbuild or Makefile here, so the hack carries over
    git diff --diff-filter=AM "${KSU_VARIANT_REF}"..builtin -- kernel/ uapi/ \
      ':!kernel/.clangd' \
      ':!kernel/.clang-format' \
      ':!kernel/.gitignore' \
      ':!.gitignore' > susfs_port_clean.patch

    echo ">>> 6. Applying surgical SuSFS port patch to ${KSU_VARIANT_REF}..."
    git apply susfs_port_clean.patch
    rm susfs_port_clean.patch

    echo ">>> 7. Applying KPM overrides and Restoring AVC Spoofing..."
    sed -i '/config KPM/,/help/ s/default n/default y/' kernel/Kconfig 2>/dev/null || true
    sed -i '/select KALLSYMS/d' kernel/Kconfig 2>/dev/null || true
    
    # Inject AVC spoofing directly into the amalgamation wrapper
    if [ -f "kernel/ksu_main.c" ] && ! grep -q 'avc_spoof.c' "kernel/ksu_main.c"; then
        echo '#include "feature/avc_spoof.c"' >> kernel/ksu_main.c
        echo "  -> [APPLIED] Injected avc_spoof.c into ksu_main.c amalgamation."
    fi
    
    # Restore the AVC Spoofing enum that the downgrade patch erased
    for f in include/uapi/feature.h kernel/include/uapi/feature.h uapi/feature.h; do
        if [ -f "$f" ] && ! grep -q 'KSU_FEATURE_AVC_SPOOF' "$f"; then
            sed -i '/KSU_FEATURE_MOUNT_HIDE = 16,/a \    KSU_FEATURE_AVC_SPOOF = 10003,' "$f"
            echo "  -> [APPLIED] Restored KSU_FEATURE_AVC_SPOOF (10003) enum in $f"
        fi
    done  
    
    # Fix namespace collision exposed by the 10003 enum in the amalgamation wrapper
    if [ -f "kernel/policy/feature.c" ]; then
        sed -i 's/forced_mask/feat_forced_mask/g' kernel/policy/feature.c
        sed -i 's/forced_pending/feat_forced_pending/g' kernel/policy/feature.c
        echo "  -> [APPLIED] Decoupled namespace collisions in feature.c"
    fi
    
    # Restore AVC Spoofing boot sequence directly into the amalgamation file
    if [ -f "kernel/ksu_main.c" ] && ! grep -q 'ksu_avc_spoof_init();' "kernel/ksu_main.c"; then
        # 1. Inject the signature and call for init
        sed -i '/ksu_selinux_hide_init();/i \    extern void ksu_avc_spoof_init(void);' kernel/ksu_main.c
        sed -i '/ksu_selinux_hide_init();/a \    ksu_avc_spoof_init();' kernel/ksu_main.c
        
        # 2. Inject the signature and call for exit
        sed -i '/ksu_selinux_hide_exit();/i \    extern void ksu_avc_spoof_exit(void);' kernel/ksu_main.c
        sed -i '/ksu_selinux_hide_exit();/a \    ksu_avc_spoof_exit();' kernel/ksu_main.c
        
        # 3. Inject the signature and call for late_init
        sed -i '/ksu_feature_apply_forced();/i \    extern void ksu_avc_spoof_late_init(void);' kernel/ksu_main.c
        sed -i '/ksu_feature_apply_forced();/i \    ksu_avc_spoof_late_init();' kernel/ksu_main.c
        
        echo "  -> [APPLIED] Restored AVC Spoofing ignition switches in ksu_main.c"
    fi
    
    UPSTREAM_BRANCH="${KSU_VARIANT_REF}"

else
    echo ">>> 2. Stable mode active: Calculating exact upstream anchor commit via merge-base..."
    git fetch --quiet "https://github.com/SukiSU-Ultra/SukiSU-Ultra.git" main
    UPSTREAM_HASH=$(git merge-base HEAD FETCH_HEAD)
    UPSTREAM_BRANCH="${KSU_VARIANT_REF}"
    echo "  -> Found mathematically true upstream anchor: ${UPSTREAM_HASH:0:7}"
fi

echo ">>> 8. Calculating official environment variables for parent Gatekeeper..."
CALCULATED_COUNT=$(git rev-list --count "${UPSTREAM_HASH}" 2>/dev/null || echo "11950")
CALCULATED_TAG=$(git describe --tags --abbrev=0 "${UPSTREAM_HASH}" 2>/dev/null || echo "v0.0.0")

# =========================================================
# Post-Integration Hotfixes & Safeguards
# =========================================================

echo ">>> Applying SuSFS dummy functions to satisfy linker..."

FILE_PKG="kernel/manager/pkg_observer.c"
if [ -f "$FILE_PKG" ]; then
    if grep -F -q 'void susfs_parse_priority_app_strings(void) {}' "$FILE_PKG"; then
        echo "  -> [SKIP] pkg_observer.c already contains dummy function."
    else
        sed -i '1i #include <linux/susfs.h>' "$FILE_PKG"
        sed -i '2i void susfs_parse_priority_app_strings(void) {}' "$FILE_PKG"
        echo "  -> [APPLIED] Injected susfs_parse_priority_app_strings into pkg_observer.c"
    fi
else
    echo "  -> [INFO] pkg_observer.c not found. Hotfix may no longer be required."
fi

FILE_DISPATCH="kernel/supercall/dispatch.c"
if [ -f "$FILE_DISPATCH" ]; then
    # Updated to check for the correct __user signature
    if grep -F -q 'void susfs_set_priority_uid_filter(void __user **user_info) {}' "$FILE_DISPATCH"; then
        echo "  -> [SKIP] dispatch.c already contains dummy function."
    else
        sed -i '1i #include <linux/susfs.h>' "$FILE_DISPATCH"
        # Updated to use the correct variable and signature
        sed -i '2i void susfs_set_priority_uid_filter(void __user **user_info) {}' "$FILE_DISPATCH"
        echo "  -> [APPLIED] Injected susfs_set_priority_uid_filter into dispatch.c"
    fi
else
    echo "  -> [INFO] dispatch.c not found. Hotfix may no longer be required."
fi

echo ">>> Checking for Linux 6.12+ LSM API Mismatch using BASE_VER (${BASE_VER})..."
if [ "${BASE_VER}" == "6.12" ]; then
    LSM_HOOK_FILE="kernel/hook/lsm_hook.c"
    if [ -f "$LSM_HOOK_FILE" ] && grep -q 'security_add_hooks' "$LSM_HOOK_FILE"; then
        echo "  -> Kernel 6.12 detected. Disarming deprecated LSM hook registration..."
        sed -i 's/security_add_hooks.*/(void)ksu_hooks;/g' "$LSM_HOOK_FILE"
        echo "  -> lsm_hook.c runtime panic trap bypassed!"
    fi
else
    echo "  -> Kernel ${BASE_VER} detected. Legacy LSM hook is perfectly valid."
fi

cd ..

echo "  -> Target Tag: $CALCULATED_TAG"
echo "  -> Target Hash: ${UPSTREAM_HASH:0:7}"
echo "  -> Target Count: $CALCULATED_COUNT"
echo ">>> SukiSU-Ultra module preparation complete. Returning to Gatekeeper..."
