# The instruments

> ⚠️ **AI-generated.** Maintained by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

Everything that measured a number in [`../../README.md`](../../README.md). They
are kept together because most of the mistakes in this investigation were
instrument mistakes, not reasoning mistakes, and the fix always ended up written
into the script that made it.

☠️ **Run every one of these under `systemd-run --unit=… --collect`, never in the
foreground over ssh.** An ssh timeout once killed a probe mid-script and left the
modem and the ADSP unbound with nothing running to rebind them. The unattended
wrapper for all of it is [`../night/`](../night/README.md).

## Measuring a current

| tool | the question it answers |
|---|---|
| [`slope-leg.sh`](slope-leg.sh) | **the workhorse.** A discharge-slope leg with an arbitrary cut applied: descend, settle, six sleeps, then six awake controls. ☠️ Compare phase-A slopes between legs directly; the derived mA is for scale only |
| [`slope-fit.py`](slope-fit.py) | reduce a slope run to a current: `I_sleep = I_awake × (slope_A / slope_B)` |
| [`suspend-slope.sh`](suspend-slope.sh), [`suspend-leg.sh`](suspend-leg.sh) | the earlier, single-purpose versions `slope-leg.sh` generalises |
| [`idle-leg.sh`](idle-leg.sh) | one leg of an awake idle measurement |
| [`await-charge.sh`](await-charge.sh) | wait for a full pack, then `exec` the next measurement — so one transient unit covers the whole chain |

## Decomposing the awake floor

| tool | the question it answers |
|---|---|
| [`idle-ladder.sh`](idle-ladder.sh) | one-boot cumulative subtraction, S0–S5 plus a restore control. ☠️ A cumulative ladder attributes any episode inside a stage to that stage's cut — use it to generate candidates, not to price them |
| [`idle-ladder-fit.py`](idle-ladder-fit.py) | the floor (p10) with a bootstrap SE, the median with its own, and every marginal marked when it is inside the noise |
| [`freq-probe.sh`](freq-probe.sh) | the controlled three-phase version: baseline, cut, restored, in one boot. This is what refuted the ladder's "the modem costs 84 mA" |
| [`de-compare.sh`](de-compare.sh), [`de-compare-fit.py`](de-compare-fit.py), [`de-switch.sh`](de-switch.sh) | one desktop environment against another, and the greetd switch that arranges it |

## Comparing the two systems

The goal stated 2026-08-24 is a comparison — pmOS down to the oracle's level or
below — so the numbers on the two sides have to come from one instrument on one
protocol, or they are two measurements rather than a comparison.

| tool | the question it answers |
|---|---|
| [`idle-ab.sh`](idle-ab.sh) | **the instrument the goal is scored on.** The same awake-idle measurement on pmOS and on Ubuntu Touch: panel off, on battery with the cable still in, radio up. Reports the floor (p10) and the median, never a mean, and integrates `bms/cc_soc` where the gauge exists |
| [`panel-witness.sh`](panel-witness.sh) | every candidate answer to "is the panel actually off", printed side by side, so the disagreement between them is visible instead of one being picked and called proof |
| [`night-ladder.sh`](night-ladder.sh) | N consecutive `idle-ab.sh` windows, unattended, driven from the phone so the host may be switched off. Resumes at the rung it reached after a reboot, restores the charge input on every exit path including SIGTERM at shutdown, and stops at a capacity floor rather than measuring the pack flat. Ships with [`fp3-night-ladder.service`](fp3-night-ladder.service) and [`fp3-charge-guard.service`](fp3-charge-guard.service) |
| [`ladder-summary.py`](ladder-summary.py) | **what a night cost**, where `idle-ab-fit.py` answers what an hour costs. Integrates I·V as well as I, sums rungs rather than differencing endpoints, and on the oracle prints the integrated-to-coulomb ratio |
| [`burst-source.sh`](burst-source.sh) | the current and the kernel's own `workqueue_execute_start` + `timer_expire_entry` on **one clock**, so a burst can be laid against the work that ran during it. Wraps `idle-ab.sh` rather than re-implementing the panel proof. ☠️ Its current figures are tracer-inflated and are never an idle number — what survives the overhead is the structure |
| [`burst-profile.py`](burst-profile.py) | floor / median / p90 / p99, the share of samples at ≥1.5× floor, the excess over floor, and the autocorrelation peak lag — the shape of a window, where a fit gives its level |
| [`burst-attrib.sh`](burst-attrib.sh) | **written because the tracer answered "no"**: CPU-busy from `/proc/stat`, cpuidle power-collapse residency and WFI usage, both cpufreq policies and the wlan packet counters, sampled alongside the current with **no tracepoint at all**. Decides whether a burst is the CPU being awake or something that costs power without running code |
| [`burst-attrib-fit.py`](burst-attrib-fit.py) | splits a `burst-attrib` capture by the thing it is explaining — the current — and prints every other column on both sides of that split, then says which of the three verdicts the data supports: code running, an idle-depth burst, or neither. Drops everything before the `# window_from=` mark |
| [`burst-modem-ab.sh`](burst-modem-ab.sh) | A-B-A' on the modem RF with `mmcli --disable`. ☠️ Never the remoteproc: restarting that costs audio until the next reboot and a mixer write afterwards oopses the kernel |
| [`burst-wlan-ab.sh`](burst-wlan-ab.sh) | A-B-A' on the wlan radio. ☠️ Exists because `wlan_pps` being flat excludes *traffic* and nothing else — a radio with power-save off sits in receive whether or not a packet arrives. Refuses to start if the ssh session is on the wlan link |
| [`burst-knob-ab.sh`](burst-knob-ab.sh) | the generic A-B-A': `burst-knob-ab.sh <label> <off> <on> <state> <expected-off> [window]`. ☠️ Written to stop the third copy — the modem and wlan scripts are the same twenty lines with a different verb, and duplication is how this directory once got two panel-blanking implementations that disagreed. Refuses to label a leg "off" unless the state command confirms it |
| [`burst-rail.sh`](burst-rail.sh) + [`burst-rail-fit.py`](burst-rail-fit.py) | **the instrument of last resort**: `state` and `opmode` for all ~57 regulators on every sample, split by burst/quiet. ☠️ `opmode` is the point — a rail need not switch off to stop costing, it drops to idle/LPM, and an enabled/disabled census would call such a rail "constant". ☠️ Output is a correlation, never an attribution: no per-rail current exists here (`requested_microamps` is what a consumer asked for, and is 0) |
| [`discharge-gate.sh`](discharge-gate.sh) | wait for the charger to **terminate** (`status=Full`), then `exec` the discharge run. ☠️ `discharge-run.sh`'s own gate is `capacity >= 97 %`, which **99 % passes while the pack is still absorbing 190 mA** — a run started mid-taper measures the tail of a charge, not the head of a discharge. Bounded at 90 minutes so a charger that never terminates does not leave a unit waiting until someone notices |
| [`burst-master.sh`](burst-master.sh) + [`burst-master-fit.py`](burst-master-fit.py) | **the fourth instrument on the same burst, and the first three all said "not me"**: per sample, each RPM master's shutdown count, XO shutdown count, XO-off duration and active-core bitmask, split by burst/quiet. The column that carries the answer is the **XO-off percentage** — a master that holds the crystal through the burst and releases it through the quiet is the owner, whatever its transition counts say. ☠️ The tick is the 19.2 MHz XO, not the sleep clock; measured, `/19.2e6` lands inside uptime and `/32768` is three orders out. ☠️ It only reads — restarting the modem remoteproc costs audio until the next reboot |
| [`discharge-run.sh`](discharge-run.sh) | **one continuous discharge from a full pack to the phone switching itself off.** ☠️ Deliberately the one instrument here with *no* capacity floor: it measures the pack, not the system, and `capacity` is what is under test. Refuses to start below 97 %, or with the panel up. Settles the pack's true capacity, the OCV→SoC curve and the mapping's lower leg in one run |

☠️ **Compare energy across the two systems, not mA.** `current_now` is current,
and two runs rarely cover the same part of the pack: measured 2026-08-26/27, the
matched ladders spanned 4.150 → 3.708 V on pmOS against 4.262 → 3.967 V on the
oracle, and at a lower pack voltage the same power draws more current. The gap
read **+19.5 % in mA and +12.9 % in mW** — 6.6 points of it was the discharge
curve. mV/h is worse again: 442 against 295 mV looks like 50 % and is mostly the
Li-ion curve steepening below 3.9 V, where only one of the two ran.

☠️☠️ **The coulomb counter exists on one side only.** `cc_soc` +
`full_uAh=3060000` on the 4.9 oracle; on mainline no `cc_soc` and `full_uAh=?`.
Where both exist they disagree by **2.056×** over eight hours — and in the
direction that rules out sampling shortfall, since too few samples under-count.
The likeliest reading is that **the sampling itself wakes the phone**: a sysfs
read every ~5 s brings it up, so `current_now` measures the awake-and-idle draw
while the counter integrates in hardware with sleep included. Do **not** carry
that ratio to pmOS to "correct" a figure — it is a property of how often a system
wakes, which is the quantity under comparison. Compare integrated to integrated.

☠️ **TIE THE START POINTS, or the comparison inherits a gauge disagreement it
cannot see.** Measured 2026-08-27: the two systems' `capacity` readings are **30
points apart** on the same pack (pmOS 63 % against UT 33 %), so two ladders that
both "started at ~93 %" did not start from the same pack state. Before the slot
switch, on the source system, with the **charge input OFF and the pack rested**,
record `capacity` AND `voltage_now`; the first rung on the target system must open
at that same voltage. Both halves are needed: charging inflates the reading (4.379 V
charging against 4.262 V the moment the input was cut), and a percentage alone
cannot cross two gauges that disagree. If the first rung does not open at that
voltage, the difference is real consumption between the two readings — log it,
never absorb it into the ladder.

☠️☠️ **A flat carpet of wakeups cannot explain a burst, and counting them will
never say so.** Measured 2026-08-27: while the current swung 57.5 → 409 mA and two
thirds of the samples were bursts, the traced event rate in the burst bins and in
the quiet bins was **313 vs 316 per 5 s** — every top function at the same per-bin
rate, the 1 % difference pointing the wrong way. The instinct on seeing 24 321
wakeups in six minutes is to name the biggest one as the cause; the split by
burst/quiet is what stops that, and it costs one pass over the same file. **Always
split the trace by the thing you are explaining before you rank it** — a ranking
alone is a picture of the background, not of the event.

☠️☠️ **A mark that is written but not honoured is worse than no mark**, because
the output looks filtered. `burst-attrib` writes its `# window_from=` cutoff at the
END of the capture (it only learns the panel wait when idle-ab returns), and the
first `burst-attrib-fit.py` read the file in one sequential pass — setting the
cutoff after it had already kept every row. Measured 2026-08-27, on a leg where a
key press had woken the panel: the control came back with all 195 samples instead
of 179, median 109 instead of 102, p90 261 instead of 213 — and a ready-made
story ("re-enabling the modem cost something") sitting right there. **Prove a
filter by feeding it a file you know it must shorten.**

☠️☠️ **A rail name is not a rail.** This phone has two PMICs and **twenty of the
rail names collide** — there are two `l1`, two `s3`, two `l9`. A census that
records only `name` therefore hands every finding a coin flip over which chip it
is about, and on 2026-08-27 that produced "`s1` is the MSS supply, by citation
from five other msm8953 boards" — a sentence whose subject was never established.
The identity of a rail is its **parent device**, so `burst-rail.sh` now writes
that into the header and `burst-rail-fit.py` prints `name@parent`. A citation that
resolves the name is not evidence about the thing.

☠️ **Packets are not power.** A flat packet counter excludes traffic and excludes
nothing else. The same shape recurs: `capacity` is not charge, `current_now` is
not energy, an event count is not a level. Ask what the field is a count OF before
reading it as the thing you care about.

☠️ **A rung that produced nothing still looks like a rung.** Prove the instrument
on the target system with a short window before arming a night: the first pmOS
attempt returned 44 lines and zero samples, and a second one was needed to show
that the cause was the observer's own timeout rather than the phone.

☠️ **Each single panel witness has already lied once**, which is why
`panel-witness.sh` prints all of them: the oracle sat fully powered at backlight
brightness 37–38; `setScreenPowerMode("off")` returned `true` over a lit panel;
`/sys/class/drm/*/dpms` is owned by the compositor and a good run was declared
invalid on it. The one that does not lie is the panel bias rail — and ☠️ **read
its `state`/`enable`, never its `microvolts`**: measured 2026-08-26, across a
`blank=4` that demonstrably powered the panel down, `lcdb_ldo`/`lcdb_ncp` went
`enabled → disabled` while `microvolts` did not move off 5500000, because that
file reports the rail's *configured* voltage. Reading the voltage is very
probably the origin of the claim that `fb0/blank` is only a half blank.

☠️ And until 2026-08-26 `idle-ab.sh` proved the panel dark **once, at the door**,
then measured for an hour without looking again — on the exact question it exists
to settle. It now carries the panel state in every sample and refuses to report a
floor from a window the panel relit inside.

## Getting to the other system

| tool | the question it answers |
|---|---|
| [`gptattr.py`](gptattr.py) | read, and flip, the Qualcomm A/B boot-control attribute bits in the GPT — the whole slot-switch mechanism on this eMMC device |

☠️ **`qbootctl -s <slot>` cannot switch slots on this phone.** It aborts in a UFS
`bLun` step (`Unable to open '/dev/bsg/ufs-bsg0'`) that has no meaning on eMMC,
and the `-i` flag its own help text advertises for exactly that case is **not
implemented** in the packaged build — getopt answers `unrecognized option: i`.
Reading works, so `qbootctl` remains a useful independent check on what
`gptattr.py` wrote. Measured 2026-08-26 on `qbootctl-0.2.2-r1`, the newest in
Alpine edge.

The attribute layout is Qualcomm's, not the generic AOSP one: priority 48–49,
active 50, tries 51–53, successful 54, unbootable 55. ☠️ `gptattr.py dump` does
not take that on faith — it XORs the `_a` against the `_b` attribute of every
slotted pair and prints which fields differ, so a wrong layout shows up before
anything is written. On this device exactly one bit differs, bit 50, and
`active` is therefore what the bootloader reads; `gptattr.py active <slot>` flips
that bit and nothing else, rather than rewriting priority, tries and successful
the way a full `set_active` would. ☠️ It also surfaced that **`modem_a` is marked
`unbootable=1 prio=0 tries=0`** — state we did not create, left untouched
deliberately.

## Asking the RPM what it did

| tool | the question it answers |
|---|---|
| [`rail-census.sh`](rail-census.sh), [`rail-census-parse.py`](rail-census-parse.py) | which rails vote active and never vote sleep, traced across a real suspend and decoded against the FP3 rail map |
| [`vlow-probe.sh`](vlow-probe.sh), [`leg3.sh`](leg3.sh), [`leg3-control.sh`](leg3-control.sh) | the sleep-set XO vote: does zeroing it let the RPM reach `vlow`, and is it worth any current |
| [`oracle-capture.sh`](oracle-capture.sh) | the same records from the Ubuntu Touch oracle on `slot_a` — the ground truth for every "is this normal?" question |

☠️ `rpm_master_stats` is a module and nothing autoloads it; without a `modprobe`
the whole APSS column reads `?`, which looks exactly like "the processor never
collapsed". And ☠️ `qcom_stats`' `Client Votes` field is an instantaneous,
fluctuating sample — a before/after pair of it proves nothing.

## Watching for something rare

| tool | the question it answers |
|---|---|
| [`emmc-watch.sh`](emmc-watch.sh) | did the card fall off the bus, and what was the RPM doing when it did. ☠️ Logs to tmpfs, because the filesystem it watches is the one that dies. Superseded for unattended use by [`../night/guardian.sh`](../night/guardian.sh), which also acts |
| [`episode-watch.sh`](episode-watch.sh) | the unexplained 44-minute episode of 2026-08-18. ☠️ Must never run during a suspend leg — a sampler once a minute is a wakeup once a minute |
| [`pll-sweep.sh`](pll-sweep.sh), [`pll-vs-voltage.sh`](pll-vs-voltage.sh), [`pll-ramp-fit.py`](pll-ramp-fit.py) | the `apcs-cpu0-pll` failures: how often, and whether they depend on pack voltage. They do not — 7.3 per 10 000 transitions, flat from 4.32 V to 3.93 V |

## The modem's idle duty (2026-08-28/29)

The whole remaining gap to the oracle is one term — the modem core's awake duty
on LTE — so these ask about that and nothing else. Background and the table of
dead candidates: [`../leads/modem-idle-lte.md`](../leads/modem-idle-lte.md).

| tool | the question it answers |
|---|---|
| [`learn-prep.sh`](learn-prep.sh) + [`learn-cycle.sh`](learn-cycle.sh) | does the r79 gauge learning actually converge on the pack? prep walks the pack under the recharge threshold and back up to a terminated charge — ☠️ a pack sitting at 91 % on the cable does not charge, it inhibits, so the upper anchor has to be *produced* — then learn-cycle discharges to a floor with `charge_full` in **every row**, because the learning fires inside an anchor and a value read only at the end cannot say when it moved |
| [`modem-window.sh`](modem-window.sh) + [`modem-window-fit.py`](modem-window-fit.py) | one duty window, **on either system**: it branches on the stack (`mmcli` vs the oracle's two ofono modems, a master-stats directory vs a single file) but never on the question, and writes the modem's power state, access technology, signal and serving cell into the same file as the counters. ☠️ Built because a window taken before registration is not a window about idle behaviour |
| [`boot-level-sample.sh`](boot-level-sample.sh) | one window per boot with the candidates beside it — camped cell, band, channel, signal, operator, firmware. ☠️ The duty is fixed at boot and does not decay, so a window is a property of its boot |
| [`duty-vs-uptime.sh`](duty-vs-uptime.sh) | is the level a post-boot decay or a per-boot constant? Forty-six windows over 4.8 hours answered: constant, slope +0.36 %/hour |
| [`band-ab.sh`](band-ab.sh) | A-B-A′ on the LTE band inside one boot, with the band list restored afterwards. ☠️ The witness reads `--nas-get-rf-band-info`, the variable the lever moves — a leg camped on a band other than the one requested is void, not evidence |
| [`smd-wake-source.sh`](smd-wake-source.sh) | per-round residency plus a per-channel census of the modem's SMD edge, with a double-deref kprobe on the channel name |
| [`rpmsg-ept.py`](rpmsg-ept.py), [`diag-probe.py`](diag-probe.py) | open a named rpmsg channel through the control device and speak HDLC-framed DIAG on it. State and the exact next sequence: [`../leads/diag-bringup.md`](../leads/diag-bringup.md) |
| [`modem-fw-swap.sh`](modem-fw-swap.sh) | kept for the record with a do-not-run banner — the firmware difference it was written to test did not exist |

## Suspend residency: how long it sleeps, and what that is worth

| tool | the question it answers |
|---|---|
| [`suspend-rate.sh`](suspend-rate.sh) | how much of each `rtcwake` window the phone actually sleeps, and **which IRQ ended it** — the `wake_irq` column resolves `/sys/power/pm_wakeup_irq` to a name, because the Linux irq number is an allocation and moves between boots. This is the instrument that named ModemManager across four legs |
| [`sleep-night.sh`](sleep-night.sh) | what residency is worth in mA. ☠️☠️ **Read its header before reading its output**: `capacity`, `charge_now` and `current_now` are three sysfs names for **one** software integrator in `qcom_smbx.c`, and its suspend-gap branch counts nothing — so the capacity column is pinned by design across exactly the window being measured. The measure is the `v_uV` column (a hardware rest OCV), it needs hours, and the run must start **below** the flat top of the discharge curve |
| [`sleep-knob-ab.sh`](sleep-knob-ab.sh) | A-B-A′ on one knob measured in **residency** instead of duty or mA — the third wrapper, because residency and duty are different quantities and a null on one is not a null on the other (stopping ModemManager left the duty flat at 38/36/37 % and took the suspend from 16-53 s to the full 602 s). Its first job: `mmcli -m 0 --disable` separates a daemon **poll timer** from a modem **indication subscription** with nothing patched — the daemon keeps all its timers, the subscriptions go with the disable |
| [`call-wake-test.sh`](call-wake-test.sh) | does an incoming call still raise the phone once a knob is applied — the responsiveness half of the trade, which no residency number replaces |
