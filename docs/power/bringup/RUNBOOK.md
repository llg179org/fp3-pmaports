# Power investigation run-book

> ⚠️ **AI-generated.** Maintained by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

**This file is the resume point.** It is rewritten whenever the state changes, so
that a context compaction — or a new session — costs nothing. Read it first, do
what "Next step" says, then update it. Everything else on this page ages out;
the reasoning lives in [`bringup/`](README.md) and the findings in
[`README.md`](../README.md).

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
   [`README.md`](../README.md) under "The real cause".
4. *Why does the RPM record nothing?* — **answered 2026-08-17**: `system_pc`
   named affinity level 1 in its PSCI parameter, so TZ never performed the APSS
   handshake. `0x42000353` fixes it and the RPM now counts APSS shutdowns; a
   second change stops the AP being woken once a second by our own vMPM
   deadline cap. Both landed. Detail under "Next step".
5. **Current: the RPM records the AP going down, but still never enters `vlow`
   or `vmin`.** A master being down is necessary and not sufficient — the RPM
   aggregates over resource votes as well. The question is now which rails are
   still voted active-set while the phone sleeps.

## The LPASS question is CLOSED (2026-08-21), and here is where it went

Kept here because it was previously recorded only in a working note that this
page never pointed at — which on 2026-08-23 cost a re-run of the whole bisect
and a retracted conclusion. Detail:
[`leads/lpass-mclk-gate-state.md`](leads/lpass-mclk-gate-state.md).

**Two root causes, both fixed and both in the kernel the phone runs:**

1. `msm8916-wcd-digital` called `clk_prepare_enable(mclk)` unconditionally at
   probe; on msm8953 that mclk is a q6afe clock, i.e. an ADSP request held for
   the lifetime of the driver. Fixed by moving it into DAI startup/shutdown —
   `ASoC: msm8916-wcd-digital: hold mclk only while a stream runs`.
2. A second latch: `qcom-ngd-ctrl` silently dropped every core
   reconfiguration-sequence message, which is where the generic SLIMbus teardown
   sends NEXT_DEACTIVATE_CHANNEL / NEXT_REMOVE_CHANNEL. `enable_stream` had a
   real implementation and there was no `disable_stream`, so the ADSP never saw
   a **TX (source)** channel removed and held the XO vote forever. RX never
   latched. Fixed by porting the downstream `SLIM_USR_MC_CHAN_CTRL` recipe —
   `slimbus: qcom-ngd-ctrl: implement disable_stream so the ADSP releases the
   channel` (`cff137fdef8e` on `debug-int/7.1.3`, shipped in r63).

**How to read the instrument, because it is ambiguous and has now misled once:**
`Shutdown count` going flat means *either* pinned awake *or* asleep and staying
down. The disambiguators are `Last XO shutdown enter` vs `Last XO shutdown exit`
and `Active cores bitmask` — `enter > exit` with `cores 0x0` is asleep.
`tools/lpass-trace.sh` prints the verdict; never quote the count alone.

**Verified on r73, 2026-08-23:** clean boot, LPASS cycles during bring-up, takes
its last shutdown at ~34 s of uptime and reads `ASLEEP cores=0x0` from there on.
☠️ An ADSP restart re-introduces the latch for that boot (post-SSR re-attach) —
so any measurement taken after an SSR is measuring that, not steady state.

☠️ **And it is not the `vlow` gate.** Measured twice, on 2026-08-21 and again on
2026-08-23 with the ADSP `remoteproc` stopped outright: `vlow`/`vmin` `Count`
stay 0 either way. The gate is still unidentified.

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
different regime, not noise. Full write-up in [`README.md`](../README.md), data in
[`2026-08-15_ab-current-legs.txt`](captures/2026-08-15_ab-current-legs.txt).

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
the 10 mA regime** - that much is solid. Full reasoning in [`README.md`](../README.md).

### S4 ran, 2026-08-15 18:55 → 23:16 — the ratio holds, the calibration does not

The leg completed unattended: settle 900 s, `phase A done suspends=8 of 8`,
every cycle `slept=901s of 900s`, phase B's eight windows, charger and greetd
restored by the trap. 90 % → 72 %, which is the worst case predicted before it
started (564 mAh if nothing ever slept). Logs:
[`2026-08-15_S4-slope.txt`](captures/2026-08-15_S4-slope.txt) and
[`2026-08-15_S4-curlog.txt`](captures/2026-08-15_S4-curlog.txt).

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
in [`2026-08-15_S3-slope-aborted.txt`](captures/2026-08-15_S3-slope-aborted.txt) - only
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
| current while suspended | `docs/power/bringup/tools/suspend-slope.sh` — ☠️ **only `voltage_now`/`current_now` are live**; `capacity`, `charge_now` and `voltage_ocv` are one cached number the frozen poll worker maintains, and all three lie across a suspend. Use a slope of compensated `voltage_now`, calibrated against an awake control |
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
[`2026-08-16_apcs-cpu0-pll-lock-failures.txt`](captures/2026-08-16_apcs-cpu0-pll-lock-failures.txt).

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

### The first leg after the fixes is WITHDRAWN, and the control is why

`nocap-20260817` completed cleanly — 8 suspends of 8, every one `slept=901s of
900s` — and `slope-fit.py` reports **120 mA asleep** against the pre-fix leg's
60 mA. That number is not reported as a result, because two things about the
leg make it incomparable and both are visible in its own output.

| | `post-pll` (pre-fix) | `nocap` (post-fix) |
|---|---|---|
| phase A voltage span | 3.923 → 3.900 V | **4.268 → 4.178 V** |
| phase B voltage span | 3.868 → 3.786 V | 4.148 → 4.015 V |
| phase A raw slope | −15.92 mV/h | −54.26 mV/h |
| phase A `current_now` mean | 121.5 mA | **256.2 mA** (max 402) |
| phase B `current_now` mean | 155.3 mA | 156.5 mA |

**1. It ran on the wrong part of the discharge curve.** The method assumes
`dV/dQ` is roughly constant between the two phases; the reference leg sat in the
flat region around 3.9 V, this one started at 4.33 V where the curve falls much
faster, and its two phases sit in visibly different parts of it. A steeper mV/h
at a high state of charge is expected for the same current, and the A/B ratio
only cancels that if both phases share a slope.

**2. The wake-window current doubled**, which corrupts the IR compensation the
fit applies: 0.12 Ω × 256 mA is a 31 mV correction where the reference leg
applied 15 mV. There is a plausible mechanism — with the deadline cap gone the
AP now stays down for the full 900 s instead of being resurrected every second,
so the resume transient it wakes into is a different and larger thing, and the
20 s `SETTLE_WAKE` was chosen when no deep sleep was happening.

☠️ **The control is what makes this readable rather than a mystery.** Phase B
came back at 156.5 mA against the reference leg's 155.3 — the method is intact
and the awake regime is unchanged. It is phase A's sampling that moved. A leg
without its awake control would have published 120 mA and called the day a
regression.

**Next, in order, and measure before re-running:** characterise the resume
transient directly (wake from a 900 s sleep, sample `current_now` every 2 s for
180 s) so `SETTLE_WAKE` is set from data rather than from a number that used to
work; then re-run with both phases below ~4.0 V so they share the flat region.

### ☠️ One read of `current_now` is not a measurement

Run to find how long the resume transient lasts, so `SETTLE_WAKE` could be set
from data. It answered a different and more useful question, and it disproved
the hypothesis it was built for. Data:
[`2026-08-17_pmos_resume-shape.txt`](captures/2026-08-17_pmos_resume-shape.txt).

**There is no decaying transient.** 90 reads two seconds apart after a 901 s
deep suspend:

| window | mean | median |
|---|---|---|
| 0–20 s | 159.5 mA | 143.3 mA |
| 20–60 s | 175.0 mA | 141.5 mA |
| 60–100 s | 169.0 mA | 157.3 mA |
| 100–180 s | 170.1 mA | 151.3 mA |

Flat. Waiting longer after a wake buys nothing, so the withdrawn leg's second
explanation — that a deeper sleep means a bigger transient the 20 s settle no
longer covers — is **wrong**, and is retracted here.

**What is true instead: the attribute is enormously noisy.** Those 90 reads have
a standard deviation of **70.5 mA** on a ~150 mA signal, a range of 93 to 450,
and a visibly bimodal distribution — periodic activity beating against the
sampler, the same trap this page already recorded once at a 60 s interval. A
single read therefore carries **±138 mA at 95 %**.

☠️ **And `suspend-slope.sh` took exactly one read per sample, then multiplied it
by 120 mΩ to compensate the voltage.** ±138 mA of current error is **±17 mV** of
injected error, and phase A of the reference leg travels **23.6 mV in total**.
The correction meant to clean the measurement was noisier than the thing it
corrects. That is the real explanation for both the r² = 0.80 on that fit and
the withdrawn leg's phase A reading 256 mA where a 10-sample awake reference
taken the same evening read 129: eight draws from a heavy-tailed distribution.

**Fixed**: every sample now takes 20 interleaved voltage/current reads over 10 s
and uses the **median** — the mean would still chase the bimodality. That is
±31 mA and ±4 mV, which is small against the signal. Voltage gets the same
treatment because it comes off the same ADC in the same call and carries the
same beat. Samples now carry an `nread=` field so a log says for itself which
regime it was taken in.

### The tracepoint answers it: only the LDOs never vote for sleep

Armed the new `qcom_rpm_smd_write` tracepoint across a real 30 s suspend.
2159 events. Trace kept as
`2026-08-17_pmos_rpm-votes.trace` (never committed - the raw ftrace was too large; the
decoded result is in [`leads/rpm-sleep-set.md`](leads/rpm-sleep-set.md)).

| resource type | active | sleep |
|---|---|---|
| `clk2` | 894 | 17 |
| `bslv` (bus slave) | 262 | 106 |
| `bmas` (bus master) | 232 | 102 |
| `smpa` (SMPS corners) | 216 | **208** |
| `clk1` | 60 | 48 |
| **`ldoa` (LDO rails)** | **14** | **0** |

So the source-level guess was too broad and the truth is sharper: `rpmpd` votes
sleep for the SMPS corners, `icc-rpm` for both bus directions, `clk-smd-rpm` for
the clocks. The only hole is the **LDOs**, which is exactly
`qcom_smd-regulator.c` — the one file with a single active-only write path.

The 14 `ldoa` events are seven rails — `l3, l6, l7, l8, l11, l12, l13` — each
enabled once and disabled once during the window, all with key `swen` (`73 77
65 6e`), the RPM's enable key.

☠️ **Read that count as a floor, not a total.** The tracepoint fires on
*changes*. A rail enabled during boot and never touched since has had a standing
active-set vote ever since and emits nothing at all now. Seven rails moved
during a 30 s window; every enabled rail on the phone is holding a vote.

**The fix is therefore narrow and upstreamable**: give `qcom_smd-regulator.c` a
sleep-set write path, sending the sleep request when it differs from the active
one, as `rpm_vreg_aggregate_requests()` does downstream. It is a correctness gap
on every RPM-SMD SoC, not an FP3 quirk — and note this is now backed by a
runtime measurement, not only by reading two trees.

## ☠️☠️ 2026-08-18: the eMMC fell off the bus overnight — READ THIS FIRST

The night of the 17th produced no measurement and one serious finding.

**The leg was truncated by a shell bug of mine** (`sample()` used `i`, which is
also every caller's loop counter), so it ran 32 minutes instead of 4.25 hours.
Fixed and committed; verify with a short dry run —
`suspend-slope.sh dryrun 60 2 120` — and check that the settle rows run
`n=0..14`, phase A `n=0,1`, phase B `n=0,1` before trusting a long one.

**And then the eMMC stopped answering.** At 01:16, hours after the leg ended,
with the phone idle on the charger:

```
mmc0: cache flush error -110
mmc0: mmc_hs400_to_hs200 failed, error -110
mmcblk0: recovery failed!
```

`-110` is ETIMEDOUT. The card did not respond, the controller could not fall
back from HS400, root went `emergency_ro`, and from then until morning the
journal contained nothing but its own failure to write. A reboot cleared it
completely: `Filesystem state: clean`, the card re-enumerated at HS400, and
`fp3-selftest` is back to 27 ok / 3 failed with all three explained (two are the
hand-built kernel and DTB not matching the package, one is the known amplifier
case).

⚠️ **Treat this as caused by our own change until shown otherwise.** It is the
first occurrence in months of work, and it happened on the first night after the
application processor began actually collapsing. One occurrence is not proof of
causation, but the mechanism is plausible and specific: if CX collapses while
the controller is merely runtime-suspended, its registers are lost and it comes
back in exactly this state. Downstream has a `qcom,restore-after-cx-collapse`
property (set for sdm845, not msm8953) and mainline has a `restore_dll_config`
path in `sdhci_msm_runtime_resume()` — both are places to look, neither has been
checked yet.

**What this costs, and what it does not.** It can lose data, so no long
unattended run until it is understood. It does not threaten the port: nothing on
the phone is irreplaceable, every artefact is rebuildable from the repositories,
and the failure recovered on a plain reboot.

### 2026-08-18 morning: the gate passed, and the suspect narrowed

**The instrument is fixed and verified.** `suspend-slope.sh dryrun-20260818 60 2
120` ran the loops it was told to
([`2026-08-18_pmos_dryrun-gate.txt`](captures/2026-08-18_pmos_dryrun-gate.txt)): settle
`n=0,1`, phase A `n=0,1` with `slept=61s of 60s` both times and `suspends=2 of
2`, phase B `n=0,1`, charger restored. Long legs can be trusted again. Run this
gate after any edit to the script - it costs eight minutes and it is the only
thing standing between a shell slip and another wasted night.

**The eMMC suspicion moved from *occurrence* to *duration*.** Four readings,
none of which needed a build:

1. Vendor msm8953 does not set `qcom,restore-after-cx-collapse`. The property
   exists in the vendor tree and is applied to **sdm845 only**, on a platform
   that performs system power collapse constantly. Mainline agrees by a
   different route: `restore_dll_config` is true for the sdm845/sdm670/sc7180
   variant info and false for `qcom,sdhci-msm-v4`, which is what our node is.
2. So "CX collapsed and ate the DLL" is not the mechanism the silicon vendor
   thinks applies to this SoC. It is not disproved, but it is no longer the
   leading candidate, and no patch should be written on it yet.
3. **AP collapse alone does not do it.** Measured this morning on the running
   kernel: APSS `Shutdown count` reached 46 357 in about 43 minutes - roughly
   eighteen collapses a second - with root read-write and `mmc0` at HS400
   throughout. The card survives the event happening; whatever hurt it is not
   the event.
4. What that leaves is the other half of the change: with the vMPM deadline cap
   removed, the processor can now stay down for a **long uninterrupted stretch**
   instead of being poked awake once a second. The failure appeared at 01:16
   with the phone idle on the charger, hours after the leg ended - which is
   exactly the condition that produces the longest collapses of the night.

So the experiment is a soak, not a build: leave the phone idle on the charger
with [`emmc-watch.sh`](tools/emmc-watch.sh) running and see whether it recurs, with the
record on tmpfs this time so that it survives the filesystem it is watching.
Started 2026-08-18 at uptime 2620, `apss_shut=48262`.

☠️ **`rpm_master_stats` is a module and nothing autoloads it.** The DT node is
present and the platform device is created, but with no driver bound
`/sys/kernel/debug/qcom_rpm_master_stats/` does not exist at all. A reader that
does not `modprobe` first gets nothing and can easily read that as "the
processor never collapsed".

### 2026-08-18: why the RPM never turns the crystal off

`vlow` is the RPM's XO-off record, and APSS `XO shutdown count` has been 0 for
every boot of this investigation while MPSS (6116), PRONTO (21278) and LPASS all
shut XO down routinely. So the question "why is `vlow` zero" is the same question
as "what does the application processor hold XO for".

The answer is a standing sleep-set vote, and it is structural rather than
accidental. In `clk-smd-rpm.c` every RPM clock exists twice - a plain one and an
`_a` peer marked `active_only` - and `to_active_sleep()` is the whole difference:

```c
	if (r->active_only)
		*sleep = 0;
	else
		*sleep = *active;
```

`clk_smd_rpm_prepare()` then writes **both** sets. So preparing the plain
`bi_tcxo` asks the RPM to keep the crystal running *while the processor is
asleep*, and the RPM obliges - exactly as the vendor comment quoted earlier in
this page says it will.

☠️ **The table that used to be here named the wrong thing, and it was measured
wrong the same morning it was written - see "who actually holds it" below.**
`clk_summary` lists the devices that hold a clk *handle*, not the devices that
enabled the clock. The proof is in the same output: `gpu@1c00000` appears under
`gcc_oxili_gfx3d_clk`, whose enable count is zero.

☠️ **The tracepoint cannot answer this one.** `bi_tcxo` is `clk0/0`, and no
`clk0` write appears anywhere in the captured trace: the vote was cast once at
boot and never changed, and a tracepoint on the write path only sees changes.
This is the standing-vote blind spot noted when the trace was taken, and here it
is costing a whole resource. `clk_summary` is the instrument for this question,
not the trace.

☠️ **And mainline gave the eMMC controller an XO vote the vendor never took.**
Vendor `sdhc_1` has `iface_clk`, `core_clk`, `ice_core_clk` and nothing else;
mainline's node adds `<&rpmcc RPM_SMD_XO_CLK_SRC>` as `"xo"`. It happens not to
matter here because runtime PM releases it, but it is a difference from the
oracle that was not deliberate.

### Who actually holds it - measured 2026-08-18, and it is neither remoteproc

Two probes on the r60 package kernel
([`2026-08-18_pmos_xo-vote-probe.txt`](captures/2026-08-18_pmos_xo-vote-probe.txt)):

| step | `bi_tcxo` | `apss_xo` | `vlow` | `vmin` |
|---|---|---|---|---|
| baseline | 6 | 0 | 0 | 0 |
| after a 60 s control suspend | 9 | 0 | 0 | 0 |
| after **stopping** modem + ADSP | **9** | 0 | 0 | 0 |
| after a second 60 s suspend | 9 | 0 | 0 | 0 |
| after **unbinding** `qcom-q6v5-mss` | **9** | – | – | – |
| after **unbinding** `qcom_q6v5_pas` | **9** | – | – | – |

Neither stopping the firmware nor unbinding the driver moves the count by one.
So the experiment never changed its own input, and **the suspends in it prove
nothing about the hypothesis** - they were run against an unchanged vote.

The source says the same thing, and would have said it first. On msm8953 `"xo"`
is a **proxy** clock for the modem (`msm8953_mss.proxy_clk_names`), and
`qcom_msa_handover()` drops the proxy clocks as soon as the firmware takes over.
A running modem was never holding it.

What is left is the floor of 6 with everything idle, moving between 6 and 10 with
eMMC activity, and nothing in this instrument can attribute it further. The
question "does the sleep-set XO vote block `vlow`" is therefore still open, and
attribution by elimination has run out of levers: the way to answer it is to
make `bi_tcxo`'s sleep vote zero in the kernel and read `vlow`, not to keep
guessing at who enabled it.

☠️ **Run device probes under `systemd-run`, never in the foreground over ssh.**
The unbind probe was run directly, the ssh call hit its timeout mid-script, and
the script died with the session - leaving the modem and the ADSP unbound with
nothing left running to rebind them. `emmc-watch` survived the same moment
because it was a transient unit.

### ☠️ Six loops that could not fail, 2026-08-18

All three were mine, all three cost only wall-clock, and all three are the same
mistake: **a condition the pre-change state already satisfies**. Written down
because the next one will look just as reasonable.

```sh
until ! pgrep -f 'pmbootstrap.py build linux-fp3'; do sleep 60; done
```
The loop's own command line contains that string, so `pgrep` matched itself. It
was still "waiting for the build" forty minutes after the build finished.

```sh
until ! ssh $DEV 'systemctl is-active slope-dryrun' | grep -q active; do ...
```
`is-active` prints **`inactive`** when the unit is gone, and `inactive` contains
`active`. The loop outlived its unit by an hour.

```sh
ssh $DEV 'sudo sh -c "(sleep 2; reboot) &"'
until ssh $DEV 'uname -r' | grep -q msm8953; do sleep 10; done
```
Two faults at once. The backgrounded `reboot` died with the ssh session, so no
reboot happened at all; and the wait would not have noticed either way, because
the *old* kernel answers `uname -r` exactly like the new one. It reported
"VISSZAJÖTT" against a machine with an uptime of 1 h 49 m.

A fourth, an hour later and the same shape:

```sh
nohup pmbootstrap build ... > build.log &
until grep -q 'Finished building packages' build.log; do sleep 30; done
```
The file still held the *previous* build's log, so the wait was satisfied
before the new build had written a byte, and it reported a finished build
against a package that did not exist. Truncate the log first, and check the
artefact - not the narration.

A fifth, and this one corrupted a measurement rather than just wasting time:

```sh
load_start                      # eight busy cores, to reach the flat region faster
while :; do
	v=$(cat "$BATT/voltage_now")
	[ "$v" -le "$TARGET" ] && break
```
The threshold was chosen for a **resting** pack and tested against a **loaded**
one. Eight cores pull the terminal voltage down by about 360 mV, so the first
check read 3.954 V against a 4.030 V target, declared the descent finished after
sixty seconds, and handed a leg to the slope instrument at 4.238 V - deep in the
steep region the target exists to avoid. Shed the load and let it recover before
every comparison.

**6. Waiting for a file nothing would ever write.**

```sh
until [ -s .../bfki8zinb.output ]; do sleep 15; done
```

The output belonged to the xo-unbind probe, which had already died with its ssh
session. The file was 0 bytes at 08:05 and still 0 bytes when the loop was
killed at 10:05 - two hours of polling for a writer that no longer existed. A
wait needs a liveness check on the *producer*, not only on its product: if the
job is a transient unit, poll `systemctl is-active`, and if it is not a unit,
give the loop a bounded iteration count so it reports failure instead of
waiting forever.

The rule that fixes all six: **wait on something that changes**, and prove it
changed - and make sure the thing you compare against was measured under the
same conditions as the threshold. For a reboot that is `/proc/sys/kernel/random/boot_id`, captured before
and compared after; and schedule the reboot with `systemd-run --on-active=2` so
it survives the session that asked for it.

### ★★★ 2026-08-18: the sleep-set XO vote WAS blocking the processor - and the oracle does not do this

`clk_smd_rpm.xo_sleep_off=1`, r61, one boot, two 60 s suspends
([`2026-08-18_pmos_xo-sleep-off.txt`](captures/2026-08-18_pmos_xo-sleep-off.txt)):

| | before | with `xo_sleep_off=1` |
|---|---|---|
| APSS `XO shutdown count` | **0**, every boot since 2026-08-14 | 100 at 31 s, **1952** at 3.5 min |
| APSS `XO total duration` | 0 | 2 747 593 309 ticks ≈ **143 s** |
| suspends / failures | – | 2 / 0, resume intact |
| `vlow` / `vmin` `Count` | 0 | **0** |

So the mechanism was real: the sleep-set vote written by
`clk_smd_rpm_handoff()` at probe - before any consumer exists, which is why the
write tracepoint never saw it and why unbinding drivers did nothing - was what
kept the application processor from ever shutting the crystal down. Zero that
vote and it shuts it down constantly, and nothing breaks.

☠️ **And that is not the good news it looks like.** The Ubuntu Touch oracle,
running the vendor stack on the same hardware, reports APSS `xo_count: 0x0` and
`xo_accumulated_duration: 0x0` while its MPSS, PRONTO and LPASS all shut XO down
thousands of times
([`2026-08-15_ut_oracle_rpm-master-stats.txt`](captures/2026-08-15_ut_oracle_rpm-master-stats.txt)).
**The vendor's application processor never does this either.** Our pre-change
behaviour matched the oracle exactly; the change makes us diverge from it. So
this is either a saving the vendor leaves on the table, or a vote the processor
is supposed to hold - and nothing measured so far distinguishes those.

`vlow` and `vmin` did not move, which means whatever they record needs more than
the application processor's XO vote.

**What this costs to find out, in order:**

1. **The current.** That is the question this whole page exists for, and there is
   now a fixed instrument and a change worth A/B-ing. A slope leg with
   `xo_sleep_off=1` against one without it answers "does it save anything"
   without needing to know what `vlow` means.
2. **Whether the vendor's RPM ever reaches `vlow` at all.** Not in any capture
   we hold: the UT files carry the master stats and the downstream cpuidle LPM
   histogram, but not the RPM system sleep record, which downstream exposes at
   `/sys/kernel/debug/rpm_stats`. If the vendor also sits at zero, then `vlow`
   is not a reachable state on this SoC and it has been the wrong instrument
   since 2026-08-14 - a possibility that has never been tested.

### Where the sleep-set vote comes from, and why it is not simply a bug

`clk_smd_rpm_handoff()` writes the value into **both** the active and the sleep
set, for **every** clock in the platform's table, at probe - before any consumer
exists. The table contains both peers of each clock, so this includes the `_a`
active-only ones, whose entire reason to exist is that
`to_active_sleep()` gives them `*sleep = 0`.

That has been there since the driver's first commit, `00f64b58874e` (Georgi
Djakov, 2016), whose message says it is based on the codeaurora driver. **The
codeaurora driver does not do it.** Vendor `clk_rpmrs_handoff_smd()` sends no
RPM message at all - it sets the software rate and returns - and then defers to
`rpm_clk_prepare()`, which is otherwise line-for-line what mainline's
`clk_smd_rpm_prepare()` still is, active-only distinction included. So the
unconditional sleep-set write is a divergence introduced in the port, nine years
old, and it is on every SMD-RPM platform: msm8916, msm8974, apq8084, msm8953,
sdm660, sm6115, qcs404 and the rest.

☠️ **That does not make it a bug, and the oracle is why.** The vendor's APSS
never shuts XO down either - `xo_count: 0x0`, zero accumulated duration - so
whatever route it takes, downstream ends up holding an XO sleep vote too.
Mainline reaches the vendor's *outcome* by a mechanism the vendor does not use.
Removing the vote makes us diverge from the outcome, which is the opposite of
the usual direction of a fix, and the only thing that can say whether it is an
improvement is the current.

Worth reporting either way once there is a number; worth nothing as an argument
without one.

### ★ VERDICT: the XO sleep-vote A/B is a clean NEGATIVE, 2026-08-18 20:30

Both legs are in, both fitted with the same `slope-fit.py`, both run on r61 from
the same rootfs, 8 h apart, phase A and phase B in the same voltage windows.

| | experiment `xo_sleep_off=1` | control `xo_sleep_off=N` |
|---|---|---|
| raw file | `2026-08-18_pmos_xo-on-leg.txt` | `2026-08-18_pmos_xo-off-leg.txt` |
| APSS `XO shutdown count` during the leg | **1952** | **0** |
| phase A window | 4.0739 -> 4.0279 V | 4.0560 -> 4.0071 V |
| **phase A slope (asleep)** | **-35.29 mV/h** (r2 0.994) | **-35.44 mV/h** (r2 0.962) |
| phase B window | 3.9937 -> 3.9025 V | 3.9746 -> 3.8859 V |
| phase B slope (awake control) | -71.20 mV/h (r2 0.992) | -66.15 mV/h (r2 0.990) |
| phase B current, measured | 150.1 mA | 161.0 mA |
| derived asleep | 74.4 mA | 86.3 mA |

☠️ **Do not read that last row as a 12 mA win.** Read the row above it instead.
The two *sleep* slopes are **-35.29 and -35.44 mV/h - the same number to 0.4 %**,
measured over near-identical voltage windows, while the XO shutdown count went
from 0 to 1952 between them. The entire 74.4-vs-86.3 gap comes from the
**awake** reference disagreeing between the legs (150.1 vs 161.0 mA, -71.20 vs
-66.15 mV/h), not from anything the sleeping phone did.

So the honest statement is: **making the RPM shut the XO down 1952 times over a
90-minute suspend leg changed the measured discharge rate by nothing at all.**

That is consistent with the structural gate rather than surprising: `vlow` and
`vmin` have read 0 in every capture ever taken here, *including* the leg with
1952 XO shutdowns. The APSS master can drop its XO vote all it likes; the RPM
still never enters a low-power mode, because some other master or some rail keeps
voting. The UT oracle points the same way - the vendor's APSS does not shut the
XO down either, and the vendor phone still idles far below this.

**What this closes:** the XO branch. Do not spend more on `xo_sleep_off`, and do
not carry it as a default (it is not one - the boot label is plain
`postmarketOS`).

**What this opens:** nothing, which is exactly why the decomposition is next. No
mechanism yet accounts for even 20 mA of the ~60 mA, and this leg has just
removed one of the two candidates that looked mechanical. Every patch written
before the budget exists is a guess.

**Method note worth keeping.** The ratio method's weak point showed itself here:
the derived figure moved 16 % between two legs whose sleep behaviour was
identical, purely because phase B differed. When comparing two legs, **compare
the phase-A slopes directly** - same instrument, same window, no division - and
use the derived mA only to give the reader a scale. A ratio hides which half
moved.

### ★★★ CONFIRMED by same-day control: the modem stack costs ~36 mA ASLEEP

Leg `baseline-20260819`, **no cuts**, same pack and same day as
`nomodem-20260819`, launched by `await-charge.sh` at 99 % and run to completion:
**6 of 6 suspends**, `dpms=Off`, raw
[`2026-08-19_pmos_baseline-leg.txt`](captures/2026-08-19_pmos_baseline-leg.txt).

| leg | cut | phase-A slope | r² | phase-B awake | derived asleep |
|---|---|---|---|---|---|
| `xo-on-20260818` | — | −35.29 mV/h | 0.994 | 150.1 mA | 74.4 mA |
| `xo-off-20260818` | — | −35.44 mV/h | 0.992 | 161.0 mA | 86.3 mA |
| **`baseline-20260819`** | **—** | **−35.77 mV/h** | 0.926 | 101.3 mA | **79.1 mA** |
| **`nomodem-20260819`** | **modem stack** | **−22.62 mV/h** | 0.994 | 97.3 mA | **43.3 mA** |

Two things make this a result rather than a claim.

**The baseline reproduced.** Three legs with no cut, across two days and three
different awake controls, gave phase-A slopes of −35.29, −35.44 and −35.77 mV/h.
That is a 1.4 % spread on the quantity being compared, and it is the first time
this instrument has demonstrated its own repeatability.

**The pair is same-day and its awake controls agree.** 101.3 vs 97.3 mA, unlike
the 150-vs-161 mismatch that made yesterday's derived figures incomparable. So
here the derived numbers may be read directly: **79.1 → 43.3 mA, about 36 mA
saved asleep by stopping `ModemManager`, `rmtfs` and `tqftpserv`.**

☠️ **The window difference runs against the finding, not for it.** The control's
phase A sits at 3.97-4.02 V and the cut leg's at 4.06-4.09 V. Lower is deeper
into the plateau, where the same current produces a *flatter* slope - so the
control had the easier half of the curve and still came out steeper. The effect
is real or understated.

⚠️ The control's phase-A fit is the weak one, r² = 0.926 against 0.994 for the
cut leg. Treat 36 mA as ±5, not as three digits.

**What it is not.** It is not a fix - a phone needs its modem - and it is not
yet a mechanism. Awake, the same cut is worth ~2 mA at the floor and ~23 mA in
bursts; asleep it is worth 36 mA. Something in that stack is either keeping the
MPSS out of its own low-power state or waking the application processor
repeatedly, and those two have different fixes. **The next measurement is
wakeup accounting across a suspend**, not a patch.

### ★ RESUME POINT, 2026-08-20 05:00 - READ THIS FIRST

**Nothing is running on the device.** No transient units, no host pollers, no
guardian. The phone was rebooted at 04:48 into a clean autologin session: modem
`registered`, root `rw`, sound card present, charger connected.

☠️ **The night installed 19 packages that are still there** - the ofono stack,
`iproute2`, Qt, `icu-data-full` - and free space on `/` fell from 345 MB to
234 MB. Nothing was enabled and no boot configuration was touched, but a floor
measured after 2026-08-20 is measured on a larger install than one measured
before it. The full inventory is in
[`../../sailfish-native/README.md`](../../sailfish-native/README.md).

## What the night settled

**The ADSP leg came in, and it is a null.** `adsprestart-20260819`, gated on a
probe suspend that showed the DSP collapsing for 30 625 ms of 30 000 before the
four hours were committed. Phase-A slope **−34.32 mV/h** against the baseline's
−35.77, on an instrument whose baseline reproduces to 1.4 % across three legs -
so **4 %, and the window sits lower where the OCV curve is flatter**, which
biases it optimistic. Read it as *at most 4 %, plausibly nothing*.

**And the holder of the ADSP is named — it is upstream's, not ours.**
`c0f0000.codec` is bound to `msm8916-wcd-digital-codec`, the SoC's internal
digital codec, which is not in this phone's audio path.
`msm8916_wcd_digital_probe()` calls `clk_prepare_enable()` on `mclk`
(`LPASS_CLK_ID_INTERNAL_DIGITAL_CODEC_CORE`, supplied by the ADSP over APR) and
on `ahbix-clk`, unconditionally, releasing them only in `remove()`. No runtime PM,
no DAPM gating. ☠️ An earlier version of this page attributed it to this port's
WCD9335 MCLK work; that was wrong and is corrected in
[`leads/lpass-never-sleeps.md`](leads/lpass-never-sleeps.md).

**Four branches closed**, so nobody re-runs them: an ADSP client holding LPASS
(six stages, up to stopping the DSP); the regulator sleep set costing anything
droppable (five suspect rails became one with USB unbound, and that one is the
eMMC's); USB stopping the DSP collapsing (three alternating rounds); and the held
ADSP session being the lever (the leg above).

## Where the numbers stand

| | draw |
|---|---|
| awake idle, panel off, session running | ~58-63 mA |
| the panel, powered at zero brightness | +24.5 ± 6.4 mA |
| asleep, no cuts (`baseline-20260819`) | 79.1 mA |
| asleep, ADSP collapsing (`adsprestart-20260819`) | 70.8 mA |
| asleep, modem stack cut (`nomodem-20260819`) | 43.3 mA |
| every userspace service tested, five of five | zero |

☠️ `mem_sleep` offers **only `[s2idle]`**. "Deep sleep" here means getting the RPM
into `vlow`, and `vlow` has read **`Count: 0` in every capture ever taken on this
device** - including with the audio DSP collapsing for the whole of every suspend.
A master being down is **necessary and not sufficient**, and that is a measured
correction to the claim this investigation carried for several days.

## ★ 2026-08-20 05:45: the modem's 36 % is not AP wakeups, and not our userspace

Two censuses, twelve suspends, `tools/wakeup-census.sh`. Raw:
[`captures/2026-08-20_wakeup-census.txt`](captures/2026-08-20_wakeup-census.txt)
and [`captures/2026-08-20_mpss-census.txt`](captures/2026-08-20_mpss-census.txt).

**The AP side is a clean negative.** Six arms, alternating modem-up / modem-cut,
60 s asked each: **every one elapsed 62 s** with `suspends=+1` and no wakeup
source's active count moving. Nothing wakes the application processor early, with
the modem stack running or stopped. So the 36 % is **not** paid in resumes.

**The modem side does not confirm the other hypothesis either:**

| round | arm | MPSS shutdowns | XO off |
|---|---|---|---|
| 1 | modem up | +0 | 0 ms of 61 000 |
| 1 | modem cut | +0 | 0 ms of 62 000 |
| 2 | **modem up** | **+3** | **49 442 ms of 62 000** |
| 2 | modem cut | +0 | 0 ms of 62 000 |
| 3 | modem up | +0 | 0 ms of 62 000 |
| 3 | modem cut | +0 | 0 ms of 62 000 |

Five of six arms show the MPSS never going down across the suspend — and **the one
exception is an uncut arm**. Cutting our userspace never made the modem sleep.

Two things follow, and the second is a criticism of the original result:

1. **The modem is capable of it.** In that one arm it kept the crystal off for
   80 % of the suspend, so nothing structural prevents it. What gates it is not
   our host software.
2. ☠️ **"Cutting the modem stack" does not cut the modem.** `systemctl stop
   ModemManager rmtfs tqftpserv` stops *host* services; the radio stays powered,
   registered and attached throughout — `mmcli` says so on the way back in.
   Whatever the 36 % is, it is not "the modem being off". `rmtfs` and `tqftpserv`
   are the interesting two, because they serve the modem's own filesystem and TFTP
   requests: stopping them changes what the modem *does*, not whether it runs.

☠️ **n is 3 per arm and one positive.** This narrows; it does not name. What it
removes is the two explanations that were easiest to reach for.

## ★ 2026-08-20 11:16: the first rmtfs ab-leg ran clean and is a lead, not a result

`ab-leg.sh rmtfs-20260820 "rmtfs" 6 900` — dry run passed first (4/4 arms,
cut applied and restored), then the real leg: descent 4.39 → 4.03 V, **12 of 12
suspends slept 901–902 s of 900**, charger and greetd restored on exit. Raw:
[`captures/2026-08-20_ab-leg-rmtfs.txt`](captures/2026-08-20_ab-leg-rmtfs.txt).

| arm | n | median mV/h |
|---|---|---|
| CUT (rmtfs stopped) | 6 | **−16.33** |
| FULL | 6 | −73.02 |

Difference +56.7 mV/h in CUT's favour — 78 % of FULL — **but the within-arm
scatter is 97 mV/h and the standard error of the difference 56, so it is inside
2 SE and the fitter itself refuses it.** Several CUT arms measured *rising*
voltage: post-descent relaxation reaches well past the 20 s settle, and a 900 s
suspend does not integrate it away.

Two mechanical notes from this run: `TARGET` in `ab-leg.sh` is now
env-overridable so a dry run can skip the descent (a priced leg leaves the
default), and the leg was launched under `systemd-run --collect` so it survives
both the suspends and the SSH drops.

**Next: the same leg, stronger** — longer suspends halve the relative
relaxation noise and more anything helps the median: `ab-leg.sh rmtfs2-<date>
"rmtfs" 8 1800` (~8.5 h of arms) once the pack is back above the 4.2 V /
95 % start gates. If +56.7 mV/h is even half real, 8 × 1800 s puts it past 2 SE.

### ★★ 2026-08-20 19:30: the second leg is a clean null, and the instrument failed its power budget

`ab-leg.sh rmtfs2-20260820 "rmtfs" 8 1800` ran 11:40 → 19:26; every arm slept
1802–1803 s of 1800; ended safely on the 3.8 V floor after cycle 8's CUT arm
(8 CUT / 7 FULL arms, charger restored). Raw:
[`captures/2026-08-20_ab-leg-rmtfs2.txt`](captures/2026-08-20_ab-leg-rmtfs2.txt).

| arm | n | median mV/h |
|---|---|---|
| CUT | 8 | −40.44 |
| FULL | 7 | −39.27 |

**Difference −1.16 mV/h (3 % of FULL).** The first leg's +56.7 did not
reproduce — it was the noise its own fitter refused to accept.

☠️ **But the null is weak too, and that is the real finding.** A 36 %-of-sleep
effect is ~14 mV/h at these slopes, and the per-suspend scatter is ~87 mV/h —
so this design would need ~40 arms per side to resolve the effect it was built
to chase. Per-suspend slopes on a gauge whose single reads scatter ±138 mA are
intrinsically this noisy; the instrument that *did* detect the 36 %
(`nomodem-20260819`) integrates a whole 4 h phase into one fitted line.
**Pricing the three services separately therefore costs a slope-leg each**, the
very cost `ab-leg.sh` was invented to avoid — the invention ran and failed its
power budget. What the alternation still excludes: any *fast-acting* rmtfs
effect bigger than ~90 mV/h.

Next: `slope-leg.sh <tag> rmtfs` overnight — same instrument and protocol as
`nomodem-20260819`, one cut for the whole leg, compared by phase-A slope
against `baseline-20260819` (−35.77) and the nomodem leg.

### ★★★ 2026-08-21 00:15: rmtfs alone carries about half the modem's cost — and the effect is slow-acting

`slope-leg.sh rmtfsslope-20260820 rmtfs` ran overnight and completed clean
(6 of 6 sleeps, phase B control intact, charger restored). Raw:
[`captures/2026-08-21_pmos_rmtfs-slope-leg.txt`](captures/2026-08-21_pmos_rmtfs-slope-leg.txt).

The phase-A ladder, the comparison the instrument is built for:

| leg | cut | phase-A slope | vs baseline |
|---|---|---|---|
| `baseline-20260819` | — | −35.77 mV/h | — |
| `adsprestart-20260819` | ADSP collapsing | −34.32 | ≤4 % |
| **`rmtfsslope-20260820`** | **rmtfs only** | **−28.46** (r²=0.99) | **−20 %** |
| `nomodem-20260819` | all three | −22.62 | −37 % |

**So rmtfs alone buys about 20 % of the sleeping draw — roughly half of the
trio's 37 % — an order of magnitude past the instrument's 1.4 % spread.** The
remainder sits in `ModemManager`/`tqftpserv` or in the combination.

**And this names the shape of the mechanism.** The ab-leg alternation, which
re-applied the same cut for 30-minute windows, measured a clean null on the
same service the whole-leg cut prices at 20 %: **the effect needs time to
appear.** Whatever the modem does when its filesystem service is gone, it
takes longer than half an hour to settle into it. That is a property the
mechanism hunt can use — and it is why both results are right.

⚠️ Two honesty notes: the phase-A window (3.98→3.94 V) sits lower than the
baseline's (4.09→4.06), which biases the ratio optimistic — the direction and
order of magnitude are safe, the third digit is not. And phase B's control
came in at 124.1 mA against the usual ~150; the derived asleep figure
(71.6 mA) is therefore less comparable across legs than the slope ratio is.

Next, in order: the same whole-leg cut for `ModemManager` and for `tqftpserv`
(one night each), and only then the mechanism question — what rmtfs's absence
makes the modem stop doing, with `qcom_rpm_master_stats` (MPSS shutdowns, XO
duration) read across the sleeps of whichever leg shows the saving.

### ☠️☠️ 2026-08-21 05:00: `rmtfs -P` — stopping rmtfs POWERS THE MODEM DOWN, and it rewrites every "service cut" above

Found while recovering the phone after the second overnight leg: `ModemManager`
would not start (`msm-modem-uim-selection` looping on "node with id 0 not found
in QRTR bus"), because **the modem remoteproc (`4080000.remoteproc`) was
offline** — and had been since 23:25. The cause is in the unit file:

```
ExecStart=/usr/bin/rmtfs -r -P -s
```

`-P` powers the modem processor down when rmtfs exits. `systemctl stop rmtfs`
is therefore not a service cut — **it is a modem shutdown**. And the modem does
not come back when rmtfs restarts; it stays down until someone writes `start`
to the remoteproc (which is what the recovery did; after that MM starts and the
radio registers again — `pd-mapper` keeps failing with "no pd maps available",
noted as an open question).

What this rewrites, leg by leg:

* **`nomodem-20260819` (−37 %)** cut all three services, so it powered the
  modem down. Its honest name is *modem-off*, not "modem stack cut". The ~36 mA
  is what the **modem processor being off** is worth — unusable as a fix, since
  the phone needs the modem, but finally a named mechanism.
* **`rmtfsslope-20260820` (−20 %)** also powered the modem down at the cut.
  Same state, measured lower — the two legs disagree by more than the
  instrument's spread, and the differing voltage windows are the suspect.
* **`mmslope-20260821` (−27 %)** is **contaminated**: the modem was already
  offline for its entire duration (never rebooted after the rmtfs leg). It
  measured *modem-off + MM stopped*, not "MM alone". Its number must not be
  read as ModemManager's price.
* **The ab-leg null and the "slow-acting effect" story are both re-explained,
  and the story is retracted.** The first CUT arm powered the modem down; the
  rmtfs restart between arms did not bring it back; so every subsequent arm —
  CUT and FULL alike — ran modem-off. Identical states, null by construction.
  Nothing here ever measured a slow-acting effect.
* **The 2026-08-20 05:45 census line "the radio stays powered, registered and
  attached throughout" needs re-reading** — it was taken across stop/restart
  cycles of all three services and `mmcli` answered on the way back in. With
  `-P` in the unit, what exactly the modem was during those arms is now an
  open question, not a fact.

The method lesson is the same one the USB census taught, one layer deeper:
**"stop a userspace service" is not a bounded intervention until every side
effect of the stop is enumerated.** `-P` was in the unit file all along; nobody
had read it.

What a valid service-pricing now requires: the modem verified `running` at cut
time and at leg end (one `cat /sys/class/remoteproc/*/state` in the leg
preamble and epilogue), and **rmtfs never stopped** while pricing anything
other than modem-off itself.

### ★★★ 2026-08-21 09:20: the first VALID service price — ModemManager alone is ~10 %, not 27 %

Leg `mmslope2-20260821`, run exactly to the validity rule above: only
`ModemManager` cut, `rmtfs` untouched, and the mpss verified `running` in the
preamble, at every monitor poll, **and in the epilogue**. 6 of 6 suspends
completed, rc=0, charger restored. Raw:
[`captures/2026-08-21_pmos_mm2-slope-leg.txt`](captures/2026-08-21_pmos_mm2-slope-leg.txt).

| phase | window | slope | r² | `current_now` mean |
|---|---|---|---|---|
| A (asleep, MM cut, modem RUNNING) | 3.9472 → 3.9037 V | **−32.23 mV/h** | 0.9693 | 133.1 mA |
| B (awake control) | 3.8714 → 3.7996 V | −55.06 mV/h | 0.9885 | 144.3 mA |

Read against the phase-A ladder: baseline −35.77, this leg −32.23 — **the
ModemManager daemon with the modem alive is worth about 3.5 mV/h, ~10 % of
sleeping draw.** The earlier `mmslope` leg's −26.13 (−27 %) is confirmed void:
most of what it "measured" was the `-P`-powered-down modem it inherited from
the rmtfs leg before it. The adsprestart leg put per-leg reproducibility at
≤4 %, so ~10 % is above the noise floor but only just — it is a real but
minor cost, and it does **not** carry the modem's 36 %.

What this decides: **the modem's ~36 % (nomodem −22.62 vs baseline −35.77) is
the modem processor itself being up, not any one userspace daemon.** MM is
~10 %; the remainder is the MPSS's own floor (XO holds, RPM votes cast by the
modem as an RPM master). A tqftpserv leg is now unlikely to find more than
noise — the interesting instrument is `qcom_rpm_master_stats` around sleeps:
does the MPSS ever XO-shutdown while registered, and if not, is that a
network/config question (PSM, eDRX, band) rather than an AP-side one.

### ★★ 2026-08-21 09:31: the MPSS duty-cycles during AP suspend — XO held ~37 % of the time

Answered the same morning, on the charger (this probe counts shutdowns, it does
not need a discharge leg). Snapshots of `qcom_rpm_master_stats` around one
`rtcwake -m mem -s 300`, modem registered throughout. Raw:
[`captures/2026-08-21_pmos_mpss-xo-suspend-probe.txt`](captures/2026-08-21_pmos_mpss-xo-suspend-probe.txt).
Tick rate is the 19.2 MHz XO (verified: the APSS timestamp delta over the
307 s wall window is 5.90e9 ticks).

| master | Δ shutdowns | Δ XO-off time | share of the 307 s window |
|---|---|---|---|
| MPSS | +745 | +194.0 s | **63 % off, 37 % holding XO** |
| PRONTO | +31 | +303.7 s | ~99 % off |
| APSS | +89 | 0 | never XO-shutdowns (vendor identical) |
| LPASS | **+0** | +0 | still never sleeps |

So the modem is **not** a master that never sleeps — it wakes ~2.5×/s
(745/300, faster than a bare 1.28 s LTE paging cycle, so more than paging is
running) and holds the crystal ~113 s out of every 300. That residency is the
mechanism behind the remaining ~26 % (36 % modem-off minus ~10 % MM): it is
**network/protocol territory — paging cadence, PSM/eDRX — not an AP-side kernel
defect.** The AP-side avenues on the modem are closed; what would move it is
carrier/modem configuration, which is out of scope for this bring-up.

Two standing facts restated by the same capture: the LPASS took zero new
shutdowns across the suspend (the never-sleeps lead is still the open AP-side
item), and the APSS never XO-shutdowns by design — matching the oracle.

### ★★★ 2026-08-21 midday: the LPASS sleeps PERMANENTLY once the audio-card boot path is out

The never-sleeps hunt ran the same day as a live-removal ladder plus a
module-blacklist bisection over ~6 reboots. Every live removal failed —
userspace audio (pipewire/pulseaudio, socket-masked and autospawn-off),
our watchers (fp3-voiced/spkwatch/ringwatch), the SMGR sensor stack, the
sound card, the internal codec, even the SLIMbus NGD controller: with all
of them gone the LPASS still would not take a shutdown, and an ADSP SSR in
that fully stripped state released it within 10 s (2 → 17 shutdowns). So
the holding state lives **inside the ADSP**, is created once at boot, and
no AP-side handle removal releases it — only firmware restart, or not
creating it in the first place.

The blacklist bisection then found the creator. With
`snd_soc_apq8016_sbc` + `snd_soc_msm8916_digital` + wcd9335 + NGD + smgr
all blocked at boot, the LPASS enters XO shutdown ~75 s into boot and
**stays there indefinitely** (`Active cores bitmask: 0x0`, last-enter >
last-exit, counters static because nothing wakes it). The full q6/APR
module stack was loaded on that boot — **the q6 protocol layer is
exonerated**; the culprit is in the card/codec/wcd9335/NGD probe group
(bisection of that group in progress below).

☠️ **Method trap that cost several reads: a static shutdown counter is
ambiguous.** "Count stopped growing" means *frozen awake* only if
last-XO-exit > last-XO-enter; when last-enter is the newer timestamp the
master is DOWN and staying down — the success case reads identically to
the failure case in the count column. Always capture the full stats
block, never just the two counts.

☠️ And a permanent LPASS sleep did **not** move `vlow` (still 0, client
votes 0x1050105) — LPASS was necessary, not sufficient. The LDO
active-only sleep-set gap (`leads/rpm-sleep-set.md`) remains the next
named blocker.

### ★★★ 2026-08-21 12:10: the codec fix works — and a SECOND, later latch showed itself

The culprit was pinned to `msm8916-wcd-digital` (codec loaded with the card
blocked → frozen awake from ~27 s; codec blocked → sleeps forever), i.e. the
probe-time unconditional `clk_prepare_enable(mclk)` — on msm8953 mclk is the
ADSP's own q6afecc `LPASS_CLK_ID_INTERNAL_DIGITAL_CODEC_CORE`, so the enable
is a standing AFE clock request. The one-way behaviour (releasing the clock
live does not help, only SSR does) means the DSP **latches awake on the first
request**, so the fix is to never make it at probe: mclk moved into the DAI
startup/shutdown path. Kernel commit `4b09b2158dd8` on `wip/7.1.3/power`
("ASoC: msm8916-wcd-digital: hold mclk only while a stream runs"),
hot-swap-deployed as `snd-soc-msm8916-digital.ko` (clang-built test vehicle,
vermagic-matched; the ftrace WARN it may log is the known toolchain-mismatch
artifact, not a defect).

Rebooted with the FULL stack restored (card, wcd9335, NGD, smgr, pipewire,
pulseaudio, watchers): **LPASS took 56 shutdowns in the first two minutes**
against 2-for-the-whole-uptime before. The fix is proven necessary.

☠️ **And then a second latch fired.** At ~38.8 s (ADSP ticks) the LPASS
froze awake again — during session bring-up (pulseaudio's UCM profile probe
opens every PCM around 24 s; the exact trigger between 24–52 s is not yet
pinned). Same one-way signature: no PCM open afterwards, mclk enable-count 0,
NGD runtime-suspended, and stopping watchers/iio-sensor-proxy/snsregd or
removing the smgr modules releases nothing. The aw8898's DAPM widgets
(IN/SPK PA/OUT) read On with the BE DAI off — worth chasing, but not the
ADSP holder by itself. The UT oracle plays audio and still sleeps 4344×, so
mainline is missing some teardown the vendor stack performs after audio use.
**Open follow-up: find what the first audio-path use leaves behind in the
ADSP** — candidates: q6afe port start/stop asymmetry, q6adm/q6asm session
teardown, an ADSP-internal object created on first APR audio traffic.

☠️ Every live-removal negative from the earlier round was confounded: the
codec latch was present on all those boots, so "removing X does not release
LPASS" said nothing about X. With the codec fixed, live removals get their
meaning back — and the second latch has already been probed clean of the
sensor stack and our watchers.

Audio regression: `speaker-test` runs; `fp3-selftest --only speaker-amp`
FAILs with the **documented pre-existing aw8898 death signature** (amp not
answering on I2C) — the patch touches only the internal codec, and this is
the known open bug, not a regression. The wcd9335 acoustic path needs an
`--acoustic` run with a human when convenient.

☠️ Recovery notes from the live-removal round: rebinding the sound card
after an unbind fails with `genirq: Flags mismatch irq 143` → `-EBUSY`
(wcd9335 never frees its SLIM Slave IRQ on teardown — itself a bug worth
fixing); only a reboot restores audio. The greetd-user pipewire masks do
nothing — since the 2026-08-16 autologin the session user is fp3, and
`systemctl mask` on our /etc-installed watcher units fails ("File exists");
`systemctl disable --now` is the working form. A plain `blacklist` line
does not stop dependency-loads by name — `install <mod> /bin/false` does.

### ★★★ 2026-08-22 10:30: the SECOND latch is GONE — it was the missing disable_stream teardown

Measured on the first ordinary boot of the r64 package kernel (`#65-fp3`,
built 2026-08-21 18:29, the first *installed* kernel carrying both the mclk
fix `4b09b2158dd8` **and** the SLIMbus `disable_stream` fix `dbb414e0be28`),
full stack up — card, wcd9335, NGD, smgr, pipewire, pulseaudio, watchers,
autologin session:

* At 82 min uptime the LPASS sat in XO shutdown (last-enter > last-exit,
  `Active cores bitmask: 0x0`), 66 XO shutdowns / 81 shutdowns taken, and a
  45 s two-point sample showed the counters static **in the down state** —
  the success signature, per the static-counter trap above.
* Live trigger test: 5 s of `speaker-test` through the default path, then
  one read 30 s later — **+3 XO shutdowns, back down** (enter > exit,
  bitmask 0x0). Audio use no longer pins the ADSP.
  cmd: `speaker-test -t sine -f 440 -l 1`, then
  `grep -E 'count|enter|exit|Active' .../qcom_rpm_master_stats/LPASS`.

So the "second latch" of 2026-08-21 12:10 needs its attribution corrected:
that boot ran the *pre-r64* kernel with only the mclk fix hot-swapped as a
`.ko` — its SLIMbus controller still dropped the stream-teardown messages,
so the first PCM open over SLIMbus left the ADSP holding the channel and an
XO vote forever. That is exactly the defect `dbb414e0be28` (and upstream's
pending disable_stream patch, see `lkml-drafts/`) fixes, and with it in the
booted kernel the latch is unreproducible. The open follow-up "find what the
first audio-path use leaves behind in the ADSP" is **closed: a SLIMbus
channel + XO vote, released by disable_stream**. The q6afe/q6adm/q6asm
teardown-asymmetry candidates were never the culprit.

Standing consequence for the ladder: with both latches fixed in the package
kernel, the LPASS now duty-cycles on an ordinary boot with the full audio
stack — the "LPASS never sleeps" lead is closed end-to-end.

## Next, in order

**The instrument for it is written and unarmed:**
[`tools/ab-leg.sh`](tools/ab-leg.sh) + [`tools/ab-leg-fit.py`](tools/ab-leg-fit.py).
One descent, then the arms **alternate** — one suspend with the cut, one without,
repeating — so drift, temperature and the OCV curve's shape act on both equally
and no cross-day control is needed. Both arms from one pack.

☠️ **Run the dry run after any edit**: `ab-leg.sh dryrun-ab "rmtfs" 2 60`.

☠️ **The obvious analysis is wrong and a synthetic test caught it before any
device time was spent.** Regressing all of one arm's samples against time is
contaminated: between two CUT suspends the FULL arm ran and discharged the pack,
so that discharge lands in the CUT fit's gaps. On data built with a true 11.6 mV/h
difference, the whole-arm regression reported **2.1**. The fitter therefore
compares **per-suspend** slopes, and it was proved on three known answers — a real
37 % effect (found), identical arms (refused), and one usable suspend per arm
(refused, after that case crashed it).

☠️ **A null from this leg means "no fast-acting difference".** The cut is
re-applied from cold every cycle, so an effect that needs ten quiet minutes to
appear cannot show up in a 900 s alternation.

☠️ **And there is no fast instrument to do it with.** `charge_now` was tested as a
way to price a state in fifteen minutes instead of four hours
([`captures/2026-08-20_coulomb-probe.txt`](captures/2026-08-20_coulomb-probe.txt)):
it has 0.01 % resolution, which was the hopeful part, but it is an OCV lookup and
not a coulomb count — `dQ/dt` read 85.2 mA where medianed `current_now` read 62.0,
37 % apart in the direction sag predicts. **Sleeping currents still cost a slope
leg**, so a three-way service cut is three legs, and the way to afford it is the
alternating-arms-within-one-descent design, not a cheaper meter.

1. **The modem's 36 %, now narrower.** AP wakeups are excluded and a userspace
   cut does not move the MPSS, so the next question is which of the three
   services carries it — and `rmtfs` is the first suspect, because it answers the
   modem's own filesystem requests and stopping it changes what the modem does
   rather than whether it runs. A three-way `freq-probe`-style cut, one service at
   a time, prices them separately. **Partly answered 2026-08-21 09:20: MM alone
   is ~10 %; the bulk of the 36 % is the MPSS itself. Next instrument is
   `qcom_rpm_master_stats` around sleeps, not another service leg.**
2. **What else votes.** The regulator branch and the master branch are both
   closed, so what is left is another master or a standing resource vote. ☠️ The
   `qcom_rpm_smd_write` tracepoint is blind to a vote cast once at boot and never
   changed - `clk_summary` is the instrument for those, not the trace.
3. **Confirm and fix the internal codec's clocks** - one `unbind` and a 30 s
   suspend confirms it; the fix is runtime PM or DAPM gating in
   `msm8916-wcd-digital.c`. Upstreamable. ☠️ Not scheduled for its current: ~4 %.

☠️ Still no patch on any of this. Four mechanically plausible branches have now
closed, two of them because someone asked what *else* was true of the phone at
the time - and the answer both times was a USB cable.

### ★★ The modem stack is the first thing to move the SUSPEND number, 2026-08-19 08:20

Leg `nomodem-20260819`, `slope-leg.sh` with `ModemManager rmtfs tqftpserv` cut,
started from a full pack. **6 of 6 suspends, every one `slept=902s of 900s`** -
nothing woke it early. Raw: [`2026-08-19_pmos_nomodem-leg.txt`](captures/2026-08-19_pmos_nomodem-leg.txt).

| phase | window | slope | r² | `current_now` mean |
|---|---|---|---|---|
| A (asleep) | 4.0879 → 4.0592 V | **−22.62 mV/h** | 0.9938 | 94.0 mA |
| B (awake control) | 4.0308 → 3.9634 V | −50.86 mV/h | 0.9973 | 97.3 mA |

Both fits are the best this instrument has produced.

**Compare phase-A slopes directly, per the rule the XO A/B paid for:**

| leg | cut | phase-A slope | window |
|---|---|---|---|
| `xo-on-20260818` | — | −35.29 mV/h | 4.074 → 4.028 V |
| `xo-off-20260818` | — | −35.44 mV/h | 4.056 → 4.007 V |
| **`nomodem-20260819`** | **modem stack** | **−22.62 mV/h** | 4.088 → 4.059 V |

**The sleeping discharge rate fell by 36 %.** And the direction is conservative:
today's window sits 30-50 mV *higher*, where the OCV curve is steeper and the
same current would produce a *faster* voltage fall. The effect is real or
understated, not inflated by the window.

Converted to current it is 43-55 mA asleep against 68-86 mA for the two legs of
2026-08-18, depending on which leg's awake control is used to calibrate - call
it **25-30 mA saved asleep**, and do not quote a third digit.

☠️ **The awake control is 97.3 mA and the figure this instrument has always
reproduced is ~155 mA.** By the rule written on the fitter itself, that is where
you stop and ask why. The answer is consistent rather than alarming: `freq-probe`
measured the modem cut as worth ~2 mA at the *floor* but ~23 mA at the *median*,
i.e. the modem stack's cost is bursts, not baseline - and a discharge slope
integrates bursts. The awake slope fell 23 % (−66.15 → −50.86 mV/h) in the same
leg, which is the same story from the other instrument. It still means **this
leg's derived mA cannot be compared with yesterday's derived mA**; only the
slopes can.

☠️ **This needs a same-day control before it is a result.** Every comparison
above is against legs from a different day. The one experiment that settles it
is `slope-leg.sh` with no cut, run next, on this pack and this boot sequence.
Until then the honest claim is: *a leg with the modem stack cut discharged 36 %
more slowly asleep than two legs without it, taken the day before.*

### ☠️ The vlow vote mask is live, and a before/after reading of it proves nothing

`qcom_stats/vlow` carries a `Client Votes` field. Read before the leg it was
`0x17131715`; read after, with the modem stopped, `0x15111511` - which looked
like the modem's bits clearing, and would have been a genuine instrument on the
structural gate.

It is not. Re-read three times over thirty seconds with every service running
again, it gave `0x15111511`, then `0x13171511`, then `0x17131713`. **The mask is
an instantaneous sample and it fluctuates on its own.** A single before/after
pair of it means nothing; using it at all would need repeated sampling at
suspend entry.

`Count` remains **0** in both, as in every capture ever taken on this device.
The gate did not open, even in the leg that saved 25-30 mA.

### ★ RESUME POINT, 2026-08-19 04:15

**Running on the device:** `slope.service` -
`slope-leg.sh nomodem-20260819 ModemManager rmtfs tqftpserv`, started 04:10 from
a full pack (100 %, 4.329 V). Descent, 1800 s settle, 6x900 s asleep, 6x900 s
awake control. Ends about **08:15**. A host poller checks every 4 minutes and
exits when the unit does.

☠️ **Nothing else may touch the device until it finishes** - no `apk`, no
`episode-watch.sh`, no CPU-heavy anything. Phase A is measuring suspends; a
wakeup a minute would be measuring the instrument.

**Why the modem cut.** Awake it is worth 2 mA (`freq-probe`), so any difference
asleep is attributable to the *sleep-vote* path rather than to awake load - and
MPSS is one of the masters whose vote the RPM waits on. Every other candidate
the ladder tested came back zero.

Baseline for it, captured 04:08: `qcom_stats/vlow` **Count 0**,
`Client Votes: 0x17131715`. As it has been in every capture ever taken here.

**Order for what remains** (the user reversed it; the install still has to
precede the legs that need it):

| # | what | how long |
|---|---|---|
| 1 | *(running)* deep-sleep slope leg | → 08:15 |
| 2 | redo ladder stage S5 - "wifi costs 0.6 mA" was measured inside the anomaly and is void | ~25 min |
| 3 | Sxmo install: `apk add --simulate` first, read for `Purging`, then boot-fallback check | ~30 min |
| 4 | four `de-compare.sh` legs, one boot each | ~2 h 45 |

**New and not yet deployed:** `episode-watch.sh`. On 2026-08-18 the idle floor
doubled for ~44 minutes, silenced the PLL storm entirely, and cleared on its
own; the ladder mis-attributed it and the controlled probe exonerated the cut,
leaving it unexplained with nothing watching for it. This samples current
(median of nine reads), cpufreq residency, transition counts and the PLL failure
count once a minute to tmpfs, bounded to 48 h. Deploy it **after** the slope
leg, and never during one.

### Superseded - the A leg, started 2026-08-18 08:5x

`leg3` is a transient systemd unit on the device. To see where it is:

```sh
ssh fp3@172.16.42.1 'sudo systemctl is-active leg3'
ssh fp3@172.16.42.1 'sudo tail -20 /var/log/leg3-20260818.txt'   # descent
ssh fp3@172.16.42.1 'cat /home/fp3/suspend-slope.txt'            # the leg itself
```

When it finishes, fit it and compare against the reference:

```sh
scp fp3@172.16.42.1:/home/fp3/suspend-slope.txt docs/power/2026-08-18_pmos_xo-on-leg.txt
python3 docs/power/slope-fit.py docs/power/2026-08-18_pmos_xo-on-leg.txt
python3 docs/power/slope-fit.py docs/power/2026-08-17_pmos_post-pll-slope-leg.txt   # 60.1 mA
```

☠️ **Read phase B first.** If its directly-measured awake current is not the
figure already known (~155 mA), the ratio means nothing and the leg is void -
that check is what withdrew the leg of 2026-08-17.

☠️ **Read the settle rows before trusting phase A.** The descent runs eight busy
cores, which took the pack from 29.4 °C to about 38 °C, and a cooling pack reads
a falling voltage that has nothing to do with charge leaving it. `SETTLE_OFF` is
1800 s for this leg specifically to burn that off; the settle rows are what say
whether it was enough.

**Then the control leg**, which is the whole point. The script for it exists:
`docs/power/bringup/tools/leg3-control.sh`, installed as `/root/leg3-control.sh` - `leg3.sh`
with the guard inverted, the tag `xo-off-20260818`, the log
`/var/log/leg3c-20260818.txt`, and two guards the A leg did not need (see
below). Neither number means anything alone.

Full sequence, in order, and none of the steps is optional:

```sh
# 1. Charge back up. The A leg started its descent at 4.266 V and ended the
#    run near 3.9 V; leg3-control.sh refuses to start below START_MIN=4.200 V
#    because a control that begins on a half-empty pack sits on a different
#    part of the discharge curve, which is exactly what withdrew 2026-08-17.
ssh fp3@192.168.100.17 'cat /sys/class/power_supply/pmi632-battery/voltage_now'

# 2. ☠️ Check the charger is actually taking. suspend-slope.sh suspends USBIN
#    and the bit lives in the PMIC across a warm reboot.
ssh fp3@192.168.100.17 'cat /sys/class/power_supply/pmi632-charger/online'
# if 0:  echo Charging > /sys/class/power_supply/pmi632-charger/status

# 3. Switch the boot label back and reboot. This is also the step that undoes
#    the experiment-as-resting-state, so it has to happen anyway.
sudo sed -i 's/^default .*/default postmarketOS/' /boot/extlinux/extlinux.conf
sudo reboot                       # allow ~5 min; r60/r61 have both been slow

# 4. Confirm the fact, not the label.
cat /sys/module/clk_smd_rpm/parameters/xo_sleep_off        # must read N
cat /proc/cmdline                                          # no xo_sleep_off=1
sudo modprobe rpm_master_stats     # nothing autoloads it

# 5. Run it as a transient unit. ☠️ A foreground ssh command dies with the
#    session; that is how the xo-unbind probe left the modem unbound.
sudo systemd-run --unit=leg3c --collect /root/leg3-control.sh
sudo systemd-run --unit=emmc-watch --collect /root/emmc-watch.sh
```

The script moves `/home/fp3/suspend-slope.txt` aside by itself this time
(`.pre-xo-off-20260818`), because that file is append-only across runs and
still holds the A leg's samples. Read phase B first, then the settle rows,
then compare - the same order as for the A leg.

☠️ `/home/fp3/suspend-slope.txt` is append-only across runs and the aborted
first attempt wrote settle rows under the same tag. It was moved to
`suspend-slope.pre-xo-leg.txt` before this leg started; `leg3-control.sh` now
does that move itself rather than trusting anyone to remember it.

**Boot state right now:** `default postmarketOS-xo`, which is r61 plus
`clk_smd_rpm.xo_sleep_off=1`. The plain `postmarketOS` label is the same kernel
without it, and `postmarketOS-fallback` is r60. Put the default back to
`postmarketOS` when the A/B is done - the experiment must not become the
resting state.

### What the leg is, started 2026-08-18 09:00

`leg3.sh` on the device, as a transient unit: ride the pack from 4.379 V down to
4.030 V - the flat part of the curve, which is what withdrew the leg of
2026-08-17 - then hand over to `suspend-slope.sh xo-on-20260818 900 6`. Six
15-minute sleeps and six awake controls, roughly five hours end to end with the
discharge.

☠️ It refuses to start unless `/sys/module/clk_smd_rpm/parameters/xo_sleep_off`
reads `Y`. A leg that cannot say which side of an A/B it measured is worth
nothing, and the tag in the sample lines is a promise while the parameter is the
fact.

The control leg is the same script from the plain `postmarketOS` boot label,
which has to be run before the two can be compared. Neither number means
anything alone.

After this leg the phone sits at the greeter, because `suspend-slope.sh` stops
`greetd` and restarting it does not restart the session - reboot before reading
`03-autologin`.

**Order of work from here:**

1. ~~Dry-run the fixed instrument~~ — **done 2026-08-18, passed.**
2. eMMC soak running. AP collapse alone is excluded; the open question is
   whether a *long* collapse does it. If it recurs, the separation is cheap:
   restore the vMPM deadline cap alone and the AP still collapses, just never
   for long.
3. The next slope leg.
4. The XO vote above, which now looks like a bigger lever than the LDOs: the
   RPM cannot enter `vlow` at all while any sleep-set XO vote stands, and no
   amount of regulator work changes that.

☠️ **Do not mirror the active vote into the sleep set and expect anything.**
The RPM already treats a missing sleep-set request as "use the active one at all
times", so writing the same numbers into both sets is a no-op by construction.
What is needed is a sleep vote that is *lower* than the active one, which in
mainline terms means `regulator-state-mem` subnodes and `set_suspend_*` ops in
`qcom_smd-regulator.c` - a design, not a one-liner.

### The LDO layer, read against the vendor source - 2026-08-18, offline

The tracepoint run said the LDOs are the only RPM clients that never vote for
sleep (14 active / 0 sleep). The source says why, and the vendor tree on disk
says what the missing mechanism looks like.

**Mainline sends no sleep-set request for any regulator, ever.**
`drivers/regulator/qcom_smd-regulator.c` contains exactly one
`qcom_rpm_smd_write()`, in `rpm_reg_write_active()`, and it is hard-coded to
`QCOM_SMD_RPM_ACTIVE_STATE`. There is no sleep path to be missing a case in;
the concept is absent from the driver.

**The vendor expresses it in the binding.** In
`hadk22/kernel/fairphone/sdm632/drivers/regulator/rpm-smd-regulator.c`,
`qcom,set` is a *mandatory* per-node bitmask - `BIT(0)` active, `BIT(1)` sleep -
and probe fails without it. The driver creates two RPM handles
(`handle_active`, `handle_sleep`) and aggregates the two sets separately.

**And the FP3's own DT uses all three values.** From
`arch/arm64/boot/dts/qcom/msm8953-regulator.dtsi`:

| node | `qcom,set` | meaning |
|---|---|---|
| `pm8953_s2_level`, `pm8953_s7_level` | 3 | both sets |
| `pm8953_s2_level_ao`, `pm8953_s7_level_ao`, `pm8953_l7_ao` | 1 | active only |
| `pm8953_s7_level_so` | 2 | **sleep only** |

That is the same shape `clk-smd-rpm` uses for clocks, where every RPM clock has
a plain node and an `_a` `active_only` peer. One physical rail, up to three
regulator nodes, and the consumer picks its set by picking the node. Mainline
collapses that to one node per rail which is, in write terms, permanently
active-only.

☠️ **Do not build the obvious change.** Mirroring the active request into the
sleep set is a no-op by construction: a resource with no sleep-set request has
its active request used at all times, so an explicit mirror produces the same
aggregate. That is the same reasoning that made the XO experiment worth
building only because it wrote a *lower* sleep value, not an equal one.

The informative change is an explicit sleep-set request with `swen=0` for rails
nothing needs in suspend - and it is not blanket-safe, because
`regulator-always-on` rails and anything the modem or memory needs across
suspend must keep their vote. So the next step is data, not code: **the list of
the 14 rails still holding an active vote at suspend entry**, which the
`qcom_rpm_smd_write` tracepoint already collects. Take it after the A/B legs;
the device is committed until then.

### The A leg landed: 74.4 mA with the sleep-set XO vote zeroed

`docs/power/bringup/captures/2026-08-18_pmos_xo-on-leg.txt`, r61 booted from the
`postmarketOS-xo` label (`clk_smd_rpm.xo_sleep_off=1`), `leg3.sh` from
4.266 V down to 4.018 V under load, 1800 s settle, then six 900 s sleeps and
six awake windows. All six suspends completed (`slept=901s of 900s`), the
script exited rc=0 and restored the charger.

```
phase A  4.0739 -> 4.0279 V   slope -35.29 mV/h   r2=0.9938   I mean 137.6 mA
phase B  3.9937 -> 3.9025 V   slope -71.20 mV/h   r2=0.9922   I mean 150.1 mA
RESULT   asleep 74.4 mA   (= 150.1 x 0.496)
```

**The control passes.** Phase B's directly-measured awake current is 150.1 mA
against the 155.3 mA this instrument has returned before, so the method is
intact and the awake regime is unchanged. Two early phase-B windows read 101
and 126 mA and briefly looked like the awake baseline had moved; they were
settling, and the six-window mean is what counts. A partial phase is not a
phase.

☠️ **Do not compare this to the reference leg's 60.1 mA.** That was a different
day, a lower state of charge and an earlier kernel. And within this leg the two
phases do not share a region: phase A sits at 4.03-4.07 V, above the plateau,
while phase B is at 3.90-3.99 V inside it. That is the same systematic that
withdrew 2026-08-17, much milder here but pointing the same way - it inflates
phase A's mV/h and therefore the computed sleep current, so 74.4 mA is an upper
bound rather than a figure.

**Which is exactly why the number that matters is the difference.**
`leg3-control.sh` rides down to the same 4.030 V target from the same 99%
start, so its two phases land in the same two regions and the systematic
cancels in the A-vs-control comparison even though it does not cancel inside
either leg.

## 2026-08-22 — the PLL enable-failure fix landed (v2), measured clean

`apcs-cpu0/cpu4-pll failed to enable!` (35 warnings in a 94-minute r64 window;
~18 per 10000 frequency transitions): sugov reprograms a cluster's PLL from the
other cluster, and if the owner power-collapses mid-latch the SPM gates the PLL
and the lock poll times out. Fix on all three fork layers
(`wip/7.1.3/power` a05596e933a5 / `integration/7.1.3` 43711fd59d49 /
`debug-int/7.1.3` c5a18f94965e): a clk-notifier holds a **global
cpu_latency_qos** request at 0 (WFI only) across PRE→POST_RATE_CHANGE plus an
`smp_call_function_any()` kick.

☠️ **The first version used per-CPU dev_pm_qos and deadlocked on every boot** —
sysrq-w caught the ABBA live: the notifier held `clk_prepare_lock` and wanted
the CPU device's dev_pm_qos mutex, while the msm GPU devfreq's min_freq QoS
notifier held that mutex and called back into `clk_set_rate`. Every clk op
(sdhci runtime PM included) queued behind it and the wedge looked like storage
death. Evidence: `/mnt/1TB/Fp3-Sailfish/pll-deadlock-20260822/`; the v1 tips
are kept as `archive/pll-v1-deadlock-*`. cpu_latency_qos has no notifier chain
(kernel/power/qos.c) — spinlock only — so it is safe under clk_prepare_lock.

Validation on r65 (#66-fp3), power collapse enabled throughout:

```
30 min bursty load, both clusters (pll-v2-meas.sh):
  27720 freq transitions (7965 c0 + 19755 c4), 24916 power-collapse entries
  PLL enable failures: 0        (baseline predicts ~50 for this window)
plus a 37-min idle window earlier the same boot: 0 failures (r64 idle: ~14)
```

cpuidle sanity: state1 usage kept climbing during and after the run — the QoS
request does not stick outside the rate-change window.
