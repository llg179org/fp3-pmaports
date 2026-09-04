# ☠️ The `-110/-6` is NOT caused by suspend. Measured 2026-09-04 12:31–12:32.

The operator repeated the "first touch does not work" case in `gnome-calculator`,
with the ledger running. It caught the failure **twice, with no suspend between
them and none since 12:25:57**.

## The two events

Anchor `kt 3650.04 = 12:32:53`, so:

```
kt 3234.27  = 12:25:57   PM: suspend exit          (the last resume; suspends -> 2)
kt 3558.08  = 12:31:21   Failed to read input event: -110
kt 3558.09  = 12:31:21   Failed to read input event: -6
kt 3605.70  = 12:32:09   Failed to read input event: -110
kt 3605.70  = 12:32:09   Failed to read input event: -6
```

`suspends` stayed at **2** across the whole session (12:29:51 → 12:32:30 in the
ledger). So:

- the first failure came **324 s (5.4 min) after** the resume, in the middle of
  ordinary use;
- the second came **47.6 s after the first**, with heavy touch traffic in
  between and no sleep of any kind.

**A resume cannot explain an event that happens twice, minutes apart, without
one.** `0314fee3ce35` (the `system-pc` affinity change) is therefore not the
cause of what we measured here.

☠️ **And the signature is Bert's exactly**: each `-110` (ETIMEDOUT) is followed
one millisecond later by a `-6` (ENXIO) — the "i2c -110/-6" of his mail, as a
pair, not as two separate observations.

## The pattern that does predict it: a short idle, not a suspend

From the ledger, the touch-interrupt counter either side of each failure:

```
12:31:06  irq=4144   ... last activity
12:31:22  irq=4147   err110=1   <<< -110      ~15 s gap, 3 stray interrupts
12:31:54  irq=4864   ... last activity
12:32:09  irq=4867   err110=2   <<< -110      ~15 s gap, 3 stray interrupts
```

Both failures are preceded by **~15 s of touch inactivity** and land on the
first real access after it. That is the same shape as the 11:22 event, where the
idle happened to be a suspend — a suspend is just a long idle.

☠️ n=2 for the gap length. It is a hypothesis with two supporting instances, not
a measured threshold. What it predicts and how to test it is below.

## The mechanism, from the driver source

`drivers/input/touchscreen/himax_hx83112b.c` at `5aafd59e553a`:

- `himax_bus_read()` performs **four** i2c transactions per event read: a burst
  enable, two address writes, then the data read. Any one of them failing aborts
  the whole read.
- `himax_handle_input()` logs the error and returns. `himax_irq_handler()` turns
  that into `IRQ_NONE`. **The touch event is dropped outright.**
- There is **no retry anywhere in the driver** — `grep -E 'retry'` finds nothing.
- `himax_suspend()`/`himax_resume()` only `disable_irq`/`enable_irq`. They do not
  touch the controller's power state and issue no wake-up transaction.

So whatever leaves the controller unresponsive for one transaction — its own
doze after a short idle being the obvious candidate — the driver has no second
chance, and the touch is simply lost. That *is* "the first touch does not work".

## Consequences

1. **The symptom is a driver defect, not a device-tree regression.** A retry on
   the first transfer after an idle is the shape of the fix, and this port has
   already written the same fix for the same class of bug on the same board:
   `media: i2c: ak7375: retry the first transfer of a resume` in the
   `ak7375-pm` series.
2. **The hold on `0314fee3ce35` should stay for now anyway** — this measures our
   device, not Bert's, and "reverting fixed it for him" is still unexplained. But
   the reason for the hold has changed: it is no longer "we suspect this commit",
   it is "we cannot yet explain his observation".
3. **The planned A/B is the wrong experiment.** Deploying the reverted dtb would
   have compared two arms of a fault that does not depend on the variable being
   changed. Had the earlier single-trial-per-arm plan been run, it would have
   produced a clean arm A and been read as "the revert fixes it".

## Next, and it is cheap

Test the gap hypothesis directly, since it needs only touches: touch, wait a
measured interval (5 s, 10 s, 20 s, 30 s), touch once, and read whether `err110`
moved. The ledger already records everything needed; only the waiting is manual.
That yields the idle threshold and the per-attempt failure rate — the number the
whole experiment lacked.

## Instrument note

The ledger's `err110` field is now proven **in situ**: it fired on two real
events, not only on a synthetic line. The caveat recorded when it was built is
discharged.
