# Snapshot focus UI — the shape agreed 2026-08-15

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who specified the design and reviewed every change.

This is the specification the focus rework is built to, written down before the
code so that the reasons survive the patches. What each defect was, and how it
was found, belongs in `docs/camera/bringup/README.md`; this file is the target.

## Why the rework exists

Focus on this phone was spread over two controls that could contradict each
other, and three separate paths that advertised a capability and did nothing:

1. an `Autofocus` switch (on → `AfModeContinuous`, off → `AfModeAuto`), and
2. a `Focus Mode` dropdown (`continuous` / `manual` / `face`) whose `manual`
   value was wired to nothing at all — `apply_focus_mode()` acted only on
   `face`.
3. The lens-distance slider was reachable only by finding a switch called
   *"Automatic — Focus Distance"* in the **Preferences** window, which is not
   where anybody looks while taking a picture.

Measured on the device the same day, two more:

4. the focus mode set at start-up could be lost — a control written before the
   first frame goes to a pipeline with no request to carry it — leaving the
   camera hunting continuously with autofocus switched off;
5. `FOCUS_SETTLE_MS = 900`, the wait between triggering a focus and taking the
   flash picture, against a **measured** full sweep of ~4800 ms. The shutter
   fired mid-scan, with the lens at an arbitrary sweep position.

## The shape

**One control, not two.** The `Autofocus` switch is gone. Focus is a single
mode with four values:

| mode | what the camera does | the distance slider |
|---|---|---|
| `continuous` (default) | hunts by itself, whole frame | inactive |
| `face` | hunts, following a detected face | inactive |
| `tap` | does not hunt; a tap focuses **and takes the picture** | inactive |
| `off` | does nothing; the lens stays where it is put | **active** |

`off` is what makes manual focus reachable at all: it is the only mode in which
`LensPosition` is the thing driving the lens.

**Where it lives.** Out of Preferences, onto the camera page: a small button
next to the flash button, opening a popover with the four modes and the dioptre
slider. Live controls belong where the picture is being taken.

**Taps.** In `tap` mode a single tap focuses and shoots — the double tap that
used to mean "focus and shoot" is gone, and the second press of a double tap is
swallowed so one gesture never takes two pictures. Double-tap-to-zoom stays in
`continuous` and `face`, where the camera is focusing on its own anyway.

**Where the tap points.** A tap sends `AfWindows` for the tapped zone, so the
score is taken over what was pointed at. Without it the metering is all 25
zones and a close subject is diluted by the background that never sharpens —
measured: a 4.9 % modulation against an 8 % `min-contrast` gate, so the scan
was rejected and the lens went back where it started.

**Who focuses before a picture.** `take_picture()` owns it, so every trigger
(tap, shutter button, anything later) behaves the same:

| situation | before the capture |
|---|---|
| flash wanted | flash on → let the exposure settle → focus **under the light** → shoot |
| no flash, mode `tap` or `off` | focus → shoot |
| no flash, mode `continuous` / `face` | shoot at once; the camera is already focused |

Focusing under the flash rather than before it is deliberate and predates this
rework: a contrast-detection algorithm has least to work with in the dark,
which is the situation the flash exists to fix.

**Timing is not tuned here.** `FOCUS_SETTLE_MS` is set from the measured sweep
so that the wait is *correct*; making the sweep shorter (fewer steps, GPU
stats) is a separate exercise with its own measurements.

## Deliberately not done

- The 25-zone metering default is left alone; narrowing it is measured after
  `AfWindows` lands, not guessed at.
- `min-contrast` is not retuned until the zone change is measured — the
  frame-to-frame noise was the same size as the whole focus signal, so a lower
  gate would chase noise rather than find focus.
