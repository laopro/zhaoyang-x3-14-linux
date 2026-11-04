#!/bin/bash
# zhaoyang-x3-14-linux -- uninstaller. Reverts everything install.sh does.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run as root (sudo ./uninstall.sh)" >&2; exit 1; }

KEEP_LOG=1
[ "${1:-}" = "--purge-log" ] && KEEP_LOG=0

echo "==> removing files"
rm -fv /etc/udev/rules.d/90-zhaoyang-power.rules \
       /etc/modprobe.d/zhaoyang-power.conf \
       /usr/local/lib/zhaoyang-power/aspm-r8169-fix.sh \
       /usr/lib/systemd/system-sleep/s0ix-drain \
       /lib/systemd/system-sleep/s0ix-drain 2>/dev/null || true
rmdir /usr/local/lib/zhaoyang-power 2>/dev/null || true
[ "$KEEP_LOG" = 0 ] && rm -fv /var/log/s0ix-drain.log

echo "==> reloading udev rules"
udevadm control --reload

echo "==> restoring driver default (ASPM off) on the live device"
for d in /sys/bus/pci/devices/*; do
    [ -r "$d/vendor" ] && [ -r "$d/device" ] || continue
    [ "$(cat "$d/vendor")" = "0x10ec" ] || continue
    [ "$(cat "$d/device")" = "0x8168" ] || continue
    for f in l1_2_aspm l1_1_aspm l1_aspm l1_2_pcipm l1_1_pcipm; do
        [ -w "$d/link/$f" ] && echo 0 > "$d/link/$f" || true
    done
    echo "    $(basename "$d"): ASPM L1.x disabled"
done

echo
echo "Done. Reboot to fully restore defaults (runtime PM and modprobe options)."
[ "$KEEP_LOG" = 1 ] && echo "Kept /var/log/s0ix-drain.log (use --purge-log to remove)."
