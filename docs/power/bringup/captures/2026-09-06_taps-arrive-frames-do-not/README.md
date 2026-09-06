# The taps arrive. The frames do not.

**2026-09-06**, pmOS on slot b, kernel r88 (`6113869dcc3d`), `fp3-taptest.py`
run as a systemd unit against phoc. Raw log beside this page as
`taptest-run1.log`.

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who made the measurement.

## What the operator reported

*"I pressed the button, the character did not appear; I pressed MARK, and when
the MARK sign appeared it printed the character too."*

## What the log says

**118 taps, alternating `. o . o` without a single BREAK.** Every tap the
operator made was delivered to the client and written to the log at the
millisecond. Nothing was lost between the panel and the application.

The two MARK presses bracket the phenomenon and put a number on it:

| the tap the operator did not see | logged at | MARK pressed at | it went unpainted for |
|---|---|---|---|
| `.` #79 | 18:59:43.956 | 18:59:47.347 | **3.4 s** |
| `o` #90 | 18:59:55.980 | 18:59:58.128 | **2.1 s** |

Three and a half seconds is not a scheduling hiccup or a slow frame. The
application had already called `queue_draw()` — that call sits directly after
the log line in `_pressed`, so the log line proves it ran — and the screen did
not change until the *next* input event arrived.

## Why this matters beyond the test app

This is the shape of the original complaint that started the touch work: digits
pressed on the calculator that appear only later. It was investigated as a lost
**touch**, and the kernel was exonerated for it
([`../../touch/lost-taps.md`](../../touch/lost-taps.md)). This run says the input
is not lost at the client either — what is missing is the **presentation**. An
operator cannot tell those two apart by eye, and every instrument used so far
counted events rather than frames.

## ☠️ What this capture does NOT establish

- **When the frame was actually painted.** This run has no draw timestamps: the
  log records presses, not paints, so "unpainted for 3.4 s" rests on the
  operator's report for the *seeing* half and on the log only for the *pressing*
  half. That is exactly the gap a second instrument has to close, and
  `fp3-taptest.py` now logs `DRAW #n` from inside its draw function for it.
  Until a run with those lines exists, the mechanism is a hypothesis.
- **Where in the stack the frame is lost.** GTK's frame clock, phoc's damage
  handling and the panel's own self-refresh are all candidates and none is
  tested here.
- **That it happens without any further input at all.** The operator waited
  ~3.4 s, which is strong, but the controlled form — tap once, touch nothing for
  five seconds, watch — has not been run yet.

## ☠️ And a note on the earlier "lost taps"

Every GUI-based round of this investigation before today measured what the
operator *saw*. If frames are withheld until the next event, then a perceived
lost tap is the expected observation even when the input path is perfect — so
the eleven "lost" taps that an earlier reflowing layout manufactured were not
the only way this instrument could lie. The log, not the screen, is the witness.
