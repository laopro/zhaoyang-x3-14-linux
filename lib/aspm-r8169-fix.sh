#!/bin/sh
# Re-enable PCIe ASPM L1.x on the RTL8168h so the platform can reach S0ix.
# Part of: zhaoyang-x3-14-linux  (Lenovo ZhaoYang X3-14 IRL / 83GX ONLY)
#
# Double-gated on purpose, because benefit and risk have different scope:
#   - the BENEFIT is platform-specific (this board's Intel S0ix path)
#   - the RISK is chip-specific (ASPM breaks some RTL8168 revisions)
# On any other hardware this exits without touching a thing.
#
# Called from udev with the device's sysfs path as $1.

DEV="$1"
DMI=/sys/class/dmi/id

SUPPORTED_MODELS="83GX"
SUPPORTED_FAMILY="ZhaoYang X3-14 IRL"
SUPPORTED_REVISION="0x15"       # RTL8168h/8111h, XID 541

# --- gate 1: chassis ---
[ "$(cat "$DMI/sys_vendor" 2>/dev/null)" = "LENOVO" ] || exit 0

model=$(cat "$DMI/product_name" 2>/dev/null)
family=$(cat "$DMI/product_family" 2>/dev/null)
ok=0
for m in $SUPPORTED_MODELS; do
    [ "$model" = "$m" ] && ok=1
done
[ "$family" = "$SUPPORTED_FAMILY" ] && ok=1
[ "$ok" = 1 ] || exit 0

# --- gate 2: NIC revision ---
[ -r "$DEV/revision" ] || exit 0
[ "$(cat "$DEV/revision")" = "$SUPPORTED_REVISION" ] || exit 0

# --- apply ---
cd "$DEV/link" 2>/dev/null || exit 0
for f in l1_aspm l1_1_aspm l1_2_aspm l1_1_pcipm l1_2_pcipm; do
    [ -w "$f" ] && echo 1 > "$f"
done
exit 0
