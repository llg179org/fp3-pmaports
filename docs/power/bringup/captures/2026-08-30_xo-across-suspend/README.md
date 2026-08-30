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

---

## ☠️☠️ CORRECTION, same afternoon: this does not price the target, and the repository already knew

The measurement above is sound. **The conclusion drawn from it was not**, and the
answer was in this repository before the window was spent.

`findings-log.md` (2026-08-19) records an A/B in which the APSS `XO shutdown
count` was deliberately moved **from 0 to 1952** over a 90-minute suspend leg —
so the application processor *can* be made to drop its XO vote on this device.
The result:

| | XO off 0× | XO off 1952× |
|---|---|---|
| sleep discharge slope | **−35.29 mV/h** | **−35.44 mV/h** |

**The same number to 0.4 %.** The apparent 74.4 vs 86.3 mA difference in that
capture comes entirely from the two legs' *awake* references disagreeing, not
from anything the sleeping phone did. The log's own verdict: *"making the RPM
shut the XO down 1952 times over a 90-minute suspend leg changed the measured
discharge rate by nothing at all"*, and *"do not spend more on `xo_sleep_off`"*.

**Why it bought nothing, also already recorded:** `vlow` and `vmin` read 0 in
every capture ever taken here, **including that leg**. The APSS master can drop
its XO vote all it likes; the RPM still never enters a low-power mode, because
some other master or some rail keeps voting. The oracle points the same way —
the vendor's APSS does not shut the XO down either, and the vendor phone still
idles far below this.

**So what today's window actually adds** is narrower than what was written above,
and worth keeping in that narrower form:

- the zero is now measured **across a real 601 s sleep**, with two moving masters
  in the same file as a control and PRONTO's 98.1 % fixing the tick rate — the
  earlier zeros came from windows in which the phone could not stay asleep;
- and it therefore **rules out** the reading that today's long sleeps might have
  changed the AP's behaviour. They did not.

**What it does not do is price the ≤50 mA row**, because the lever it names has
already been pulled and paid nothing. The binding constraint is the RPM never
reaching `vlow`/`vmin`, and the APSS XO vote is demonstrably not what holds that.

☠️ **How this was nearly published wrong.** Four hours before writing it I
promoted two rules into `/fp3-kernel-test` — *grep the captures for the field,
not the topic* and *read the closed leads before spending a window* — and then
did neither. `grep -rn 'XO shutdown count' captures/ leads/ findings-log.md`
would have surfaced the closure in one command. **A rule you wrote this morning
is not a rule you followed this afternoon.**
