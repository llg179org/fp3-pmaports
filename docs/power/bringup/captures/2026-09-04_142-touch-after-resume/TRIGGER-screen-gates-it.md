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

## ☠️ The measurements that were wasted, and why

Five automated campaigns produced 0 stalls in 52 688 transactions and each null
was a *predicted* null:

* probing at 0.33-2 transactions/s against a real-use rate of ~50/s;
* probing at 44/s, which keeps a CPU spinning and may prevent the very idle
  transition under suspicion;
* **every one of them beginning with an unbind**, which may reset the state
  being measured - raised by the operator, and unanswered;
* and all of them counting the wrong denominator. Time, then transactions, then
  resumes were each fitted in turn; the one that separates cleanly is the
  **screen cycle**, which was not measured until the operator named it.

☠️ And the fingerprint that misled all day: the 15 s duration. It is the QUP
`xfer_timeout` constant (2 s + 131072 x 99 us = 14.98 s), identical for every
hang whatever the cause. "Same 15 s" was repeatedly taken as evidence of the
same mechanism. It is evidence of nothing.

## Where this points

`media: i2c: ak7375: retry the first transfer of a resume` on this same phone:
*"the first transfer after the supplies come up can time out ... the resume
returns -110"*. Same signature, different controller, already diagnosed and
fixed once here - by retrying. `himax_hx83112b` retries nowhere, so one -110
costs a dropped touch and, because of the timeout constant, 15 s of dead panel.

The i2c-qup pinctrl fix (`1380c70af7b3`) is already in the running kernel and is
working correctly here - the pinmux dumps above are what it produces.
