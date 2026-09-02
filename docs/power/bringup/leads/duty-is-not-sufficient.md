<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# ☠️ Duty is not a sufficient statistic for current, and this repo's own band ladder proves it

**Status:** a correction to how every milliamp figure in this investigation is
derived. It does not overturn any duty measurement; it overturns the step that
turns a duty into a current.

## The model, and where it came from

`mA = 41.4 + 133 × duty` was fitted on **sleeping** windows — two points from the
eight-hour rtcwake censuses that produced the 86 ± 4 mA figure. It has carried
every "what would this be worth" statement since.

## The band ladder contradicts it, in this repo's own numbers

From [`../captures/2026-09-01_band-ladder/`](../captures/2026-09-01_band-ladder/),
four legs in one boot, 44 minutes, median `current_now` per leg:

| band | duty | model says | **measured** | residual |
|---|---:|---:|---:|---:|
| eutran-1 (mean of two legs) | 48.8 / 51.6 % | 106.3 mA | **147 mA** | **+41** |
| eutran-20 | 34.1 % | 86.8 mA | **93 mA** | +6 |

The model is nearly right on one band and 41 mA short on the other. Whatever the
extra term is — transmit power is the obvious candidate, since eutran-1 is
2100 MHz and eutran-20 is 800 MHz with 9 dB better RSRP in that ladder — **it is
not carried by duty**, and the same duty means different currents on different
bands.

☠️ **The quantitative form of this is contaminated and must not be quoted.**
`current_now` can only be sampled with the AP awake, so those 147 and 93 mA are
*awake* currents, while the 133 mA/duty slope was fitted on *sleeping* windows.
An implied "slope" computed across the two band points therefore compares two
different quantities. The qualitative claim survives; a number does not.

## What this does to the headline

The A/B/A' ladder is pinned to **eutran-1** — the band where the model predicts
worst. So:

- "IMS off is worth **58 mA**" (133 × (0.480 − 0.044)) is **a model evaluation on
  the band where the model is least trustworthy**. It is not a conservative
  estimate and it is not a measurement.
- "The cheap state is **47.3 mA**" (41.4 + 133 × 0.044) inherits the same problem,
  plus the intercept's own — 41.4 mA is the extrapolation of a two-parameter fit
  to duty = 0, which is not a measurement of anything and has no owner.

**What stands unchanged:** every duty number, the mechanism, and the direction.
The IMS loop is causal for ~44 pp of modem duty, three times over, and stopping
it is measured to be free on this network. What is *not* established is how many
milliamps that buys.

## What would fix it

Either drop the model and measure the two states directly in the unit the goal is
written in, or refit it with a band parameter. The first is cheaper and is what
the current front is now organised around — see the plan items for the
rest-endpoint census, the threshold-time ratio, and the QG raw registers.
