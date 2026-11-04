#!/bin/bash
# zhaoyang-x3-14-linux -- installer
# Distro-agnostic (udev + modprobe + systemd-sleep), but HARDWARE-SPECIFIC:
# it refuses to run on anything other than a Lenovo ZhaoYang X3-14 IRL (83GX).
set -euo pipefail

SUPPORTED_MODELS="83GX"
SUPPORTED_FAMILY="ZhaoYang X3-14 IRL"
DMI=/sys/class/dmi/id
SRC="$(cd "$(dirname "$0")" && pwd)"

DO_MODPROBE=1; DO_TOOLS=1; FORCE=0
for a in "$@"; do case "$a" in
    --no-modprobe) DO_MODPROBE=0 ;;
    --no-tools)    DO_TOOLS=0 ;;
    --force)       FORCE=1 ;;
    -h|--help) sed -n '2,6p' "$0"; echo
        echo "Usage: sudo ./install.sh [--no-modprobe] [--no-tools] [--force]"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
esac; done

die() { echo "error: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die "run as root (sudo ./install.sh)"

# ---------------------------------------------------------------- hardware
vendor=$(cat "$DMI/sys_vendor" 2>/dev/null || true)
model=$(cat "$DMI/product_name" 2>/dev/null || true)
family=$(cat "$DMI/product_family" 2>/dev/null || true)

match=0
[ "$vendor" = "LENOVO" ] || match=-1
if [ "$match" = 0 ]; then
    for m in $SUPPORTED_MODELS; do [ "$model" = "$m" ] && match=1; done
    [ "$family" = "$SUPPORTED_FAMILY" ] && match=1
fi

if [ "$match" != 1 ]; then
    echo
    echo "  This machine is not a supported model."
    echo "    vendor : ${vendor:-unknown}"
    echo "    model  : ${model:-unknown}"
    echo "    family : ${family:-unknown}"
    echo
    echo "  Supported: LENOVO / $SUPPORTED_MODELS / $SUPPORTED_FAMILY"
    echo
    echo "  This is NOT a generic Realtek or Linux power fix. It re-enables PCIe"
    echo "  ASPM on a NIC where the kernel disables it on purpose, which can cause"
    echo "  packet loss or link drops on other boards and chip revisions."
    echo
    if [ "$FORCE" != 1 ]; then
        echo "  Refusing to install. See the README if you believe your machine is the"
        echo "  same board under a different SKU; --force overrides this check."
        exit 1
    fi
    echo "  --force given: installing anyway. You are on your own."
    echo
fi

# ---------------------------------------------------------------- locate sleep dir
SLEEPDIR=""
for d in /usr/lib/systemd/system-sleep /lib/systemd/system-sleep; do
    [ -d "$d" ] && SLEEPDIR="$d" && break
done

echo "==> installing ASPM helper"
install -d -m 755 /usr/local/lib/zhaoyang-power
install -m 755 "$SRC/lib/aspm-r8169-fix.sh" /usr/local/lib/zhaoyang-power/

echo "==> installing udev rules"
install -d -m 755 /etc/udev/rules.d
install -m 644 "$SRC/udev/90-zhaoyang-power.rules" /etc/udev/rules.d/

if [ "$DO_MODPROBE" = 1 ]; then
    echo "==> installing modprobe options"
    install -d -m 755 /etc/modprobe.d
    install -m 644 "$SRC/modprobe/zhaoyang-power.conf" /etc/modprobe.d/
fi

if [ "$DO_TOOLS" = 1 ]; then
    if [ -n "$SLEEPDIR" ]; then
        echo "==> installing s0ix-drain measurement hook ($SLEEPDIR)"
        install -m 755 "$SRC/tools/s0ix-drain" "$SLEEPDIR/"
    else
        echo "==> skipping s0ix-drain: no systemd-sleep directory found"
    fi
fi

# ---------------------------------------------------------------- apply now
echo "==> reloading udev rules"
udevadm control --reload

echo "==> applying ASPM fix to the live device"
applied=0
for d in /sys/bus/pci/devices/*; do
    [ -r "$d/vendor" ] && [ -r "$d/device" ] || continue
    [ "$(cat "$d/vendor")" = "0x10ec" ] || continue
    [ "$(cat "$d/device")" = "0x8168" ] || continue
    /usr/local/lib/zhaoyang-power/aspm-r8169-fix.sh "$d" || true
    if [ -r "$d/link/l1_2_aspm" ] && [ "$(cat "$d/link/l1_2_aspm")" = "1" ]; then
        echo "    $(basename "$d"): L1.2 enabled"
        applied=1
    fi
done
[ "$applied" = 1 ] || echo "    no matching NIC changed (already set, or not present)"

echo
echo "Done."
if [ "$DO_MODPROBE" = 1 ]; then
    echo
    echo "The spd5118 blacklist needs the initramfs rebuilt if that module is"
    echo "included in yours. Run whichever applies to your distro:"
    echo "    dracut --force                 # Fedora, RHEL, openSUSE"
    echo "    update-initramfs -u            # Debian, Ubuntu"
    echo "    mkinitcpio -P                  # Arch"
fi
echo
echo "Verify after the next suspend:"
echo "    cat /var/log/s0ix-drain.log"
echo "    cat /sys/bus/pci/devices/*/link/l1_2_aspm"
