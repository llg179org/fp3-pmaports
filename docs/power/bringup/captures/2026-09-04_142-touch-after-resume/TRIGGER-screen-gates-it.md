# A deterministic trigger, and what it is NOT

2026-09-04, late. Written after a day in which every automated attempt to
provoke the fault produced nothing.

## The reproducer

`142-trigger.sh` — unbind the touch driver, issue one i2c transaction, and the
screen state decides the outcome. Interleaved arms, five each, no reboot:

```
round 1 OFF  15.0704 s errno 110  STALL      round 1 ON  0.0006 s errno 6  ok
round 2 OFF  15.0692 s errno 110  STALL      round 2 ON  0.0004 s errno 6  ok
round 3 OFF  15.0899 s errno 110  STALL      round 3 ON  0.0003 s errno 6  ok
round 4 OFF  15.0465 s errno 110  STALL      round 4 ON  0.0006 s errno 6  ok
round 5 OFF  15.1061 s errno 110  STALL      round 5 ON  0.0006 s errno 6  ok

screen OFF: 5/5      screen ON: 0/5      (p ~ 0.004; 7/7 vs 0/7 including reruns)
```

Both halves are required. With the driver **bound** and the screen off, twenty
screen off/on cycles with the same probe gave **0 stalls** (`142-repro.sh`, six
cycles logged before it was stopped, plus the gate run). Unbind alone with the
screen on gives 0/7. Only unbind **and** screen-off together stall.

## What it is not — do not read this as "#142 reproduced"

The operator's fault happens with the driver **bound** and the reset line held.
This reproducer needs the driver unbound, which never happens in real use. What
it establishes is narrower and still worth having:

* the touch chip **can** hold the bus long enough to burn the full QUP
  `xfer_timeout`, and
* whether it does is **gated by the screen**, deterministically.

## Everything that was eliminated, by measurement, not by argument

| candidate | measured | verdict |
|---|---|---|
| shared regulator dropping | `regulator_summary`, screen on vs off | `l6` unchanged, `normal 1800mV` both |
| i2c controller runtime PM | `78b7000.i2c/power/runtime_status` | `suspended` in **both** arms before the probe |
| pinctrl sleep/default state | `pinmux-pins` pin 10/11 | identical: `gpio` before, `blsp_i2c3` after, both arms |
| touchscreen reset GPIO | `pinmux-pins` pin 64 | `GPIO ...:592` -> `UNCLAIMED` on unbind, identically in both arms |

Nothing Linux can see differs between a stalling and a non-stalling run. The
difference reaches the chip through the display module, where the kernel has no
instrument. The DT says as much: `touchscreen@48` declares **no supply at all**.

## ☠️ The correction: the probe WAS a valid instrument

An earlier version of this page concluded that an unused-address probe "does not
sample the same population" as the driver's reads, on the strength of 0 stalls in
52 688 transactions. **That conclusion was wrong**, and the same day's data says
so once it is sorted by the idle time *before* each probe rather than by rate:

```
idle before probe   probes  stalls    rate
      0.02 s (44/s)  52688       0    0.00 %
      0.5 s           1392       0    0.00 %
      2 s              300       0    0.00 %
      3 s               40       0    0.00 %
     10-60 s            20       1    5.00 %
     15 s               60       1    1.67 %
     45 s                3       1   33.3  %
```

There is a threshold between 3 s and 10 s, and it is the strongest effect
measured all day - not a marginal one. Had the 52 688 fast probes carried the
15 s rate, they would have produced ~878 stalls.

What happened is a self-inflicted wound worth recording. The probe rate was
raised through the afternoon because the operator ledger appeared to show the
fault scaling with transactions; raising the rate necessarily dropped the idle
below the threshold that actually governs it. The null that produced was then
read as "the instrument is invalid" instead of "the instrument was moved out of
its working range". The page had even flagged the risk in advance - *"the
interesting range is below one second, and nothing has been measured there"* -
and the sub-second measurement was taken as a verdict on the instrument rather
than as the answer to that question.

The screen A/B above is unaffected: both its arms used a 12 s blank, i.e. the
same idle, above the threshold. Its 5/5 against 0/5 is a screen effect measured
at constant idle.

## Three gates, each measured

1. **idle >= ~10 s** before the transaction (threshold between 3 s and 10 s)
2. **screen off** (5/5 against 0/5 at an identical 12 s idle)
3. **not a fresh boot** - the weakest leg, one observation each way:
   `armB-clean-boot-trial2.txt` is a clean boot with a real suspend/resume on
   the suspect `0x42000353` and ~513 post-resume touch interrupts, and **no
   -110**; `armB-first-touch-after-resume.txt` is a boot carrying **187
   suspends**, with one -110 landing exactly on the first touch after a resume.

Gate 3 also explains the afternoon: the phone was rebooted five times, so every
later run was on a young boot.

☠️ And the fingerprint that misled all day: the 15 s duration. It is the QUP
`xfer_timeout` constant (2 s + 131072 x 99 us = 14.98 s), identical for every
hang whatever the cause. "Same 15 s" was repeatedly taken as evidence that two
events were one. It is evidence of nothing.

## Where this points

`media: i2c: ak7375: retry the first transfer of a resume` on this same phone:
*"the first transfer after the supplies come up can time out ... the resume
returns -110"*. Same signature, different controller, already diagnosed and
fixed once here - by retrying. `himax_hx83112b` retries nowhere, so one -110
costs a dropped touch and, because of the timeout constant, 15 s of dead panel.

The i2c-qup pinctrl fix (`1380c70af7b3`) is already in the running kernel and is
working correctly here - the pinmux dumps above are what it produces.
