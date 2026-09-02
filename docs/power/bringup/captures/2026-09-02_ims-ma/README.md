<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# The loop's price with the AP actually asleep: ~40 mA against ~200, and the modem sleeps the whole window

`tools/ims-ma.sh 45 600`, 2026-09-02 02:21–04:02, one boot, on battery (USB input
suspended in the PMIC, cable left plugged so ssh survives), AP suspended in
600 s rtcwake cycles. Expensive leg first, deliberately.

| leg | IMS | MPSS duty | dV/dt | → mA at that voltage |
|---|---|---|---|---|
| expensive | on | **45.6 %** | −142 mV/h | ~200 ☠️ see below |
| cheap | off | **asleep the whole window** | −12.3 mV/h | **~40** |

Both legs read band `eutran-1`, `registered`, at their end.

## ★ The strongest line here is not a current at all

With the AP asleep, the cheap leg's MPSS **XO-off time exceeded the window** —
2861 s of off-time inside 2700 s, because an exit carried sleep in from before
it. The canonical reader refuses to call that a duty and reports a lower bound,
which is the right answer: **the modem was down essentially the entire 45
minutes.** The ladder's 4.8 % was measured with the AP awake; with the AP asleep
the residue disappears too.

The expensive leg reproduces the ladder exactly — 45.6 % against 44.5 / 46.8 % —
which is the cross-check that says the two instruments are measuring the same
thing.

## ☠️ What the milliamp numbers are worth

The conversion uses the local slope of the 2026-08-28 discharge reference at each
leg's own voltage (1.425 mA per mV/h at 4.275 V; 3.233 at 4.205 V), because
`charge_counter` does not exist on this device and `charge_now` is frozen at the
3 060 000 µAh nameplate — the same dead integrator that made `capacity` read
100 % for all 100 minutes of this run.

Three reasons not to quote ~200 vs ~40 as the loop's price:

1. **The expensive leg starts on surface charge.** It began at 4.32 V seconds
   after the charger was cut at 100 %. Its early slope is relaxation plus load,
   not load — so ~200 mA is an overestimate and the pair is not clean.
2. **The cheap leg sits at the resolution floor.** Two of its five rounds show
   zero or *rising* voltage. −12.3 mV/h over 50 minutes is barely above what this
   ADC can say, which is exactly the objection raised against dV/dt on the flat
   top of the curve before the run finished.
3. **Mid-leg band is unobserved.** Both ends read `eutran-1`, but this script
   samples only at the ends, and a reselection inside a leg would not show.

So the honest statement is: **~40 mA is consistent with the ≤50 mA goal and
nothing in this run contradicts it — but it is not a proof, and the number to
quote is still pending.**

☠️ **And an instrument was left on the table.** `current_now` is live on this
device — sampled here right afterwards it read 275.9 → 272.4 → 266.6 mA while
charging, and the 2026-08-28 reference file this analysis leans on *has a
`cur_uA` column*. It cannot replace dV/dt for a **sleeping** phone (the AP must
be up to read it), but it prices every awake comparison directly, and it should
have been in this script's sampler from the start.

## What a clean rerun needs

- Pin the band, and sample it mid-leg, not only at the ends.
- Let the pack settle off the plateau before the first leg starts.
- A/B/A', so a repeat of the expensive arm brackets the drift.
- Sample `current_now` at every wake alongside the voltage.

## Raw

`raw/log.txt`, `raw/rounds-{expensive,cheap}.txt` (per-round voltage),
`raw/mpss-{expensive,cheap}.txt` (the master-stats pair per leg).
