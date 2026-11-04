# Diagnosis

How the S0ix blocker on this board was traced, and how to re-diagnose it if it
ever comes back. Nothing here is specific to a distribution.

## 1. Confirm the machine actually suspends to s2idle

```bash
cat /sys/power/mem_sleep          # expect: [s2idle]
```

This laptop has no S3. `(supports S0 S4 S5)` in `dmesg` confirms firmware only
offers S0ix, so if S0ix fails there is no deep-sleep fallback — you get a fake
suspend at ~2.5 W and no warning about it.

## 2. Measure S0ix residency

Two counters, either works:

```bash
# no root needed
cat /sys/devices/system/cpu/cpuidle/low_power_idle_system_residency_us

# root needed, same information
sudo cat /sys/kernel/debug/pmc_core/slp_s0_residency_usec
```

Both are **cumulative microseconds since boot**. To get a residency
percentage, read before suspending and after resuming, and divide the delta by
the elapsed wall-clock time. `tools/s0ix-drain` does exactly this
automatically.

A reading of `0` after a long suspend means S0ix was never entered. That is
the symptom.

## 3. Find which device blocks it

```bash
sudo cat /sys/kernel/debug/pmc_core/substate_residencies
sudo cat /sys/kernel/debug/pmc_core/package_cstate_show
```

If the package never gets past PC3, something is holding a PCIe link up. Walk
the ASPM state of every device:

```bash
for d in /sys/bus/pci/devices/*/link/l1_2_aspm; do
    echo "$(echo $d | cut -d/ -f6): $(cat $d)"
done
```

On this board the Realtek NIC reports `0` while everything else reports `1`.

## 4. Confirm the culprit

Toggle it by hand and re-measure. If re-enabling L1.2 on that one device turns
residency from 0 % into ~99 %, you have found it:

```bash
cd /sys/bus/pci/devices/0000:02:00.0/link
for f in l1_aspm l1_1_aspm l1_2_aspm l1_1_pcipm l1_2_pcipm; do
    echo 1 | sudo tee $f
done
```

Then suspend for an hour and check the counter again.

## 5. Why the driver did it

`r8169` disables ASPM for this chip family deliberately — documented errata
where ASPM causes packet loss and NIC hangs on certain board and BIOS
combinations. It is not a bug; it is a conservative trade of power for
stability, made for all hardware because the driver cannot tell which boards
are affected.

The ordering consequence matters for the fix: the driver turns ASPM off **as
it binds**, so anything that re-enables it must run *after* bind. A udev rule
on `ACTION=="bind"` is the correct hook. Setting it earlier, or via kernel
command line, gets silently undone.

## 6. Useful cross-checks

```bash
# instantaneous power draw, awake
cat /sys/class/power_supply/BAT*/power_now      # microwatts

# package power, needs root
sudo turbostat --quiet --show PkgWatt --interval 5

# what else is not using runtime PM
sudo powertop --html=/tmp/pt.html

# wakeup sources
cat /proc/acpi/wakeup
```

## 7. The measurement trap

The embedded controller only reports **whole-percent** battery capacity, and
1 % is ~0.46 Wh on the 45.76 Wh pack. `upower`'s history therefore cannot
resolve a short suspend at all: an 11-minute suspend drains far less than one
percentage point, so the number you get is noise, or is dominated by the few
minutes the machine was awake on either side.

Reading `energy_now` directly on each side of the suspend is finer-grained
(10 mWh steps), which is what `tools/s0ix-drain` does — but it still needs
**at least an hour** of suspend before the result means anything.

Finally: take two measurements of deliberately different lengths and check
they agree. If the longer one is worse, something is waking the machine
periodically and you have a different problem to chase.
