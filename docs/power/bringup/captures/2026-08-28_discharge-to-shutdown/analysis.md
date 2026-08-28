# 2026-08-28 — the pack holds 2185 mAh, and the gauge stops at 35 %

> ⚠️ **AI-generated.** Claude (Opus 5) under the direction of Lajosházi, László
> Gergely.

`discharge-gate.sh` → `discharge-run.sh 10`, one continuous run from a
**terminated** charge to the phone switching itself off. pmOS r77 (`#78-fp3`),
panel proven dark for **all 6408 rows**, charge input cut and proven
(`status=Discharging`), no sample gap longer than 60 s.

| | |
|---|---|
| duration | **17.94 h** (2026-08-27 17:57 → 2026-08-28 11:56) |
| claimed capacity | **100 % → 35 %** — it never got below 35 |
| terminal voltage | 4.308 V → **2.864 V** |
| integrated draw | **2185 mAh** |
| nameplate `charge_full` | 3060 mAh — **the pack delivered 71 % of it** |
| current | p10 56, **median 108**, p90 217 mA (mean 122, and the mean is not the number) |

## The finding, and it is one number

**`charge_full` is the 3 060 000 µAh nameplate, and the pack holds 2185 mAh.**
Everything else follows arithmetically: the gauge divides real coulombs by a
denominator that is **40 % too large**, so it under-counts the percentage
consumed. 2185/3060 = 71.4 % of nameplate spent → the reading lands near 29 %,
and it stopped at **35 %** (the residual ~6 points being the QG's own OCV
correction). **The missing 35 points are not a drift or a slope error — they are
the difference between the nameplate and the cell.**

This is the direct confirmation of the 2026-08-27 crosscheck (pmOS 63 % against
the oracle's 33 % on the same rested pack), and it is stronger, because nothing
here depends on the oracle or on an assumed OCV curve.

## The cliff at the bottom

| claimed | voltage | hours in |
|---|---|---|
| 48 % | 3.600 V | 14.78 |
| 39 % | **3.400 V** (`voltage_min_design`) | 17.20 |
| 37 % | 3.200 V | 17.68 |
| 36 % | 3.000 V | 17.88 |
| **35 %** | **2.864 V** | **17.94 — off** |

The last 200 mV took four minutes. **The phone crossed its own design minimum
with the gauge reading 39 %** and kept going for 45 minutes, because nothing in
the stack acts on `voltage_min_design` — the shutdown, when it came, was the
hardware's, not the software's.

☠️ **2.864 V is well below where a Li-ion should be taken**, and this run did it
because there was no low-battery cut-off in the way. Do not repeat this casually:
the measurement is worth a deep discharge once, not routinely.

## What this settles, and what it does not

* ✅ The pack's real capacity: **2185 mAh**, 71 % of nameplate. Every
  "points → mAh" figure on **both** systems has been computed against 3060.
* ✅ The gauge's ~30-point optimism, with a mechanism rather than a comparison.
* ✅ The lower leg of the discharge curve, which no capture had: 3.6 V is 48 %
  claimed and roughly 20 minutes of real charge from the bottom.
* ☠️ It does **not** settle the 2.12× / 1.20× / 1.13× ladder contradiction on its
  own — that needs the same correction applied to both ladders' charge columns,
  which is the next piece of work and needs no device.
* ☠️ One deep discharge measures the pack **as it is today**, at 21–27 °C, at
  ~110 mA. Capacity is temperature- and rate-dependent; this is not a datasheet
  number.

## The fix this implies

`charge_full` must be **learned**, not the nameplate — the QG path already has
the machinery to track a full-to-empty excursion. Until it is, `capacity` on this
phone will keep telling its owner it has a third more battery than it does, and
will keep stopping at 35 % when the phone dies.
