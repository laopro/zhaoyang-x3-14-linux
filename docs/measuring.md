# Measuring and verifying the fix

This page explains how to check, with numbers, that the fix works on your
machine. The measurement is not exposed by any standard tool, so this is the
only place it is documented.

## What "working" means

Three things have to be true at the same time:

| Check | Command | Good value |
|---|---|---|
| ASPM is enabled on the NIC | `cat /sys/bus/pci/devices/0000:02:00.0/link/l1_2_aspm` | `1` |
| The platform reaches deep idle | `cat /sys/devices/system/cpu/cpuidle/low_power_idle_system_residency_us` (cumulative µs since boot) | grows during suspend |
| Suspend drain is low | `/var/log/s0ix-drain.log` | `avg` ≈ 0.35–0.40 W, `S0ix` ≥ 99 % |

The second check is the decisive one. `S0ix` is the share of the suspend
spent in the deep state. If it is near 0 %, the fix is not working, whatever
the battery says.

## Where the numbers come from

`tools/s0ix-drain` is a systemd-sleep hook. It runs on every suspend and
resume and appends one line to `/var/log/s0ix-drain.log`:

```
2026-11-10 09:32:45  slept=11.19 h  drain=3.780 Wh  avg=0.338 W  %/h=0.75  S0ix=99.9%
```

- `slept`: wall-clock time between the two hooks.
- `drain`: change in `energy_now` of the battery (`/sys/class/power_supply/BAT*`), in Wh.
- `avg`: `drain / slept`.
- `%/h`: `avg` as a percentage of `energy_full` per hour.
- `S0ix`: delta of the residency counter divided by `slept`.

The battery reports energy in 10 mWh steps, so any suspend shorter than about
an hour is dominated by rounding. Ignore those lines.

## How to read the log

Keep only rows that meet all of these:

1. `slept` is at least **0.5 h**, ideally several hours.
2. The laptop was on battery the whole time. Rows with `drain` ≤ 0 or
   `avg` ≤ 0 mean the charger was connected and energy went **up**. They are
   not measurements. Check `cat /sys/class/power_supply/ADP0/online` (1 =
   charger connected) and ignore rows recorded while it was 1.
3. `S0ix` is above 99 %.

Good result: `avg` between 0.33 and 0.40 W, `S0ix` 99.8–99.9 %.

Rows that look wrong and are not:

- Very short suspends (under 2 min) show huge `avg` values such as 0.68,
  1.44 or 12 W. This is rounding plus the time spent entering and leaving
  the suspend.
- Zero drain on a 100 % battery means the charger was connected.

## Step by step, on a fresh install

1. Confirm the fix is active before suspending:

   ```bash
   cat /sys/bus/pci/devices/0000:02:00.0/link/l1_2_aspm   # expect 1
   ls /usr/lib/systemd/system-sleep/s0ix-drain            # hook installed
   ```

2. Unplug the charger. Start with the battery at 60 % or more so the
   reading is not affected by low-battery behaviour.

3. Suspend for a long period. A full night is best.

4. Wake up and read the log:

   ```bash
   tail -5 /var/log/s0ix-drain.log
   ```

5. Check the residency counter directly. It should have increased by roughly
   the suspend length:

   ```bash
   cat /sys/devices/system/cpu/cpuidle/low_power_idle_system_residency_us
   ```

If the log shows `S0ix` near 0 % for long suspends, run `sudo ./uninstall.sh`
and then `sudo ./install.sh` again, and check that `l1_2_aspm` is `1`.

## Baseline for comparison

Without the fix, on this machine, the same hook logs `S0ix=0.0 %` and about
2.5 W while suspended. The gap between those two numbers is the whole
improvement.

## Known gaps in the hook

- It does not check whether the charger is connected during the suspend. A
  suspend while charging produces rows with negative drain. Filter them as
  described above.
- It only records the battery it finds first in `/sys/class/power_supply/`.
  Machines with two batteries are not handled.
