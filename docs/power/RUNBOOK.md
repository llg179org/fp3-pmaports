# Power investigation run-book

> ⚠️ **AI-generated.** Maintained by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

**This file is the resume point.** It is rewritten whenever the state changes, so
that a context compaction — or a new session — costs nothing. Read it first, do
what "Next step" says, then update it. Everything else on this page ages out;
the reasoning lives in [`bringup/`](bringup/README.md) and the findings in
[`README.md`](README.md).

## Where the question stands

The search moved three times on 2026-08-14 and landed outside this SoC:

1. *Does a suspend reach the RPM?* — wrong level.
2. *Does anything notify the RPM?* — nothing did; mainline msm8953 described no
   MPM. Added, and the notification demonstrably runs.
3. *Why does the governor never select the deepest cluster state?* — **answered**:
   `genpd_governor_data::cached_power_down_state_idx` is declared `bool`, so a
   cached state index of 2 comes back as 1 and the search, which only walks
   downwards, can never reach index 2 again. Six years old, not msm8953-specific.
   Fixed; `cluster-pc` 0 → 14516 per minute, `system-pc` 0 → 3531. Written up in
   [`README.md`](README.md) under "The real cause".
4. **Current: the RPM still records nothing.** `qcom_stats` `vlow`/`vmin` are 0
   and the APSS master record is all zeros, while the AP now completes a
   system-level power collapse ~47 times a second. The question is now the RPM
   handshake alone.

## Next step

★★★ **Answered: with the display genuinely off, the genpd fix is worth ~9 %.**
Two legs per arm, fresh boot each, 200 samples after a 300 s settle, display gate
enforced: **−119.0 mA with the fix, −130.5 mA without**, arms non-overlapping.
The earlier panel-on set had the opposite sign and was also correct - it was a
different regime, not noise. Full write-up in [`README.md`](README.md), data in
[`2026-08-15_ab-current-legs.txt`](2026-08-15_ab-current-legs.txt).

★★ **But the 130 mA is the wrong regime, found 2026-08-15.** The phone had
**never suspended**: `/sys/power/suspend_stats/success` read 0 after 50 minutes
of uptime, and `mem_sleep` offers only `[s2idle]`. Everything measured so far
describes *runtime idle with a full phosh session alive* - `greetd`, pipewire,
wireplumber, five `xdg-desktop-portal`s, gvfsd, avahi, wpa_supplicant - and a
modem talking at 28 `smd-edge` interrupts a second. A phone's night is s2idle,
and no number had ever been taken there.

**s2idle works.** Probed: 90 s requested via the RTC wakealarm, 91 s slept,
`success` 0 → 1, `fail` 0, WiFi reassociated on its own. The RTC time is stuck
in 1970 (no `offset` nvmem cell, `docs/TODO.md`) but an alarm is *relative*, so
it is unaffected - which is what makes an unattended suspend leg safe.

☠️ **Three battery instruments have now failed, all for one reason.** There is
no coulomb counter here. `qcom_smbx` gets everything from
`adc-battery-helper.c`, whose poll worker runs every 30 s and maintains an
8-deep moving average - i.e. a four-minute trailing one - and **that worker does
not run while userspace is frozen**. So:

| attribute | live? |
|---|---|
| `voltage_now`, `current_now` | **yes** - straight to the ADC on every sysfs read |
| `voltage_ocv`, `capacity`, `charge_now` | no - one cached number under three names |

The casualties, in order: integrating `charge_now` gave **209 mA** in an awake
control window where `current_now` reads 130, and **exactly zero** asleep;
`capacity` read **97 % at both ends** of a 3 h suspend; `voltage_ocv` looked
instantaneous (it equals `voltage_now - current_now × 120 mΩ` to the microvolt)
but is the ring average, five of whose eight slots were still pre-suspend 90 s
after resume. Every number from all three is withdrawn. In each case the
**control window is the only thing that caught it**.

What the S2 leg still supports, from the live pair alone: compensated
`voltage_now` fell 4.222 V → 4.062 V over 3 h. Both ends are biased the same way
(surface charge at the start, resume polarisation at the end), so 160 mV is an
**upper bound**. But a 10 mA leg would move only ~11 mV, so **suspend is not in
the 10 mA regime** - that much is solid. Full reasoning in [`README.md`](README.md).

### S4 ran, 2026-08-15 18:55 → 23:16 — the ratio holds, the calibration does not

The leg completed unattended: settle 900 s, `phase A done suspends=8 of 8`,
every cycle `slept=901s of 900s`, phase B's eight windows, charger and greetd
restored by the trap. 90 % → 72 %, which is the worst case predicted before it
started (564 mAh if nothing ever slept). Logs:
[`2026-08-15_S4-slope.txt`](2026-08-15_S4-slope.txt) and
[`2026-08-15_S4-curlog.txt`](2026-08-15_S4-curlog.txt).

**Suspend is not in question this time.** The dense logger took 213 samples
during phase B and only 55 during phase A, over the same 1.79 h — it was frozen
for the missing ones. A sampler that stops counting *is* the proof that
userspace was down, and it is independent of anything the slope says.

**What the fit gives:**

| phase | slope of compensated V | r² | dense-logger current |
|---|---|---|---|
| settle | −60.3 mV/h | 0.28 ☠️ not a line | 146 mA |
| A (asleep) | −42.3 mV/h | 0.93 | (frozen) |
| B (awake) | −89.1 mV/h | 0.97 | 245 mA |

So **asleep the phone draws 0.475 of what it draws awake**, and that ratio rests
on two clean straight lines. Multiplying it out gives 116 mA — and that number
is **withdrawn**, because the control fails.

☠️ **Phase B measured 245 mA where ~130 mA was expected — the fourth control
failure in a row, and the first one that is not obviously the instrument's
fault.** Checked immediately afterwards, with the panel dark and every CPU at
0 %, the phone drew −249, −127 and −253 mA on three reads two seconds apart. It
really is in a ~210-250 mA regime tonight, so phase B is not misreading; the
**~130 mA reference** is what does not reproduce. Until that is explained, no
absolute sleep current can be quoted, only the ratio.

Two candidates, neither yet tested, and the first is ours:

- **the instrument drives the load it measures.** Every reading crosses WiFi —
  the 30 s dense logger, and the SSH session watching it. The skill already
  states that a periodic sampler measures the load at the instant it is itself
  running; here it may also be *keeping the radio associated*. The test is a
  run whose samples go to a file with no network at all, fetched afterwards.
- **the 130 mA figure was taken in a different regime.** It comes from
  runtime-idle with a live session, not from a stopped greetd, and the swing
  between 127 and 253 mA within four seconds says something is duty-cycling.
  Bracket it: measure awake-idle three ways (session up, greetd stopped, greetd
  stopped and WiFi down) before using any of them as a calibration.

The ratio is the durable result and it is worth stating on its own: **suspend
halves the drain, and no more than halves it.** Whatever the absolute figure
turns out to be, s2idle on this device is not the order-of-magnitude win it is
on a phone with a working low-power state — which is a bigger finding than the
number would have been.

### ← PARKED FOR THE NIGHT, 2026-08-15 13:40 (superseded by the run above)

☠️ **This branch is a night job and must be treated as one.** A slope leg takes
the phone off VBUS, blanks the display and suspends it for hours, so it makes the
device unusable for any other work. It was started at 13:30 in the middle of a
working day and had to be aborted at 13:40, during its settle phase, before phase
A began. Nothing was measured. **Do not start one while the phone is wanted for
anything else** - schedule it when the device is free for the night.

Aborted cleanly: `slope1` and `curlog` stopped, USBIN restored (`online=1`,
battery `Charging` at +129 mA), no wakealarm armed, `greetd` back. Partial data
in [`2026-08-15_S3-slope-aborted.txt`](2026-08-15_S3-slope-aborted.txt) - only
the settle phase, but it does show the relaxation shape: current settling to
~140 mA and the compensated fall slowing from 22 to ~3.7 mV/min over 900 s, i.e.
surface charge still shedding at the end of the settle. That biases a phase-A
slope steeper, so **it inflates the sleep current rather than hiding it** - the
safe direction, but a longer settle would be better.

**To resume, at night:**

```sh
ssh fp3@192.168.100.17 'echo <pw> | sudo -S sh -c "
  : > /home/fp3/suspend-slope.txt
  systemd-run --unit=slope1 --collect /home/fp3/suspend-slope.sh S4 900 8
  systemd-run --unit=curlog --collect sh -c \"/home/fp3/curlog.sh > /home/fp3/curlog.txt\""'
```

Runs ~4.3 h. The phone is unreachable during phase A *by design* - WiFi drops in
s2idle, so a failed ping is it working, not broken.

```sh
ssh fp3@192.168.100.17 'cat /home/fp3/suspend-slope.txt'
```

Every line carries `phase=`, `t=` (uptime, s), `v=` and `i=`, all live ADC. Do
not do the arithmetic by hand - fetch both logs and run the reducer, which also
uses the dense `curlog.txt` for phase B's mean current (the load swings
140-490 mA, so 8 spaced samples estimate it badly):

```sh
scp fp3@192.168.100.17:/home/fp3/{suspend-slope,curlog}.txt docs/power/
docs/power/slope-fit.py docs/power/suspend-slope.txt docs/power/curlog.txt
```

It fits compensated voltage `v + |i| × 120 mΩ` against `t` per phase and prints
`I_sleep = mean(|i|) over phase B × slope_A / slope_B`. `slope-fit.py --selftest`
proves the fitter on a synthetic run of known ratio and on scatter that must fail
the straight-line gate.

☠️ **Check phase B first, before looking at phase A at all.** It is the control:
its `mean(|i|)` must come out near 130 mA and its slope must be a clean straight
line. If phase B does not reproduce the current we already know, the method is
broken and phase A is meaningless - that has now happened three times running.

Then check the `A<n> slept=` lines: each should read ~900 of 900. A
systematically short sleep means something is waking it and phase A is not
measuring suspend. And check the `phase=settle` lines - if compensated voltage
is still visibly falling at the end of the 900 s settle, surface charge had not
finished shedding and the first phase-A points are contaminated (the slope fit
should then drop them).

Also verify the charger came back: `cat /sys/class/power_supply/pmi632-charger/online`
should read 1. ☠️ If it reads 0 the EXIT trap did not run - clear
`USBIN_SUSPEND_BIT` (`echo Charging > .../status`) **before** any reboot.

Prediction on record, **not** a measurement: 60-110 mA, because the genpd
`interrupt-controller` domain was already collapsed 67 % of the time *while
awake* at 130 mA, so most of that draw is not the AP and suspending it cannot
remove it.

**Then** bisect whatever is left by subsystem with `idle-leg.sh` - one leg with
WiFi down, one with the modem stopped, one with `pd-mapper` disabled. That is
worth doing only once the suspend number says how much of the 130 mA is session
noise rather than platform floor.

☠️ **10 mA is a different regime, not a smaller number.** Downstream phones
reach it in full suspend with the modem in its own power-save, never in runtime
idle. Do not treat the 130 mA as a target to shave.

**The RPM question is parked, not open.** Every AP-side precondition is verified
and the two-sided vMPM dump is structurally identical; what remains is past the
PSCI call, in TZ or RPM firmware, where this kernel has no instrument.

**Upstream:** the genpd patch can now say plainly that it measurably improves
idle current on an SDM632 phone. The cpuidle-psci ordering patch is unaffected.
The vMPM timer commit (`wip/7.1.3/power` `97951baf7a85`) stays on the fork - it is
a real omission but still changes nothing measurable.

**Also still open:** GPIO wakeup map inert until the RPM takes over; the regulator
sleep set must exist *before* the RPM ever collapses; `_commit`/`pkgrel` still pin
`162f27abc328` and should move to the current `debug-int/7.1.3` tip.

☠️ **Two traps this cost:** never reboot with USBIN suspended (the bit is in the
PMIC, survives a warm reboot, and wedged the bootloader into a fastboot that
answered nothing - it took a held power button). And `systemctl stop greetd`
returns before the compositor releases DRM master, so a single write to
`fb0/blank` is silently undone.

## Device and tree state

* Phone on `slot_b`, running a hand-deployed `Image` from `debug-int/7.1.3`
  `6fd035d9501a` (build #18, `/home/fp3/Image.fix`; the A/B control is
  `/home/fp3/Image.control`, the same tree with 162f27abc328 reverted),
  not a package build. Backups in `/boot`: `vmlinuz.pre-mpmtimer`,
  `vmlinuz.genpdfix`, `vmlinuz.base-mpm`, `vmlinuz.pre-mpm`.
* The oracle is `slot_a` (Ubuntu Touch); `fastboot set_active a|b` switches, and
  `ut-ssh` reaches it.
* Kernel work is the `power` category: `wip/7.1.3/power` → `integration/7.1.3` →
  `debug-int/7.1.3`, all pushed to `fork`.
* **A package build has not been run for any of this**, so `_commit` in
  `linux-fp3/APKBUILD` still predates it. Do that before calling anything
  shipped.

## Instruments, with the paths that cost time to find

| question | command |
|---|---|
| did the SoC reach a low-power mode | `grep Count /sys/kernel/debug/qcom_stats/{vlow,vmin}` |
| which master never goes down | `cat /sys/kernel/debug/qcom_rpm_master_stats/APSS` — ☠️ one file per master, and the directory is `qcom_rpm_master_stats`, not `rpm_master_stats`; needs `modprobe rpm_master_stats` |
| how deep does idle actually get | `cat /sys/kernel/debug/pm_genpd/power-domain-cluster0/idle_states` |
| the same on the oracle | `ut-ssh 'cat /sys/kernel/debug/rpm_master_stats'` and `.../lpm_stats/stats` |
| what is waking the CPUs | two `/proc/interrupts` snapshots differenced — ☠️ stop the compositor first, or `msm_mdss` at 65/s makes the run meaningless |
| has the phone ever suspended | `grep -H . /sys/power/suspend_stats/*` — `success` is the only honest answer; `cat /sys/power/mem_sleep` says which path |
| current while suspended | `docs/power/suspend-slope.sh` — ☠️ **only `voltage_now`/`current_now` are live**; `capacity`, `charge_now` and `voltage_ocv` are one cached number the frozen poll worker maintains, and all three lie across a suspend. Use a slope of compensated `voltage_now`, calibrated against an awake control |
| does the RTC alarm wake it | `echo 0 > /sys/class/rtc/rtc0/wakealarm; echo +90 > …` then `echo mem > /sys/power/state` — ☠️ prove this **before** relying on it to bring an unattended leg back |
