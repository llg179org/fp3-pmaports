# What the controller sees during the hang

2026-09-04 19:13. The question the write-up had been ending on - does the chip
hold the bus, or does the controller never start - answered by reading the QUP
registers and the two i2c pads while a transfer was hung.

Instrument: `142-qupreg.py`, driven by `142-qupreg.sh`. Offsets are from our own
`drivers/i2c/busses/i2c-qup.c` (`QUP_STATE` 0x004, `QUP_OPERATIONAL` 0x018,
`QUP_ERROR_FLAGS` 0x01c, `QUP_HW_VERSION` 0x030, `QUP_I2C_STATUS` 0x404) and the
pad readback from `drivers/pinctrl/qcom/pinctrl-msm8953.c`
(`io_reg = 0x4 + 0x1000 * id`, `in_bit = 0`, TLMM base 0x01000000). `BUS_ACTIVE`
is BIT(8) in our driver; `BUS_MASTER` is BIT(9), which our driver does not
define - that name comes from the downstream header `i2c-msm-v2.h:166-167`.

## The capture

```
--- ARM HEALTHY (screen On, driver bound)
pad gate (bus idle, must be 1/1): gpio10=1 gpio11=1
  probe 0x50: 0.0003 s errno 6
[  0.001] STATE=0x01c OPER=0x0000c0[OUT_FULL,NO_INPUT] ERR=0x000000
          I2C_STATUS=0x0c000000[-]                     gpio10=1 gpio11=1

--- ARM HUNG (screen Off, driver unbound)
pad gate (bus idle, must be 1/1): gpio10=1 gpio11=1     <- AFTER the unbind, BEFORE the probe
[  0.001] STATE=0x01d OPER=0x000010[OUT_NOT_EMPTY] ERR=0x000000
          I2C_STATUS=0x00138700[BUS_ACTIVE,BUS_MASTER]  gpio10=0 gpio11=0
  probe 0x50: 15.0057 s errno 110
[ 15.007] STATE=0x01c OPER=0x0000c0[OUT_FULL,NO_INPUT] ERR=0x000000
          I2C_STATUS=0x0c000000[-]                     gpio10=0 gpio11=0
samples: 6197
```

## What it settles

**The controller starts.** `BUS_ACTIVE` and `BUS_MASTER` are both set, `QUP_STATE`
is 0x01d - `& QUP_STATE_MASK` = 1 = `QUP_RUN_STATE`, with `QUP_STATE_VALID` -
against 0x01c (`QUP_RESET_STATE`) at rest. The engine is running and owns the
bus. "The controller never starts" is eliminated.

**Both i2c lines are held low for the whole 15 s.** And they were **high one
second earlier**, in the same conditions - unbound, screen off - which the pad
gate recorded. So the lines are not resting low: starting the transfer pulls
them down and they never come back.

**Nothing moves.** 6197 samples across 15 s produced exactly two distinct
states: the hung one at t+0.001 and the post-timeout one at t+15.007. The
sampler prints only on change. The hang is not slow, it is frozen.

**There is no error.** `QUP_ERROR_FLAGS` is 0 throughout and
`I2C_STATUS & I2C_STATUS_ERROR_MASK` (0x38000FC) is 0: no NACK, no over- or
under-run. From the controller's point of view nothing went wrong; nothing
happened at all, until its own timeout fired.

**A byte is stuck in the output FIFO.** `QUP_OPERATIONAL = 0x10` is
`QUP_OUT_NOT_EMPTY`: the controller has data queued that it cannot put on the
wire.

Read together: master in RUN state, bus owned, data queued, no error, both wires
grounded, static for fifteen seconds. That is a bus held down by something other
than this controller - the picture an unpowered or unresponsive slave clamping
the lines produces.

## Limits, stated

* **Which pin is SDA and which SCL was not verified.** It does not matter here
  because both are low, but do not quote gpio10 or gpio11 as one or the other.
* **The residual bits of `0x00138700` are undecoded.** Bits 10, 15, 16, 17 and 20
  are set and neither driver names them. The downstream header defines
  `I2C_CLK_FORCED_LOW_STATE = 5` but never uses it, so the field it belongs to is
  unknown. The raw value is recorded so it can be decoded later.
* **This is still the unbind reproducer**, not the operator's fault. See
  `TRIGGER-screen-gates-it.md`.

## Both instrument gates passed, on known answers

`QUP_HW_VERSION = 0x20070000` - not 0, not all-ones, not uniform across offsets,
so the block was clocked and the numbers are real. And the pads read **1/1 with
the bus idle**, which is what a pulled-up i2c bus must read; had they not, the
pad readback would have been wrong and nothing it said during the hang would
have counted. Every sample is preceded by a `runtime_status` read and the loop
stops as soon as the controller is no longer active, so no clock-gated register
is ever read.
