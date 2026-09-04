# ☠️ The gap logger was blind to the fault it was built for. 2026-09-04 13:10–13:15.

## What v1 did, and why it seemed right

`142-gaps.py` v1 logged an inter-frame gap **only while `BTN_TOUCH == 1`**. The
reasoning was sound and came from a real failure earlier the same day: in the
1 Hz ledger, "the operator paused" and "the panel stalled under a finger" are the
same hole, and that ambiguity had already produced one wrong conclusion. Adding
the finger-down condition removed it.

It also removed the ability to see the main event.

## The measurement that exposed it

Between 13:10:21 (v1 start) and 13:15 there were **three 15 s stalls** —
`err110` 11→12 at 13:11:21, 12→13 at 13:13:05, 13→14 at 13:13:43, each ending a
15–16 s hole in the 1 Hz ledger. v1's largest recorded gap in that period:
**429 ms**. Gaps over one second: **zero**. Its heartbeats read `down=False`
throughout.

The finger was physically on the glass. The explanation is the fault itself:

> a touch raises an interrupt → the driver's i2c read hangs for ~15 s → **no
> frames are produced at all** → so the `BTN_TOUCH=1` of that very press never
> reaches the input layer → `down` stays False → the gap is never logged.

**The failure prevents the signal the logger's condition depends on.** A logger
gated on evidence that the fault suppresses cannot see the fault, and its silence
reads exactly like "no stalls found".

## The rule this earns

**Never filter at capture time; annotate and filter at analysis.** v1 threw the
`down=False` gaps away at the moment of writing, so no later analysis could
recover them. v2 records **every** gap with `down=` beside it, which answers the
original ambiguity just as well and keeps the events that matter.

The same discipline stated the other way round: before conditioning a measurement
on a signal, ask what the fault does to that signal. Here the fault destroys it,
which is the worst case and the easiest to miss, because the condition looks like
extra rigour.

## What v1 did establish, and still stands

Sub-second stalls with a finger down are real and frequent: 13 gaps of 100–429 ms
in ~3300 frames, against a normal 12–50 ms spacing, with the `-110` counter not
moving once. Those measurements are unaffected — v1 was blind to the long stalls,
not wrong about the short ones.

## And the association it let us confirm

With the ledger transitions read at the right rows (the transition, not the tail):
**all 14 `-110` events end a 15–16 s gap. Fourteen for fourteen, no exceptions**,
consistent throughout with the QUP `xfer_timeout` of 14.98 s.
