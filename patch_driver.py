#!/usr/bin/env python3
import sys
import os
import glob

def find_file(target_dir, filename, subdirs=None):
    """Finds a file in target_dir or in one of the subdirs."""
    if os.path.exists(os.path.join(target_dir, filename)):
        return os.path.join(target_dir, filename)
    if subdirs:
        for sd in subdirs:
            path = os.path.join(target_dir, sd, filename)
            if os.path.exists(path):
                return path
    return None

def patch_file(filepath):
    print(f"Patching {filepath}...")
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()

    # Normalize line endings to LF
    content = content.replace('\r\n', '\n')

    # Patch 1: set_wiphy_params
    target1 = "static int cfg80211_rtw_set_wiphy_params(struct wiphy *wiphy, u32 changed)"
    replacement1 = """#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 1, 0))
static int cfg80211_rtw_set_wiphy_params(struct wiphy *wiphy, int changed_param, u32 changed)
#else
static int cfg80211_rtw_set_wiphy_params(struct wiphy *wiphy, u32 changed)
#endif"""
    if target1 in content:
        content = content.replace(target1, replacement1)
        print("  - Applied set_wiphy_params patch")

    # Patch 2: set_txpower
    target2 = """static int cfg80211_rtw_set_txpower(struct wiphy *wiphy,
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(3, 8, 0))
	struct wireless_dev *wdev,
#endif
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(2, 6, 36)) || defined(COMPAT_KERNEL_RELEASE)
	enum nl80211_tx_power_setting type, int mbm)"""

    replacement2 = """static int cfg80211_rtw_set_txpower(struct wiphy *wiphy,
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(3, 8, 0))
	struct wireless_dev *wdev,
#endif
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 1, 0))
	int link_id,
#endif
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(2, 6, 36)) || defined(COMPAT_KERNEL_RELEASE)
	enum nl80211_tx_power_setting type, int mbm)"""

    if target2 in content:
        content = content.replace(target2, replacement2)
        print("  - Applied set_txpower patch")
    else:
        target2_var = target2.replace('\t', '    ')
        if target2_var in content:
            content = content.replace(target2_var, replacement2)
            print("  - Applied set_txpower patch (spaces variant)")

    # Patch 3: get_txpower (supporting both versions of the body)
    target3_original = """static int cfg80211_rtw_get_txpower(struct wiphy *wiphy,
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(3, 8, 0))
	struct wireless_dev *wdev,
#endif
	int *dbm)
{
	_adapter *padapter = wiphy_to_adapter(wiphy);

	*dbm = padapter->mppriv.txpoweridx;

	return 0;
}"""

    replacement3_original = """static int cfg80211_rtw_get_txpower(struct wiphy *wiphy,
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(3, 8, 0))
	struct wireless_dev *wdev,
#endif
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 1, 0))
	int link_id, unsigned int type,
#endif
	int *dbm)
{
	_adapter *padapter = wiphy_to_adapter(wiphy);

	*dbm = padapter->mppriv.txpoweridx;

	return 0;
}"""

    target3_other = """static int cfg80211_rtw_get_txpower(struct wiphy *wiphy,
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(3, 8, 0))
	struct wireless_dev *wdev,
#endif
	int *dbm)
{
	_adapter *padapter = wiphy_to_adapter(wiphy);
	HAL_DATA_TYPE *pHalData = GET_HAL_DATA(padapter);

	RTW_INFO("%s\\n", __func__);

	// *dbm = (12);
	*dbm = pHalData->CurrentTxPwrIdx;

	return 0;
}"""

    replacement3_other = """static int cfg80211_rtw_get_txpower(struct wiphy *wiphy,
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(3, 8, 0))
	struct wireless_dev *wdev,
#endif
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 1, 0))
	int link_id, unsigned int type,
#endif
	int *dbm)
{
	_adapter *padapter = wiphy_to_adapter(wiphy);
	HAL_DATA_TYPE *pHalData = GET_HAL_DATA(padapter);

	RTW_INFO("%s\\n", __func__);

	// *dbm = (12);
	*dbm = pHalData->CurrentTxPwrIdx;

	return 0;
}"""

    if target3_original in content:
        content = content.replace(target3_original, replacement3_original)
        print("  - Applied get_txpower patch (original variant)")
    elif target3_original.replace('\t', '    ') in content:
        content = content.replace(target3_original.replace('\t', '    '), replacement3_original)
        print("  - Applied get_txpower patch (original spaces variant)")
    elif target3_other in content:
        content = content.replace(target3_other, replacement3_other)
        print("  - Applied get_txpower patch (other variant)")
    elif target3_other.replace('\t', '    ') in content:
        content = content.replace(target3_other.replace('\t', '    '), replacement3_other)
        print("  - Applied get_txpower patch (other spaces variant)")

    # Patch 4: set_monitor_channel
    target4 = """static int cfg80211_rtw_set_monitor_channel(struct wiphy *wiphy
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(3, 8, 0))
	, struct cfg80211_chan_def *chandef
#else
	, struct ieee80211_channel *chan
	, enum nl80211_channel_type channel_type
#endif
)
{
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(3, 8, 0))
	struct ieee80211_channel *chan = chandef->chan;
#endif"""

    replacement4 = """static int cfg80211_rtw_set_monitor_channel(struct wiphy *wiphy
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 3, 0))
	, struct net_device *ndev
	, struct cfg80211_chan_def *chandef
#elif (LINUX_VERSION_CODE >= KERNEL_VERSION(3, 8, 0))
	, struct cfg80211_chan_def *chandef
#else
	, struct ieee80211_channel *chan
	, enum nl80211_channel_type channel_type
#endif
)
{
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 3, 0))
	struct ieee80211_channel *chan = chandef->chan;
#elif (LINUX_VERSION_CODE >= KERNEL_VERSION(3, 8, 0))
	struct ieee80211_channel *chan = chandef->chan;
#endif"""

    if target4 in content:
        content = content.replace(target4, replacement4)
        print("  - Applied set_monitor_channel patch")
    else:
        target4_var = target4.replace('\t', '    ')
        if target4_var in content:
            content = content.replace(target4_var, replacement4)
            print("  - Applied set_monitor_channel patch (spaces variant)")

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    print("Patching completed.")

def patch_makefile(makefile_path):
    print(f"Patching {makefile_path}...")
    with open(makefile_path, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()

    # Comment out old ccflags-y declarations at the top of the file to prevent recursion/looping
    old_ccflags_decl = """ccflags-y += $(EXTRA_CFLAGS)
ccflags-y += -I$(src) -isystem $(src) -Wno-quoted-include-in-angled-header -Wno-error=quoted-include-in-angled-header"""
    
    old_ccflags_decl_alt = """ccflags-y += $(EXTRA_CFLAGS)
ccflags-y += -I$(src) -isystem $(src)"""
    
    if old_ccflags_decl in content:
        commented = "\n".join(["# " + line for line in old_ccflags_decl.splitlines()])
        content = content.replace(old_ccflags_decl, commented)
        print("  - Commented out ccflags-y at the top of Makefile")
    elif old_ccflags_decl_alt in content:
        commented = "\n".join(["# " + line for line in old_ccflags_decl_alt.splitlines()])
        content = content.replace(old_ccflags_decl_alt, commented)
        print("  - Commented out ccflags-y (alt) at the top of Makefile")

    # Add the clean, non-recursive ccflags-y definition right before SUBARCH := ...
    subarch_decl = "SUBARCH := $(shell uname -m"
    # The quoted-include warning only exists in clang (CachyOS kernels are clang-built);
    # GCC-built kernels reject the unknown -Wno-error= option, so add it for clang only
    new_ccflags = """ccflags-y := $(EXTRA_CFLAGS)
ccflags-y += -I$(src) -isystem $(src)
ccflags-y += $(if $(CONFIG_CC_IS_CLANG),-Wno-quoted-include-in-angled-header -Wno-error=quoted-include-in-angled-header)

SUBARCH := $(shell uname -m"""

    if subarch_decl in content and "ccflags-y :=" not in content:
        content = content.replace(subarch_decl, new_ccflags)
        print("  - Added clean ccflags-y evaluation before SUBARCH")

    with open(makefile_path, 'w', encoding='utf-8') as f:
        f.write(content)
    print("Makefile patching completed.")

def patch_headers(target_dir):
    # 1. Patch osdep_service_linux.h
    osdep_path = find_file(target_dir, "osdep_service_linux.h", ["include", "os_dep/linux"])
    if osdep_path:
        print(f"Patching {osdep_path}...")
        with open(osdep_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        
        # Normalize line endings
        content = content.replace('\r\n', '\n')
        
        # Include timer.h and declare from_timer wrapper
        if "#include <linux/version.h>" in content and "undef del_timer_sync" not in content:
            # Remove any previous partial patch if it was applied
            content = content.replace("""#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 16, 0)
#ifndef from_timer
#define from_timer timer_container_of
#endif
#endif""", "")
            # Remove the previous attempt at del_timer_sync patch if it exists
            content = content.replace("""#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 15, 0)
#ifndef del_timer_sync
#define del_timer_sync timer_delete_sync
#endif
#ifndef del_timer
#define del_timer timer_delete
#endif
#endif""", "")
            if "#include <linux/timer.h>" in content:
                content = content.replace("#include <linux/timer.h>\n", "")
                content = content.replace("#include <linux/timer.h>", "")
            
            replacement = """#include <linux/version.h>
#include <linux/timer.h>

#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 15, 0)
#undef del_timer_sync
#define del_timer_sync timer_delete_sync
#undef del_timer
#define del_timer timer_delete
#endif

#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 16, 0)
#ifndef from_timer
#define from_timer timer_container_of
#endif
#endif"""
            content = content.replace("#include <linux/version.h>", replacement)
            print("  - Added timer/delete compatibility patch to osdep_service_linux.h")
            with open(osdep_path, 'w', encoding='utf-8') as f:
                f.write(content)

    # 2. Patch rtw_security.h to rename sha256_* functions
    security_path = find_file(target_dir, "rtw_security.h", ["include", "core"])
    if security_path:
        print(f"Patching {security_path}...")
        with open(security_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            
        if "struct sha256_state_rtk" in content and "rtw_sha256_init" not in content:
            replacement = """#define sha256_init rtw_sha256_init
#define sha256_process rtw_sha256_process
#define sha256_done rtw_sha256_done
#define sha256_vector rtw_sha256_vector
#define sha256_compress rtw_sha256_compress
#define sha256_prf rtw_sha256_prf

struct sha256_state_rtk"""
            content = content.replace("struct sha256_state_rtk", replacement)
            print("  - Added sha256 rename macros to rtw_security.h")
            with open(security_path, 'w', encoding='utf-8') as f:
                f.write(content)

    # 3. Patch rtw_debug.h for RTW_LOG_LEVEL fallback when debug is disabled
    debug_path = find_file(target_dir, "rtw_debug.h", ["include", "core"])
    if debug_path:
        print(f"Patching {debug_path}...")
        with open(debug_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            
        if "#ifdef CONFIG_RTW_DEBUG" in content and "RTW_LOG_LEVEL" not in content[:content.find("#ifdef CONFIG_RTW_DEBUG")]:
            replacement = """#ifndef CONFIG_RTW_DEBUG
#ifndef RTW_LOG_LEVEL
#define RTW_LOG_LEVEL 0
#endif
#ifndef rtw_drv_log_level
#define rtw_drv_log_level 0
#endif
#endif

#ifdef CONFIG_RTW_DEBUG"""
            content = content.replace("#ifdef CONFIG_RTW_DEBUG", replacement)
            print("  - Added debug level fallbacks to rtw_debug.h")
            with open(debug_path, 'w', encoding='utf-8') as f:
                f.write(content)

    # 4. Patch platform_aml_s905_sdio.h (if present)
    platform_path = find_file(target_dir, "platform_aml_s905_sdio.h", ["platform"])
    if platform_path:
        print(f"Patching {platform_path}...")
        with open(platform_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        if '#include "version.h"' in content:
            content = content.replace('#include "version.h"', '#include <linux/version.h>')
            print("  - Replaced #include \"version.h\" with <linux/version.h> in platform header")
            with open(platform_path, 'w', encoding='utf-8') as f:
                f.write(content)

def main():
    if len(sys.argv) > 1:
        target_dir = sys.argv[1]
    else:
        src_dirs = glob.glob('/usr/src/8188eu-*')
        if not src_dirs:
            print("No driver directory found in /usr/src/8188eu-*")
            sys.exit(1)
        target_dir = src_dirs[0]

    # Find ioctl_cfg80211.c
    file_to_patch = find_file(target_dir, "ioctl_cfg80211.c", ["os_dep/linux"])
    if not file_to_patch:
        print(f"File not found: ioctl_cfg80211.c in {target_dir}")
        sys.exit(1)

    patch_file(file_to_patch)

    # Find Makefile
    makefile_to_patch = os.path.join(target_dir, "Makefile")
    if os.path.exists(makefile_to_patch):
        patch_makefile(makefile_to_patch)

    # Patch headers
    patch_headers(target_dir)

if __name__ == "__main__":
    main()
