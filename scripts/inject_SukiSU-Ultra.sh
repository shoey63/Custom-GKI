#!/usr/bin/env bash
# scripts/inject_SukiSU-Ultra.sh
# Dynamic SuSFS integration module for SukiSU-Ultra

echo ">>> Executing Integration Module for SukiSU-Ultra..."

echo ">>> 1. Cloning target branch (${KSU_VARIANT_REF}) from ${KSU_VARIANT_REPO_URL}..."
git clone -b "${KSU_VARIANT_REF}" "${KSU_VARIANT_REPO_URL}" "${MANAGER_DIR}"

ln -sfn "../${MANAGER_DIR}" "common/${MANAGER_DIR}"
cd common
bash "${MANAGER_DIR}/kernel/setup.sh" "${KSU_VARIANT_REF}"
cd ..

cd "${MANAGER_DIR}"

echo ">>> 2. Fetching upstream data from ${UPSTREAM_REPO} to cross-reference..."
git fetch --quiet "https://github.com/${UPSTREAM_REPO}.git" "${TARGET_BRANCH}"

if [ "${USE_DYNAMIC_TRANSPLANT}" == "true" ]; then
    echo ">>> 3. Dynamic mode active: Anchoring clone to YAML-provided Upstream Hash (${UPSTREAM_HASH:0:7})..."
    git reset --hard "${UPSTREAM_HASH}"

    echo ">>> 4. Fetching upstream builtin branch..."
    git fetch --quiet "https://github.com/${UPSTREAM_REPO}.git" builtin

    echo ">>> Configuring dummy Git identity for transplant operations..."
    git config --global user.email "runner@github.actions"
    git config --global user.name "GitHub Actions Canary"

    echo ">>> 5. Transplanting built-in SuSFS kernel/ tree onto pristine main anchor..."
    git rm -rf --quiet kernel/
    git checkout FETCH_HEAD -- kernel/

    git add kernel/
    git commit -m "chore: transplant built-in SuSFS kernel tree from upstream/builtin"
    UPSTREAM_BRANCH="${TARGET_BRANCH}"
else
    echo ">>> 3. Stable mode active: Calculating exact upstream anchor commit via merge-base..."
    
    # Mathematically finds the divergence point on main, bypassing the local transplant commit
    UPSTREAM_HASH=$(git merge-base HEAD FETCH_HEAD)
    echo "  -> Found mathematically true upstream anchor: ${UPSTREAM_HASH:0:7}"
    
    # Export it so fetch_manager.sh can use it in the exact-match API hunt later
    echo "UPSTREAM_HASH=$UPSTREAM_HASH" >> $GITHUB_ENV
    UPSTREAM_BRANCH="${KSU_VARIANT_REF}"
fi

# 6. Calculate the official counts EXACTLY from the rock-solid hash
CALCULATED_COUNT=$(git rev-list --count "${UPSTREAM_HASH}" 2>/dev/null || echo "11950")
CALCULATED_TAG=$(git describe --tags --abbrev=0 "${UPSTREAM_HASH}" 2>/dev/null || echo "v0.0.0")

echo ">>> Auditing and applying universal SukiSU-Ultra hotfixes..."

# Fix #1: Lock kernel/Makefile version & SHA macros to exact UPSTREAM_HASH for offline Kleaf sandbox
if [ -f "kernel/Makefile" ] && grep -q 'rev-list --count $(REPO_BRANCH)' kernel/Makefile; then
    sed -i "s/rev-list --count \$(REPO_BRANCH)/rev-list --count ${UPSTREAM_HASH}/g" kernel/Makefile
    sed -i "s/rev-parse --short=8 HEAD/rev-parse --short=8 ${UPSTREAM_HASH}/g" kernel/Makefile
    sed -i 's/LOCAL_COUNT     := $(if $(GITHUB_COMMITS),$(GITHUB_COMMITS),$(git_commit_count))/LOCAL_COUNT     := $(git_commit_count)/g' kernel/Makefile
    echo "  [+] APPLIED Fix #1: Locked kernel/Makefile version calculation to anchor ${UPSTREAM_HASH:0:7}."
else
    echo "  [i] SKIPPED Fix #1: kernel/Makefile version calculation already locked or not present."
fi

# Fix #2: Safety check for MLS CEXPR_L2H2 constraint typo (scontext -> tcontext in selinux_hide.c)
if [ -f "kernel/feature/selinux_hide.c" ] && grep -A 1 "case CEXPR_L2H2:" kernel/feature/selinux_hide.c | grep -q "scontext->range.level\[0\]"; then
    sed -i '/case CEXPR_L2H2:/{n;s/scontext->range.level\[0\]/tcontext->range.level[0]/;}' kernel/feature/selinux_hide.c
    echo "  [+] APPLIED Fix #2: Corrected CEXPR_L2H2 MLS range check from scontext to tcontext (selinux_hide.c)."
else
    echo "  [i] SKIPPED Fix #2: CEXPR_L2H2 scontext bug not found in selinux_hide.c."
fi

# Fix #3: SukiSU-Ultra LSM Hook API Fix for Linux 6.12+ (sed version)
echo ">>> Auditing LSM hook compatibility for BASE_VER: ${BASE_VER}..."
if [ "${BASE_VER}" = "6.12" ]; then
    LSM_HOOK_FILE="kernel/hook/lsm_hook.c"

    if [ -f "$LSM_HOOK_FILE" ] && grep -q 'security_add_hooks(ksu_hooks, ARRAY_SIZE(ksu_hooks), "ksu");' "$LSM_HOOK_FILE"; then
        echo "  -> Linux 6.12 branch detected. Patching security_add_hooks using sed..."
        
        # 1. Replace the string literal pointer "ksu" with the address of our struct lsm_id
        sed -i 's/security_add_hooks(ksu_hooks, ARRAY_SIZE(ksu_hooks), "ksu");/security_add_hooks(ksu_hooks, ARRAY_SIZE(ksu_hooks), \&ksu_lsmid);/g' "$LSM_HOOK_FILE"

        # 2. Inject the static struct lsm_id definition right above the ks_lsm_hook_init function call
        sed -i '/void __init ksu_lsm_hook_init(void)/ {
            n
            a\    static const struct lsm_id ksu_lsmid = {\n        .name = "ksu",\n        .id = 0,\n    };
        }' "$LSM_HOOK_FILE"

        echo "  [+] Successfully patched lsm_hook.c via sed."
    else
        echo "  [i] lsm_hook.c already patched or file not found."
    fi
else
    echo "  -> BASE_VER is ${BASE_VER}. Legacy LSM string hook is compatible. Skipping patch."
fi

if ! git diff --quiet; then
    git add .
    git commit -am "Hotfixes applied"
fi

cd ..

echo "  -> Target Tag: $CALCULATED_TAG"
echo "  -> Target Hash: $UPSTREAM_HASH"
echo "  -> Target Count: $CALCULATED_COUNT"
echo ">>> SukiSU-Ultra integration complete."
