# The operator's fault, caught with the driver bound: the slave stretches the clock

2026-09-06 06:36:55, kernel r85 (`#86-fp3`, `9c2d03f147c8`). The first capture of
the fault that actually bothers the operator, as opposed to the one the unbind
reproducer makes.

```
i2c_qup 78b7000.i2c: transfer to 0x48 timed out, bus active, master is us,
                     SDA 1 SCL 0 (I2C_STATUS 0x0411a700)
i2c_qup 78b7000.i2c: bus still held after 10 bus-clear attempts: clear not
                     accepted, bus still active, (I2C_STATUS 0x04006300, BUS_CLR 0x1)
```

Full analysis in [`../../../touch/142-i2c-stall.md` section 10](../../../touch/142-i2c-stall.md).
The short version, because it changes what we thought:

* **0x48** is the touch controller's own address - this is the driver's read in
  ordinary use, not the synthetic 0x50 probe.
* **`SDA 1 SCL 0`** is a powered slave stretching the clock. The reproducer's
  hang reads `SDA 0 SCL 0`, an unpowered part clamping both lines. **Two
  mechanisms behind one duration**, which is why the supply fix could be correct
  and the operator's fault continue.
* **`BUS_CLR 0x1`** after ten attempts means the block never accepted the clear.
  The earlier reading - "clocking cannot revive a dead chip" - is true of the
  reproducer and wrong here. Fixed in `af2628ca18d2`: reset the core to idle and
  bring it back up first, as the vendor driver does.
* `himax_hx83112b` logged **nothing**: its retry succeeded on a later attempt, so
  the panel never wedged - but the tap was lost anyway. The input log shows
  `PRESS #7` held **9 ms** against neighbours at 89-119 ms. **The retry protects
  the panel, not the touch.**

## Eliminated the same morning, automatically

`fp3-resume-probe.sh`, no human involved: blank, unblank, then probe the bus at
0, 1, 3 and 10 s after it returns, interleaved with a no-blank control.

```
after resume: 0 / 8 probes stalled       control: 0 / 8
```

all sub-millisecond. ☠️ Two limits, stated because the table hides them: `0/8`
bounds the rate only at ~31 % (rule of three), and the probe measures the **bus**
rather than touch **sensing** - a controller that is alive but silent leaves the
bus spotless.

## ☠️ The probe broke the other instrument

Unbinding the driver destroys the input node, which kills `fp3-touch-gaps`;
systemd restarted it **12 times** between 06:31 and 06:34, resetting its counters
each time. Stop the logger, or skip the unbind, before running the probe. An
instrument that quietly disables another one is worse than no instrument.
