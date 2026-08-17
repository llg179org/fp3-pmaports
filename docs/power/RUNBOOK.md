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
4. *Why does the RPM record nothing?* — **answered 2026-08-17**: `system_pc`
   named affinity level 1 in its PSCI parameter, so TZ never performed the APSS
   handshake. `0x42000353` fixes it and the RPM now counts APSS shutdowns; a
   second change stops the AP being woken once a second by our own vMPM
   deadline cap. Both landed. Detail under "Next step".
5. **Current: the RPM records the AP going down, but still never enters `vlow`
   or `vmin`.** A master being down is necessary and not sufficient — the RPM
   aggregates over resource votes as well. The question is now which rails are
   still voted active-set while the phone sleeps.

## Next step

★★★★ **2026-08-17: the RPM handshake is fixed. One hex digit.**

`system_pc` asked the firmware for **affinity level 1** — the same level the
cluster states use — so TZ aggregated up to a cluster and never performed the
APSS handshake with the RPM. Downstream composes the parameter rather than
spelling it out, and the recursion bumps the affinity level once per cluster
level that leaves its default: once for the system cluster (mode 3 at shift 8)
and once for the L2 cluster (mode 5 at shift 4) — **`0x42000353`**, not
`0x41000353`. Our four lower rungs already matched that composition bit for bit,
which is what makes the top one's mismatch believable rather than a guess.

Measured on the device, one 91 s suspend each side:

| | before (`0x41000353`) | after (`0x42000353`) |
|---|---|---|
| APSS `Shutdown count` | **0**, all boot | 633 → **724** (+91) |
| APSS transition timings | all zero | `sleep 12232` / `wake 12386` |
| `power-domain-system` S2idle | 3 (kernel-side only) | 0 → **92** |
| `vlow` / `vmin` Count | 0 | **0** |
| `XO shutdown count` | 0 | **0** |

So the application processor now tells the RPM it is down, and the RPM believes
it. That is the gap this page has been chasing since 2026-08-14, and it was one
nibble in one property. Landed as `0314fee3ce35` on `wip/7.1.3/power`, cherry-
picked to `integration/7.1.3` and `debug-int/7.1.3`, all three pushed.

**Two things are immediately visible in that table, and both are the next work:**

1. **91 shutdowns in 91 s — it wakes every second.** That is our own
   `MPM_MAX_SLEEP_NS = NSEC_PER_SEC` clamp in `mpm_write_wakeup()`: the RPM is
   never asked to keep the AP down for longer than a second, so it does not.
   Downstream applies **no clamp at all** — it writes the broadcast timer's CVAL
   verbatim, and deliberately writes all-ones when no timer is armed, meaning
   "no scheduled wake, rude wakeup only". So a far-future deadline is the
   vendor's own encoding and demonstrably not refused. ⚠️ Note also that
   downstream reads the **memory-mapped** timer frame's CVAL while we compute
   from `arch_timer_read_counter()`; if `CNTVOFF` is non-zero those are different
   counter domains, which would be a silent, total failure. Check that before
   trusting a longer deadline.
2. **`vlow`, `vmin` and XO shutdown are still 0.** The AP going down is
   necessary, not sufficient: the RPM aggregates across all masters *and* all
   resource votes. The next suspect is sleep-set vote coverage — which rails are
   still voting active-set — not this path.

⚠️ **No current number yet.** The RPM counters moving is not the same as the
draw falling, and this page has been wrong in exactly that way before. Until a
leg is run, the honest statement is that the handshake works, not that the phone
saves anything.

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

### Why suspend only halves it: there is no `deep` state

Measured 2026-08-15, minutes after the S4 leg:

```sh
cat /sys/power/state      # freeze mem disk
cat /sys/power/mem_sleep  # [s2idle]
```

`mem_sleep` offers **s2idle and nothing else**, so `echo mem > /sys/power/state`
— what the leg ran, and what `suspend_stats` counted 8 of — is s2idle. Tasks
freeze and the CPUs go idle, but the SoC never reaches VDD_MIN or XO shutdown,
because that needs every subsystem to have dropped its RPM votes for clocks,
regulators and buses. One driver still holding one vote is enough to prevent it,
and mainline msm8953 registers no `deep` (`PM_SUSPEND_MEM`) platform op at all.

This is the same fact as the 0.475 ratio, seen from the other side, and it means
the ratio is close to the ceiling of what this suspend path can give. Chasing it
by tuning userspace is the wrong lever; the lever is a `deep` state, which means
the RPM vote path. Before any of that, get the awake baseline honest (above) —
a ratio against a wrong reference cannot say how much is left on the table.

#### ☠️ Correction, 2026-08-16: the paragraph above is wrong, and so is its lever

The *observation* stands — `mem_sleep` really is `[s2idle]` only — but the
inference drawn from it does not. Two things were assumed and neither survived
being measured.

**1. s2idle does reach the system power collapse here.** genpd counts entries
made from the s2idle path in a separate column, so this is directly readable
rather than argued. Around one 20 s RTC-woken suspend:

```sh
cat /sys/kernel/debug/pm_genpd/power-domain-system/idle_states
```

| domain | state | `S2idle` before → after |
|---|---|---|
| `power-domain-system` | S0 | 0 → **1** |
| `power-domain-cluster0` | S2 | 0 → **1** |
| `power-domain-cluster1` | S2 | 0 → **1** |

So the claim that "the SoC never reaches VDD_MIN or XO shutdown" is not what the
counters say: the *system* domain collapsed, from s2idle, on the first try. The
mechanism the paragraph reached for — every subsystem dropping its RPM votes —
is evidently already happening, because the domain could not have gone down
otherwise. Whatever else explains the 0.475 ratio, it is not "suspend never gets
deep".

**2. `deep` is not a lever anybody can pull from here.** On arm64 the only
writer of `deep` is `suspend_set_ops()`, and the only caller that can reach it
on this SoC is `psci_init_system_suspend()` in `drivers/firmware/psci/psci.c`
(read on `7.1.3/main`, the base we run):

```c
	if (!IS_ENABLED(CONFIG_SUSPEND))
		return;
	ret = psci_features(PSCI_FN_NATIVE(1_0, SYSTEM_SUSPEND));
	if (ret != PSCI_RET_NOT_SUPPORTED)
		suspend_set_ops(&psci_suspend_ops);
```

`CONFIG_SUSPEND=y` is set, so the absent `deep` means the secure firmware
answered `NOT_SUPPORTED` to the `SYSTEM_SUSPEND` SMC. Every other
`suspend_set_ops()` caller in mainline lives under `arch/arm/mach-*`,
`arch/mips` or `arch/powerpc` — there is no qcom arm64 platform suspend op to
add one from. It is therefore a **TZ firmware fact**, not a kernel or config
one, and it is reachable neither by patching the kernel nor by tuning userspace.

☠️ **And it disposes of the "did a regression take it away?" question.**
Userspace never touches `mem_sleep` — it is written at kernel init, before
systemd exists — so the switch to systemd cannot have removed it, and no
mainline kernel version ever had a non-PSCI route to it on this SoC. Note also
that `psci_init_system_suspend()` logs **nothing** either way, so its verdict
leaves no trace in `dmesg` to grep for; `tests/baseline/sleep-states.txt` is
that trace, and `tests/checks/99-suspend-test.sh` is what notices it changing.

The check also asserts the *depth*, because that is the property that can
actually regress: a suspend that freezes userspace, holds one wakeup source and
never lets the domains go still passes every outward test — screen off, phone
unresponsive, RTC wakes it — while saving almost nothing. The `S2idle` counter
is the only thing that separates those two cases. Proven in both directions on
2026-08-16: PASS live on the device; FAIL with a baseline claiming a lost state;
FAIL with `deep` injected over `mem_sleep` by bind-mount; SKIP against a fixture
with no `S2idle` column.

### ☠️★★★ The awake baseline was not idle: the CPU0 PLL was failing to lock

Found 2026-08-16 while looking for why phase B measured 245 mA. The previous
boot's kernel log carries **266 copies** of

```
apcs-cpu0-pll failed to enable!
WARNING: drivers/clk/qcom/clk-alpha-pll.c:421 at wait_for_pll+0xf4/0x108, CPU#5: sugov:0/113
  wait_for_pll  <- x0 = 0xffffff92 = -110 = -ETIMEDOUT
  alpha_pll_huayra_set_rate
  clk_change_rate / clk_core_set_rate_nolock / clk_set_rate
  _opp_config_clk_single / _set_opp / dev_pm_opp_set_rate
  set_target / __cpufreq_driver_target / sugov_work
```

Every one is the little cluster's PLL (`policy0`) refusing to lock while
schedutil tries to change frequency. Full capture:
[`2026-08-16_apcs-cpu0-pll-lock-failures.txt`](2026-08-16_apcs-cpu0-pll-lock-failures.txt).

**The timing is what matters.** The first is at 21:49:55 and they run to
06:22:55 — several a minute at the start, thinning out later. Phase A finished
around 21:14 and phase B ran to 23:16, so:

| phase | PLL storm |
|---|---|
| settle | no |
| **A (asleep)** | **no — it was over before the first failure** |
| **B (awake control)** | **yes, from ~35 min in to the end** |

So the control leg — the one whose whole job is to reproduce a current we
already know — ran on a CPU whose frequency transitions were failing. That is
the first concrete candidate for 245 mA against an expected 130, and it is
testable rather than a shrug.

☠️ **It does not simply invalidate the ratio, and it does not simply rescue it
either.** The method computes `mean(|i|)_B × slope_A / slope_B`, so an inflated
phase B raises the current *and* steepens the slope, and the two partly cancel.
"Partly" is not a number, so the 116 mA stays withdrawn — but note the error
direction is not knowable without redoing it.

**This also killed the phone.** The previous boot's journal ends mid-line at
06:22:57 with no shutdown sequence at all — no `Reached target Shutdown`,
nothing — after a `mpm_pd_power_off` / `genpd_sync_power_off` warning at
06:22:27 and a PLL failure at 06:22:55. It came back by itself. An abrupt cut
with a preceding clock failure is not a low-battery power-off; a low-battery
power-off is orderly and logged.

**What to do next, in this order:**

1. Find out whether the storm is voltage-dependent. It began at ~3.82 V raw,
   the lowest the phone had been all session, and one more occurred in the
   fresh boot at 3.89 V while charging — so a pure sag explanation is already
   weakened, and it needs the actual test: repeat a fixed cpufreq sweep at high
   and low battery and count failures. `git grep -n "failed to enable"
   drivers/clk/qcom/clk-alpha-pll.c` shows there is no retry there at all.
2. Only then re-run a slope leg. Any leg whose phase B overlaps the storm is
   measuring the storm.
3. Note that this may also be the missing half of the 130-vs-245 puzzle, which
   was previously attributed to the sampler keeping the radio associated. Both
   remain candidates; this one has a log line and the other does not.

### 2026-08-17: running step 1 — the PLL rate against a falling pack

**Method.** `pll-vs-voltage.sh` drives `pll-sweep.sh` repeatedly while USBIN is
suspended, so every point is the same sweep on the same boot, minutes apart,
with only the voltage moving. The rate is failures per **transition**, read from
the kernel's own `total_trans` delta, because a `scaling_setspeed` write the
governor coalesces away exercises nothing and would otherwise be counted as a
transition that survived. `pll-ramp-fit.py` reads the log and fits rate against
voltage.

**How it is run unattended.** Three things that each cost a run before they were
fixed:

* Start it as a **transient systemd unit**, not with `nohup`. A `nohup`-ed job
  under `sudo` over ssh is killed with `Terminated` when the ssh session's scope
  goes away — measured, thirteen minutes lost — and the only reason it did no
  harm is that the script's EXIT trap restored charging on the way out.
* Give the unit `ExecStopPost=` that restores charging, as well as the script's
  own trap. ☠️ `USBIN_SUSPEND_BIT` lives in the PMIC and survives a warm reboot;
  it must never outlive the measurement that set it.
* Cut the ramp on **voltage, not on a clock**. A supervisor watching for the
  threshold ends the run where the science ends, and leaves enough charge for
  whatever runs next.

**Sizing.** Rounds per point is a resolution knob, not a quality knob: the total
number of transitions a night can buy is fixed by wall-clock, so slicing finer
costs nothing in total statistical power and gains voltage resolution. The first
attempt used 5000 rounds and took ~98 minutes per point, which would have
produced two points and no ramp at all; 1500 rounds gives ~12.5 minutes per
point and ~13 500 transitions in it.

☠️ **Count failures from the journal, never from `dmesg`.** The ring buffer
wraps: two `dmesg | grep -c` reads twenty minutes apart on one boot returned 35
and then 34, so the count went *down* while failures were still accumulating. A
leg could report itself clean precisely because the storm had been loud enough
to push its own evidence out of the buffer. `pll-sweep.sh` takes a `journalctl`
cursor; `suspend-slope.sh` now carries a `pll=` field on every sample from the
same source, so each leg says for itself whether it was contaminated instead of
that being reconstructed afterwards.

**Result so far — the top of the pack, and it is flat.** Seven points over
4.318 → 4.137 V, ~13 500 transitions each: 12.6, 7.4, 5.2, 5.9, 8.9, 12.6, 4.4
per 10 000, pooled **8.1 per 10 000** (77 failures in 94 586 transitions). The
fitted change across that span is 7.4 per 10 000 against an uncertainty of 7.8,
so there is no voltage dependence to see here. For comparison the 2026-08-16
baseline was 18 per 10 000 at 4.358 V.

⚠️ That covers only the top 181 mV. The sighting this was run to explain was at
3.82 V, and the ramp had not reached it when this was written — so the claim
that is supported *now* is narrower than the question: **the storm runs at a
full pack too, and does not vary with voltage while the pack is full.** It
already means the storm cannot be explained by sag alone.

**In flight at the time of writing (2026-08-17 morning).** The ramp was cut by
hand at 06:32 after 26 points, because the pack was falling ~0.9 mV/min by then
and reaching 3.80 V would have pushed the leg that follows into the afternoon.
Final ramp numbers: **26 points, 4.318 → 3.931 V (386 mV), 255 failures in
351 325 transitions = 7.3 per 10 000**, fitted change 3.9 against an uncertainty
of 2.9 and `r = +0.47` — no voltage dependence, and what little slope there is
runs the *wrong* way for the sag hypothesis.

⚠️ So step 1 is answered for 4.32 → 3.93 V only. Below 3.93 V is still untested,
and the 3.82 V sighting sits just under that edge. If the storm ever needs a
sharper answer, that is the gap to close.

## Step 2 answered: what the phone draws asleep

The slope leg `post-pll-20260817` ran 06:33 → 10:53 and completed clean: **8
suspends of 8**, every one `slept=901s of 900s`, so nothing woke it early and
phase A really is measuring suspend. Log and fit:
`2026-08-17_pmos_post-pll-slope-leg.txt`.

| phase | compensated V | slope | r² | `current_now` mean |
|---|---|---|---|---|
| settle | 3.9815 → 3.9424 | −156.6 mV/h | 0.63 | 142.1 mA |
| A (asleep, 8×900 s) | 3.9232 → 3.8996 | −15.92 mV/h | 0.80 | 121.5 mA |
| B (awake control) | 3.8677 → 3.7864 | −41.18 mV/h | 0.93 | 155.3 mA |

**I_sleep = 155.3 mA × (15.92 / 41.18) = 60 mA.**

That is the first number for suspend on this device that came off a live
instrument. Read it against the two regimes it sits between: clean awake idle is
~130 mA, and the ~10 mA that the platform ought to reach is still an order of
magnitude below this. **s2idle roughly halves the draw and no more** — so
whatever keeps the phone at 130 mA awake is mostly still running with the
kernel frozen, and that, not the awake figure, is the next thing to chase.

⚠️ Phase A's fit is the weak one (r² = 0.80 over 23.6 mV of travel). The
direction is safe; treat the 60 mA as ±10 rather than as three digits.

**The `pll=` column paid for itself, twice.** Phase A took **8** failures in its
1.79 h; phase B took **137** in the same 1.79 h — a storm ~17× denser in the
awake leg, exactly the contamination that cost the 2026-08-15 run its 116 mA.
This time it is measured rather than reconstructed. And it does *not* invalidate
the result: `I_awake` and `slope_B` both come out of phase B, so a storm that
inflates the draw inflates the slope with it and the quotient is immune to first
order. That immunity is the reason the calibration is against a measured current
instead of against the OCV table — worth keeping in mind before anyone
"improves" the method by dropping phase B.

☠️ **The journal counter is a floor, not a total.** The `pll=` field went
**down** across the phase boundary — 320 at the end of A, 288 at the start of B
— so `journalctl -k -b` had already dropped records of this boot. It lies in the
same direction as `dmesg` did, just later: a loud enough storm evicts its own
evidence. Every count in this document is therefore a lower bound. If an exact
count ever matters, take a cursor at the start of the leg and read forward from
it rather than counting the whole boot.

## 2026-08-17 evening: the AP now sleeps through, and the next layer is named

Removing the one-second cap did exactly what the arithmetic said it would. Same
instrument, same 91 s suspend, one boot apart:

| | with the 1 s cap | cap removed |
|---|---|---|
| APSS `Shutdown count` | +91 | **+1** |
| `power-domain-system` S2idle | +92 | **+1** |
| woke on time | yes | yes (91 s of 90 s) |

So the application processor goes down once and stays down for the whole
suspend, instead of being brought back up every second to pay a 12 ms sleep
transition and a 12 ms wake transition each time. Landed as `ff064e2b608c` on
`wip/7.1.3/power`, cherry-picked and pushed to all three branches; the device
runs it as build `#2` from a hand-installed `/boot/vmlinuz`.

☠️ **A symptom I listed wrongly, corrected from the oracle.** I had counted
APSS `XO shutdown count: 0` among the things still broken. The Ubuntu Touch
capture shows `xo_count: 0x0` and `xo_accumulated_duration: 0x0` for APSS as
well — on the stack that works. Only MPSS, PRONTO and LPASS do XO shutdowns of
their own; the application processor never does. So that field being zero is
normal and proves nothing either way.

**What is genuinely still zero: `vlow` and `vmin`.** Both `Count` and
`Accumulated Duration`, after the AP has begun shutting down properly. The AP
going down is necessary and not sufficient — the RPM aggregates across every
master *and* every resource vote, so the next question is which rails are still
voted active-set while we sleep.

⚠️ **Do not read the `Client Votes` field yet.** Four consecutive reads on an
idle system gave `0x11151715`, `0x13171317`, `0x11131715`, `0x17151715` — always
nibbles from {1,3,5,7}, never stable. Either it is a live racy read or mainline's
`qcom_stats.c` decodes the field differently from the vendor's reader. An
instrument that changes its answer between two reads of an unchanged system is
not yet an instrument.

### Why `vlow`/`vmin` stay at zero: the regulators never vote for sleep

Found in the vendor source and confirmed against our own tree. The RPM keeps two
vote sets, and the vendor driver documents what happens when only one is used —
`drivers/regulator/rpm-smd-regulator.c:225-235`:

> *"For any given regulator, if an active set request is present, but not a
> sleep set request, then the active set request is used at all times, **even
> when the Apps processor is power collapsed**."*

So an active-only vote is not neutral. It is a vote to hold the rail at its
awake value through the collapse. Downstream declares **all 23** pm8953 rails
`qcom,set = <3>` — active *and* sleep — and the `_ao` / `_so` suffixed corner
regulators in `msm8953-regulator.dtsi` exist precisely so CX and MX can drop to
retention while asleep and still be held high while awake.

Our `drivers/regulator/qcom_smd-regulator.c` has exactly one write path and it
is `QCOM_SMD_RPM_ACTIVE_STATE` (line 72). `grep -c SLEEP` on that file returns
**0**. Every rail therefore holds its enable, voltage and load votes while the
application processor is collapsed, and the RPM cannot minimise Vdd against two
dozen standing votes.

★ **This gap only became reachable today.** Until the affinity level was fixed
the AP never collapsed at all, so a sleep-set vote would have had nothing to
take effect at. The bug was there the whole time and could not have been
measured — which is worth remembering before treating "we checked that" as
covering a layer that was unreachable at the time.

☠️ **Do not start by writing sleep votes.** Telling the RPM to drop a rail the
system still needs while collapsed is a hang, not a failed experiment. Two free
checks come first, both from debugfs on a live phone:

| check | what it would mean |
|---|---|
| `pm_genpd/pm_genpd_summary` | `rpmpd.c:1005-1007` clamps CX/MX to `max_state` = TURBO in **both** sets until `sync_state` fires. If that is pinned, it masks any regulator fix |
| `interconnect/interconnect_summary` | five msm8953 paths are `RPM_ALWAYS_TAG`, so their bandwidth is voted into the sleep set; a consumer that forgets to zero its request holds BIMC up |
| `clk/clk_summary` | the mainline stand-in for downstream's `clock_debug_print_enabled(true)`, which Qualcomm calls at suspend for exactly this reason |
| `/sys/class/regulator/*/state` | bounds the problem: which of the 23 rails are even enabled |

And there is no way to read the RPM's *aggregated* state — neither tree has one,
and the vendor's `rpm_send_msg` debugfs is write-only. What is observable is what
the AP sends, which is the answerable question. The cheapest instrument is a
tracepoint in `qcom_rpm_smd_write()` (`drivers/soc/qcom/smd-rpm.c:94`), whose
arguments already carry the state, type, id and payload.
