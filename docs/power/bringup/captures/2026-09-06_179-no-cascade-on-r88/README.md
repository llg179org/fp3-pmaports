# #179 — a touch fault no longer cascades, measured over 184 active minutes

**2026-09-06**, pmOS `linux-fp3-7.1.3-r88`, `uname -v #89-fp3`, source commit
`6113869dcc3d`. Sampler log beside this page as `r88.tsv`; analysed with
`touch-exposure.py` from
[`../2026-09-05_178-retry-rate-on-r83/`](../2026-09-05_178-retry-rate-on-r83/),
which groups by `boot_id` before differencing and refuses a verdict below 36
active minutes.

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, whose use of the phone is the measurement.

## The exposure, which is what makes the result mean anything

| boot | window | **active min** | interrupts | −110 | −6 | −5 | qup timeout / cleared / held |
|---|---|---:|---:|---:|---:|---:|---|
| `1fed245f` | 11:58–14:30 | **98** | 94 548 | 0 | 0 | 0 | 0 / 0 / 0 |
| `8408f76d` | 14:34–15:06 | 0 | 0 | 0 | 0 | 0 | 0 / 0 / 0 |
| `191c53a4` | 15:58–16:38 | 0 | 0 | 0 | 0 | 0 | 0 / 0 / 0 |
| `a935562a` | 16:52–17:28 | 0 | 0 | 0 | 0 | 0 | 0 / 0 / 0 |
| `6ff8e254` | 17:46–22:54 | **86** | 90 627 | 0 | 0 | 0 | **1 / 1 / 0** |

**184 active minutes** across the two boots that carry any exposure — five times
the 36-minute floor the task sets. The three empty boots say nothing and are
listed so they cannot later be mistaken for clean runs.

## The signature, which is the actual criterion

#179 judges the **shape** of a fault, not its count: on r82 every `-110` was
followed within the same second by a `-6`, and one wedge needed a driver rebind.
Since the r88 boot (`uptime 18556 s`, 5 h 09):

```
[ 4187.839699] i2c_qup 78b7000.i2c: transfer to 0x48 timed out, bus active,
               master is us, SDA 1 SCL 0
               (I2C_STATUS 0x0411a700 STATE 0x0000001d OPER 0x00000010 ERR 0x00000000)
[ 4187.841826] i2c_qup 78b7000.i2c: bus cleared after 1 attempt(s)
```

| | |
|---|---:|
| `i2c_qup` timeouts | **1** |
| recovered by the hardware bus-clear, 2 ms later | **1** |
| himax `-110` | **0** |
| `-6` — the second half of the cascade | **0** |
| `-EIO` / `-5` | **0** |
| **`Disabling IRQ`** | **0** |
| driver rebinds needed | **0** |

The panel kept working through and after it — the same boot recorded thousands
of taps in `fp3-taptest`, all delivered.

☠️ The other two "timed out" lines in the log are `qcom,slim-ngd` (SLIMbus, the
audio path) and have nothing to do with this; counting them would have inflated
the number sevenfold, and the first count taken here did exactly that before it
was split by subsystem.

## ☠️ What this does NOT settle

- **The fault rate is not measured, and cannot be by this run.** #178 states the
  problem in its own note: with the driver retry in place a transient failure
  produces **no log line at all**, so "zero errors" is ambiguous between "no
  faults" and "faults absorbed". Distinguishing them needs a counter the driver
  does not have. `touch-exposure.py` says the same in its own verdict line —
  *"clean, but only rules out 'worse than r82'."*
- So this closes **#179** (the cascade), not **#178** (the rate).
- The supply fix is not judged here either; the unbind reproducer cannot see it,
  which is why the task forbids using it for this.
