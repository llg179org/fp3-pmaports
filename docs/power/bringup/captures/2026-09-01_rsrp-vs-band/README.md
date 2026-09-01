# The 17 points belong to the band, not to signal level

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed the measurements it rests on.

Analysis, 2026-09-01. No new measurement: this pools ten legs taken today, each
600 s or 300 s, each carrying band, cell and RSRP alongside its duty. Sources:
[`2026-09-01_band-ladder`](../2026-09-01_band-ladder),
[`2026-09-01_mode-ladder`](../2026-09-01_mode-ladder),
[`2026-09-01_cpuidle-ab`](../2026-09-01_cpuidle-ab).

## Why

The band is worth 17 duty points inside our stack, and an outside review pointed
out that duty is also loosely monotonic in RSRP across the same ladder — so the
"band effect" might really be a **signal-level** effect, with a weaker serving
cell buying more per-DRX measurement. That is a different mechanism with a
different fix, and separating them normally means waiting for the network to
move. It does not here: seven of today's legs sat on eutran-1 across a 3.9 dB
spread of RSRP.

## The test

If RSRP drove duty at the rate the cross-band spread implies, the within-band
legs would show it.

| | RSRP span | duty span | slope |
|---|---|---|---|
| within eutran-1 (7 legs) | −97.6 … −93.7 (3.9 dB) | 48.8 … 51.7 (**2.9 pts**) | **+0.25 pts/dB** |
| across bands (3 band means) | −95.0 … −85.8 (9.2 dB) | 50.4 … 34.1 | **1.77 pts/dB** |

At 1.77 pts/dB, the 3.9 dB spread inside eutran-1 would produce **6.9 points** of
duty. The measured spread is 2.9 points — the ladder's own repeatability — and
the fitted slope is seven times too small, with the wrong sign for the
hypothesis (more negative RSRP giving slightly *lower* duty).

⇒ **RSRP does not drive duty over −93.7 … −97.6 dBm.** The 17 points belong to
the band.

## What this does not say

It covers one 3.9 dB window. A threshold effect outside it — an s-nonintrasearch
gate that only engages below some level — would be invisible here, and the claim
is scoped to the range measured.

And **band is still confounded with cell**: every eutran-1 leg is on cell
1470762, every eutran-3 leg on 1470732, every eutran-20 leg on 1470722. Nothing
here separates "this band costs more" from "this particular cell costs more".
Splitting those needs two bands on one cell, or one band on two cells, and
neither has been measured.
