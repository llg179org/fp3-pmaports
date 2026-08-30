# 2026-08-30 — the application processor never lets the crystal go, asleep or not

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed every change and made or reviewed
> every measurement it rests on.

**Command:** `radio-cycle-ab.sh A 600 1` (leg A only — the gate then stopped the
run, correctly, because leg A came out in the long regime). One 600 s alarm,
12:22:27 → 12:32:53, slept **601 s**, ended by `pm_wakeup_irq=72` — the RTC.
`rpm-xo-snapshot.sh` before and after; the difference *is* the integral.

## The result

| RPM master | XO delta (ticks) | at 19.2 MHz | share of the 626 s window | power-collapses in it |
|---|---:|---:|---:|---:|
| **APSS** | **0** | **0.0 s** | **0.0 %** | **879** |
| LPASS | 0 | 0.0 s | 0.0 % | 0 |
| MPSS | 6 614 655 473 | 344.5 s | 55.0 % | 1358 |
| PRONTO | 11 786 390 707 | 613.9 s | **98.1 %** | 180 |

**The measurement calibrates itself.** PRONTO's delta comes to 98.1 % of the
wall-clock window — the WiFi core let the crystal go for essentially all of it —
which fixes the tick rate at 19.2 MHz to within two percent and proves the
counters advance *during* the suspend rather than only around it. Without that
row the absolute seconds would be an assumption; with it they are read off.

**And the application processor is a flat zero across the same window**, while
its own `Shutdown count` rose by **879**. So it power-collapsed nearly nine
hundred times in ten minutes and did not once vote the crystal off.

## What it settles

The goal's arithmetic (`TODO.md`, "the goal now has an arithmetic") sends the
**≤50 mA** target below the modem's reach and into the intercept, on the grounds
that `APSS XO off` reads zero. Earlier today that row was marked *unpriced*,
because the evidence behind it came from a system that could not stay asleep —
two completed suspends in a hundred and twenty attempts.

**That caution is now spent: the row is priced, and it reads the same.** This
window was a real 601 s sleep, ended by the alarm rather than by anything
interrupting it, with two other masters moving in the same file as the control.
The application processor does not reach the state the target needs, and s2idle
as configured here does not take it there.

☠️ **What this does *not* say.** It does not say the hardware cannot. It says
that with this kernel, this configuration and this set of votes, the AP's XO
vote is never released. Which of those three is responsible is the next
question, and it is a different one from anything on the modem front — nothing
about the modem's traffic can change a vote the application processor holds by
itself.

## Read with

- `leads/sleep-length-is-a-state.md` — the regime this window belongs to (long).
- `TODO.md` "the goal now has an arithmetic" — the row this prices.
