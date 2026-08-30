# 2026-08-30 — the control leg for step 0: does the OCV fit reproduce a known number?

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

**Command:** `awake-ocv-control.sh 90 300` (90 minutes, 300 s between samples),
14:26–15:57, ModemManager stopped, panel down (`bl_power=4`), charge input cut
(`status=Discharging`). 18 samples, 98 % → 93 %, 4.2976 V → 4.2049 V.
**Fitted with:** `sleep-night-fit.py` against
`captures/2026-08-28_discharge-to-shutdown/discharge.txt`.

## Why this ran before the sleeping leg

`sleep-night.sh` prices a suspend from the rest-OCV slope, which is a **new
instrument aimed at the one regime nothing else can measure** — the shape that
once produced a "spectacular sub-2 mA" reading on this project. A control in a
regime the phone already has a number for is the cheapest way to find out whether
the fit means anything.

## The reading

```
average draw = 122.3 mA   (rms residual 20.5 mAh)
☠️ the run sits on the flat top of the curve (>4.15 V); a night's drain there is
   inside the sample spread
```

**Compared against what?** Not a single number — and that matters. Awake idle on
this phone has been measured across a band, because the modem's duty is not
stationary:

| source | awake idle |
|---|---|
| `2026-08-28_2gonly-master-ab/` leg A (LTE) | 98.5 mA |
| same series, leg A′ | 101.0 mA |
| `2026-08-28_radiolow-master-ab/` leg A | 128.0 mA |
| same series, leg A′ | 88.5 mA |

**122.3 mA sits inside that band.** The control therefore passes the bar it was
built for — the fit does not return an absurd number — but it does **not**
discriminate better than roughly ±20 %.

## What that licenses, and what it does not

✅ **Good enough for step 0's decision table**, whose branches are `< 15 mA`,
`15–40 mA` and `> 40 mA`. A ±20 % instrument separates those cleanly.

❌ **Not good enough for anything finer** — no ranking of levers by a few mA, no
"this change saved 8 %". Any such claim needs a different instrument.

☠️ **And the tool's own flat-top warning applies to this leg**, which is why the
residual is 20.5 mAh: the pack started at 98 % and ended at 93 %, mostly above
4.15 V. The sleeping leg that follows starts at 93 % and runs down, so its fit
sits on a progressively more readable stretch than this one did.

☠️ **The control is not in the goal's configuration either.** ModemManager is
stopped for both legs, so this is a phone that cannot receive a call — see
`power/NEXT-RUN.md`, "what step 0 measures is a FLOOR, not a night".
