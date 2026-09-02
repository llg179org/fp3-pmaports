<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# ★★★★★ The IMS loop also stops the AP sleeping — and the cheap state draws ~40 mA

`tools/ims-ma3.sh 25 60 eutran-1`, 2026-09-02 06:53–08:11, one boot, on battery
(USB input suspended in the PMIC), band pinned, and the fuel gauge's hardware
current accumulator read as the **first thing on every wake** — the instrument
that keeps counting while the AP is suspended
([`../../leads/qg-accumulator-current.md`](../../leads/qg-accumulator-current.md)).

The IMS switch vector was read back at each leg's **start and end** and held in
all three: A and A′ voice/VoWiFi/video/SMS/UT `True`, B all `False`. Every leg on
`eutran-1`, `registered`.

## ★ The finding nobody was looking for: with IMS on, the AP cannot stay asleep

The alarm was 60 s in every leg. What the phone actually did between wakes:

| leg | IMS | min | p25 | **median** | p75 | sleeps under 30 s |
|---|---|---:|---:|---:|---:|---:|
| A  | on  | 1 s | 3 s | **16 s** | 61 s | 31/53 (58 %) |
| **B**  | **off** | 4 s | **59 s** | **62 s** | 62 s | **5/29 (17 %)** |
| A′ | on  | 2 s | 7 s | **18 s** | 51 s | 35/56 (62 %) |

With IMS off, three quarters of the sleeps run the **full alarm**. With IMS on,
well over half end in under thirty seconds and a quarter end in **under seven**.
The loop is not only keeping the modem awake — its RRC traffic keeps waking the
**application processor** too, through the modem SMD edge this project armed as a
wake source so that calls would ring.

That is a system-level cost the modem-duty model never carried, and it is the
reason the measured current gap is larger than that model predicts.

## The current

Aggregated the way the accumulator has to be — **Σaccum / Σcnt**, not a mean of
per-sample means — and gated: a sample whose `cnt` implies a window longer than
that leg's sleep began *before* the sleep and carries the previous wake's awake
current, so it is dropped.

| leg | MPSS duty | wakes/s | kept | **current** |
|---|---:|---:|---:|---:|
| A  | 46.8 % | 2.57 | 7/54 | 91.0 mA |
| **B**  | **4.5 %** | **3.14** | **22/30** | **40.1 mA** |
| A′ | 47.7 % | 2.52 | 11/57 | 98.8 mA |

**The B number is the one that stands**: 22 of 30 samples survive the gate, on
the only leg that genuinely slept a full minute at a time. **~40 mA, under the
50 mA goal** — and it agrees with the ~40 mA the voltage-slope method gave for
the same state by a completely different route, which is the first time two
independent methods have agreed here.

☠️ **A and A′ are not sleeping-floor numbers.** Those legs barely slept, so their
windows are dominated by awake current and only 7 and 11 samples survive the
gate. Read them as the system's cost in that state, not as a floor. The ~55 mA
difference is therefore a *system* difference — duty plus lost sleep — which is
the honest label for it.

☠️ **The dropped fraction confirms the gate's own theory.** In leg B, which
actually slept 60 s, 27 % of samples were contaminated against the ~21 %
predicted from the accumulator's 76 s wrap period. In A and A′ the figure is
81–87 %, exactly because those legs never slept long enough for a wrap to land
inside the sleep — the gate is not broken there, the sleep is.

## ☠️ What still gates the absolute claim

The accumulator and `current_now` agree to ~2 mA, but they **share the PMIC and
its ADC**: that agreement validates the conversion, the sign and the register
reading — the likely mistakes — and says nothing about a gain or offset error in
the layer they share. A gain error is second order (5 % of 50 mA is 2.5 mA); an
**offset** error decides between "40 mA, goal met" and something else, and it does
not cancel in a difference used as an absolute. Every current number in this
project inherits that one calibration, the 2185 mAh reference curve included,
because its mAh axis was integrated from this same chip.

The only witness that does not pass through the PMI632 is a shunt in series with
the pack — the FP3's battery is removable, so it is a one-off calibration rather
than a census.

## Raw

`raw/log.txt` (per-leg IMS read-backs), `raw/samples-{A,B,A2}.txt` (one line per
wake: accumulator, count, current, voltage, capacity), `raw/mpss-*.txt`.
