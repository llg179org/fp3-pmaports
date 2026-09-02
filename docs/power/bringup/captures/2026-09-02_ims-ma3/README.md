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

☠️ **The gate's scale is the leg's own sleep, not the alarm.** On a leg that
sleeps the full 60 s the two coincide; on a leg that does not — which is exactly
what the expensive state does — they differ by four times. Reading it as
"3.35 × alarm" keeps 39 contaminated samples in leg A instead of 7 and drags it
from 91.0 mA down to 84.2 mA. Reproduce the table with
[`../../tools/ma3-fit.py`](../../tools/ma3-fit.py), which carries the gate and
the bootstrap.

| leg | MPSS duty | wakes/s | slept | kept | **current** | 95 % CI |
|---|---:|---:|---:|---:|---:|---|
| A  | 46.8 % | 2.57 | 16 s | 7/54 | 91.0 mA | ±8.4 |
| **B**  | **4.5 %** | **3.14** | **62 s** | **22/30** | **40.1 mA** | **±1.0** |
| A′ | 47.7 % | 2.52 | 17 s | 11/57 | 98.8 mA | ±8.4 |

**The B number is the one that stands**: 22 of 30 samples survive the gate, on
the only leg that genuinely slept a full minute at a time. **40.1 ± 1.0 mA**
(95 %, bootstrap on Σaccum/Σcnt) — under the 50 mA goal by more than the band.

☠️ **The band is within-leg only, and that is the smaller of the two errors.**
A and A′ are the same configuration measured twice, 50 minutes apart, and they
differ by 7.8 mA — inside their own ±8.4, so it is consistent with sampling
noise, but it is the only boot-to-boot-shaped evidence here and it is a single
pair. The B leg has no such twin at all: **one leg, one boot.** A number with a
tight band and no replication is the same failure the "58 mA" headline was, in a
more convincing costume.

☠️ **Do not cite the voltage-slope ~40 mA as corroboration.** An earlier draft
did, calling it "the first time two independent methods agreed". That method was
retracted in this same investigation as unusable on this timescale (a 100 mV jump
between two consecutive readings minutes apart; feeding one leg into the
reference curve yielded 1806 mA). A retracted number is not a witness, and an
agreement with one is anecdote, not evidence.

☠️ **A and A′ are not sleeping-floor numbers.** Those legs barely slept, so their
windows are dominated by awake current and only 7 and 11 samples survive the
gate. Read them as the system's cost in that state, not as a floor.

## ☠️ How to say the gap — and how not to

The ~51–59 mA between the legs is a **system** difference: modem duty **plus the
AP sleep the loop destroys**. It must not be quoted as "what the modem duty
costs". That would be a different quantity — IMS on, but the AP sleeping through
it — and nobody has measured it.

Nor can it easily be measured here. Separating the two means silencing the modem
SMD edge towards the AP, and this project's own 2026-08-26 finding stands in the
way: on this platform a non-wake IRQ does not fail to wake the AP, it **aborts
s2idle**. A disarmed leg would most likely land in a third state — awake through
suspend-abort — that answers neither question. If it is ever needed it will be
for the VoLTE direction (where the bearer stays up and the question becomes what
the AP pays), not for this report.

That is not a concession, because the decision-relevant number is the
system-level one: the goal says ≤50 mA at the wall, and 40.1 ± 1.0 is measured
against exactly that.

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

**But the offset can be bounded without one**, because it does not enter the two
routes with the same weight. The accumulator carries it directly (measured =
I + ε). The voltage-and-reference-curve route carries it only through the
capacity axis, since the 2185 mAh was itself integrated at ~110 mA — so its error
is about I × (ε/110), i.e. 0.36 ε at 40 mA. If the two agree to within δ, then
|ε − 0.36 ε| = 0.64 |ε| ≤ δ, hence **|ε| ≤ 1.6 δ**: an agreement to 2–3 mA would
bound the offset to ±3–5 mA with no shunt at all. That needs a long rested
block with radio-off OCV endpoints — a valid second route, unlike the retracted
short-window slope — and it is what the replication plan below buys alongside the
repeat.

**Until it is replicated, the honest label is "measured on one leg of one boot,
40.1 ± 1.0 mA within-leg, calibration unbounded".** Three boots across two days
plus one OCV-bounded block turns that into a number; the plan is item 85.

## Raw

`raw/log.txt` (per-leg IMS read-backs), `raw/samples-{A,B,A2}.txt` (one line per
wake: accumulator, count, current, voltage, capacity), `raw/mpss-*.txt`.
