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

## ☠️ The likeliest explanation is the instrument's own blindness

Reading `_draw` after the refutation above: **a tap on a half changed almost
nothing on screen.**

- The two halves draw a *static* `.` and `o`. They looked identical before and
  after a press — the halves had **no feedback of any kind**. Only MARK flashed.
- The only things that changed were the header count and **one 16 px character
  appended to a block of ~167 identical `.o.o.o` glyphs**.
- Tapping fast makes the block visibly grow, so it reads as responsive. Tapping
  once and watching gives the eye nothing to catch.

That predicts the operator's exact report — *"the character appeared when I
pressed MARK"* — with no display fault at all: MARK flashes the whole bar bright
yellow for 350 ms, the one unmissable change on the screen, and the eye then
re-reads the block and finds the symbol that had been there the whole time.

**So this page's headline may have been explaining an artefact of its own
instrument's visual design.** It is not established either way — the display
path is still unmeasured — but a mechanism that requires nothing unusual now
outranks one that requires frames to go missing.

### ☠️ …and the operator rejected that, with the standing they have and I do not

Put to the operator the same evening, the answer was: *"I did see what the last
character at the end of the row was. It was not my perception."* They were
watching the one glyph the explanation above assumes they could not pick out.

**That testimony outranks the reasoning.** I inferred the operator's perception
from the source code; they reported it from in front of the screen, which is the
only place it can be observed. The blindness explanation is therefore **not
supported**, and it is kept here only as a candidate that was proposed and
rejected — not as the leading one. The feedback changes made for it are still
worth having, because an instrument should not depend on the operator tracking
one 16 px glyph even when they can.

What remains, after two mechanisms have fallen, is that **nothing in the chain
has been measured end to end**. That is what the staged instrument below is
for.

## What was changed, and what it buys

`fp3-taptest.py`, same run loop, four additions:

| before | after |
|---|---|
| a tap on a half changed nothing visible | the touched half **flashes** for 200 ms (left green, right blue) |
| no way to see where the finger landed | a white disc is drawn **at the touch point** for the flash, so a tap that crossed the divider looks like a wrong-side tap rather than a lost one |
| the new symbol was one glyph among 167 | the **newest symbol is drawn large** in the record area, and highlighted in yellow inside the block |
| no way to tell whether the screen updates at all | ★ a square top-right that **changes colour on every paint** |

★ The paint tick is the real instrument fix. If frames stop reaching the panel
the square stops changing, and that is visible **without touching anything** —
which is what this whole question needed and no earlier version had. It cycles
on existing paints and never schedules one, so it cannot alter the scanout
behaviour under test.


## The instrument the whole day was missing: the four hops, timed

Every stage of one tap is reachable from inside the app, and was verified
present on this device before any of it was written:

| stage | source | what it measures |
|---|---|---|
| `evt→raw` | `event.get_time()` vs `CLOCK_MONOTONIC` at the handler | kernel → libinput → phoc → Wayland transport |
| `raw→ges` | `EventControllerLegacy` → `GestureClick::pressed` | GTK gesture arbitration |
| `ges→draw` | → `_draw` | render scheduling |
| ★ `draw→shown` | `Gdk.FrameTimings.get_presentation_time()` | **when the frame actually reached the display** |

The last row is the measurement this investigation needed all day and the reason
the `grim` probe was confounded: presentation time comes from the compositor's
own feedback about a frame that was already on its way, so looking at it does
not create it.

They are drawn as four blocks at fixed coordinates, coloured by their own
thresholds. ☠️ **Grey means "could not be measured" and is deliberately not the
colour of "fast"** — an unmeasured hop shown as green is precisely how this
instrument would lie.

Two honesty gates are built in:

- ☠️ **The event clock is tested, not assumed.** On wlroots the `GdkEvent` time
  should be `CLOCK_MONOTONIC` milliseconds, but that is a claim about the
  compositor; the app checks the implied latency is within 0–2000 ms and marks
  the stage unusable otherwise. Calibrating an offset from the first event was
  written first and thrown away — it makes the test circular, the first sample
  reading 0 ms by construction.
- ☠️ **The one-shot repaint is a perturbation and is labelled as one.** The
  presentation time of a frame is only known after that frame is reported back,
  so showing it needs a second paint 400 ms later. It is one per tap, never a
  tick callback, so it cannot turn into the continuous repaint that would change
  the scanout behaviour under test.

## The buffer question, answered from our own kernel

There is exactly one bounded queue in the path, and it is in the kernel: the
per-client `evdev` ring, `roundup_pow_of_two(max(hint_events_per_packet × 8,
64))` (`EVDEV_BUF_PACKETS = 8`, `EVDEV_MIN_BUFFER_SIZE = 64` in
`drivers/input/evdev.c`).

For this panel, computed from the device's own advertised capabilities
(`/proc/bus/input/devices`: `ABS_X, ABS_Y, ABS_MT_SLOT, ABS_MT_TOUCH_MAJOR,
ABS_MT_WIDTH_MAJOR, ABS_MT_POSITION_X, ABS_MT_POSITION_Y, ABS_MT_TRACKING_ID`)
and `HIMAX_MAX_POINTS = 10` slots, `input_estimate_events_per_packet()` gives
**80 events per packet** — the worst case, all ten fingers on every axis — so
the ring is **1024 events**.

A real one-finger tap is nothing like 80 events: about 10 for the press frame
and 4 for the release. So the ring holds on the order of **70 taps**, and only
matters if the reader stalls that long.

★ **And an overflow is not silent.** The kernel injects `EV_SYN/SYN_DROPPED` and
the client must resync, so "the buffer overflowed and swallowed it" is a
*checkable* claim rather than a story. Nothing above the kernel has a fixed tap
limit: phoc's and GTK's queues are memory-bounded lists.

## ★ First end-to-end timing: the input path is 7.5 ms, the display is 73 ms

The instrument needed three fixes before it measured anything, all of them the
same class of bug — **a stage that silently reports "unmeasurable" looks exactly
like a stage that is fast**:

1. ☠️ **`EventControllerLegacy` in the default BUBBLE phase saw nothing.**
   `GestureClick` had already claimed the sequence. Every run on this page
   before now printed `raw 0` in its header and that was read as "no raw touch
   events on this transport" rather than as a bug in the controller's phase.
   Fixed with `set_propagation_phase(CAPTURE)`.
2. ☠️ **The stage record was never reset**, so after the first tap the resolve
   was never re-armed again and a whole run produced exactly **one** `STAGES`
   line — which the operator saw as *"the number does not change after a
   press"*.
3. ☠️ **In the CAPTURE phase the signal hands the handler `None`**; the event
   must be fetched with `controller.get_current_event()`. Every press raised
   `AttributeError` inside the handler, GTK swallowed it, the app kept running,
   and the log showed nothing but `n/a`. **A handler that throws is
   indistinguishable from one that is never called.**

With all four hops finally measured:

```
evt->raw 4.8 ms   raw->ges 0.9 ms   ges->draw 1.8 ms   draw->present 73.4 ms
                                                       (refresh 16.7 ms)
```

| hop | cost |
|---|---|
| kernel → libinput → phoc → app | **4.8 ms** |
| GTK gesture arbitration | **0.9 ms** |
| render scheduling | **1.8 ms** |
| ★ **drawn frame → on the display** | **73.4 ms — about 4.4 refresh intervals** |

Three samples so far: **118.4, 80.3, 73.4 ms**. The whole input path costs
7.5 ms and the presentation costs an order of magnitude more.

☠️ **Not yet a result, and two things must be checked before it is quoted:**

- **Is `get_presentation_time()` real feedback or a prediction?** GDK exposes
  `get_predicted_presentation_time()` separately and `get_complete()` was true,
  which is suggestive and not conclusive. A number that is really the frame
  clock's own estimate would be a plausible fabrication of exactly the shape
  this investigation wants.
- **Three samples are not a distribution**, and all three were the first taps
  after an idle period, which is the case most likely to carry a wake-up cost.

- ☠️ And even at 73 ms this does **not** yet explain the original report, which
  was *nothing at all until the next tap* — 73 ms is perceptible but it is not
  that. It may be the "small delay" the operator described later in the day; it
  is not obviously the same phenomenon as the first one.

## ☠️☠️ WITHDRAWN: those three numbers measured the instrument

The operator, after using the staged version: *"in the previous version (without
the small boxes and the evt numbers) the display was fast and there were no
misses; now it is as if the display had slowed down."*

They are right, and the mechanism was written into this page as a risk before it
happened. To display a frame's presentation time the app called `queue_draw()`
from the resolve, **one extra forced frame 400 ms after every tap**. During a
sequence of taps that is a second stream of repaints interleaved with the real
ones.

So **`118.4 / 80.3 / 73.4 ms` are withdrawn**: they may be measuring, in part,
the frames the measurement itself added. They are kept here because the shape of
the error is the lesson — the perturbation was identified, written down in a code
comment as the reason the resolve was one-shot rather than a tick callback, and
then quoted as a result anyway. **Labelling a confound is not controlling for
it.**

★ **And the operator's report is itself the second, independent detection of
this class of problem today** — the first being their rejection of the
"you could not see the glyph" explanation. Both times the person in front of the
screen had information no amount of reading the source could produce.

### The fix

The resolve now **only logs and stores**; the blocks update at the next natural
paint, which is the next tap. Nothing in the measurement path schedules a frame
any more. The log is the measurement; the screen is a convenience.

A single isolated tap therefore has its presentation time in the log but not yet
on screen — which is the correct trade: the alternative is the instrument that
was just withdrawn.

### What must be re-measured

Everything in the block above. The hop costs from the input side (`evt->raw`,
`raw->ges`, `ges->draw`) are much less exposed to this — they are all upstream of
the paint — but they were taken in the same contaminated runs and get no free
pass.

## ★★ LOCALISED: GTK's gesture recogniser swallows the lost taps

990 taps in one run (`taptest-run7-990-taps.log`), with the raw counter finally
working:

| | |
|---|---:|
| raw `touch-begin` events delivered to the client | **1030** |
| taps the gesture recogniser produced | **990** |
| **raw events that produced no tap** | **40** |
| alternation BREAKs the app logged by itself | **61 (6.2 %)** |

And the 40 are not scattered — **every BREAK has one sitting immediately before
it**:

```
TAP   19:50:12.132  .  #5
RAW   19:50:12.241  RAW touch-begin #6   ->  TAP  o  #6      delivered
RAW   19:50:12.321  RAW touch-begin #7   ->  (no tap)        SWALLOWED
RAW   19:50:12.430  RAW touch-begin #8   ->  BREAK + TAP o #7
```

The same shape at 19:50:14.489 and 19:50:15.019, and so on.

**So the touch is not lost in the panel, the driver, libinput or the
compositor — all of those delivered it, and the app's raw controller counted it.
It is lost inside GTK, between the `GdkEvent` and `GestureClick::pressed`.**

This is precisely the split the raw counter was added for, written into the
source months of debugging ago:

```
kernel CONTACT  ->  RAW  : lost in libinput or phoc
RAW  ->  tap           : lost in GTK's gesture recognition
```

☠️ **And it could not be measured until an hour before this run**, because the
controller was in the default BUBBLE phase and saw nothing at all. Every earlier
run on this page printed `raw 0` and that was read as a fact about the
transport. **The instrument that would have answered the question was present
and silently disabled the whole time.**

### The leading cause, not yet confirmed

`Gtk.GestureClick` handles **one touch sequence at a time**. The operator taps
with two fingers alternately, so a second finger landing before the first lifts
is exactly the case a single-sequence recogniser rejects. The build after this
run logs `fingers-down` and the raw touch position with every event, and tracks
`TOUCH_END`/`TOUCH_CANCEL`, which decides it.

If that is the cause then it is **an artefact of this instrument**, not a device
fault — but the same GTK arbitration runs under every GTK app on the phone, so
"the calculator dropped a digit" would have the same explanation and the same
fix, and neither is in the kernel.

## ☠️ I over-corrected the withdrawal an hour earlier

The presentation numbers were withdrawn as contaminated by the forced repaint.
The repaint is gone, and in this run, over 484 samples:

| stage | median | p90 | max |
|---|---:|---:|---:|
| `evt->raw` | 3.1 ms | 14.0 | 39.8 |
| `raw->ges` | 0.5 ms | 0.7 | 25.0 |
| `ges->draw` | 5.0 ms | 21.2 | 87.6 |
| **`draw->present`** | **59.0 ms** | **76.9** | **347.6** |

**The effect survives removing the perturbation**, so the perturbation was not
its cause. The withdrawal was right to be cautious and wrong in what it
concluded; both are kept. What the forced repaint did cause is the *operator's*
report that the display had got slower — that observation stands and was the
reason the repaint was removed, which was worth doing on its own.

☠️ **59 ms is still not quotable**, for the reason named when it was first
measured and still not settled: `get_presentation_time()` may be the frame
clock's own prediction. The next build logs it against
`get_predicted_presentation_time()`; if they are equal every time, the
"measurement" is a model.

## ★★★ CONFIRMED: every lost tap had a second finger already down

The build that logs `fingers-down` with each raw touch, 542 taps:

| | |
|---|---:|
| raw `touch-begin` delivered | **560** |
| taps `GestureClick` produced | **542** |
| **raw touches that produced no tap** | **18** |
| of those, with **1** finger down | **0** |
| of those, with **2** fingers down | **18** |
| taps with 1 finger down | 542, none lost |
| `touch-cancel` events | 0 |

**100 % of the losses happened while a second finger was still down, and none
happened otherwise.** `Gtk.GestureClick` handles one touch sequence at a time;
alternating two fingers means the next touch regularly lands before the previous
one lifts, and the recogniser rejects it.

The swallowed touches are logged with their positions — `71,561`, `72,562`,
`83,548` — all in the **left** half, which is why the BREAKs read `o repeated`:
the `.` between two `o`s is the one that disappeared.

So the chain is now complete, and nothing in it is a device fault:

```
panel -> himax driver -> libinput -> phoc -> GdkEvent      all deliver (560/560)
GdkEvent -> GestureClick::pressed                          18 dropped, all on overlap
```

### The fix, and why it is the right one

`fp3-taptest.py` now drives a tap from the **raw touch**, and keeps
`GestureClick` only for the `raw->ges` timing and as a control. The header shows
`raw` and `gest` side by side, so the gap between them stays visible instead of
being something a future run has to rediscover.

☠️ **Note what this does and does not say about the original complaint.** It
fully explains the losses *in this instrument*, which used a single-sequence
recogniser and an operator alternating two fingers. Whether the calculator
drops digits for the same reason is **not** established here — but it is now a
concrete, cheap thing to test, and it is in GTK, not in the kernel.

## ★ The presentation time is real feedback, not a prediction

The check named twice on this page, run over 237 samples:

| | |
|---|---:|
| `get_presentation_time() == get_predicted_presentation_time()` | **0 / 237 (0 %)** |
| difference between them | median **24.5 ms**, min 7.9, max 77.1 |

They never coincide, so the number is the compositor's own feedback about a
frame that was presented, not the frame clock's model of when it expected to
present one. **`draw->present` is a measurement and may be quoted as one:**

```
median 49.3 ms   p10 44.3   p90 67.9      (refresh 16.7 ms)
```

About three refresh intervals from the app finishing its paint to the frame
being on the screen, on a phone whose whole input path costs under 5 ms.

☠️ **What causes those three frames is still unknown** — compositor pipeline
depth, the DRM page-flip path and the panel's own latency are all untested. What
has changed is that the number is now trustworthy enough to be worth explaining.

## ★★★ The fix works: 704 touches on the halves, 704 taps, zero lost

The build that takes its taps from the raw touch instead of `GestureClick`:

| | before (run 8) | after (run 9) |
|---|---:|---:|
| raw touches on the two halves | 542 | **704** |
| taps produced | 542 | **704** |
| **lost** | **18** | **0** |
| of those, two fingers down | 18 — every one lost | **16 — none lost** |

Sixteen touches landed with a second finger still down and **all sixteen became
taps**. That closes the loop: the losses were `GestureClick`'s single-sequence
arbitration and nothing else.

☠️ **My own analysis had a false positive first.** Ten raw touches had no tap
after them and were counted as losses; they were at `y = 60…337`, in the
**record area**, which `_handle_tap` deliberately ignores. The correct count
excludes anything above `MARK_TOP`, and then it is zero. An analysis script gets
no more benefit of the doubt than the instrument it reads.

### The 29 BREAKs in this run are not losses either

They come in runs: ten consecutive `.` between 20:05:45.2 and 20:05:46.7, then
nineteen between 20:05:50.3 and 20:05:54.1, all at `x ≈ 71–94`, evenly spaced
about 200 ms apart. That is the operator tapping one side on purpose. The app
logs a BREAK whenever the alternation fails, deliberate or not — and since raw
touches and taps are equal at 704 on the halves, **every one of those taps had
its own raw touch**. A BREAK means "the alternation broke", never "a tap was
lost"; only the raw-versus-tap gap means that, which is why both counters are on
screen.

### The stage numbers reproduce across two independent runs

| stage | run 8 median | run 9 median | run 9 p90 |
|---|---:|---:|---:|
| `evt->raw` | 3.1 ms | 2.9 ms | 15.5 |
| `raw->ges` | 0.5 ms | 0.7 ms | 1.1 |
| `ges->draw` | 5.0 ms | 6.9 ms | 24.6 |
| **`draw->present`** | **49.3 ms** | **48.8 ms** | 65.7 |

Half a millisecond apart on the number that matters, from separate runs with
different tap patterns. **The input path costs about 10 ms and the display costs
about 49 ms — three refresh intervals — and that is now the only unexplained
thing left on this page.**

## The instrument, as it stands

Four **stacked** rows, one per hop, each carrying its own value chip, its own
12-sample bar row scaled to that hop's own worst value (not a shared scale,
which would flatten the fast hops into nothing), and its own **running light**
that steps only when *that* hop produces a new sample.

★ The per-row light is what makes a silent stage visible: if `draw->shown` stops
being reported its light freezes while the other three keep stepping, and that
is legible at a glance without comparing numbers. It is the same idea as the
global paint tick, applied per stage — and it exists because this page has twice
been misled by a stage that reported nothing and looked like a stage that was
fast.

☠️ **The startup text must fit the record area** — the top 4/8 of the window,
360×180 logical px here. Written once at font 13 it overran onto the MARK bar
and past the right edge (screenshot taken, layout fixed at font 11: about 44
characters wide, about 20 lines). The rule is in a comment above the text:
**screenshot it after editing.** `taptest-instructions-screen.png` beside this
page is the fitted version.

## Third run, larger sample: still zero lost

| | run 8 | run 9 | run 10 |
|---|---:|---:|---:|
| raw touches on the halves | 542 | 704 | **792** |
| taps produced | 542 | 704 | **792** |
| **lost** | **18** | 0 | **0** |
| two-finger touches | 18, all lost | 16, none lost | **59, none lost** |
| BREAKs | 61 (6.2 %) | 29 | **5 (0.6 %)** |

Fifty-nine overlapping touches, none lost. The five BREAKs are `run=2`/`run=3`
same-side repeats with `raw == tap == 792`, so each had its own touch: the
operator tapped the same side twice, which is not a loss.

| stage | run 8 | run 9 | run 10 | run 10 p90 |
|---|---:|---:|---:|---:|
| `evt->raw` | 3.1 | 2.9 | 3.6 | 15.0 |
| `raw->ges` | 0.5 | 0.7 | 0.8 | 1.2 |
| `ges->draw` | 5.0 | 6.9 | 4.9 | 23.2 |
| **`draw->present`** | 49.3 | 48.8 | **56.6** | 79.8 |

### ☠️ The analysis script produced a false alarm — again

The presentation check first reported `pres == pred` in **342 of 676** samples,
which would have meant the number was the frame clock's model after all. It is
an artefact of the *script*: 342 is exactly the count of samples with no
presentation time at all, where `pres = 0` and `pred = 0` — and zero equals
zero. Counted only over samples that have a presentation time: **0 of 334**,
median difference 30.4 ms. The validation stands, now on a second independent
run.

That is the second false positive from an analysis script on this page (the
first counted taps in the non-target record area as losses). **The scripts that
read the instrument need the same scepticism as the instrument.**

## Marking the overlapping touches, with a dotted zero

A touch that lands while another finger is still down now appends `0` to the
record: those were exactly the touches `GestureClick` dropped silently, so they
are marked rather than left to be inferred. The BREAK `!` glyph is gone — a
repeat is already visible as a repeat.

☠️ The glyph has to be readable *against `o`*, so the font matters. Checked by
rendering `0 o O` in every monospace font on the device
(`dotted-zero-font-check.png`): **Adwaita Mono draws a dotted zero; Droid Sans
Mono and the generic `monospace` alias do not.** The record text now selects
Adwaita Mono explicitly. Rendering it was the point — the alternative was
assuming which font has a dotted zero, which is exactly the kind of claim that
looks fine until someone reads the screen.

## Tapping the record clears it

A tap in the record area wipes the mark string, so a long session can be cut
into readable stretches without restarting the app and losing the run.

Two choices worth stating, because both could have been made the other way and
would have quietly cost something:

- ☠️ **The counters are NOT reset.** `raw`, `gest`, `breaks` and the tap totals
  are the measurement; the string is only its display. Clearing both would
  discard the one number this whole page turns on — the gap between `raw` and
  `gest`, which *is* the lost taps.
- ☠️ **The clear is logged** (`CLEAR`, with the position and how many marks were
  dropped). Without that line a later analysis sees a mark sequence that
  suddenly shortens and cannot tell a deliberate wipe from a fault — and this
  page has already produced two false alarms from analysis scripts reading the
  log too literally.
