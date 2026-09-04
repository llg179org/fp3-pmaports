# #156: nothing re-arms the stall — not a periodic wakeup, not a long idle

2026-09-04, 21:25-23:32. Raw log: `wd-ab-250-per-arm.txt`, script `142-wd.sh`.

## What was asked, and what ran

The task asked for the idle held at 15 s with only `fp3-usbnet-watchdog.timer`
varied, ~500 probes per arm. **250 per arm ran, not 500** - ten interleaved
blocks of 50, which is half the requested size. The estimate given when it was
launched ("~4.2 h") was also wrong by a factor of two; it took 2 h 7 min.

```
WD-ON   0 / 250        WD-OFF  0 / 250        idle 15 s, screen off
arming probe (discarded): 15.0759 s errno 110
```

## What it settles, and what it cannot

**Settled: the fault does not recur.** At the rate measured in this exact regime
earlier the same day (1/60 = 1.7 % per probe), 500 probes expect 8.3 stalls;
observing none has probability 0.02 %. Rule of three puts the post-arming rate
below **0.60 %** per probe against 1.7 % before it. Pooled with every other
screen-off run today, after the arming probe: **0 stalls in 26 658 probes**,
which is below 0.0113 %.

**Not settled: which arm is better.** 0 against 0 cannot rank them. The finding
is that *neither* produces events, which is a statement about the fault, not
about the watchdog.

## What it does to gate 1 of the write-up

Gate 1 said the fault needs an idle of ~10 s or more, and the page then recorded
that this was confounded with "a 30 s watchdog tick fell inside the idle window",
because in those arms the two were the same variable. **This run dissolves both
candidates rather than choosing between them:** every one of the 500 probes had
a 15 s idle, half of them with the watchdog ticking and half without, and none
stalled.

So neither the idle length nor the periodic wakeup is the trigger. What separates
a stalling probe from a non-stalling one is whether it is the **first transaction
after an arming event** - the panel releasing pm8953_l6 when the display goes
down, or an unbind. The arming probe of this very run hung for 15.08 s, one
minute before 500 probes in the same conditions hung for none.

That is the account `ROOTCAUSE-the-panel-owns-the-rail.md` gives, and this run is
its sharpest confirmation to date - the fault was armed once, fired once, and did
not come back for two hours.

## Why the historical hits are consistent with this

The earlier "1/60 at 15 s idle" and "1/20 at 10-60 s" campaigns each began with
their own unbind, so each carried one arming event. Their single hits landed at
probe 3 and at round 3 rather than at probe 0, so the fault can fire a few probes
after the arming rather than exactly on the first - but once, not repeatedly.

## ☠️ What this does NOT show

It says nothing about the driver-bound case, which is the operator's actual
fault. Every probe here ran with the touch driver unbound. And it does not test
the fix: that is `142-trigger.sh` on a kernel carrying the #155 commits, still
waiting on a flash.
