# #179 — the bus-clear does not rescue an unpowered slave, and the diagnostic works

2026-09-05 21:11–21:14. Kernel r84 (`#85-fp3`, `_commit=896aac5ad103`), which adds
the QUP `I2C_STATUS` decode on timeout and the hardware bus-clear.

## The instrument, and why it was used despite an earlier note saying not to

`../2026-09-04_142-touch-after-resume/142-trigger.sh`, unchanged, `PER=3 BLANK=12`,
plus `echo "file i2c-qup.c +p" > /sys/kernel/debug/dynamic_debug/control` so the
`bus cleared after` line is visible.

☠️ **#179's own note said this script "CANNOT judge this and must not be used for
it". That was too broad and is corrected here.** The script is blind to the
*supply* fix and to the *himax retry*, because it unbinds the driver and so drops
the regulator votes and never calls `himax_read_events`. It is **not** blind to
the i2c-qup timeout path, which is exactly where the bus-clear lives — the stall
it provokes goes through `qup_i2c_wait_for_complete` like any other.

## Result

```
round 1 OFF  2.0527 s errno 110  >>> STALL      round 1 ON  0.0010 s errno 6  ok
round 2 OFF  2.0425 s errno 110  >>> STALL      round 2 ON  0.0010 s errno 6  ok
round 3 OFF  2.0367 s errno 110  >>> STALL      round 3 ON  0.0006 s errno 6  ok
screen OFF: 3/3 stalled     screen ON: 0/3
```

and, three times, in the kernel log:

```
i2c_qup 78b7000.i2c: transfer to 0x50 timed out, bus active, master is us,
                     SDA 0 SCL 0 (I2C_STATUS 0x00138700)
i2c_qup 78b7000.i2c: bus still held after 10 bus-clear attempts
```

## What it establishes

**The diagnostic works, and independently confirms the bit assignment.**
`0x00138700` is exactly the value captured by hand with `142-qupreg.py` on
2026-09-04, and the driver now decodes it unaided: SDA and SCL both low, bus
active, master is us. The pad readback that day said the same. Two instruments,
built from different sources, agreeing on the same register.

☠️ **The bus-clear FAILED, 3 of 3.** The hypothesis that writing
`QUP_I2C_MASTER_BUS_CLR` would end this stall is **disproven in this regime**.

## Why it failed, and why that was foreseeable

Two independent reasons, and they agree:

1. **The vendor's own gate excludes this case.** `i2c_msm_qup_slv_holds_bus()`
   requires `!(status & QUP_BUS_MASTER)` — recovery runs only when we are *not*
   the master. Our status says `master is us`. The downstream driver would not
   have run its bus-clear here either, so this is not a case where mainline is
   missing something the vendor has.
2. **The slave has no power.** This regime is screen-off *and* driver-unbound, so
   nothing votes for `pm8953_l6` and the touch half of the panel is unsupplied —
   the mechanism in `../2026-09-04_142-touch-after-resume/ROOTCAUSE-the-panel-owns-the-rail.md`.
   An unpowered chip clamps the lines through its ESD path and no number of clock
   pulses persuades it to let go. Bus-clear can only help a *powered* slave stuck
   mid-byte.

## ☠️ What this does NOT say, and it is the important half

It says **nothing** about whether the bus-clear helps the fault the operator
actually hits: driver bound, screen on, panel powered, mid-use. This reproducer
cannot reach that regime — its only timeout-producing combination is the
unpowered one, and its other two arms NACK in under a millisecond, leaving
nothing to recover.

So the change is **not** shown useless. It is shown not to rescue a dead chip,
which nothing could. Whether it ends the field cascade is still open and still
needs 36 active minutes of ordinary use.

## Next, concretely — done, and deliberately NOT flashed tonight

The failure line did not say *which* of the three exit conditions (`BUS_CLR`
readback, `BUS_ACTIVE`, `SDA`) never cleared. `a268f0d4ccdc` makes it say so, and
is pushed on all three branches.

☠️ **The phone was left on r84 and not rebuilt for it.** r84 already prints the
raw `I2C_STATUS` on every timeout, and all three bits are in that word — so the
new line saves a hand decode, it does not add information the phone cannot
currently give. Against that, a build and flash costs ~30 minutes and restarts
the exposure window that #179 is waiting for the operator to fill. Convenience
does not outrank the measurement.

It rides along on the next kernel build for another reason.
