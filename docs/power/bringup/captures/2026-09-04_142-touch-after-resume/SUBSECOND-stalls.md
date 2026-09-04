# The sub-second stalls are real. Measured 2026-09-04 13:10, at millisecond resolution.

## First, a retraction that came before the measurement

The operator reported second-long stalls, often before a 15 s one. The 1 Hz
ledger appeared to confirm it: nine "2 second gaps", four of them immediately
before a long stall. ☠️ **That confirmation was false and the evidence was my
own instrument.**

One ledger iteration costs ~60 ms (`dmesg | grep -c` alone is 23 ms of it)
against a `sleep 1`, so the period is ~1.06 s and the wall-clock stamp steps by
2 seconds roughly every seventeenth sample, with no sample missing at all. The
discriminator I had not looked at is the **interrupt rate inside the gap**:

```
the "2 s gaps":   12-33 interrupts/s   against a surrounding 20-80/s  -> normal, drift
the 15 s stalls:  0-3.5 interrupts/s   against the same 20-80/s       -> real
```

Every one of the short "confirmations" ran at full rate. The pattern I presented
as supporting the operator's hypothesis was the cadence of my own sampler. It was
also the answer they were hoping for, which is the half that should have made me
check it first.

## The right instrument

`142-gaps.py`: reads `/dev/input/event4` and uses the **kernel's own timestamp**
on each event, so there is no sampling and no drift. It logs the interval
between consecutive `SYN_REPORT` frames, and — the part that matters as much as
the resolution — **only while `BTN_TOUCH == 1`**. Without that condition, "the
operator paused" and "the panel stalled under a finger" are the same hole in the
log, which is exactly the confusion that cost the 15 s reading earlier in the day.

Validated before use, not after: `BTN_TOUCH` (0x14a = 330) is confirmed present
in the device's own `capabilities/key` (`400 0 0 0 0 0`, bit 330), because a
logger conditioned on a capability the device does not have would stay silent and
be indistinguishable from "no stalls found".

## What it found, in the first minute

701 frames, five gaps of 100 ms or more with the finger on the glass:

```
13:10:38.181     100.8 ms
13:10:46.214     126.9 ms
13:10:46.999     429.5 ms
13:11:03.214     125.7 ms
13:11:24.114     142.4 ms
```

Normal inter-frame spacing at 20-80 frames/s is 12-50 ms, so 429 ms is an order
of magnitude out. About one stall per 140 frames.

☠️ **And the `-110` counter did not move once** during any of them: it was 11
before and 11 after. So the sub-second stalls carry **no i2c error at all**,
while every 15 s stall carries one.

## Two phenomena, not yet one mechanism

| | sub-second | 15 second |
|---|---|---|
| duration | 100-430 ms | 14.98 s, six of six then eleven |
| frequency | ~1 per 140 frames | 11 in ~90 min |
| `-110/-6` | **never** | **always** |
| explained by | nothing yet | the QUP `xfer_timeout` exactly |

Whether they are the same fault at two severities — the operator's hypothesis,
that shorts precede longs — is now **testable and not yet tested**: it needs a
15 s stall to occur while this logger runs, so the seconds before it can be read.
That is what is being watched for.

The honest state of that hypothesis: the evidence I offered for it was withdrawn,
and no replacement evidence exists yet. It is a good hypothesis from the person
using the device, and it is untested.
