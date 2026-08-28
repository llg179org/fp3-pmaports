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

### ★★★★★ The answer, as of 2026-08-28 evening: it is the modem's awake time on **LTE**

**2G reproduces the oracle's number on our own phone.** A-B-A′ on the access
technology, MPSS duty as the measure, 184 samples a leg, the phone registered and
call-capable throughout:

| leg | access tech | current median | **MPSS core up** | edge IRQ/s |
|---|---|---|---|---|
| A | `lte` | 98.5 mA | **34.8 %** | 34.7 |
| B | `gsm, gprs` | **54.0 mA** | **6.5 %** | 35.0 |
| A′ | `lte` | 101.0 mA | **34.2 %** | 35.6 |

A and A′ 0.6 points apart. **6.5 % is the oracle's 6.3 %**, and 54.0 mA is *below*
its 55–64 mA band. ☠️ 2G is an instrument, not a proposal — the networks are being
switched off.

**The slot switch settled it, and inverted the search.** One instrument on both
systems within half an hour, same operator and cell (`captures/2026-08-28_modem-window-both/`):

| | pmOS | oracle |
|---|---|---|
| access technology / registration | `lte`, registered | `lte`, registered |
| data context | **none** — `rmnet_ipa0` DOWN, 0 bytes | **active** — `rmnet_data2`, 10.124.125.20 |
| **MPSS awake** | **34.8 %** | **6.1 %** |

6.1 % reproduces the 2026-08-24 figure to a fifth of a point, this time with the
radio state in the same file as the counters. So **LTE is not intrinsically
expensive on this hardware** — and **the cheaper system is the one doing more.**
The question is no longer what we hold that they release, but what they set up that
we never do: the vendor stack runs `netmgrd` and `ipacm` to build the IPA data
path, and on pmOS the IPA is probed and no channel is ever brought up.

☠️ Signal does not explain it and points the wrong way — ofono `Strength = 12–15`
against ModemManager's `78 %`.

☠️ **And the two fronts are independent.** `edge_irq_per_s` is 34.7 / 35.0 / 35.6
across all three legs: the modem's SMD-edge ring is the same on LTE and on 2G while
the core's duty moves five-fold. The ring is not what keeps the core awake, so
fixing the consumption will **not** hand back the suspend residency. Each front
needs its own fix.

### The arithmetic underneath it

Everything below this block is the trail that led here and is kept for its
caveats; **this is the current state.**

| | idle, panel dark, radio up | instrument |
|---|---|---|
| pmOS, modem core **up** | **98–101 mA** | `current_now` median, two 1 h windows |
| oracle (UT) | **55–64 mA** | `cc_soc`, three windows |
| pmOS, modem core **down** (`--set-power-state-low`) | **57.5 mA** | `current_now` median, 360 s leg |
| SoC floor, MPSS *and* PRONTO both down | 63 mA | conditional median, `burst-master.sh` |

**Take the modem's awake time away and this phone idles where the oracle idles.**
There is no residual pmOS overhead behind that term: 57.5 mA sits inside the
oracle's own 55–64 mA band, and `63 + 26 = 89` against a measured 98–101 closes
the arithmetic (26 mA = the duty differential, `(0.352 − 0.063) × 91 mA`).

The duty itself, measured as a master bitmask rather than as current:

| | MPSS core up |
|---|---|
| oracle, 565 s window | **6.3 %** |
| pmOS, three windows | **34–36 %** (up to 51 % on a fresh leg) |
| pmOS, `--set-power-state-low` | **0.0 %** — 186 of 186 samples |

☠️ **`mmcli --disable` does not move it** (36/34/34 %) while `--set-power-state-low`
takes it to zero: "disabled" stops the radio's *use*, "low" powers the *core* down.
Two knobs that look like one lever act on different layers.

**Three candidates are spent, and each died to a measurement, not an argument:**

- *Linux-side levers* — `mmcli --disable`, `ModemManager` stopped, `iio-sensor-proxy`
  stopped: 36/34/34, 38/36/37, 36/39/36 %. All flat, and the modem's own SMD edge
  read zero through the daemon-less leg. **The modem wakes by itself.**
- *Modem firmware* — ☠️ **dead, 2026-08-28.** `modem_a`, `modem_b` and our rootfs
  copy all carry `QC_IMAGE_VERSION_STRING=MPSS.TA.3.1.C1-425464`. The `325768` that
  made this look like a difference is the **metabuild** number out of
  `verinfo/ver_info.txt`, and our own image embeds that string too — a metadata
  file on one side read against a binary's own version string on the other.
- *"The oracle's 6.3 % might be a powered-down modem"* — the 565 s UT window never
  recorded its radio state, and the same session ran both ofono modems
  `Powered=false`. Closed from our own side without a slot switch: a powered-down
  modem reads **0.0 %**, and 6.3 % is not 0 %.

**So both systems run the same firmware on the same SoC with the same RPM and TZ,
both have the modem powered and registered, and one keeps its modem core down 94 %
of the time while the other keeps it down 50–70 %.** What is left is not a power
lever and not a firmware version but **what the two stacks ask the modem to do** —
attach state, DRX/paging cycle, which QMI services hold it. `mmcli -m 0` reports
`packet service state: attached` on pmOS; whether the oracle attaches a bearer at
idle is a one-line read on each side and is the next measurement.

### ★ The responsiveness side, which is the other half of the goal

The target is UT's consumption **at UT's responsiveness** — a call must still wake
the phone. Measured baseline on r78, modem SMD edge armed, six `rtcwake -m mem -s
600` cycles: slept **60 / 2 / 9 / 6 / 6 / 19 s**, median 7.5 s, **residency ~2.8 %**.
An armed edge rings roughly once every 2 s (IPCRTR, signal-level, 2026-08-22) and
kills the suspend; disarmed, suspends hold 3/3 and calls do not arrive.

☠️ And **neither system sleeps** — the oracle managed 2 completed suspends out of
120 attempts with the full recipe applied (2026-08-24). So suspend residency is
headroom *below both*, not the difference between them, and it must not be quoted
as an explanation of the gap. It was, on the morning of 2026-08-28, and that entry
is withdrawn.

---

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
| ★★★★★ **what keeps our modem core awake 34–36 % against the oracle's 6.3 %** — same firmware, same SoC, both registered; every Linux-side lever flat and the firmware candidate dead. Next: compare attach state / DRX / bearer between the two stacks | [`bringup/findings-log.md`](bringup/findings-log.md) 2026-08-28 |
| ★ **the call-wake ↔ suspend-residency trade** — armed edge: calls arrive, residency ~2.8 %; disarmed: suspends hold 3/3, calls do not. The ring is IPCRTR signal-level traffic and IPCRTR is also how a call arrives, so the channel is not a lever | [`bringup/findings-log.md`](bringup/findings-log.md) 2026-08-22 / 08-28 |
| ⏳ **the gauge divides by the nameplate** — this pack yields 2175 mAh across the OCV table's full span against a declared 3060, so `capacity` floors at 35 % and UPower never acts. Fix is a learned `charge_full`, design settled | [`../TODO.md`](../TODO.md) T1 |
| ★ **the modem stack costs ~36 mA asleep** — reproduced against a same-day control, and **the only intervention that has ever moved the sleeping slope**. The mechanism is still unnamed, and this is where the next measurement belongs | [`bringup/findings-log.md`](bringup/findings-log.md) (Part II) |
