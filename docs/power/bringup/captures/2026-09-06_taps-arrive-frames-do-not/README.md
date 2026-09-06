# The taps arrive, and so do the frames - the loss is further out still

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

## ☠️ Run 2 REFUTES the mechanism this page first proposed

The paragraph above says the screen did not change "until the next input event
arrived", and offers the missing frame as the explanation. `fp3-taptest.py` was
then given a `DRAW #n` line inside its draw function — the instrument that half
of this page called for — and run again. **The draw runs immediately, every
time:**

| | |
|---|---|
| presses with a draw timestamp | **122** (82 + 40, two windows) |
| median press → draw | **1.0 ms** |
| worst press → draw | **25 ms** |
| BREAKs | **0** |

And the controlled form was run: six taps each followed by **3.1 – 11.0 s** of
silence, and every one of them was drawn within **1 – 4 ms**. The operator, in
that same round, still saw nothing until the next tap.

So "`queue_draw()` was called but no frame was produced" is **wrong**. The
client renders, promptly, on every tap, including taps followed by eleven
seconds of nothing. ★ And GTK4's draw function is driven by the frame clock,
which on Wayland ticks on `wl_surface` frame callbacks — so a draw that runs is
also evidence the compositor was asking for frames and taking them. (An
inference from how the toolkit works, not a measurement of the compositor.)

## The compositor's own output was current

`shot-after-tap.sh` grabs the compositor's output with `grim` two seconds after
a tap that follows a quiet period, and records the log's mark count at that
instant. Four uncontaminated samples; the one kept here,
`compositor-output-2.6s-after-an-isolated-tap.png`:

```
shot4  19:16:11  marks_at_tap=167  marks_now=167  contaminated=no
       line: 19:16:08.392  .  #167  x=103/360
```

The image reads **`167 (. 84 / o 83) raw 0 breaks 0`** and its mark string ends
in `.` — exactly tap #167. The composited output was up to date 2.6 s after the
tap.

☠️ **This does NOT prove the panel is at fault, for two reasons, and neither is
small:**

1. **`grim` may provoke the very frame it measures.** It copies through
   `wlr-screencopy`, which can schedule a composite rather than hand back
   whatever was last scanned out. A current image is then guaranteed by the act
   of looking, and says nothing about what the panel was showing.
2. **These four samples may contain no failure at all.** During this exact
   round the operator reported *"a small delay, but then it appeared"* — i.e.
   the display was updating. Sampling the working case cannot localise the
   broken one.

## Where that leaves it

Input is exonerated twice over: 162 taps across two runs, perfect `. o` 
alternation, zero BREAKs, every one logged. Rendering is exonerated: median 1 ms
to the draw. What remains unlocalised is everything between the client's drawn
frame and the light coming off the panel — compositor scanout, DRM page flip,
or the panel's own refresh — and the one instrument tried against it is
confounded by rule 1 above.

## ☠️ A probe that measured the operator instead of the device

The first arming of `shot-after-tap.sh` returned **zero** shots over a full four
minutes, and the tempting reading was that the probe was broken. It was not: in
that window the operator tapped **40 times with a median gap of 0.28 s**, and
the probe required an isolated tap. The probe was fine and the *input pattern*
was not the one it needed — a distinction worth the thirty seconds it took to
check the log, because "the tool is broken" would have sent the next hour into
rewriting a working tool.

## ☠️ What this capture does NOT establish

- ~~**When the frame was actually painted.**~~ **ANSWERED by run 2, above, and
  the answer overturned this page's first conclusion**: the paint happens within
  1 ms. Kept rather than deleted, because the shape of the original mistake is
  the point — the missing instrument was named correctly here and the hypothesis
  written next to it was still wrong.
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
