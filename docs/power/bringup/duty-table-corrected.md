> ⚠️ **AI-generated.** Maintained by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

# Every duty number, re-read with the corrected instrument

**2026-08-31.** Two independent parser defects in `tools/modem-window-fit.py`
fell within an hour of each other (`87be062`, `474ff79`), and **both produced
the same false `awake 100.0%`**. Every duty figure this project has ever quoted
came out of the broken version, so all of them were re-run against the fixed
one. This page is the result — the table, and which earlier conclusion survives.

Reproduce it with:

```sh
for f in $(grep -rlE '^(BEFORE|AFTER)' captures/ | sort); do
    python3 tools/modem-window-fit.py "$f"
done
```

## The corrected table

`awake %` per RPM master. **pmOS** rows are ours, **UT** rows the oracle.

| capture | APSS | MPSS | PRONTO | LPASS |
|---|---|---|---|---|
| pmOS 08-28 `pmos-lte` | never entered | **34.8%** | 26.7% | **asleep all window** |
| UT 08-28 `ut-lte` | never entered | 6.1% | 23.2% | 3.0% |
| UT 08-28 `ut-ipacm-on` | never entered | 8.0% | 24.1% | 2.9% |
| UT 08-28 `ut-ipacm-off` | never entered | 6.6% | 21.3% | 2.9% |
| UT 08-28 `ut-ipacm-off-real` | never entered | 6.4% | 20.8% | 2.9% |
| UT 08-28 `ut-netmgrd-off` | never entered | 5.3% | 20.9% | 2.8% |
| UT 08-30 `oracle-context-ab` A | never entered | 6.9% | 23.1% | 3.0% |
| UT 08-30 `oracle-context-ab` B | never entered | 5.2% | 21.3% | 2.9% |
| UT 08-30 `oracle-context-ab` A′ | never entered | 5.4% | 22.7% | 2.9% |
| pmOS 08-31 `mm-duty-ab` A | never entered | 5.1% | 19.1% | **asleep all window** |
| pmOS 08-31 `mm-duty-ab` B | never entered | 4.9% | 16.7% | **asleep all window** |
| pmOS 08-31 `mm-duty-ab` A2 | never entered | 4.9% | 16.8% | **asleep all window** |

## What survives, what dies, what is new

**MPSS is untouched by both fixes.** Every MPSS figure is bit-identical before
and after — the master that actually toggles was never affected by either
defect. So the D-track keeps its foundation, and now holds it from an
instrument that has been shown to fail and been repaired:

* pmOS **34.8%** (08-28) stands.
* the oracle's **5–8%** stands, across nine independent windows.
* pmOS **4.9–5.1%** (08-31) stands.

⇒ the open question is unchanged and still the sharpest one on this front: the
same stack gave 34.8% on 08-28 and 4.9% three days later. **The duty is a state,
not a property** (`leads/sleep-length-is-a-state.md`), and nothing yet names
which state.

> ☠️ **Updated 2026-09-01 — the low readings above are n=1 or n=2, and 55 sleep
> windows since disagree with them.** Three whole-night censuses with
> ModemManager stopped now give **33.4 – 42.9 %, mean 36.3 %, none below 30 %**,
> across Wi-Fi up and Wi-Fi down and two days
> ([`captures/2026-09-01_modem-night-control/`](captures/2026-09-01_modem-night-control/README.md),
> [`captures/2026-09-01_wifi-up-arm/`](captures/2026-09-01_wifi-up-arm/README.md)).
> The 4.9–5.1 % rows stand as readings of the windows they were taken in; they no
> longer stand as *the* MM-stopped duty, and no arithmetic should use them as one.
>
> The rows also differ in a way this table does not record: the 08-31 low windows
> were taken with the cable in and the pack `Full` — a **charging** phone. Whether
> that is the state the lead is looking for is being measured now, and the
> decomposition that makes it legible is wake **length**, not wake rate: 148 ms
> awake per XO cycle cable-out against 16 ms in the 5 % window, at a nearly
> unchanged ~2.4–3.1 cycles per second.

**The LPASS differential is dead.** pmOS LPASS reads *asleep the whole window*
in all four of its captures; the oracle's 2.8–3.0% is a real, small duty. Both
systems' audio DSP sleeps. What looked for three days like our worst master was
the arithmetic inverting on a master that never woke.

**PRONTO is a new channel, and it was never visible before.** It printed
`100.0%` in every capture ever taken, because the `[TZ]` block of zeros that
follows it was being read into it. Corrected, it is **16.7–26.7% awake on both
systems** — pmOS 16.7–26.7%, UT 20.8–24.1%.

☠️ Read that carefully before it becomes the next LPASS: the ranges **overlap**.
PRONTO is not a differential, it is a cost both systems pay, and the oracle pays
it while drawing far less. It is a named suspect for item 18 (what draws ~41 mA
in s2idle) and nothing more — and even that is weak, because these are *awake*
windows. Whether PRONTO stays up **under s2idle** has never been measured.

**APSS never enters XO shutdown on either system.** Unchanged, and it agrees
with the closure recorded on 2026-08-30: this is the platform's normal state,
not a pmOS defect.

## The method this is the second instance of

Two defects, two different mechanisms, one identical symptom — a saturated
`100.0%`. The habit that catches this is already recorded (findings-log, and
the skill note `004d681`): **read every column on every run, and when a value is
saturated — 0%, 100%, a counter that does not move — decide explicitly whether
it is a finding or an artefact.** Neither defect needed new hardware or a new
capture to find. Both needed someone to disbelieve a round number.


## Was the WiFi even on during the floor measurement? (item 24)

Asked of the **log**, not of a new measurement, because the answer was already
written down twice.

**1. The `# wifi: ?` in every night-ladder header is a known blind spot, not an
"off".** `tools/idle-ab.sh` says so in its own comment: `/proc/net/wireless`
needs `CONFIG_CFG80211_WEXT`, which pmOS does not build, and *"every pmOS
capture from 2026-08-26 and -27 recorded `wifi: ?` **with the link plainly
associated**"*. Reading that field as "no WiFi" inverts it.

**2. The harder witness is in the same header, and it is unambiguous:**

```
# remote processors: 4080000.remoteproc=running a204000.remoteproc=running adsp=running
```

`a204000` is `wcnss: remoteproc@a204000`, `qcom,pronto-v3-pil`
(`arch/arm64/boot/dts/qcom/msm8953.dtsi:1955`) — the PRONTO subsystem itself.
**16 of 16** header samples across all eight rungs of
`captures/2026-08-26_pmos-night-ladder/` say `running`.

⇒ **PRONTO was loaded and running for the whole night**, and the step-0 gates
(ModemManager stopped, `bl_power=4`, `status=Discharging`) never gated WiFi. The
48 mA floor therefore **contains** whatever WCNSS costs, alongside the ~7 mA
modem term — which is exactly the room the unexplained ~41 mA lives in.

☠️ **What this does not establish.** The 48 mA fit comes from the 58-round
`sleep-night.sh` discharge run, and *that* run's capture is not in this
repository — the `running` lines above are from the ladder night of the same
regime, not from the fitted run itself. Same phone, same gates, same days; still
a different file. Until the night run's own environment header is read, "PRONTO
was up during the fitted night" is an inference from a sibling capture, not a
direct reading. It is also **not** evidence that the radio was transmitting: a
loaded remoteproc is a floor on the subsystem's state, not a duty.
