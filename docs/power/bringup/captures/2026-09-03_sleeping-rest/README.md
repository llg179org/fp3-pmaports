<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# ★ The sleeping rest works — and the same measurement caught the acceptance criterion lying

2026-09-03 03:30–03:46, 15 × 60 s sleeping samples, radio off, USB input
suspended. Both rests of the [2026-09-02 night](../2026-09-02_night-replication/)
ran with **zero** suspends — on a plain `sleep`, so the AP was awake throughout,
and neither OCV endpoint could settle.

## What the fix bought

| | 09-02 night | 09-03, with `nap()` |
|---|---:|---:|
| `PM: suspend entry` during the rest | **0** | **15** |
| voltage over the last 3 minutes | −0.78…−0.91 mV/min | **4.264 / 4.263 / 4.264 / 4.264 V** = ±1 mV |

So swapping `sleep` for `rtcwake` does exactly what it was added for.

## ☠️ But the verdict came out RED, and the fault was in the INSTRUMENT

The script reported "5.39 mV/min, NOT RESTED" for a series whose last four points
are **within 1 mV**. The cause: it computed the slope from the **first and last**
of the trailing six points — that is a two-sample difference, not a slope — and
nine minutes in, a load dip pulled two samples down by 30 and 90 mV. One of them
landed at the *start* of the window.

```
 496 s  4.282 V
 558 s  4.236 V   ← dip
 620 s  4.204 V   ← dip
 682 s  4.264 V
 744 s  4.263 V
 806 s  4.264 V
 868 s  4.264 V
```

On the same data:

| estimator | result |
|---|---|
| old (first−last of the trailing 6) | **5.42 mV/min → NOT RESTED** |
| new (MAD filter + fit, trailing 6) | **0.10 mV/min → RESTED**, "2 samples dropped as outliers" |

☠️ **The fix is not smoothing.** A load dip inside a rest is a **disturbance**,
not noise, and it has to be named: the script prints how many samples it dropped,
and if fewer than four survive the verdict is not "did not settle" but
**"disturbed rest"** — two different things, and one must not be allowed to
masquerade as the other. Same principle as the legs' attribution rule: the
explanation changes the *label*, not the fate.

☠️ **And a window-length lesson.** Over eight samples (≈7 min) the fit gives
−2.73 mV/min, because the window reaches back to the higher level *before* the
dip — the dip moved the pack permanently lower, so there is a real fall there.
Over six (≈5 min) it gives 0.10. The criterion's original intent was "the last
five minutes" too; the longer window is not more robust, it **answers a different
question**.

Raw data: [`raw.txt`](raw.txt).
