# libcamera has no `imx363` sensor-properties entry

> ⚠️ **AI-generated.** Written by Claude (Opus 5) working under the direction of
> Lajosházi, László Gergely, who reviewed every change and made or reviewed
> every measurement it rests on.

Found 2026-08-25 while checking that the camera still works on r76 — it does.
`cam -l` enumerates `Internal back camera`, loads
`/usr/share/libcamera/ipa/simple/imx363.yaml`, and reports the focus lens range.
It also says this, every time:

```
WARN CameraSensorProperties camera_sensor_properties.cpp:538
     No static properties available for 'imx363'
WARN CameraSensorProperties camera_sensor_properties.cpp:540
     Please consider updating the camera sensor properties database
WARN CameraSensor camera_sensor_legacy.cpp:502
     'imx363 0-001a': No sensor delays found in static properties.
     Assuming unverified defaults.
```

☠️ **This is a different database from the one we already patch.** `temp/libcamera`
carries `0100-add-imx363-sensor-helper.patch`, which adds the sensor *helper*
(`libipa`, the gain-code ↔ gain conversion the IPA needs). The *properties*
database — `src/libcamera/sensor/camera_sensor_properties.cpp` — has no imx363
entry, and a web search of libcamera's patchwork and mailing list found none
pending either (entries exist there for imx415, imx477, imx335, gc08a3, ov7251,
ov9281 and others). So this is an upstreamable gap, not a local packaging miss.

## What an entry needs, and what we can honestly fill in

| field | value | basis |
|---|---|---|
| `unitCellSize` | **{ 1400, 1400 }** nm | ★ Cross-checked, not taken on one source's word. The IMX363 is quoted as 1.4 µm pitch with a 4032×3024 array and a 1/2.55" (7.05–7.06 mm) diagonal. Those are separable facts, and they agree: 4032 × 1.4 µm = 5.645 mm, 3024 × 1.4 µm = 4.234 mm, diagonal **7.06 mm**. |
| `testPatternModes` | **empty** | Measured on the device: `v4l2-ctl -d /dev/v4l-subdev16 -l` lists exposure, h/vflip, wide_dynamic_range, camera_orientation, camera_sensor_rotation, vertical_blanking, horizontal_blanking (read-only) and analogue_gain — **no `test_pattern` control**. Our driver exposes none, so there is nothing to enumerate. |
| `sensorDelays` | **unknown** | ☠️ Cannot be looked up and will not be guessed. It says how many frames after a write an exposure or gain change takes effect; a wrong value makes the AE apply its correction to the wrong frame, which shows up as hunting or lag. It has to be measured. |

## How to measure the delays (not yet done)

While streaming at a fixed frame rate, step `exposure` (or `analogue_gain`) by a
large amount at a known frame, then find the first frame whose mean luminance
reflects the new value. The number of frames between the two is the delay.
Repeat for gain and for `vertical_blanking`. The device side is ready — the
control is writable on `/dev/v4l-subdev16` and `cam` can dump frames.

☠️ **Before spending that effort, settle whether it costs us anything at all.**
The delays are consumed through `DelayedControls` in a pipeline handler, and this
device runs the **`simple`** pipeline handler with the software ISP. If that
handler does not use `DelayedControls`, the missing entry costs nothing on this
phone and the warning is noise for us — the entry would then be worth submitting
for other imx363 boards, not for ours. Answer that from the libcamera source
before measuring anything.

## Related, and NOT this

The camera wedge (`../../TODO.md`, "The camera wedges the phone…") is a separate
matter. ☠️ One of its listed facts was retracted the same day: the boot-time
`cci ... timeout` + `imx363 ... -110` is **not** a symptom — it is our own
`imx363_power_on()` warm-up loop absorbing the first cold I2C transaction, which
the driver's own comment predicts. One `-110` and no "failed to read chip id"
beside it is exactly what a working warm-up looks like.

---

## 2026-08-26 — the gate is settled from the source: the entry **is** consumed, and there is a log line that proves it

The previous section set a gate before spending any measurement on this: *does
the `simple` pipeline handler use `DelayedControls` at all?* If it did not, a
`sensorDelays` entry would be decoration and the whole lead could be dropped.

Read out of `libcamera v0.7.1` (the version the `libcamera` aport builds — its
`_pkgver`, tarball in `cache_distfiles`). **It does**, and the chain is short:

`src/libcamera/pipeline/simple/simple.cpp:568`

```c++
const CameraSensorProperties::SensorDelays &delays = sensor_->sensorDelays();
std::unordered_map<uint32_t, DelayedControls::ControlParams> params = {
        { V4L2_CID_ANALOGUE_GAIN, { delays.gainDelay,     false } },
        { V4L2_CID_EXPOSURE,      { delays.exposureDelay, false } },
};
delayedCtrls_ = std::make_unique<DelayedControls>(sensor_->device(), params);
```

Note **which two** fields are used: `exposureDelay` and `gainDelay`.
`vblankDelay` and `hblankDelay` are read by other pipeline handlers, not by ours,
so measuring them would buy this device nothing.

**What we get today, having no entry** —
`src/libcamera/sensor/camera_sensor_legacy.cpp:488`:

```c++
static constexpr CameraSensorProperties::SensorDelays defaultSensorDelays = {
        .exposureDelay = 2, .gainDelay = 1, .vblankDelay = 2, .hblankDelay = 2,
};
...
LOG(CameraSensor, Warning)
        << "No sensor delays found in static properties. "
           "Assuming unverified defaults.";
```

So the fallback is not silent: **libcamera says out loud that it is guessing.**
That turns a source-reading argument into two things measurable on the device,
and neither has been run yet:

1. ☠️ **Confirm the warning actually fires for our camera.** If
   `No sensor delays found in static properties` is not in the libcamera log for
   `imx363`, then something else is supplying properties and this whole lead is
   built on a misreading. **Run this before writing any patch** — it is the
   cheapest possible disconfirmation and it costs one camera start.
2. **Establish whether the delays are applied at all.** `delayedCtrls_` is only
   driven when the pipeline finds a **frame-start event emitter**
   (`simple.cpp:1656`: `if (frameStartEmitter) { setFrameStartEnabled(true); …
   frameStart.connect(…) }`). If our camss/imx363 path emits no
   `V4L2_EVENT_FRAME_SYNC`, `DelayedControls` is constructed and never applies
   anything — the entry would be correct and inert. Read the pipeline's own
   `Debug` log for the emitter, or check the subdev for the event.

**Only if both come back positive is measuring the true delays worth the time.**
And the measurement is then well defined: step the gain (or exposure) by a large
amount on one frame and find how many frames later the change appears — that
count *is* `gainDelay` / `exposureDelay`.

☠️ **Two things are still not inventable and must not be guessed into a patch:**
the delays themselves, and the test pattern modes (measured absent: the driver
exposes no `test_pattern` control, so `testPatternModes` stays empty). Only
`unitCellSize = { 1400, 1400 }` is safely derivable, and it is cross-checked two
independent ways in the section above.
