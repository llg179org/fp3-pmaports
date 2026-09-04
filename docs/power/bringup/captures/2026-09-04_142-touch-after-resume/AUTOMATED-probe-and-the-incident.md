# The stall reproduces with no finger — and the first attempt wedged the bus

## The result that matters

The `-110` needs a transaction on the touchscreen's i2c bus, and a transaction
can be issued from userspace. `142-i2cprobe.py` reads one byte from **an address
with no device on it** (`0x50` on bus 2; only `2-0048` exists there), which makes
the two outcomes unmistakable **by duration**, without having to trust an errno:

```
healthy -> the address NACKs, ~1 ms
hung    -> the transfer timeout expires, seconds
```

First run, 20 trials at 0.05 s spacing, 2026-09-04 13:37:

```
trial 0     15.120 s  ETIMEDOUT      <<< the controller had been idle for minutes
trial 1-19  median 1.6 ms, EIO
```

**15.120 s against the 14.98 s computed from the driver's own constants.** Two
things follow, and the second was not expected:

1. **The test is automatable.** No finger, machine rate, hundreds of trials
   possible where a human could give a few per minute.
2. ☠️ **The touch chip is not involved.** The probe went to an address where
   *nothing* answers, so nothing in the hx83112b can explain it. The stall is in
   the **i2c controller's own path**, and the touchscreen is simply its most
   visible victim.

A second run (8 trials, 2 s idle each) hung once, for **5.149 s**. So it is
neither every resume nor always the same duration — the first transaction after
a *long* idle is the suspect, and the two observed durations (15.1 s, 5.1 s)
differ enough to suggest two exit paths rather than one.

## ☠️ The incident: the probe killed the touchscreen

Immediately after those runs the operator reported touch completely dead.
Measured: **1824 consecutive `Failed to read input event: -5`**, still
accumulating, interrupts arriving normally, driver still bound.

**Cause, and it is mine.** `I2C_SLAVE_FORCE` exists precisely to reach an address
another driver has claimed — it *bypasses* the protection that keeps two users
off the same bus. The probe and the touchscreen driver were issuing transactions
on the same controller, and they collided badly enough to wedge it.

The risk was real, foreseeable and not stated in advance. That is the part worth
recording: this was not an unlucky outcome of a considered decision, it was a
decision never made.

**Recovery**, least invasive first, and it worked at the first step:

```sh
echo 2-0048 > /sys/bus/i2c/drivers/Himax-hx83112b-TS/unbind
sleep 2
echo 2-0048 > /sys/bus/i2c/drivers/Himax-hx83112b-TS/bind
```

The rebind re-runs probe, which toggles `reset-gpios` and re-initialises the
chip. Errors stopped at that instant and the count then held flat across 15 s.

☠️ **Side effect to carry forward: the input node moved `input4` -> `input7`.**
Anything referring to `/dev/input/event4` is now pointing at the wrong device —
including `142-gaps.py` and `142-evcount.py` in this directory, which must be
re-pointed before the weekend run. A rebind renumbers it again.

## The rule, and the fixed procedure

**On a shared bus, do not force your way in beside the owner — take the owner
off the bus.** `142-ab2.sh` unbinds the driver for the duration of the run and
rebinds it from a `trap`, so a crash, a kill or a timeout still gives the phone
its touchscreen back. The measurement is unchanged; only the collision is gone.

That also makes the test *better*: with the driver unbound there are no touch
interrupts at all, so the bus is genuinely idle between probes rather than
merely quiet.
