# Power on the Fairphone 3

> ⚠️ **AI-generated.** These pages, and the code and measurements they describe,
> were written by Claude (Opus 5) working under the direction of Lajosházi,
> László Gergely, who reviewed every change and made or reviewed every
> measurement they rest on.

**This page is the current state and nothing else.** What the phone draws today,
what has been fixed and shipped, what is still open, and how to read the numbers
without being misled by them.

Everything dated — every measurement narrative, every theory that was held and
then disproved, every lead still being chased — is under
[`bringup/`](bringup/README.md) and is **not** revised when the device changes.

## Where everything lives

| | |
|---|---|
| **this page** | the current state: draws, fixes, open questions, caveats |
| [`bringup/RUNBOOK.md`](bringup/RUNBOOK.md) | ★ **the resume point.** What is running on the device right now and what to do next. Read it first if you are picking the work back up |
| [`bringup/README.md`](bringup/README.md) | the narrative of how the idle current was localised |
| [`bringup/findings-log.md`](bringup/findings-log.md) | the dated record, in the order it happened |
| [`bringup/leads/`](bringup/leads/) | the open leads, one page each |
| [`bringup/night/`](bringup/night/README.md) | the unattended-night harness: preflight, guardian, queue, supervisor |
| [`bringup/tools/`](bringup/tools/) | the instruments — legs, probes, fitters |
| [`bringup/captures/`](bringup/captures/) | the raw data every number here came from |
| [`bringup/patches/`](bringup/patches/) | patches carried out of this work |
| [`bringup/disproven/`](bringup/disproven/README.md) | hypotheses that were disproved, kept so they are not re-run |
## Where the numbers stand

Idle here means display off, WiFi associated, one SSH session open. Unless a row
says *asleep*, it is not a measurement of a sleeping phone.

| | draw | measured |
|---|---|---|
| pmOS, as a stock image ships it | **166 mA** | 2026-08-12 |
| pmOS, with the camera released | **68 mA** | 2026-08-13 |
| Ubuntu Touch, same protocol | 86 mA | 2026-08-11 |
| awake, idle, panel **off**, session running | **58–63 mA** | 2026-08-19 |
| the panel, powered at zero brightness | **+24.5 ± 6.4 mA** | 2026-08-19 |
| asleep, no cuts | 79.1 mA | 2026-08-19 |
| asleep, modem stack cut | **43.3 mA** | 2026-08-19 |
| every userspace service tested, five of five | zero | 2026-08-19 |

☠️ **`backlight = 0` is not `dpms off`.** A panel at zero brightness is still
powered, and every idle floor measured before 2026-08-19 was about 25 mA high
because of it. The marginals in those measurements all stand; the levels do not.

☠️ **The derived mA of a slope leg is for scale only.** Compare phase-A slopes
between legs directly — a ratio hides which half of it moved. The baseline
reproduced at −35.29, −35.44 and −35.77 mV/h across three legs, which is a 1.4 %
spread and the instrument's own demonstration of repeatability.

☠️ **One `current_now` read scatters by ±138 mA.** Take a median, never a mean,
and never a single sample. Where the distribution is a quiet floor plus bursts,
the **floor (p10)** is the statistic that answers "what does this cost", not the
median.

☠️ **Percentages are not comparable between the two operating systems.** They run
different gauges. Over one matched 6.66 h idle window the vendor gauge reported 6
points against 571 mAh integrated, and ours reported 36 points against 1319 mAh.
Compare integrated current and terminal voltage; treat the percentage as a
measurement *of the gauge*.

☠️ **There is no `deep` on this platform.** `/sys/power/mem_sleep` offers
`[s2idle]` only. s2idle itself works — 6 of 6 suspends, full duration,
`suspend_stats` 6 success / 0 fail, and the cores reach `cpu-power-collapse`.
What is missing is the system-level RPM state, and "deep sleep" on this device
means getting the RPM into `vlow`/`vmin`, not finding a suspend mode that is not
there.

**pmOS does not suspend on its own here, because we asked it not to.** Automatic
sleep works and was demonstrated on this base; it is switched back off because an
incoming call cannot wake the phone, and a missed call costs more than 140 mA
does. `sleep-inactive-battery-type` is `'nothing'`; neither kernel offers
`/sys/power/autosleep`. The whole finding is in
[Suspend works, and is switched off on purpose](#suspend-works-and-is-switched-off-on-purpose).

**What answers "did it sleep?"**, in order of cost:

* `/sys/power/suspend_stats/success` read **before and after** the window — the
  delta is valid; the absolute number is not, since it counts from boot;
* `dmesg | grep 'PM: suspend'` — the `entry (s2idle)` / `exit` pair. Note the
  printk clock stops while suspended, so a 60 s sleep shows as a fraction of a
  second between the two lines. The pair is the evidence, not the gap.

☠️ The Ubuntu Touch side of the autosleep claim is **withdrawn pending
re-measurement**: it compared wall clock against `/proc/uptime`, and
`/proc/uptime` reports boottime, which *includes* suspended time. Verified
against a suspend we know happened: 71 s of wall clock, 71 s of uptime, across a
demonstrated 60 s sleep.
## What is fixed and shipped

Each of these landed on `wip/7.1.3/power`, was cherry-picked to
`integration/7.1.3` and carried to `debug-int/7.1.3`, which is what the phone
runs. The reasoning behind each is in
[`bringup/findings-log.md`](bringup/findings-log.md).

| fix | what it was | measured effect |
|---|---|---|
| the genpd `bool` | `cached_power_down_state_idx` declared `bool`, so a cached index of 2 came back as 1 and the search could never reach index 2 again | `cluster-pc` 0 → 14 516/min, `system-pc` 0 → 3531 |
| the `system_pc` affinity nibble | the PSCI parameter named affinity level 1, so TZ aggregated to a cluster and never performed the APSS handshake with the RPM. `0x42000353`, one hex digit | APSS `Shutdown count` 0 → +91 in 91 s |
| the vMPM deadline cap | `MPM_MAX_SLEEP_NS = NSEC_PER_SEC` asked the RPM never to keep the AP down longer than a second | the AP stays down instead of waking once a second |
| the MPM notification path | mainline msm8953 described no MPM at all, so nothing told the RPM a suspend had happened | the notification demonstrably runs |

## What is still open

| question | where it is being worked |
|---|---|
| **LPASS never shuts down** — 2 shutdowns / 0.12 s since boot against 4344 on the vendor stack. A master that never goes down is a sufficient explanation for `vlow` reading 0 in every capture ever taken here | [`bringup/leads/lpass-never-sleeps.md`](bringup/leads/lpass-never-sleeps.md) |
| **the modem stack costs ~36 mA asleep** — reproduced against a same-day control; the mechanism is not yet named | [`bringup/RUNBOOK.md`](bringup/RUNBOOK.md) |
| **the RPM sleep set** — mainline's `qcom_smd-regulator.c` only ever votes the active state; 14 LDOs vote active and never sleep | [`bringup/leads/rpm-sleep-set.md`](bringup/leads/rpm-sleep-set.md) |
| **the CPU0 PLL storm** — 7.3 failures per 10 000 frequency transitions, flat in voltage. It spoils absolute awake currents; it does not spoil slope ratios | [`bringup/findings-log.md`](bringup/findings-log.md) |
| **one eMMC dropout, 2026-08-18** — the card stopped answering, root went `emergency_ro`, a reboot cleared it completely. Not reproduced across the four long runs since | [`bringup/night/README.md`](bringup/night/README.md) |

## The raw captures

Every number on this page came from a file in [`bringup/captures/`](bringup/captures/README.md),
which explains the log format, the two biases the numbers carry, and what each
file holds.

## Two biases these numbers carry

Both apply identically on both sides, so the *difference* between two captures
survives them; an absolute figure does not.

* **The logger biases its own numbers.** It wakes once a minute and reads the
  current while it is itself running, so the mean it produces is high.
* **Idle means idle with the link up.** Every one of these ran with WiFi
  associated and an SSH session open, because that is how the data got off the
  phone.

## Suspend works, and is switched off on purpose

Everything needed is present: `/sys/power/state` offers `freeze mem disk`,
`mem_sleep` is `[s2idle]` — no `deep`, and measured 2026-08-16 that costs less
than it sounds: the `S2idle` column of
`/sys/kernel/debug/pm_genpd/power-domain-system/idle_states` increments across a
suspend, so the **system power domain collapses from s2idle anyway**. `deep` is
in any case not ours to add: it exists only if the secure firmware answers
`psci_features(SYSTEM_SUSPEND)`, which this one does not. The reasoning, and why
neither systemd nor a kernel bump can have taken it away, is in
[`RUNBOOK.md`](bringup/RUNBOOK.md#why-suspend-only-halves-it-there-is-no-deep-state);
`tests/checks/99-suspend-test.sh` now asserts both the state list and the
collapse. `rtcwake` and `/dev/rtc0` work, and cpuidle has `WFI` plus
`cpu-power-collapse`.

☠️ **A first attempt on a new base must happen with someone holding the phone.**
On ports it is the *resume* that fails, and a phone that does not come back needs
a physical power-cycle. Run `rtcwake -m mem -s 60` once, in person, before
enabling automatic sleep anywhere.

**Run and passed on 7.1.3, 2026-08-14.** Both a 60 s `rtcwake` and, with the
phone in hand, real GNOME idle suspends of 116 s and 8 min: `PM: suspend entry
(s2idle)` … `exit`, `suspend_stats/success` incrementing with `fail` at 0, wake
on the power button, and WiFi re-associating unaided.

Then it was turned back off. `sleep-inactive-battery-type` is `'nothing'`, which
is **a decision, not a default that nobody looked at**:

* **An incoming call does not wake the phone.** Measured: across an 8-minute
  sleep the call arrived at the modem, the AP never woke, and on the button wake
  the queued event replayed — the dialer showed busy and closed. Of 151 IRQs only
  three are wake-armed (`wcn36xx_rx` and two thermal sensors). The modem's SMD
  edge, `irq 140` = `GIC-0 57` = the device tree's `GIC_SPI 25`, reads
  `wakeup=disabled`, and `drivers/rpmsg/qcom_smd.c` registers no wake IRQ at all,
  so there is not even a knob for it. Enabling the one knob that does exist,
  `smp2p-modem`, changed nothing — its counter did not move once across the whole
  sleep, which is what proves the call does not travel that line. See
  [`TODO.md`](../TODO.md).
* **SSH does not wake it either**, despite `wcn36xx_rx` being wake-armed: the
  connection times out with `No route to host` until the phone is woken by hand.
  Convenient for measurement — the logger cannot be contaminated by the observer
  — and a warning for anything that expects to reach the device while it sleeps.
* **The gauge gains nothing from it.** After a real s2idle, `S3_GOOD_OCV` and
  `LAST_S3_SLEEP_V` both still read `0x8000`. Suspending does not take this board
  under the PMIC's 10.4 mA S3 threshold, so the plan of *fix sleep and the gauge
  corrects itself* is measured dead. Twice, independently.

☠️ **The kernel clock stops during s2idle, so `dmesg` timestamps cannot measure
how long the phone slept.** An 8-minute sleep reads as 0.5 s between `suspend
entry` and `suspend exit`. The instrument that works is a wall-clock logger
writing to a file — run it under `systemd-run --unit=… --collect` so it survives
both the suspend and the SSH drop.

---

## ★★★ The real cause: a `bool` that should have been an `unsigned int`

*2026-08-14, late night. This is the answer to the question the oracle raised.*

The idle-depth question had a one-word answer, and it was not on this SoC at all.
In `include/linux/pm_domain.h`:

```c
struct genpd_governor_data {
	...
	bool cached_power_down_ok;
	bool cached_power_down_state_idx;   /* <- a state index, stored in a bool */
};
```

`drivers/pmdomain/governor.c` writes a state index into it and reads one back:

```c
	gd->cached_power_down_state_idx = genpd->state_idx;   /* 2 becomes true */
	...
	genpd->state_idx = gd->cached_power_down_state_idx;   /* true becomes 1 */
```

So **any idle-state index above 1 survives exactly one call.** A genpd computes
the right depth once, on the single uncached pass, caches it as `1`, and from
then on every call takes the cached path and hands the governor a `1`.
`cpu_power_down_ok()` starts its search at `genpd->state_idx` and only ever walks
*downwards*, so no state deeper than index 1 can ever be selected again.

The msm8953 cluster domain has three: `cluster-ret`, `cluster-gdhs`,
`cluster-pc`. Index 2 was unreachable from the first second of uptime.

### How it was localised

Three instrumented boots, each about two minutes to build on top of the existing
`.output`:

1. A `trace_printk` in `cpu_power_down_ok()` printing the computed
   `idle_duration_ns`, the starting index and the pick. **1622 decisions,
   `start=1` in every single one**, and 73 % of them had an idle window past
   `cluster-pc`'s 2770 µs requirement (p50 3.5 ms, p90 235 ms). So the
   next-wakeup estimate was never the problem — the search simply began one
   state too shallow. That retired the hypothesis this run started with.
2. A print on both exits of `_default_power_down_ok()`. Every runtime call was
   `CACHED idx=1`; not one fresh computation in a 3 s window.
3. A print on the fresh path only, read straight after boot. **Two lines in the
   whole trace buffer, both `FRESH idx=2 cnt=3`** — the fresh path computes the
   correct index, once, at 0.74 s, and is never taken again. Between `idx=2`
   going in and `idx=1` coming out sat the `bool`.

☠️ The measurement that would have been wrong: reading the *outcome* counters.
`cluster-pc` showed `usage 0, rejected 0` — indistinguishable from "the hardware
refuses it" and from "the window is too short". Only printing the governor's
*input* separated them.

### What it changes, measured

Same phone, display off, 60 s, the only difference being `bool` →
`unsigned int`:

| | before | after |
|---|---|---|
| `cluster-pc`, cluster0 | **0** entries | **14516** entries, 67.3 s |
| `cluster-pc`, cluster1 | 1 entry, 2 ms | 8243 entries, 59.1 s |
| `system-pc` (`power-domain-system`) | **0** | **3531** entries, 34.8 s |
| MPM domain power-off | 0 | 3582 |

The system domain matters twice over: `genpd_power_off()` refuses to power off a
parent unless **every child is already in its deepest state**
(`drivers/pmdomain/core.c`, `child->state_idx < child->state_count - 1`), so with
the clusters pinned at index 1 the level above them was structurally
unreachable — which is why the MPM notification to the RPM, added earlier the
same evening and demonstrably working, still had nothing to notify about.

47 system power collapses a second is the same order as the oracle's 41/s.

### Provenance

Introduced by commit `e94999688e3a` ("PM / Domains: Add genpd governor for
CPUs", Ulf Hansson, 2019-04-11) and carried unchanged through `f38d1a6d0025`
("PM: domains: Allocate governor data dynamically based on a genpd governor",
2022) when the field moved into `struct genpd_governor_data`. It has been a
`bool` for six years. Nothing here is msm8953-specific: **every SoC whose genpd
has three or more idle states has been losing its deepest ones**, silently, with
zero rejected counts to show for it.

☠️ What still does not move: `qcom_stats` `vlow`/`vmin` are both still 0 and the
RPM's APSS master record is still all zeros. Those are the next question, and
they are now a question about the RPM handshake alone, with the AP side doing
its part 47 times a second.

## ☠️ Which battery attributes can be believed, and when

Reference, because getting this wrong cost three measurement legs. `qcom_smbx`
has no coulomb counter; everything comes from
`drivers/power/supply/adc-battery-helper.c`, whose work function runs every
`POLL_TIME` = 30 s and maintains an 8-deep ring average
(`ADC_BAT_HELPER_MOV_AVG_WINDOW_SIZE`) — i.e. a four-minute trailing one.

| attribute | source | across a suspend |
|---|---|---|
| `voltage_now` | `get_voltage_and_current_now()` — **live ADC, every read** | usable |
| `current_now` | `get_voltage_and_current_now()` — **live ADC, every read** | cannot be sampled while frozen |
| `voltage_ocv` | `help->ocv_avg_uv`, the ring average | **lies** |
| `capacity` | that average through the DT OCV table | **lies** |
| `charge_now` | `capacity × charge_full / 100` | **lies** |

The bottom three are one measurement under three names, so they agree with each
other by construction and that agreement is not corroboration. The frozen worker
means all three stay a blend of pre-freeze and post-resume samples for four
minutes after a resume.

`factory-internal-resistance-micro-ohms` in the DT is 120 mΩ; the OCV table
(`ocv-capacity-table-0`) runs 4.376 V at 100 % down to 3.000 V at 0 %, and is
close to linear at ~10.6 mV per 1 % between 86 % and 68 %.

### What the withdrawn S2 leg still supports

Only the live pair, and only as a bound. `voltage_now` fell from 4.2055 V (at
139 mA) to 4.0383 V (at 198 mA) across the three hours; compensated by hand with
the device tree's 120 mΩ `factory-internal-resistance-micro-ohms`, that is
4.222 V → 4.062 V, a 160 mV drop.

Both ends are biased the **same** way, so 160 mV is an upper bound and not an
estimate: the first was taken 300 s after leaving a CV charger, with surface
charge still elevating it, and the second 90 s after a resume that pulled 725 mA,
with polarisation depressing it and a static 120 mΩ under-correcting a transient.

The bound is still worth something. The sub-20 mA hypothesis needs essentially
the whole 160 mV to be artifact: a 10 mA leg over three hours moves 30 mAh, which
in this region of the table (~10.6 mV per 1 %) is about 11 mV. **So suspend is
not in the 10 mA regime.** How far it sits from the awake 130 mA, this leg cannot
say.

### The instrument that follows from all of this

Two live attributes, no cached ones, and a **slope** rather than a difference - a
slope cancels any constant offset, which is what every bias found so far turns
out to be, provided the sampling conditions are identical at every point. Then
calibrate that slope against a current the ADC measures directly, rather than
against the OCV table:

* **phase A** - N sleeps of T seconds; after each, exactly 20 s of quiet awake
  time, then one live `(voltage_now, current_now)` read. The fixed wake window is
  what makes the polarisation offset the same at every sample.
* **phase B** - the same total time awake and idle, sampled identically, where
  `current_now` gives the true mean current outright.

`I_sleep = I_awake × (slope_A / slope_B)`. The OCV table never enters, and
`dV/dQ` is near-constant across the span this covers (the table gives ~10.6 mV
per 1 % from 86 % down to 68 %), so the ratio holds. Phase A runs first, so both
phases sit in a similar part of the curve.

Phase B is the same-instrument control, and it is not optional: the awake current
is known independently, so phase B has to reproduce ~130 mA. If it does not,
phase A means nothing.

Run it with [`suspend-slope.sh`](bringup/tools/suspend-slope.sh) and reduce it with
[`slope-fit.py`](bringup/tools/slope-fit.py), which fits both phases, prints the control block
first and flags a phase whose points are not a straight line. `slope-fit.py
--selftest` checks it against a synthetic run of known slope ratio *and* against
scatter that must fail the straight-line gate.
