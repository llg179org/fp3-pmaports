# 2026-08-27 — burst-master, second window (the repeat)

> ⚠️ **AI-generated.** Claude (Opus 5) under the direction of Lajosházi, László
> Gergely.

Identical conditions to
[`2026-08-27_burst-master`](../2026-08-27_burst-master/analysis.md): same boot,
radios on, panel proven off for all 73 samples, charge cut, 189 samples at 2 s.
Run purely to give the first window's separation a spread, because one median
difference is not a number.

|  | window 1 | window 2 |
|---|---|---|
| current p10 / median / p90 | 52 / 98 / 211 | 53 / 89 / 200 |
| MPSS core up | 62/189 = **33 %** | 69/189 = **37 %** |
| median with MPSS up | 166 mA | 158 mA |
| median with MPSS down | 74 mA | 67 mA |
| **difference** | **+92 mA** | **+91 mA** |

**The separation reproduces to within 1 mA.** The two medians it is built from
move by 7–8 mA between windows, so the difference is steadier than either side of
it — which is what a real effect looks like against a drifting floor.

PRONTO reproduces too, smaller: core up 119 vs 80 (window 2), 109 vs 91
(window 1).

Still true, and still limiting:

* ☠️ correlation, not intervention — both windows share every other condition;
* ☠️ the duty cycle is point-sampled at 2 s, so 33–37 % is an estimate of an
  on-time, not a measurement of one;
* the instrument does not resolve the ~15 mA wlan effect known to be present, so
  a **null** from it still means nothing at that scale. Only the separations do.

The intervention is the next capture: an A-B-A′ where the modem is disabled and
what is compared is **MPSS's duty cycle**, not the current.
