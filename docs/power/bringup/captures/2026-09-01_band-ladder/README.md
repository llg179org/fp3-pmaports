# The camping band is worth 17 points of modem duty — and we were on the worst one

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed the measurement it rests on.

2026-09-01 16:09 → 16:53, four 600 s windows inside one boot, one band each,
the first band repeated last so a band effect can be told from drift
([`../../tools/band-ladder.sh`](../../tools/band-ladder.sh)).

The run exists because at 16:07 the phone was found camped on **eutran-1**
(2100 MHz, EARFCN 500, RSRP −94.0 dBm) with an **eutran-20** neighbour 7 dB
stronger — and because the band had been recorded in **none** of the 67 census
windows that produced the "nothing moves the duty" conclusion.

## Result

| leg | band | EARFCN | cell | RSRP | **MPSS awake** | median current |
|---|---|---:|---:|---:|---:|---:|
| L1 | **eutran-1** | 500 | 1470762 | −94.4 | **48.8 %** | 139 mA |
| L2 | eutran-3 | 1300 | 1470732 | −90.4 | **31.8 %** | 108 mA |
| L3 | eutran-20 | 6200 | 1470722 | −85.8 | **34.1 %** | 93 mA |
| L4 | **eutran-1** (repeat) | 500 | 1470762 | −95.3 | **51.6 %** | 155 mA |

Every leg registered on the band it asked for, and each band came with its own
cell — the network hands out a different serving cell per band, which is why
"which band" and "which cell" are one covariate here, not two.

★ **eutran-1 costs 17 points of modem duty against the other two** (50.2 % mean
against 31.8 / 34.1 %), and the A–A′ bracket holds: both eutran-1 legs are high,
both alternatives low, so this is the band and not drift through the run. It
reproduces this repo's earlier band A/B (50.0 % against 36.4 %) on a different
day and a different cell.

★★ **And the current says the same, harder.** These are awake windows, so the
absolute numbers are awake current and not the sleep floor — but the difference
is measured on one phone within 44 minutes: **147 mA on eutran-1 against 93 mA
on eutran-20, ≈54 mA.** The duty model (133 mA per unit duty) predicts only
21 mA from the duty gap, so the expensive band costs *more* than its duty share
— consistent with 2100 MHz needing more transmit power at 9 dB worse RSRP.

☠️ **The wake RATE is not what changes.** `smd_irq_total_per_s` is 35.5, 35.5,
36.6, 35.9 across the four legs — flat. As everywhere else in this
investigation, the band moves how *long* the modem stays up, not how often it
wakes.

## ☠️☠️ What this does to today's other finding

[`../2026-09-01_bearer-arm/`](../2026-09-01_bearer-arm/README.md) read **48.8 %**
with a data context up and concluded the context costs 15 points. **48.8 % is
exactly the eutran-1 number**, and every non-eutran-1 leg here reads 31.8–34.1 %,
which is exactly the "nothing moves it" band. The bearer run's own band was not
recorded — the column did not exist yet.

So the bearer conclusion is **not supported by that measurement**: the arm is
indistinguishable from a band change and distinguishable from nothing else. It
has to be repeated with the band **locked** on both legs. This is the third time
today that a cross-configuration claim has fallen to a covariate measured on
neither side, and the second time it has fallen to this one.

## ☠️ What the band does NOT explain

**The 2026-08-31 morning episode at 4.9–5.1 %.** The cheapest band available
here reads 31.8 %. No band on this network gets the modem near 5 %, so whatever
produced that 34-minute regime is still unaccounted for, and the band is not it.

## Where this leaves the phone

The ladder restored `any`, and the network then placed the UE on **eutran-20**
(EARFCN 6200, RSRP −85.2 dBm) — the cheapest band of the three and the strongest
signal. That is the state the phone is in now, and it is not pinned.

★ **The lever this opens:** a UE-side band preference is a real, forceable knob
worth ~17 points of duty and tens of mA, against a ≤50 mA target. ☠️ It trades
coverage for power — pinning a phone that must be able to receive a call to one
band is not a shipping default without knowing what it costs where the band is
absent. The honest form is a *preference*, not a lock.
