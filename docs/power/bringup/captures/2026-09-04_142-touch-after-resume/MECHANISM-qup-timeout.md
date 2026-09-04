# The 15-second dead screen is the QUP i2c transfer timeout. Measured 2026-09-04.

## The observation that forced it

The operator reported, with a clock time: *"from 12:48:00 there was a 15-second
outage"*. The ledger for that window:

```
12:47:59  irq=13227  err110=5  ev=2104     last sample before the hole
   (16 s with NO ledger line at all - the counters did not move)
12:48:15  irq=13256  err110=6  ev=2125     <<< -110
```

The ledger samples at 1 Hz and writes on change, and was `active` throughout, so
no line means **no touch interrupt arrived for 16 seconds** — while the panel was
being touched. Immediately before the hole the rate was 20–80 interrupts per
second.

☠️ **This inverted the previous reading.** The same ~15 s holes had been recorded
as *idle* — the operator not touching, the controller dozing, the first access
after it failing. One timed report turned "nothing was happening" into "the panel
was dead while being used". The ledger alone could never have distinguished
those two: a hole looks identical either way.

## Six of six, and the length is not random

Every gap in the ledger, and which end in a `-110`:

| gap | length | ends with -110 |
|---|---|---|
| 12:31:06 → 12:31:22 | 16 s | yes |
| 12:31:54 → 12:32:09 | 15 s | yes |
| 12:42:11 → 12:42:27 | 16 s | yes |
| 12:43:13 → 12:43:29 | 16 s | yes |
| 12:47:17 → 12:47:32 | 15 s | yes |
| 12:47:59 → 12:48:15 | 16 s | yes |
| 30 other gaps, 3 s to 2664 s | — | **no** |

All six `-110` events end a 15–16 s hole. Holes of 18 s, 62 s, 66 s, 234 s,
418 s and 2664 s produce nothing. So the stall is a distinct phenomenon with a
sharp, repeatable duration — the signature of a timeout, not of idleness.

## The number comes out of the driver exactly

The touchscreen is at `2-0048` on `78b7000.i2c`, a QUP adapter driven by
`drivers/i2c/busses/i2c-qup.c` — **the same driver our `i2c-qup-pinctrl` series
patches**. Its per-transfer timeout:

```c
#define TOUT_MIN 2                       /* seconds */
#define MX_TX_RX_LEN      SZ_64K
#define MX_DMA_TX_RX_LEN  (2 * MX_TX_RX_LEN)      /* 131072 */

one_bit_t  = (USEC_PER_SEC / clk_freq) + 1;
one_byte_t = one_bit_t * 9;
qup->xfer_timeout = TOUT_MIN * HZ + usecs_to_jiffies(MX_DMA_TX_RX_LEN * one_byte_t);
```

Verified **on the live device**, not inferred from the source DTS: the running
device tree has no `clock-frequency` under `soc@0/i2c@78b7000`, so the driver
takes `DEFAULT_CLK_FREQ = I2C_MAX_STANDARD_MODE_FREQ` = 100 kHz.

```
one_bit_t  = 1000000/100000 + 1 = 11 us
one_byte_t = 99 us
xfer_timeout = 2 s + 131072 x 99 us = 2 + 12.976 = 14.98 s
```

**14.98 s against six measured stalls of 15–16 s** (1 Hz ledger resolution, so
±1 s). At 400 kHz the same formula gives 5.54 s.

## The mechanism, end to end

1. One i2c transaction to the touchscreen hangs. *Why it hangs is not yet known
   — see below.*
2. `qup_i2c_wait_for_complete()` / the DMA path call
   `wait_for_completion_timeout(&qup->xfer, qup->xfer_timeout)` and wait the
   **full 14.98 s**.
3. That runs in the touchscreen's threaded IRQ handler, so no touch is processed
   for the whole 15 s: the panel is completely dead, which is exactly the
   reported symptom.
4. It returns `-ETIMEDOUT` (**-110**); the next transaction of the same
   `himax_bus_read()` returns `-ENXIO` (**-6**). That is Bert Karwatzki's
   "i2c -110/-6" pair.
5. `himax_handle_input()` logs and drops the event — the driver has no retry —
   and normal operation resumes.

## The defect worth sending

`xfer_timeout` is computed once at probe from **`MX_DMA_TX_RX_LEN`, the largest
transfer the controller could ever do (128 KB)**, and then applied to *every*
transfer. A 12-byte touch event read that hangs therefore blocks for fifteen
seconds. The timeout should scale with the actual message length.

That is a generic i2c-qup bug, not an FP3 one: any 100 kHz device on a QUP bus
whose transaction hangs freezes its driver for 15 s. It goes to the same tree and
maintainer as `i2c-qup-pinctrl` (Andi Shyti, i2c-host).

A DTS `clock-frequency = <400000>` would shorten the stall to 5.5 s. That is a
mitigation, not a fix, and it changes the bus speed for a reason unrelated to bus
speed — so it is not the patch to send.

## ☠️ What is NOT explained

**Why the transaction hangs in the first place.** The timeout arithmetic explains
the *duration* of the dead screen and nothing about the *trigger*. Six events in
~75 minutes of use, no suspend involved in any of them.

Note the standing suspicion this reopens: `i2c-qup-pinctrl` exists because this
controller's pads are left in the wrong state across runtime PM, and the fix
selects the sleep/default pinctrl states. Whether an incompletely restored pad
state is what makes a transaction hang here has **not** been tested, and the
series is currently cut against v7.3-rc1 where the resume path was rewritten.
That is a hypothesis with a plausible mechanism and no measurement behind it.

## Retracted on the way

- ☠️ *"Each -110 follows ~15 s of touch inactivity"* — wrong. The operator was
  touching throughout; the hole **is** the fault, not its precondition.
- ☠️ *"The checksum path drops events silently"* — wrong. `himax_verify_checksum()`
  logs `dev_err("Wrong event checksum")`; the claim came from reading the call
  site's comment instead of the function. Measured: **zero** checksum errors on
  the device.
- ☠️ *"3 errors per 6313 interrupts"* — a misleading denominator. The event
  belongs to stalls, and there it is six for six.
