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
| **this page** | the current state: draws, fixes, open questions, caveats — and the instrument table below |
| [`../STATUS.md`](../STATUS.md) + [`../TODO.md`](../TODO.md) | ★ **the resume point.** What is running on the device and what to do next, in queue order. (The former `bringup/RUNBOOK.md` was split on 2026-08-24: its dated body is Part II of the findings-log) |
| [`bringup/README.md`](bringup/README.md) | the narrative of how the idle current was localised |
| [`bringup/findings-log.md`](bringup/findings-log.md) | the dated record, in the order it happened |
| [`bringup/leads/`](bringup/leads/) | the open leads, one page each |
| [`bringup/night/`](bringup/night/README.md) | the unattended-night harness: preflight, guardian, queue, supervisor |
| [`bringup/tools/`](bringup/tools/) | the instruments — legs, probes, fitters |
| [`bringup/captures/`](bringup/captures/) | the raw data every number here came from |
| [`bringup/patches/`](bringup/patches/) | patches carried out of this work |
| [`bringup/disproven/`](bringup/disproven/README.md) | hypotheses that were disproved, kept so they are not re-run |

## Reading the state off the device — the instruments that cost time to find

| question | command |
|---|---|
| did the SoC reach a low-power mode | `grep Count /sys/kernel/debug/qcom_stats/{vlow,vmin}` — ☠️ closed 2026-08-24: `vlow` never occurs on this platform under any OS; it is not a figure of merit here |
| which master never goes down | `cat /sys/kernel/debug/qcom_rpm_master_stats/APSS` — ☠️ one file per master, and the directory is `qcom_rpm_master_stats`, not `rpm_master_stats`; needs `modprobe rpm_master_stats` |
| the RPM's own records, raw (works on BOTH slots) | `bringup/tools/rpmstats_raw.py` — mmap `/dev/mem` at message RAM; `dd`/`devmem` EFAULT here |
| how deep does idle actually get | `cat /sys/kernel/debug/pm_genpd/power-domain-cluster0/idle_states` |
| the same on the oracle | `ut-ssh 'cat /sys/kernel/debug/rpm_master_stats'` (one file, not a directory) and `.../lpm_stats/stats` |
| what is waking the CPUs | two `/proc/interrupts` snapshots differenced — ☠️ stop the compositor first, or `msm_mdss` at 65/s makes the run meaningless |
| is a burst code, or the CPU, or neither | `bringup/tools/burst-attrib.sh 360` then `burst-attrib-fit.py …/attrib.txt` — CPU-busy, power-collapse residency, cpufreq and wlan packets on both sides of the burst/quiet split, with no tracepoints. ☠️ Measured 2026-08-27 across a 9× current swing: every column flat, cores collapsed 99 % of the time *during* the burst |
| is a burst real power or a gauge artefact | the `v_mV` column of the same capture. A real load sags the pack: ~100 mA of extra current cost 16–20 mV on three legs, a consistent 156–196 mΩ. ☠️ This witness was in every capture for a day before anyone read it |
| which rail is up when the current is up | `bringup/tools/burst-rail.sh 360` + `burst-rail-fit.py` — `state` **and** `opmode` for all ~57 regulators. ☠️ A rail need not switch off to stop costing; it drops to idle/LPM. ☠️ No per-rail current exists: the output is a shortlist for a scope, never a bill |
| has the phone ever suspended | `grep -H . /sys/power/suspend_stats/*` — `success` is the only honest answer; `cat /sys/power/mem_sleep` says which path. ☠️ `rtcwake` exits 0 even when the suspend aborts early — wall-clock the window |
| current while suspended | `bringup/tools/suspend-slope.sh` — ☠️ **only `voltage_now`/`current_now` are live**; `capacity`, `charge_now` and `voltage_ocv` are one cached number the frozen poll worker maintains, and all three lie across a suspend. Use a slope of compensated `voltage_now`, calibrated against an awake control |
| does the RTC alarm wake it | `echo 0 > /sys/class/rtc/rtc0/wakealarm; echo +90 > …` then `echo mem > /sys/power/state` — ☠️ prove this **before** relying on it to bring an unattended leg back |

## The theory: how this platform sleeps

Stable background, so the numbers below have something to sit on. Nothing in
this section is FP3-specific except where it says so; it is how every
RPM-generation Snapdragon (msm8916/8937/8953, SDM632) is built.

### The ladder

Power is given up in rungs, each one conditional on everything below it:

```
userspace idle                    nothing scheduled, timers quiet
  └─ WFI / cpu-power-collapse     cpuidle: one core at a time
      └─ cluster-ret / gdhs / pc  genpd: the whole cluster, deepest last
          └─ system-pc            genpd: the domain above both clusters
              └─ PSCI → TZ        the kernel asks the secure firmware
                  └─ APSS ↔ RPM   TZ performs the handshake: "Apps is down"
                      └─ vlow / vmin   the RPM's own low-power modes
                          └─ XO shutdown   the 19.2 MHz crystal stops
```

Two properties of the ladder explain most of this investigation:

* **Each rung is gated by the one below.** `genpd_power_off()` refuses to
  power a parent down unless every child is already in its *deepest* state —
  which is why one `bool` that capped the clusters at index 1 (see
  [the real cause](#-the-real-cause-a-bool-that-should-have-been-an-unsigned-int))
  made the entire top of the ladder structurally unreachable, with every
  counter reading zero and nothing "rejected".
* **The top rungs are not the kernel's.** Above the PSCI call sits secure
  firmware and the RPM's own firmware. The kernel can only make its request
  correctly and verify the counters move; when they do not, the remaining
  question is votes, not code paths.

### The RPM, masters, and the two vote sets

The RPM (Resource Power Manager) is a separate always-on microcontroller that
owns the shared resources: regulators, RPM-routed clocks, buses, and the XO
crystal. Around it sit the **masters** — APSS (us, the application processor),
MPSS (modem), PRONTO (WiFi), LPASS (audio DSP), TZ — and each one both
*handshakes* (tells the RPM when it powers down) and *votes* (tells the RPM
what resources it needs).

Every vote lands in one of two sets:

* the **active set** — what the master needs while it is awake;
* the **sleep set** — what it needs while it is power-collapsed.

The rule that shapes everything: **a resource with an active vote and no sleep
vote keeps its active vote at all times, including through power collapse.**
The sets only separate once the first sleep vote for that resource arrives.
So "forgot to cast a sleep vote" and "needs this rail during sleep" are
indistinguishable to the RPM — which is why the census in
[`bringup/leads/rpm-sleep-set.md`](bringup/leads/rpm-sleep-set.md) had to be
taken, and why mainline's regulator driver never casting sleep votes is a real
divergence even where it costs nothing.

The RPM enters `vlow`/`vmin` — and ultimately shuts the crystal down — only
when the aggregate allows it: **every master down (or sleep-voting), and no
resource held active-set.** That is why a master being down is *necessary and
not sufficient*, measured twice on this device: the AP handshake fixed and
`vlow` still 0, then the audio DSP collapsing for whole suspends and `vlow`
still 0.

### Why there is no `deep`, and why it does not matter

`/sys/power/mem_sleep` on this firmware offers only `[s2idle]`. `deep` (S3,
suspend-to-RAM via firmware) exists only if the secure firmware implements
PSCI `SYSTEM_SUSPEND`, and this one does not — that is not ours to add. What
makes it not matter: s2idle freezes userspace and lets cpuidle take the same
ladder as runtime idle, and **measured here, the system power domain collapses
from s2idle** — the deepest state the AP side has is reachable without `deep`.
On this platform s2idle *is* the suspend path, not a fallback for a missing
one.

The corollary is that the RPM cannot tell a deep runtime idle from a suspend —
both look like "APSS handshaked down". Sleep-set votes therefore take effect
at deepest cpuidle *any time the system is idle enough*, not just during
suspend, which is also why bolting the RPM sleep set onto the regulator
framework's system-suspend states would be the wrong shape (see the lead page).

### What "deep sleep" and the ~10 mA regime actually require

Downstream phones reach ~10 mA in **full suspend + RPM `vlow` + XO off + the
modem in its own power-save**, never in runtime idle. Translated to this
ladder, the checklist is:

1. AP side down and staying down — **done**, four fixes shipped
   ([below](#what-is-fixed-and-shipped));
2. every other master down or sleep-voting — LPASS was the holdout, now
   understood and priced (~4 %); the modem mostly keeps the XO on but is
   *capable* of releasing it (measured once, 80 % of a suspend);
3. no resource held active-set through the collapse — the LDO sleep-vote gap
   lives here, measured to leave exactly one rail up on this device (the
   eMMC's, which must stay);
4. the RPM then enters `vlow` and stops the crystal — **never yet observed
   here**, and the open question is which of 2–3 still blocks it.

☠️ **The regime is not a target to shave toward.** 130 mA runtime idle does
not become 10 mA by trimming services; the two numbers come from different
rungs of the ladder. Every measurement below states which regime it was taken
in, and comparing across regimes is the mistake this page exists to prevent.

## Where the numbers stand

Idle here means display off, WiFi associated, one SSH session open. Unless a row
says *asleep*, it is not a measurement of a sleeping phone.

**The matched eight-hour ladders (2026-08-26/27) are the current answer**, and
they supersede every single-window comparison below. Same protocol on both
systems, same pack mark, panel provably off in all sixteen rungs, run
back to back on the same day: the oracle 14:07-22:10, pmOS 23:10-07:13 after the
pack was charged back to 94 % / 4.394 V **on the UT side** before the slot switch.

☠️☠️ **CORRECTED 2026-08-28 — the energy row below is contaminated, and the
answer is ~2×.** The 17.94 h discharge to power-off gave this pack a **measured
voltage → charge curve**, including below 3.967 V where the oracle ladder has no
data and five of the eight pmOS rungs live. Reading each ladder's own voltage
travel off it: **oracle 623–651 mAh, pmOS 1308–1335 mAh, ratio 2.05–2.10×** —
i.e. the charge column's 2.12× survives, and it was never an artefact of the
single OCV anchor. Four handles on the same two ladders now line up: the oracle's
voltage travel (623–651) and its own hardware coulomb counter (**501 mAh**) agree;
its `current_now` integral (**1031 mAh**) does not, because sampling `current_now`
wakes a phone that would otherwise sleep. On pmOS the two handles agree to 8 %, as
they must, since pmOS barely sleeps. **So both the energy and the current rows
below were integrated against an inflated oracle.** Account: `bringup/findings-log.md`,
2026-08-28.

| over 8 h, idle, panel off | UT (oracle) | pmOS | pmOS vs UT |
|---|---|---|---|
| **energy (I·V integrated)** | **525.6 mW** | **593.5 mW** | **+12.9 %** |
| current (integrated) | 129.0 mA | 154.1 mA | +19.5 % |
| **floor (p10), rung mean** | 72.2 mA | **56.9 mA** | **−21 %** |
| median, rung mean | 126.3 mA | 161.8 mA | +28 % |
| `capacity` over the run | 94 → 69 (25 pt) | 92 → 63 (29 pt) | +14 % |
| coulomb counter | 62.7 mA / 16.4 % | **not available** | — |

**Our floor is below the oracle's and our median is above it**: pmOS sits quieter
and wakes more expensively. ☠️ The "+12.9 % over a night" that used to close this
paragraph is **withdrawn** — see the correction above; the pack says ~2×. The floor
and median rows are unaffected, because they are distributions of the same
instrument on each system rather than an integral compared across them. Repeat with
`tools/ladder-summary.py` over a run's rung files.

**The same two ladders as charge moved, which is the other half of the picture:**

| | UT ladder | pmOS ladder |
|---|---|---|
| own `capacity` | 94 → 69 = **25 pt** | 92 → 63 = **29 pt** |
| own voltage travel | 4.262 → 3.967 = **295 mV** | 4.150 → 3.708 = **442 mV** |
| coulomb counter | 92.4 → 76.0 = **16.5 %** | **none on this system** |
| **on the oracle's scale** | 25 pt (by definition) | **86.8 → 33.5 ≈ 53 pt** |

pmOS moved **roughly twice the charge** in the same eight hours while its own
gauge reported 29 points against 25 — and the voltage travel says it without any
mapping (442 mV against 295, ending 259 mV below anywhere the oracle went).

✅ **Confirmed 2026-08-28, and the anchor is gone.** The oracle-scale column used to
map pmOS voltages through the UT ladder's own V→`capacity` points, hanging below
3.967 V off the single 3.735 V OCV → 33.5 % cross-check. That extrapolation has
been replaced by a **measured** curve for this pack, read at each ladder's own
endpoints: **623–651 mAh against 1308–1335 mAh, 2.05–2.10×**, where the mapped
estimate said 2.12×. Two independent routes to the same number, three percent
apart.

☠️ **The top of that column is contested by ~6 points** — 86.8 % by the voltage
mapping against ~93 % by the time budget (the 7.2-point fall it wants would need
1202 mA for the 11 minutes between the two, where even an implausible 800 mA boot
costs 4.8). Unresolvable from what was captured: **the two systems' `voltage_now`
have never been compared on the same pack under the same load.** A constant offset
is excluded — the +90 mV that would fix the start puts the end at 44 % where 33.5
was measured. The conclusion survives either way (53 or 59.5 points, both ≈2× the
oracle's 25).

### ★ Protocol for every comparison ladder from here on

> **Before the slot switch, on the UT side, with the charge input OFF and the pack
> rested, record `capacity` AND `voltage_now`. The first rung of the pmOS ladder
> must then open at the same voltage** — which pins its percentage to the oracle's
> by construction, instead of leaving the two ladders' start points untied.

Both halves matter. Charging inflates the reading (4.379 V charging against
4.262 V the moment the input was cut — 117 mV of it was the charger), and the
percentage alone cannot cross two gauges that disagree by 30 points. If the first
rung does **not** open at that voltage, the gap is real consumption between the
two readings and gets logged as such, never absorbed into the ladder.

☠️ **Compare charge through the measured curve — energy was not the safe choice
either.** The half of this that stands: the two ladders did not cover the same part
of the pack (pmOS 4.150 → 3.708 V against the oracle's 4.262 → 3.967 V), so raw mA
and raw mV/h are both wrong (442 vs 295 mV looks like 50 % and is mostly the Li-ion
curve steepening below 3.9 V, where only pmOS ran). ☠️☠️ **The half that was wrong,
until 2026-08-28: "so compare energy".** Energy is `current_now` × `voltage_now`
integrated, so it inherits everything wrong with `current_now` — and on the oracle
`current_now` is contradicted by that phone's own coulomb counter by 2.056×,
because reading it every few seconds wakes a phone that would otherwise be asleep.
**The instrument that does not have this problem is the pack**: convert each
ladder's voltage travel to mAh through the curve measured on 2026-08-28
(`captures/2026-08-28_discharge-to-shutdown/`) and compare those. Doing that gives
2.05–2.10×, against the 12.9 % the energy comparison reported.

☠️☠️ **The oracle has a coulomb counter and we do not.** `cc_soc` +
`full_uAh=3060000` on the 4.9 side; on mainline there is no `cc_soc` and
`full_uAh` reads `?`. Where both exist they disagree by **2.056×** over the same
eight hours (integrated 1030.6 mAh against a coulomb 501.2 mAh) — in the direction
that rules out sampling shortfall, because too few samples under-count. The
likeliest reading is that **the sampling itself wakes the phone**. That ratio must
**not** be carried over to "correct" a pmOS figure: it is a property of how often
a system wakes, which is the thing under comparison. Every row above is therefore
integrated-against-integrated. **Getting a coulomb counter onto the mainline side
is the highest-value instrument work left in this area.**

☠️ **The 15.3 mA oracle floor is withdrawn** (2026-08-26). It was one window on
2026-08-24, and the state-of-charge explanation offered for it died on its own
test: over 94 % → 69 % the oracle's floor does not move, and rung 5 covers exactly
that capture's 4.050 V and reads 71.0 mA. The reproducible oracle figure is
**69–77 mA floor / 59–64 mA integrated**. Anything scored against 15.3 mA — the
"3.5× against us" framing included — was scored against an outlier.

The single-window history below is kept because the marginals in it stand; read
the levels against the ladders above.

| | draw | measured |
|---|---|---|
| pmOS, as a stock image ships it | **166 mA** | 2026-08-12 |
| pmOS, with the camera released | **68 mA** | 2026-08-13 |
| Ubuntu Touch, same protocol | 86 mA | 2026-08-11 |
| awake, idle, panel **off**, session running | **58–63 mA** | 2026-08-19 |
| the panel, powered at zero brightness | **+24.5 ± 6.4 mA** | 2026-08-19 |
| asleep, no cuts | 79.1 mA | 2026-08-19 |
| asleep, no cuts, reproduced on r64 (i2c-qup fix aboard) | 83.4 mA | 2026-08-22 |
| asleep, ADSP collapsing every suspend | 70.8 mA | 2026-08-20 |
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

☠️ **And a master going down is not enough.** Measured 2026-08-20: with the audio
DSP power-collapsing for the *whole* of every suspend, `vlow` still read
`Count: 0`. The claim this investigation carried for several days — that a master
which never shuts down is a *sufficient* explanation for `vlow` — is half wrong.

**pmOS does not suspend on its own here, because we asked it not to.** Automatic
sleep works and was demonstrated on this base. The original reason it went off —
an incoming call could not wake the phone — is **fixed as of r66 (2026-08-22)
and call-proven**: every rpmsg edge is an armable wakeup source, the
`fp3-modem-wake-arm` unit arms the modem edge at boot, and a live call woke the
phone 15 s into a 300 s suspend window. What keeps automatic sleep off now is
the successor problem: with the edge armed, the modem's payload-free signal
ring (~one poke per 2 s) re-wakes the phone within seconds of every suspend, so
call-wake and staying asleep are mutually exclusive until that ring is quieted
(measured as the 99-suspend check failing armed and passing disarmed).
`sleep-inactive-battery-type` is `'nothing'`; neither kernel offers
`/sys/power/autosleep`.

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
| the smd-edge wake IRQ (r66) | `qcom_smd_parse_edge()` requested the edge interrupt with no wake registration, so an incoming call slept through s2idle and replayed on the button | armed, a live call woke the phone 15 s into a 300 s window; disarmed (the default), windows sleep to the alarm |

## What is still open

| question | where it is being worked |
|---|---|
| ★ **the modem stack costs ~36 mA asleep** — reproduced against a same-day control, and **the only intervention that has ever moved the sleeping slope**. The mechanism is still unnamed, and this is where the next measurement belongs | [`bringup/findings-log.md`](bringup/findings-log.md) (Part II) |
| **`vlow` has never once been reached** — and as of 2026-08-23 the whole AP-side sleep-set family is closed, three measured negatives deep (XO released, every regulator voted in both sets, explicit icc sleep zeros — the three r68/r69 experiment knobs, default off). Simultaneity is not the gap (the APSS held one 121 s XO-shutdown spanning a whole suspend) and the TZ is acquitted (all-zero on the oracle too). ☠️ The decisive control is unrun: with a USB cable in, the oracle cannot sleep at all, so whether the working system ever reaches vlow is itself unmeasured | [`../TODO.md`](../TODO.md) deep-sleep next-steps; [`bringup/leads/rpm-sleep-set.md`](bringup/leads/rpm-sleep-set.md) |
| ~~**LPASS never shuts down**~~ — **solved and priced, 2026-08-19/20.** It is held by upstream's internal digital codec (`msm8916_wcd_digital_probe()` enables `mclk` and `ahbix-clk` at probe and drops them only in `remove()`). Freeing it is worth **~4 %**, inside the instrument's own spread — a correctness fix, not a power one | [`bringup/leads/lpass-never-sleeps.md`](bringup/leads/lpass-never-sleeps.md) |
| ~~**the RPM sleep set**~~ — **closed, 2026-08-19.** Five enabled rails with no sleep vote became **one** with the USB controller unbound, and that one is the eMMC's. The mainline/vendor divergence is real in the code and costs nothing droppable here | [`bringup/leads/rpm-sleep-set.md`](bringup/leads/rpm-sleep-set.md) |
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
[`findings-log.md`](bringup/findings-log.md#why-suspend-only-halves-it-there-is-no-deep-state);
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
