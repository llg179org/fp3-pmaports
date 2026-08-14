# Power on the Fairphone 3

> ⚠️ **AI-generated.** These pages, and the code and measurements they describe,
> were written by Claude (Opus 5) working under the direction of Lajosházi,
> László Gergely, who reviewed every change and made or reviewed every
> measurement they rest on.

What this phone draws under a mainline kernel, how that compares with the vendor
stack on the same hardware, and the raw captures every one of those numbers came
from — kept because the conclusions are only as good as the data, and because a
host reboot has already eaten one of these files once.

**How this was worked out is not on this page.** The investigation — the two
hypotheses that were held with confidence and then disproved, and the one device
that was named wrongly — is in [`bringup/`](bringup/README.md). This page is the
reference; that one is the reasoning, and it is not revised when the device
changes.

## Where the numbers stand

Idle here means display off, WiFi associated, one SSH session open. It is not a
measurement of a sleeping phone, and neither operating system sleeps.

| | draw |
|---|---|
| pmOS, as a stock image ships it | **166 mA** |
| pmOS, with the camera released | **68 mA** |
| Ubuntu Touch, same protocol | 86 mA |
| what releasing the camera is worth | **−98.7 mA**, about 60 % of idle |

☠️ **Percentages are not comparable between the two.** They run different
gauges. Over one matched 6.66 h idle window the vendor gauge reported 6 points
against 571 mAh integrated, and ours reported 36 points against 1319 mAh.
Compare integrated current and terminal voltage; treat the percentage as a
measurement *of the gauge*.

**pmOS does not suspend on its own here, because we asked it not to.** Automatic
sleep works and was demonstrated on this base; it is switched back off because an
incoming call cannot wake the phone, and a missed call costs more than 140 mA
does. `sleep-inactive-battery-type` is `'nothing'`; neither kernel offers
`/sys/power/autosleep`. The whole finding is in
[Suspend works, and is switched off on purpose](#suspend-works-and-is-switched-off-on-purpose).

☠️ **The Ubuntu Touch side of that claim is withdrawn pending a re-measurement**,
because the instrument it rested on cannot work. It compared wall clock against
`/proc/uptime` on the theory that `CLOCK_MONOTONIC` does not advance across a
suspend — but `/proc/uptime` does not report `CLOCK_MONOTONIC`. It calls
`ktime_get_boottime_ts64()`, and boottime **includes** time spent suspended, so
uptime tracks wall clock whether the phone slept or not. Verified against a
suspend we know happened: 71 s of wall clock, 71 s of uptime, across a
demonstrated 60 s sleep.

**What does answer "did it sleep?"**, in order of cost:

* `/sys/power/suspend_stats/success` read **before and after** the window — the
  delta is valid; the absolute number is not, since it counts from boot;
* `dmesg | grep 'PM: suspend'` — the `entry (s2idle)` / `exit` pair. Note the
  printk clock stops while suspended, so a 60 s sleep shows as a fraction of a
  second between the two lines. The pair is the evidence, not the gap.

## What the remaining floor is not

Measured 2026-08-14, with the camera already released. The floor is **139 to
143 mA**, and two whole categories of explanation are excluded:

* **Not userspace.** Ten daemons were stopped cumulatively —
  `iio-sensor-proxy`, `snsregd`, `ModemManager`, `bluetooth`, `avahi-daemon`,
  `cups`, `tuned-ppd`, `tuned`, `sleep-inhibitor`, `upower` — never restoring
  between phases, 120 s per phase. The floor did not move for any of them, and
  the means wandered non-monotonically and ended where they started. Consistent
  with the CPU total: 6.6 s of userspace time over 285 s across 8 cores, **0.3 %
  of the machine**.
* **Not the power profile.** `tuned` and `tuned-ppd` are the daemons behind
  Settings → Power Mode (`power-profiles-daemon` is not installed). Stopping both
  left the floor at 140.2 and 139.3 mA. Structurally it could not have helped:
  power saver caps CPU frequency, and the CPU is at 0.3 %.

What is left is wakeups rather than load: **143 timer IRQ/s, 134 IPI/s, 118
timer-broadcast/s, 33/s `smd-edge`**. That is where the next measurement should
go — together with the `ak7375` lens actuator, which
[on its own accounts for 152 mA](#measured-2026-08-13-it-is-the-lens-actuator-and-nothing-else)
whenever the camera stack holds it.

☠️ **A 60 s sampling interval invented a signal that is not there.** It showed a
tidy ~2-minute cycle in the current draw. At 5 s the cycle vanishes: the floor is
flat with irregular peaks, and the underlying periods are `systemd-oomd` ~5 s,
`sleep-inhibitor` and `fp3-voiced` ~10 s, `ModemManager` ~20 s, `tuned` ~25 s and
`upowerd` ~30 s — four different periods beating against the sampler. Sample
several times faster than the fastest thing you are willing to believe in.

☠️ **Stopping `upowerd` makes the UI report 0 %**, which looks exactly like a
gauge that has fallen apart. It is not: phosh sources the percentage from UPower
over D-Bus, while the kernel's own `fg:` log stays continuous and physical
throughout. Check the kernel log before believing a number on the screen.

## Holding the camera open costs about 100 mA

Measured 2026-08-13, three twelve-minute phases on one discharge, cable out,
display off, 72 samples apiece, one change between each
(`2026-08-13_pmos_camera-hold-idle-cost.txt`):

| phase | state | median battery current |
|---|---|---|
| **A** | as found — wireplumber running and holding the camera | **166.3 mA** |
| **B** | wireplumber stopped outright | 80.3 mA |
| **C** | wireplumber running, its `monitor.v4l2` and `monitor.libcamera` disabled | **67.6 mA** |

The interquartile ranges of A and C do not overlap (A's p25 is 137 mA, C's p75
is 106 mA). B and C are indistinguishable, which is the point of running C at
all: it separates *the camera being held* from *the session manager existing*.
Stopping wireplumber saves nothing beyond releasing the camera.

**The mechanism**, and why it is nobody's bug in particular:

* wireplumber holds `/dev/video0`, `/dev/media0` **and** `/dev/v4l-subdev17`
  open at idle, because libcamera's pipeline handler keeps every device of a
  camera open for as long as the `CameraManager` lives;
* `ak7375_open()` takes a runtime-PM reference, so merely *opening* the subdev
  powers the voice-coil motor — the upstream pattern for VCM drivers;
* which keeps `cam_af_2p85` (2.85 V) and `cam_io_1p8` `enabled` with one user
  each. `cam2_dig_1p2` is `disabled`, which is what makes the other two worth
  noticing.

Each is defensible alone; together they mean a phone with an autofocus motor
pays for it whenever anything enumerates cameras. A fix belongs in libcamera
(close subdevs when no camera is acquired) or in the actuator's autosuspend —
not in this repository.

☠️ **Two explanations were tested and failed**, so do not reach for them again:
it is **not CPU** (wireplumber at 0 %, load average 0.06 in phase A) and **not
the clocks** (`clk_summary` is *identical* between A and C).

☠️ **Disabling those monitors is a measurement, not a fix.** It removes the
camera from PipeWire, so no application can find it. The drop-in used here went
into `~/.config/wireplumber/wireplumber.conf.d/`, never into the package's own
files, and was removed afterwards.

### Measured 2026-08-13: it is the lens actuator, and nothing else

The hold was then split, to find out whether the cost is the actuator or the
rest of the camera chain. Three more twelve-minute phases on one discharge, the
nodes held open by a bare `sh -c 'exec 3</dev/…; sleep'` rather than by
wireplumber, so exactly one thing changes between them
(`2026-08-13_pmos_lens-vs-chain.txt`):

| phase | what is held open | median current | median power |
|---|---|---|---|
| **P0** | nothing | 79.7 mA | 0.342 W |
| **P1** | **`/dev/v4l-subdev17` alone** — the `ak7375` | **152.4 mA** | **0.643 W** |
| **P2** | `media0`, `video0`, CSIPHY/CSID/ISPIF/VFE and the `imx363` — **everything except the actuator** | 76.4 mA | 0.323 W |

**P2 is indistinguishable from P0, and P1 costs +0.30 W on its own.** The whole
of the camera-hold cost is the lens actuator; the sensor, the CSI receiver and
the VFE front end cost nothing at all while merely open. The phases carry their
own state annotations and they agree: `ak7375=active` with `cam_af_2p85` and
`cam_io_1p8` `enabled` in P1, `suspended`/`disabled` in both others.

Compare in power rather than current between runs — these phases sit at a
different state of charge from the ones above, and the same power draws less
current at a higher terminal voltage.

So the remaining question is no longer *which device*; it is why a VCM that is
powered but commanded nowhere dissipates ~0.3 W.

Where a fix goes is now specific. `ak7375_open()` takes a runtime-PM reference
and `ak7375_close()` is the only thing that drops it, so the motor stays up for
exactly as long as any file descriptor lives.

☠️ **An autosuspend delay would not help**, which is the first trap here: the
reference is *held*, not merely slow to expire, so the device never becomes idle
for autosuspend to act on.

☠️ **Nor can the reference simply move to the position write with a delay after
it** — the second trap, and a physical one. A voice coil holds a position only
while it is driven, so a timer that expires while a preview is focused would let
the spring pull the lens back to rest and the picture out of focus.

What works is to make the power follow the **requested position** rather than
the file descriptor: take the reference on the first position away from rest,
drop it when the lens is asked back to rest, where the spring holds it for
nothing. Focus is never lost, because a non-zero position keeps the reference;
the idle case costs nothing, because idle *is* the rest position.

### Measured 2026-08-13: with that change, holding the subdev is free

Same phases again, on a patched `ak7375` hot-swapped into the running kernel
(`2026-08-13_pmos_ak7375-position-power.txt`):

| phase | what is held open | median current | median power |
|---|---|---|---|
| Q0 | nothing | 82.4 mA | 0.327 W |
| Q1 | the `ak7375` subdev | 85.2 mA | 0.338 W |
| | **difference** | **+2.8 mA** | **+0.011 W** |

Against **+72.7 mA / +0.30 W** for the same pair on the stock driver. The phase
annotations agree: `ak7375` stays `suspended` and both rails `disabled` for the
whole of Q1, with the subdev open. Q0 at 0.327 W also lands on the earlier P0 at
0.342 W — two runs, different states of charge, same baseline, which is what
makes the comparison worth anything.

☠️ **Not yet validated end to end.** The autofocus regression — that a real
capture still focuses and holds focus — could not be run in the same session:
unbinding the subdev to swap the module left the media graph inconsistent
(`Failed to find MediaObject with id 0`) and libcamera stopped enumerating the
camera until a reboot. And `insmod` of a locally built module raised an
`ftrace_bug` warning, so the final word has to come from a package build rather
than a hot swap.

## Reading the captures

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

The loggers themselves (`powerlog-pmos.sh`, `powerlog-ut.sh`) are in the
[FP3 skills](https://github.com/llg179org/Claude-skills-Fairphone3) repository.

| file | what it holds |
|---|---|
| `2026-08-11_regs-pmos.txt`, `2026-08-11_regs-ut.txt` | the charger's CHGR, DCDC, BATIF, USB and MISC registers, 1280 of them, read on each OS with the same pack in the same state. 45 differed; `CHGR_CFG2` was the one that mattered |
| `2026-08-11_ut_discharge-charge.txt` | Ubuntu Touch: a night idle, a deliberate flash+camera load, then a full charge to termination |
| `2026-08-12_ut_terminates.txt` | the vendor stack reaching `TERMINATE` within a minute of the current crossing the threshold |
| `2026-08-12_pmos_iterm-fix-terminates.txt` | the same on pmOS, after `I_TERM_BIT` was left set — the single-change A/B |
| `2026-08-12_pmos_idle-discharge.txt` | pmOS idle, matched against the UT night |
| `2026-08-12_pmos_day-to-r51-termination.txt` | a day on pmOS ending in the first termination reached by the **packaged** kernel rather than by hand-deployed pieces: `linux-fp3-7.1.3-r51`, taper at 87 mA, then `Full` with `chgr_status_reg` at `0x45`. The uptime column resets partway through, at the reboot onto that package |
| `2026-08-13_pmos_camera-hold-idle-cost.txt` | the three-phase A/B/C above |
| `2026-08-13_pmos_ak7375-position-power.txt` | the same pair once more, with the driver patched so power follows the requested position: holding the subdev now costs 2.8 mA |
| `2026-08-13_pmos_lens-vs-chain.txt` | the follow-up three phases that split the hold: nothing held, the `ak7375` subdev alone, the rest of the chain without it |
| `2026-08-13_pmos_r52-charge-to-termination.txt` | a charge from 87 % to termination on `linux-fp3-7.1.3-r52`, over an SDP port (`usb_imax_uA` 500000, so ~340 mA into the pack). The taper crosses the threshold at **99.3 mA** and the charger is `Full` at `0x45` within the minute |
| `2026-08-14_pmos_resume-early-rest-anchor.txt` | a 300 s `rtcwake` suspend with the [parked](../charger/bringup/parked/README.md) `.resume_early` patch applied: the anchor fires and moves the reading 93.87 % → 91.00 % off a rested OCV. Kept because it is the evidence that the parked patch works, not that it ships |

## Two biases these numbers carry

Both apply identically on both sides, so the *difference* between two captures
survives them; an absolute figure does not.

* **The logger biases its own numbers.** It wakes once a minute and reads the
  current while it is itself running, so the mean it produces is high.
* **Idle means idle with the link up.** Every one of these ran with WiFi
  associated and an SSH session open, because that is how the data got off the
  phone.

## Suspend works, and is switched off on purpose

Everything needed is present: `/sys/power/state` offers `freeze mem disk`,
`mem_sleep` is `[s2idle]` (mainline qcom has no separate `deep`, which is
normal), `rtcwake` and `/dev/rtc0` work, and cpuidle has `WFI` plus
`cpu-power-collapse`.

☠️ **A first attempt on a new base must happen with someone holding the phone.**
On ports it is the *resume* that fails, and a phone that does not come back needs
a physical power-cycle. Run `rtcwake -m mem -s 60` once, in person, before
enabling automatic sleep anywhere.

**Run and passed on 7.1.3, 2026-08-14.** Both a 60 s `rtcwake` and, with the
phone in hand, real GNOME idle suspends of 116 s and 8 min: `PM: suspend entry
(s2idle)` … `exit`, `suspend_stats/success` incrementing with `fail` at 0, wake
on the power button, and WiFi re-associating unaided.

Then it was turned back off. `sleep-inactive-battery-type` is `'nothing'`, which
is **a decision, not a default that nobody looked at**:

* **An incoming call does not wake the phone.** Measured: across an 8-minute
  sleep the call arrived at the modem, the AP never woke, and on the button wake
  the queued event replayed — the dialer showed busy and closed. Of 151 IRQs only
  three are wake-armed (`wcn36xx_rx` and two thermal sensors). The modem's SMD
  edge, `irq 140` = `GIC-0 57` = the device tree's `GIC_SPI 25`, reads
  `wakeup=disabled`, and `drivers/rpmsg/qcom_smd.c` registers no wake IRQ at all,
  so there is not even a knob for it. Enabling the one knob that does exist,
  `smp2p-modem`, changed nothing — its counter did not move once across the whole
  sleep, which is what proves the call does not travel that line. See
  [`TODO.md`](../TODO.md).
* **SSH does not wake it either**, despite `wcn36xx_rx` being wake-armed: the
  connection times out with `No route to host` until the phone is woken by hand.
  Convenient for measurement — the logger cannot be contaminated by the observer
  — and a warning for anything that expects to reach the device while it sleeps.
* **The gauge gains nothing from it.** After a real s2idle, `S3_GOOD_OCV` and
  `LAST_S3_SLEEP_V` both still read `0x8000`. Suspending does not take this board
  under the PMIC's 10.4 mA S3 threshold, so the plan of *fix sleep and the gauge
  corrects itself* is measured dead. Twice, independently.

☠️ **The kernel clock stops during s2idle, so `dmesg` timestamps cannot measure
how long the phone slept.** An 8-minute sleep reads as 0.5 s between `suspend
entry` and `suspend exit`. The instrument that works is a wall-clock logger
writing to a file — run it under `systemd-run --unit=… --collect` so it survives
both the suspend and the SSH drop.
