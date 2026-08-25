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
