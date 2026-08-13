# Power measurements on the Fairphone 3

> ⚠️ **AI-generated.** These pages, and the code and measurements they describe,
> were written by Claude (Opus 5) working under the direction of Lajosházi,
> László Gergely, who reviewed every change and made or reviewed every
> measurement they rest on.

Raw captures from the charger and power-management work, kept because the
conclusions drawn from them are only as good as the data, and because a host
reboot has already eaten one of these files once.

Each log is one line per sample with the same fields on both operating systems,
so the two can be compared directly:

```
iso_time uptime_s capacity status charge_type vbat_uV ibat_uA temp_dC
usb_online usb_imax_uA usb_vbus_uV usb_real_type charge_done chgr_status_reg
```

`usb_real_type` and `charge_done` exist only on the vendor stack; the columns
are kept on the pmOS side with `-` so the files line up. `chgr_status_reg` is
`BATTERY_CHARGER_STATUS_1` read straight from the PMIC — its low three bits are
the charger's own state machine, and code 5 is the one that says a charge
finished.

| file | what it holds |
|---|---|
| `2026-08-11_regs-pmos.txt`, `2026-08-11_regs-ut.txt` | the charger's CHGR, DCDC, BATIF, USB and MISC registers, 1280 of them, read on each OS with the same pack in the same state. 45 differed; `CHGR_CFG2` was the one that mattered |
| `2026-08-11_ut_discharge-charge.txt` | Ubuntu Touch: a night idle, a deliberate flash+camera load, then a full charge to termination |
| `2026-08-12_ut_terminates.txt` | the vendor stack reaching `TERMINATE` within a minute of the current crossing the threshold |
| `2026-08-12_pmos_iterm-fix-terminates.txt` | the same on pmOS, after `I_TERM_BIT` was left set — the single-change A/B |
| `2026-08-12_pmos_idle-discharge.txt` | pmOS idle, matched against the UT night |
| `2026-08-13_pmos_camera-hold-idle-cost.txt` | the three-phase A/B/C above: idle current with the camera held, with wireplumber stopped, and with wireplumber running but not claiming the camera |
| `2026-08-12_pmos_day-to-r51-termination.txt` | a day on pmOS ending in the first termination reached by the **packaged** kernel rather than by hand-deployed pieces: `linux-fp3-7.1.3-r51`, taper at 87 mA, then `Full` with `chgr_status_reg` at `0x45`. The uptime column resets partway through, at the reboot onto that package |

## What these say, and what they do not

**Percent is not comparable between the two.** They run different gauges. Over
one matched 6.66 h idle window the vendor gauge reported 6 points against 571
mAh integrated, and ours reported 36 points against 1319 mAh. Compare the
integrated current and the terminal voltage; treat the percentage as a
measurement *of the gauge*, not of the phone.

**The logger biases its own numbers.** It wakes once a minute and reads the
current while it is itself running, so the mean it produces is high. This is
identical on both sides, so the difference between them survives; the absolute
figure does not.

**Idle here means idle with the link up.** Every one of these ran with WiFi
associated and an SSH session open, because that is how the data got off the
phone. None of them is a measurement of a sleeping phone. pmOS in particular
never suspended at all during these runs — `/sys/power/suspend_stats/success`
stayed at 0, because `sleep-inactive-battery-type` is `nothing`, not because
anything blocked it.

**The 198 mA against Ubuntu Touch's 86 mA is now accounted for**, and neither of
the two obvious explanations was right. The first to go was suspend. That pmOS
never suspends is measured — but so is the other side, as of 2026-08-12:
**Ubuntu Touch does not suspend either.**

The counter alone could not say so, because `success` is since boot and the
oracle slot had just been rebooted. What settles it is comparing the two clocks,
which needs no counter and no root: `CLOCK_MONOTONIC` does not advance across a
suspend, so an idle phone that sleeps shows less uptime than wall time. Sampled
twice five minutes apart on UT, with the display off and nothing but the SSH
link up:

```
1786567461 436
1786567491 466      # 30 s of wall clock, 30 s of uptime — awake the whole way
```

Neither kernel offers `/sys/power/autosleep` at all. The vendor one has the
Android wakelock interface (`/sys/power/wake_lock`, owned by `radio`) and would
suspend on a userspace daemon's say-so; ours has neither the interface nor
anything asking. So the 2.3x gap is **not** a sleeping phone against a waking
one: it is two awake phones, one of which costs more to keep awake.

What it *is* turned out to be one held-open device, worth about 100 mA — the
measurement is below. It was found by carrying on with runtime PM, measured the
same way on both sides, which is the same two-sided diff that found the charger
bug:

| | Ubuntu Touch | postmarketOS |
|---|---|---|
| devices with runtime PM `active` | 8 | **17** |
| `suspended` | 65 | 46 |
| `unsupported` (no runtime PM at all) | 719 | 293 |

The totals are not comparable — the vendor kernel enumerates far more devices —
but the `active` list is. Ours keeps two i2c buses and a USB PHY resumed that
the vendor stack does not, and the named one is **`i2c 0-000c`, the `ak7375`
lens actuator** — the camera's focus motor, left runtime-resumed with nothing
using the camera. Its neighbour on the same bus, the `imx363` at `0-001a`, is
correctly `suspended`, which is what makes the actuator worth a look rather
than a general observation about the bus.

☠️ Do not read that address as the speaker amplifier: the `aw8898` is at
`4-0034`, on a different bus, and it has no runtime PM at all (`unsupported`),
so it cannot appear in this comparison either way. `0-000c` on `i2c-0` is the
CCI bus, and `media-ctl` names the entity outright (`ak7375 0-000c ... Lens`).

### ★ Measured 2026-08-13: holding the camera open costs about 100 mA

Three twelve-minute phases on the same discharge, cable out, display off, one
change between each, 72 samples apiece
(`2026-08-13_pmos_camera-hold-idle-cost.txt`):

| phase | state | median battery current |
|---|---|---|
| **A** | as found — wireplumber running and holding the camera | **166.3 mA** |
| **B** | wireplumber stopped outright | 80.3 mA |
| **C** | wireplumber running, its `monitor.v4l2` and `monitor.libcamera` disabled | **67.6 mA** |

**A → C is −98.7 mA, about 60 % of the idle draw**, and their interquartile
ranges do not overlap (A's p25 is 137 mA, C's p75 is 106 mA). B and C are
indistinguishable, which is the point of running C at all: it separates *the
camera being held* from *the session manager existing*. Stopping wireplumber
entirely saves nothing beyond releasing the camera.

That also accounts for most of the gap this section opened with. Ubuntu Touch
idled at 86 mA; pmOS with the camera released idles at 68 mA.

☠️ **What it is not, measured rather than assumed.** Two explanations were
tested and both failed:

* **not CPU** — wireplumber sits at 0 % with a load average of 0.06 in phase A;
* **not the clocks** — `clk_summary` is *identical* between phases A and C.
  The only persistent difference in the whole system is two regulators,
  `cam_af_2p85` and `cam_io_1p8`, and the `ak7375` runtime state.

So ~100 mA is flowing somewhere on a 2.85 V rail feeding a **voice-coil motor**
that is powered but not being asked to move. That is the remaining question, and
it is a question about the part rather than about the software.

☠️ **Disabling those monitors is a measurement, not a fix.** It removes the
camera from PipeWire, so no application can find it. The drop-in used here was
written into `~/.config/wireplumber/wireplumber.conf.d/`, never into the
package's own files, and removed again afterwards — the device is back to
normal, camera node present.

Where a real fix would go: `ak7375_open()` takes a runtime-PM reference, so
merely *opening* the subdev powers the motor, and libcamera's pipeline handler
keeps every device of a camera open for as long as the `CameraManager` lives.
Neither is obviously wrong on its own; together they mean a phone with a VCM
pays for an autofocus motor it is not using, whenever anything enumerates
cameras.

### How the lead was followed

Following the one address in the runtime-PM table the rest of the way turned it
into a named mechanism before any of it was priced:

* **wireplumber holds the camera open at idle** — it has `/dev/video0`,
  `/dev/media0` *and* `/dev/v4l-subdev17` (the actuator) open with nothing
  taking pictures, found by walking `/proc/*/fd`;
* `ak7375` takes a runtime-PM reference when its subdev is opened
  (`pm_runtime_resume_and_get` in `ak7375_open`), which is why the device reads
  `active` rather than the `suspended` its probe asks for with
  `pm_runtime_idle()`;
* and that reference keeps its supplies up: `cam_af_2p85` (2.85 V) and
  `cam_io_1p8` are both `enabled` with one user each on an idle phone.
  `cam2_dig_1p2` is `disabled`, which is what makes the other two worth
  noticing rather than a general statement about the camera.

That experiment is the one measured above.
