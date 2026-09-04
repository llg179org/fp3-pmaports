# The touch half of the panel loses its supply when the display goes down

2026-09-04 21:00. This is the root cause of #142, and it was read out of the
kernel's own regulator framework - no build, no flash, no new instrument.

## The measurement

`/sys/kernel/debug/regulator/regulator_summary`, screen toggled over the phosh
ScreenSaver interface, everything else unchanged:

```
screen ON      l6   use=1  open=1   normal 1800mV
                 l6                 use=1
                    1a94000.dsi.0-iovcc   use=1
               l10  use=0  open=0   idle   2800mV     (no consumer at all)

screen OFF     l6   use=0  open=1   normal 1800mV
                 l6                 use=0
                    1a94000.dsi.0-iovcc   use=0
               l10  use=0  open=0   idle   2800mV
```

**l6 has exactly one consumer, the panel's iovcc, and it drops its vote when the
display is powered down.** l10 has no consumer in any state.

## Why that is the whole story

`himax,hx83112b` appears twice in mainline, and the two entries describe one
piece of silicon:

* `Documentation/devicetree/bindings/display/panel/himax,hx83112b.yaml` - the
  display half, which **requires** `iovcc-supply`;
* `Documentation/devicetree/bindings/input/touchscreen/trivial-touch.yaml` - the
  touch half, a catch-all with `unevaluatedProperties: false`, which cannot
  carry a supply at all.

These are TDDI parts: one die drives the display and the touch panel. Our board
DTS follows the bindings faithfully - `panel@0` takes `iovcc-supply = <&pm8953_l6>`
and `touchscreen@48` takes nothing - and the result is that the touch controller
is powered by a vote it does not hold and cannot see released.

That closes the chain measured earlier the same day:

    screen off -> panel releases l6 -> nothing votes for it
      -> the touch controller's I/O rail goes
      -> the next transfer takes the bus and both lines stay low
      -> i2c-qup waits out its 14.98 s timeout
      -> "Failed to read input event: -110", touch dropped, panel dead 15 s

and it is why the screen A/B separated so cleanly: 5/5 with the screen off
against 0/5 with it on is exactly a rail with one voter.

## What was fixed

Three commits on `wip/7.1.3/touch`, cherry-picked to `integration/7.1.3` and
`debug-int/7.1.3`, pushed (base `7.1.3/main` untouched):

```
a316c7edd163  dt-bindings: input: himax,hx83112b: give the touch half its own binding
71e8b167175c  Input: himax_hx83112b - hold the rails the touch half runs on
18483b7410a7  arm64: dts: qcom: sdm632-fairphone-fp3: give the touchscreen its supplies
```

The binding had to be moved out of `trivial-touch.yaml` before the DTS could
legally carry the property, so the fix is three patches to three trees, not one.

Verified so far: the DTB compiles and `iovcc-supply`/`vdda-supply` resolve to the
`l6` and `l10` nodes in the built blob; checkpatch --strict is clean apart from
the deliberate local `Co-authored-by:` trailer; every wip commit has its
integration twin (`git cherry`); all three branches match the remote.

## ☠️ NOT yet verified: that it actually fixes the phone

The confirming run is `142-trigger.sh` on a kernel carrying these commits, and
that needs a build and a flash. The flash is gated on queue item #151 - the next
`_commit` bump has to switch the device package's dtb to the composite
`qcom/sdm632-fairphone-fp3-rear-camera-ak7374` and check the boot-fallback net
first - so it belongs to that task, not this one.

Until that run happens this page states a mechanism that is measured
(the rail, the vote, the timing) and a fix that is only *argued*. The
pre-registered rule stands: screen-off must go from 5/5 to 0/5 over five
interleaved rounds.
