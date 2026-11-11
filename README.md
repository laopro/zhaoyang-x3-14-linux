# zhaoyang-x3-14-linux

S0ix (modern standby) and battery fixes for the **Lenovo ZhaoYang X3-14 IRL**
on Linux.

*[Léeme en español](README.es.md)*

> ### ⚠️ Scope
>
> **This is for one laptop model only: Lenovo ZhaoYang X3-14 IRL, `product_name` `83GX`.**
>
> It works on **any Linux distribution** — Fedora, Arch, Debian, Ubuntu,
> openSUSE, whatever — because it is only udev rules, modprobe options and a
> systemd-sleep hook. Nothing here is distro-specific.
>
> But it is **not** a generic Realtek fix, and **not** a general Linux power
> tweak. It deliberately reverts a safety decision the kernel makes, and that
> decision is correct on other hardware. `install.sh` refuses to run on
> anything else, on purpose. See [Risk](#risk).

Check whether this repo is for your machine:

```bash
cat /sys/class/dmi/id/product_name    # expect: 83GX
cat /sys/class/dmi/id/product_family  # expect: ZhaoYang X3-14 IRL
```

---

## The problem

Out of the box, this laptop **never enters S0ix**. It suspends and resumes
correctly, everything works — it just burns battery as if it were awake. That
is what makes it easy to miss: there is no visible symptom, only a flat
battery in the morning.

Measured S0ix residency before the fix: **0 %**.

## The cause

On Intel Alder Lake-U, S0ix entry is a chain where every link must hold:

```
all PCIe links reach L1.2
        ↓
the PCH can drop to PC8/PC9/PC10
        ↓
SLP_S0# is asserted
        ↓
real S0ix  (~0.35 W)
```

If **one** PCIe link stays up, the whole chain collapses and the machine sits
in a fake suspend: the CPU is halted but the chipset stays powered, drawing
roughly **2.5 W** instead of 0.35 W.

The blocker on this board is the **Realtek RTL8168h** (`02:00.0`, the wired
ethernet). The `r8169` driver **disables ASPM on purpose** for this chip —
there is real documented errata where ASPM causes packet loss and NIC hangs on
some board and BIOS combinations. It is a conservative driver decision that
trades power for stability.

The side effect on this laptop is that the NIC's root port never reaches L1.2,
so the package never gets past PC3, so `SLP_S0` is never asserted — and the
entire platform loses modern standby because of one network card that, on a
laptop, usually has no cable in it.

## The fix

A udev rule re-enables ASPM L1/L1.1/L1.2 **after** the driver binds — ordering
matters, since `r8169` turns it off as it loads. Runtime power management is
also set to `auto` for PCI devices, which is what `powertop` reports as *Bad*
by default.

Two optional cleanups, neither related to S0ix: the HDA codec powers down
after 1 s instead of 10 s, and `spd5118` (the DDR5 SPD temperature sensor,
which fails with `-6` on every resume on this board) is blacklisted.

## Results

Measured on a Lenovo 83GX, i3-1315U, 45.76 Wh battery, Fedora 44:

| | Before | After |
|---|---|---|
| S0ix residency | 0 % | **99.9 %** |
| Suspend power | ~2.5 W | **0.358 W** |
| Drain per hour asleep | — | **0.78 %/h** |
| Package power, awake idle | 2.68 W | 2.04 W |

Two independent suspends, of deliberately different lengths, agreeing to
within 1 %:

```
slept=2.31 h  drain=0.820 Wh  avg=0.354 W  %/h=0.77  S0ix=99.9%
slept=5.31 h  drain=1.900 Wh  avg=0.358 W  %/h=0.78  S0ix=99.9%
```

That agreement is the point. It rules out wakeups accumulating over longer
sleeps, rules out a drain that degrades with time, and rules out an artifact
of the embedded controller's coarse reporting. In practice: **≈5.3 days** of
standby, **6 %** over an 8-hour night, **38 %** over a 48-hour weekend.

## Install

```bash
git clone https://github.com/laopro/zhaoyang-x3-14-linux
cd zhaoyang-x3-14-linux
sudo ./install.sh
```

Options: `--no-modprobe` (skip the audio and spd5118 cleanups), `--no-tools`
(skip the measurement hook), `--force` (override the hardware check — read
[Risk](#risk) first).

If you keep the `spd5118` blacklist, rebuild your initramfs if that module is
included in yours: `dracut --force`, `update-initramfs -u` or `mkinitcpio -P`.

## Verify

Close the lid, leave it for **at least an hour**, then:

```bash
cat /var/log/s0ix-drain.log
```

An hour is not an arbitrary suggestion. The embedded controller only reports
whole-percent capacity, and 1 % is ~0.46 Wh on this battery — so a short
suspend drains less than the sensor can resolve and you get a meaningless
number. The included hook reads `energy_now` directly on each side of the
suspend, which is finer, but it still needs enough elapsed time.

Live ASPM state:

```bash
cat /sys/bus/pci/devices/0000:02:00.0/link/l1_2_aspm   # expect: 1
```

## Risk

**Read this before using `--force`.**

The `r8169` driver disables ASPM on the RTL8168 family because of real
hardware errata. This repo re-enables it. On this board it works, and the
measurements above are honest — but there is an important gap in that
evidence:

> **Wired ethernet has now been tested with the cable connected.** At 100
> packets/s for 60 s, ASPM on and off both showed 0 % loss and no NIC errors.
> See [docs/ethernet-test.md](docs/ethernet-test.md). A flood ping showed 39 %
> loss with ASPM on that is not explained yet, and sustained TCP throughput has
> not been tested.

If your wired ethernet starts dropping packets, flapping or stalling, this
repo is the first thing to suspect, not the last. Test instantly:

```bash
echo 0 | sudo tee /sys/bus/pci/devices/0000:02:00.0/link/l1_2_aspm
```

If that fixes it, `sudo ./uninstall.sh` and open an issue with your
`product_name`, the NIC `revision`, and what you saw.

The gates exist for this reason. `10ec:8168` is the most common Realtek GbE
PCI id in existence — it covers RTL8111/8168/8211/8411 across dozens of chip
revisions, in millions of desktop boards. A rule matching only on that id
would fire on all of them. So the udev match merely selects *which* device to
ask about; the helper script decides *whether* to act, after checking DMI and
the chip revision (`0x15`, XID 541).

## Uninstall

```bash
sudo ./uninstall.sh            # add --purge-log to drop the measurement log
```

## Same board, different SKU?

The ZhaoYang line is rebadged across markets, so the same board
(`LNVNB161216`) may ship under another `product_name`. If your DMI differs but
the hardware is the same, add your SKU to `SUPPORTED_MODELS` in both
`install.sh` and `lib/aspm-r8169-fix.sh`, confirm your NIC reports
`revision` `0x15`, and please open a PR with your DMI strings and your
`s0ix-drain.log` — more than one unit's worth of data is genuinely useful.

## Why not a kernel patch?

Because the right fix upstream is not obvious, and the evidence here is not
sufficient for one. Re-enabling ASPM in `r8169` is one of the most-reverted
areas of the networking tree: it gets enabled, breaks for a subset of users,
and gets restricted again. A patch based on one laptop with an unplugged
cable would rightly be rejected.

What *is* underdocumented upstream is the **power cost** of that decision —
plenty of people know ASPM is off on these NICs; few have measured that it
costs the platform its entire modern standby. That is worth reporting to
`netdev` as data, not as a patch. Meanwhile, a udev rule is the correct place
for a policy the kernel cannot safely assume for everyone.

## Files

| Path | Purpose |
|---|---|
| `udev/90-zhaoyang-power.rules` | triggers the ASPM fix on driver bind; PCI runtime PM |
| `lib/aspm-r8169-fix.sh` | DMI- and revision-gated ASPM re-enable |
| `modprobe/zhaoyang-power.conf` | HDA codec power save; `spd5118` blacklist |
| `tools/s0ix-drain` | systemd-sleep hook, logs drain and S0ix per suspend |
| `docs/diagnosis.md` | how this was traced, and how to re-diagnose it |

## Known limitations

- **The panel has no PSR.** Runtime PC10/DC5-6 are therefore impossible, so
  runtime S0ix with the lid open stays at 0 %. This is silicon, not
  configuration, and no amount of tuning changes it. Suspend is unaffected.
- **`ucsi_acpi` adds ~1.1 s to resume** (an EC timeout). Consistent across
  every suspend. It is latency, not power.
- **`snd_hda_intel power_save=1` may read back as `10`.** Some distros,
  Fedora among them, override it at runtime from their own rules. The
  difference is a few mW; not worth fighting.

## License

MIT. See [LICENSE](LICENSE).

## Measuring it

See [docs/measuring.md](docs/measuring.md) for how to check the fix and read `s0ix-drain.log`.
