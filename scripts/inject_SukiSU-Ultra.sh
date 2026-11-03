#!/usr/bin/env bash
# scripts/inject_SukiSU-Ultra.sh

echo ">>> Executing Integration Module for SukiSU-Ultra..."

# Override channel routing so both 'stable' and 'dynamic' runs pull the custom
# SuSFS pt_regs commits from the shoey63 fork (while leaving 'main' untouched).
if [ "${BUILD_CHANNEL}" != "main" ]; then
    if [ "${BASE_VER}" = "6.12" ]; then
        echo ">>> [OVERRIDE] Kernel 6.12 detected. Routing to pure builtin branch..."
        KSU_VARIANT_REPO_URL="https://github.com/SukiSU-Ultra/SukiSU-Ultra.git"
        KSU_VARIANT_REF="builtin"
        SKIP_REBASE_STAMP="true"
    else
        echo ">>> [OVERRIDE] Legacy kernel detected. Routing to hardened pt_regs branch (stable)..."
        KSU_VARIANT_REPO_URL="https://github.com/shoey63/SukiSU-Ultra.git"
        KSU_VARIANT_REF="stable"
    fi
fi

echo ">>> 1. Cloning target branch (${KSU_VARIANT_REF}) from ${KSU_VARIANT_REPO_URL}..."
git clone -b "${KSU_VARIANT_REF}" "${KSU_VARIANT_REPO_URL}" "${MANAGER_DIR}"

ln -sfn "../${MANAGER_DIR}" "common/${MANAGER_DIR}"
cd common
# Run setup.sh BEFORE rebasing so it links common/drivers/kernelsu without clobbering git history
bash "${MANAGER_DIR}/kernel/setup.sh" "${KSU_VARIANT_REF}"
cd ..

cd "${MANAGER_DIR}"

echo ">>> 2. Fetching upstream data from ${UPSTREAM_REPO} to cross-reference..."
git fetch --quiet "https://github.com/${UPSTREAM_REPO}.git" "${TARGET_BRANCH}"

if [ "${SKIP_REBASE_STAMP}" == "true" ]; then
    echo ">>> 3. [OVERRIDE] 6.12 Mode: Bypassing rebase and applying dynamic C hotfixes..."
    UPSTREAM_BRANCH="${TARGET_BRANCH}"
    
    # 1. Fix implicit SuSFS calls and linker errors with empty stubs
    sed -i '1i #include <linux/susfs.h>' kernel/manager/pkg_observer.c 2>/dev/null || true
    sed -i '2i void susfs_parse_priority_app_strings(void) {}' kernel/manager/pkg_observer.c 2>/dev/null || true
    sed -i '1i #include <linux/susfs.h>' kernel/supercall/dispatch.c 2>/dev/null || true
    sed -i '2i void susfs_set_priority_uid_filter(void *arg) {}' kernel/supercall/dispatch.c 2>/dev/null || true
    
    # 2. Bypass Android 16 LSM Panic and satisfy unused-variable compiler rules
    sed -i 's/security_add_hooks(ksu_hooks, ARRAY_SIZE(ksu_hooks), "ksu");/(void)ksu_hooks;/g' kernel/hook/lsm_hook.c 2>/dev/null || true
    
    # 3. Enable kpm
    sed -i '/config KPM/,/help/ s/default n/default y/' kernel/Kconfig
    sed -i '/select KALLSYMS/d' kernel/Kconfig

elif [ "${USE_DYNAMIC_TRANSPLANT}" == "true" ]; then
    echo ">>> 3. Dynamic mode active: Rebasing clone onto YAML-provided Upstream Hash (${UPSTREAM_HASH:0:7})..."
    git config user.name "github-actions[bot]"
    git config user.email "github-actions[bot]@users.noreply.github.com"

    if git rebase "${UPSTREAM_HASH}"; then
        echo "  -> On-the-fly rebase succeeded cleanly!"
        UPSTREAM_BRANCH="${TARGET_BRANCH}"
    else
        echo "  -> [WARNING] Rebase conflict detected with latest upstream!"
        git rebase --abort
        echo "  -> Aborted rebase and fell back to '${KSU_VARIANT_REF}'."
        UPSTREAM_BRANCH="${KSU_VARIANT_REF}"
    fi
else
    echo ">>> 3. Stable mode active: Calculating exact upstream anchor commit via merge-base..."
    UPSTREAM_HASH=$(git merge-base HEAD FETCH_HEAD)
    echo "  -> Found mathematically true upstream anchor: ${UPSTREAM_HASH:0:7}"
    echo "UPSTREAM_HASH=$UPSTREAM_HASH" >> $GITHUB_ENV
    UPSTREAM_BRANCH="${KSU_VARIANT_REF}"
fi

# 4. Calculate the official counts EXACTLY from the rock-solid hash
CALCULATED_COUNT=$(git rev-list --count "${UPSTREAM_HASH}" 2>/dev/null || echo "11950")
CALCULATED_TAG=$(git describe --tags --abbrev=0 "${UPSTREAM_HASH}" 2>/dev/null || echo "v0.0.0")

# 5. [OVERRIDE] 6.12 Version Spoofing (Must run AFTER calculations)
if [ "${SKIP_REBASE_STAMP}" == "true" ]; then
    echo ">>> [OVERRIDE] 6.12 Mode: Injecting furphy version stamp (${CALCULATED_COUNT} / ${UPSTREAM_HASH:0:7}) directly into Kbuild/Makefile..."
    sed -i "s/git rev-list --count HEAD/echo ${CALCULATED_COUNT}/g" kernel/Kbuild kernel/Makefile 2>/dev/null || true
    sed -i "s/git rev-parse --short HEAD/echo ${UPSTREAM_HASH:0:7}/g" kernel/Kbuild kernel/Makefile 2>/dev/null || true
    sed -i "s/git rev-parse HEAD/echo ${UPSTREAM_HASH}/g" kernel/Kbuild kernel/Makefile 2>/dev/null || true
fi

cd ..

echo "  -> Target Tag: $CALCULATED_TAG"
echo "  -> Target Hash: $UPSTREAM_HASH"
echo "  -> Target Count: $CALCULATED_COUNT"

echo ">>> SukiSU-Ultra integration complete."
