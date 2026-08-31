# The missing cell: the modem across a real suspend, with ModemManager stopped

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed the measurement it rests on.

2026-08-31, kernel `#80-fp3`. Raw: [`leg.txt`](leg.txt).

## Why this window was spent

`floor_mA = 48 ± 5 mA` was measured with ModemManager **stopped**. The claim
"the floor is the modem" was retracted the same morning because the duty applied
to it — 34.8 % — had been measured in an *awake* window, and with MM stopped an
awake window reads 5.1 %.

Then the 2026-08-30 across-suspend capture turned up an MPSS awake share of
**45 %** — measured across a real 601 s sleep, with MM **running**. Two regimes
disagreeing by ninefold makes the awake-window number unreadable for a sleeping
phone, so the retraction itself came into question: it had been made by applying
one regime's number to the other, which is the error it was retracting.

The cell that decides it had never been measured: **the modem across a real
suspend, with MM stopped** — the exact configuration the floor was measured in.

## The measurement

One `rtcwake -m mem -s 600`, `rpm-xo-snapshot.sh` either side, ModemManager
inactive, panel dark, no ssh open. Window 602.2 s, `suspend_stats` 72 → 73,
`fail=0`, ended by `pm_wakeup_irq=56` (the RTC) — a clean, alarm-ended sleep.

**Pre-registered before the run:** ~45 % ⇒ the modem is the floor's main item and
the retraction was premature; ~5 % ⇒ the retraction stands and the ~41 mA is
still unowned.

| RPM master | XO off | of the window | awake | `xo_shutdowns` delta |
|---|---:|---:|---:|---:|
| APSS | 0.0 s | 0.0 % | 100 % | 1 |
| LPASS | 0.0 s | — | **asleep throughout** | 0 |
| **MPSS** | **572.3 s** | **95.0 %** | **5.0 %** | 1888 |
| PRONTO | 601.8 s | 99.9 % | 0.1 % | 4 |

LPASS's zero is the corrected reading, not "awake 100 %": the delta is zero
*and* `xo_shutdowns` did not move, which is a master that never left XO shutdown
(see [`../2026-08-31_xo-dur-semantics/`](../2026-08-31_xo-dur-semantics/README.md)).

## What it settles

**5.0 % — the second branch. The retraction stands.** With ModemManager stopped
the modem's duty is the same asleep as awake (5.0 % vs 4.9–5.1 %), so it is
*not* regime-dependent in that configuration, and the modem's share of the 48 mA
floor is about 7 mA. **~41 mA still has no owner.**

And the floor now has almost nothing left to attribute it to. Across this
window: LPASS down, PRONTO down 99.9 %, MPSS down 95 %, and the APSS's permanent
XO vote is already priced at 0.4 % of the discharge slope
([`findings-log.md`](../../findings-log.md), 2026-08-19 A/B, 0 → 1952 shutdowns).
Four masters accounted for, and the current is still there.

The named suspect that remains is the one never measured in mA: **the USB link**
(plan item 11). The floor was measured with the cable physically in and the
CDC-NCM link enumerated — only the PMIC's input-suspend bit was set — and the
2026-08-24 capture establishes only that the controller and PHY reach runtime
suspend, not what they cost.

## ☠️ Left open, and not to be smoothed over

The 2026-08-30 window (MM **running**, across a real suspend) read 45 % awake,
while today's awake-window A-B-A′ with MM running read 4.9 %. Those two are not
reconciled. Both are n=1 for their configuration, taken on different days on a
network whose behaviour has already been shown to drift. Nothing here needs them
reconciled — the floor was measured with MM stopped, and that cell is now
measured directly — but it is a real disagreement and it is the shape of the
question the D track has to answer.
