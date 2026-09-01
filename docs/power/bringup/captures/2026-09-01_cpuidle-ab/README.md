# Barring deep idle changes the modem's duty by nothing

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed the measurement it rests on.

Measured 2026-09-01, kernel `#80-fp3`, pmOS on slot b. Raw:
[`raw/`](raw/). Instrument: [`tools/cpuidle-ab.sh`](../../tools/cpuidle-ab.sh).

## The question

The modem here wakes at the same rate as the Ubuntu Touch oracle but stays awake
about seven times longer per wake. By this evening the radio-side explanations
were gone — four different mode preferences on one cell give the same duty — and
so was the QMI one: a 300 s census in this exact state counted eighteen QRTR
messages against roughly 770 wakes, with `rmtfs` using no CPU at all.

That left one form of "the modem waits for the AP": not for an *answer*, but for
the AP to *be there* — every wake paying for an application processor climbing
out of power collapse. Barring deep idle is the strongest version of "the AP
responds instantly" the hardware can offer, so a duty that does not move
**falsifies** that, rather than merely failing to support it.

## Pre-registered

MPSS duty in the barred arm drops ≥10 points ⇒ the long wakes contain AP wake-up
latency. Duty inside the ±3-point repeatability band, with a clean witness ⇒ the
hardware-latency flavour is falsified.

## Result

| arm | deep idle | MPSS awake | `state1` entries |
|---|---|---:|---:|
| A | free | **51.7 %** | 80 645 (134.4/s) |
| B | **barred** | **50.5 %** | 27 (**0.045/s**) |
| C | free | **50.4 %** | 82 381 (137.3/s) |

**The knob took, completely:** deep-idle entries fell by 100.0 %, from 134.4/s to
0.045/s. The constraint was verified in place (`0`) during the arm and verified
released (`2000000000`) after it.

**The duty did not move.** B sits *between* A and C, and the A→C drift on its own
is 1.3 points — larger than the A→B difference.

The covariates held across all three arms: same cell 1470762, same band
eutran-1, channel 500, TAC 5300, CS and PS attached, RSRP −93.7 … −95.4,
SNR 17.8 … 18.8. No arm is voided by a reselection.

⇒ **Falsified.** The modem's extra ~175 ms per wake does not contain the AP's
wake-up latency. Together with the QMI census, both flavours of "the modem waits
for the AP" are now dead.

## What this does not say

It says nothing about the AP's own current — barring power collapse certainly
costs the AP power, and this measurement does not price that, because duty is
the cross-arm comparable and the arms ran under instrumentation load.

And it does not exclude non-latency AP involvement: RPM sleep-set votes,
interconnect and bus votes, or a missing throughput vote that leaves every unit
of the modem's radio work slower. That last one is the surviving candidate that
predicts a constant ratio between our duty and the oracle's across cells, and it
is what the next slot switch should test.
