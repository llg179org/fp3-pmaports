# Finding out where the FP3's idle current goes

> ⚠️ **AI-generated.** This page — and the measurements, scripts and analysis it
> describes — was written by Claude (Opus 5) working under the direction of
> Lajosházi, László Gergely, who reviewed every change and made or reviewed
> every measurement it rests on.

The investigation behind [`../README.md`](../README.md), kept as a narrative:
what was believed at each step, what was measured, and what that forced us to
conclude — including two hypotheses that were held with confidence and then
disproved, and one device that was named wrongly. The reference material — what
the numbers are today, which files hold them, how to repeat any of it — is in
the README; this is the reasoning.

> **Where things stand is deliberately not on this page.** What the phone draws
> today is in [`../README.md`](../README.md); what is still open is in
> [`../../TODO.md`](../../TODO.md). This is a record of how the current
> understanding was arrived at, and it is **not** revised when the device
> changes.

## Why this one is a subtraction story

There was nothing broken to find. Every subsystem involved worked: the phone
idled, the gauge reported, the camera took pictures. The question was only
*where a number went*, and a number that large hides comfortably inside a
working system.

That shapes the method. You cannot bisect a fault that does not exist, so the
whole investigation is **matched pairs**: the same protocol on two operating
systems, then the same phone with one thing changed. Nearly every wrong turn
below came from reading a single-sided observation as if it were a difference.

## The instruments

| what | how, and what it is good for |
|---|---|
| **`powerlog-pmos.sh` / `powerlog-ut.sh`** | one line a minute, identical fields on both operating systems, so a night on one can be laid against a night on the other. In the [FP3 skills](https://github.com/llg179org/Claude-skills-Fairphone3) repository; their output is in [`../`](../README.md) |
| **the oracle slot** | slot_a runs Fairphone's own 4.9 kernel on the same hardware and the same pack. Any "is this normal?" question about the phone has an answer 80 seconds away, across `fastboot set_active` |
| ~~the two clocks~~ | ☠️ **retracted, see Step 2a.** Wall clock against `/proc/uptime` cannot detect a suspend: `/proc/uptime` reports boottime, which includes suspended time |
| **the suspend counter, differenced** | `/sys/power/suspend_stats/success` read before and after a window. The delta is sound; the absolute value is not, since it counts from boot |
| **`dmesg`'s PM lines** | the `PM: suspend entry (s2idle)` / `PM: suspend exit` pair. The printk clock stops while suspended, so the sleep does not appear as a gap — the pair itself is the evidence |
| **runtime PM state, both sides** | `/sys/bus/*/devices/*/power/runtime_status`, tallied on each OS. The totals are not comparable; the `active` **list** is |
| **`/proc/*/fd`** | which process is holding a device node open. This is what turned "a device is resumed" into "wireplumber is holding it" |
| **regulator debugfs / sysfs** | `enabled`/`disabled` and the user count per rail, which says whether a runtime-PM reference is costing anything real |
| **`clk_summary`** | a whole-system clock tree snapshot, diffed between phases. Cheap, and it excludes an entire class of explanation in one comparison |
| **`systemd-run --unit=… --collect`** | how a long unattended capture is started over SSH. ☠️ `setsid nohup … &` under `sudo -S sh -c` dies when sudo exits — that mistake cost one A/B its second sample onwards |

## Raw data

All of it in [`../`](../README.md), which says what each file is worth:
`2026-08-11_ut_discharge-charge.txt` and `2026-08-12_pmos_idle-discharge.txt`
are the matched nights, `2026-08-13_pmos_camera-hold-idle-cost.txt` is the
three-phase experiment that ends this page.

---

## Step 0 — the premise, and how it was made comparable

The starting observation was that the phone felt like it drained faster on
postmarketOS than on Ubuntu Touch. That is not a measurement, and the first
piece of work was turning it into one: the same logger fields on both stacks,
the same idle definition (display off, WiFi associated, one SSH session), and a
window on each side long enough to integrate — 6.66 hours, matched.

| | Ubuntu Touch | postmarketOS |
|---|---|---|
| integrated charge | 571 mAh | **1319 mAh** |
| mean current | 86 mA | **198 mA** |
| reported percentage | −6 points | −36 points |

☠️ **The percentage column is not evidence of anything.** The two run different
gauges; −6 against −36 measures the *gauges*, not the phone. The row that
carries the argument is the integrated charge, because both sides integrate the
same PMIC's current sense.

☠️ **And one difference was cited as evidence that could not be.** Ubuntu Touch
cooled ten degrees over its night; pmOS cooled half a degree. That was written
down as a corroborating observation before noticing that the UT run happened
overnight and the pmOS run happened during a summer day. A quantity the room
controls says nothing about the device.

## Step 1 — the obvious hypothesis: it never sleeps

`/sys/power/suspend_stats/success` read **0** on pmOS, with `fail` also 0. Not
blocked, not failing — never attempted. The reason was in the session settings
rather than the kernel: `sleep-inactive-battery-type = 'nothing'`, so nobody
asks.

☠️ **Not the power profile.** The "performance / balanced / power saver" control
in the UI comes from `tuned` here (`power-profiles-daemon` is not even
installed), and it sets CPU policy only. That was checked before it could become
part of the story.

At that point the case looked closed: one phone sleeps, the other does not,
2.3×. The only thing missing was confirming the other half — which is the half
that mattered.

## Step 2 — the oracle killed it

Measured on `slot_a`: **Ubuntu Touch does not suspend either.**

The counter could not have said so. `suspend_stats/success` counts since boot,
and the slot switch had just rebooted the phone, so a 0 there proves only that
the phone booted recently. This is a general trap and worth stating as one: *a
since-boot counter is not an instrument for a question about a state you just
entered.*

So a second instrument was reached for: the two clocks. Wall clock against
`/proc/uptime`, on the theory that `CLOCK_MONOTONIC` does not advance across a
suspend, so a sleeping phone shows less uptime than wall time. Two samples five
minutes apart on UT, display off, nothing but SSH:

```
1786567461 436
1786567491 466      # 30 s of wall clock, 30 s of uptime — awake the whole way
```

Neither kernel offers `/sys/power/autosleep` at all. The vendor one has the
Android wakelock interface (`/sys/power/wake_lock`, owned by `radio`) and would
suspend if a userspace daemon asked; nothing does.

That reading — **two awake phones, one of which costs more to keep awake** —
shaped everything after it. It also contains a defect, found much later.

## Step 2a — ☠️ that second instrument cannot work either

`/proc/uptime` does **not** report `CLOCK_MONOTONIC`. `fs/proc/uptime.c` calls
`ktime_get_boottime_ts64()`, and boottime *includes* time spent suspended. So
the comparison cannot distinguish a sleeping phone from a waking one in either
direction: uptime tracks wall clock regardless.

It was caught by running the experiment the other way round — deliberately
suspending pmOS for 60 s with `rtcwake -m mem -s 60`, with the sleep proved by
`suspend_stats/success` going 0 → 1 and by a `PM: suspend entry (s2idle)` /
`PM: suspend exit` pair in `dmesg`. Across that known sleep: **71 s of wall
clock, 71 s of uptime.** A test that reads the same on a phone that definitely
slept and on one that definitely did not is not a test.

What survives and what does not:

* **pmOS not suspending on its own stands**, because it never rested on the
  clocks: nothing asks it to (`sleep-inactive-battery-type = nothing`), and
  asked explicitly it suspends and resumes cleanly.
* **The Ubuntu Touch half is withdrawn** until it is measured again with the
  counter differenced across a window, or with `dmesg`'s PM pairs.

The lesson is not "check the clock source" but something more annoying: this
instrument was invented to replace one that had just been caught being wrong
(Step 2's counter), and it was adopted **without being validated against a known
positive**. A detector nobody has shown firing is not evidence of absence — and
firing it deliberately, once, is usually cheap.

## Step 3 — the same two-sided diff, applied to runtime PM

The instrument that had just found a charger bug was a two-sided register diff.
The equivalent here is runtime PM state, tallied on both slots:

| | Ubuntu Touch | postmarketOS |
|---|---|---|
| devices `active` | 8 | **17** |
| `suspended` | 65 | 46 |
| `unsupported` | 719 | 293 |

☠️ **Only one of these three rows is usable.** The vendor kernel enumerates far
more devices, so `unsupported` and even `suspended` compare nothing. The
`active` list compares, because it is short and every entry is nameable.

Ours keeps two i2c buses and a USB PHY resumed that the vendor stack does not.
The one that could be named was `i2c 0-000c`, runtime-resumed with nothing using
it, while its neighbour on the same bus was correctly `suspended` — and that
asymmetry, on one bus, is what made it a lead rather than an observation about
buses in general.

## Step 4 — and the device was named wrongly

`0-000c` was first written down as the `aw8898` speaker amplifier. It is not.
The amplifier is at `4-0034`, on a different bus, and it has **no runtime PM at
all** (`unsupported`), so it could not appear in this comparison in either
direction. `i2c-0` is the CCI bus; `0-000c` is the **`ak7375` lens actuator**,
and `media-ctl` had been printing its name the whole time
(`ak7375 0-000c ... Lens`).

The lesson is narrow and cheap: an i2c address is not an identity. The tool that
enumerates the subsystem will say the name; ask it instead of recalling which
chip lives at which address.

## Step 5 — from a resumed device to a mechanism

A device being `active` is not yet a cost. Three questions turned it into one,
and none of them needed a kernel build:

* **who is holding it?** Walking `/proc/*/fd` found **wireplumber** with
  `/dev/video0`, `/dev/media0` *and* `/dev/v4l-subdev17` — the actuator — open,
  with nothing taking pictures.
* **why does opening it resume it?** `ak7375_open()` calls
  `pm_runtime_resume_and_get()`. Merely opening the subdev powers the motor,
  which is why the device reads `active` despite its probe ending in
  `pm_runtime_idle()`.
* **does that cost power?** `cam_af_2p85` (2.85 V) and `cam_io_1p8` are both
  `enabled` with one user each on an idle phone. `cam2_dig_1p2` is `disabled`,
  which is what makes the other two worth noticing rather than a general remark
  about the camera being wired up.

That is a complete chain from a session manager to two energised rails. What it
is not is a number.

## Step 6 — pricing it, and why there were three phases

The temptation here was to stop: the mechanism is plausible, the fix is obvious,
write it up. But "plausible mechanism" is exactly what the charger work had
already been burned by twice, so the chain was priced instead.

Three twelve-minute phases on one discharge, cable out, display off, 72 samples
each, **one change between each**:

| phase | state | median battery current |
|---|---|---|
| **A** | as found — wireplumber running and holding the camera | **166.3 mA** |
| **B** | wireplumber stopped outright | 80.3 mA |
| **C** | wireplumber running, its `monitor.v4l2` and `monitor.libcamera` disabled | **67.6 mA** |

**A → C is −98.7 mA**, and the interquartile ranges do not overlap (A's p25 is
137 mA, C's p75 is 106 mA).

☠️ **Phase C is the whole design.** B alone would have proved nothing: stopping
wireplumber removes the *audio* session manager too, so a saving there is
attributable to either. C keeps wireplumber running and takes away only its
camera monitors. B and C being indistinguishable is what pins the cost on **the
camera being held**, and it also says the session manager itself is free.

It also closes Step 0's gap. Ubuntu Touch idled at 86 mA; pmOS with the camera
released idles at 68 mA.

☠️ **The drop-in is a measurement, not a fix.** Disabling those monitors removes
the camera from PipeWire, so no application can find it. It was written into
`~/.config/wireplumber/wireplumber.conf.d/`, never into the package's files, and
removed again afterwards.

## Step 7 — what it is not

Two candidate explanations were tested rather than argued about, and both
failed:

* **not CPU** — wireplumber sits at 0 % with a load average of 0.06 during
  phase A. Whatever is spending the current is not executing instructions.
* **not the clocks** — `clk_summary` is **identical** between phases A and C.
  A whole class of "something is left clocked" explanations dies in one diff.

What survives is two regulators and one runtime-PM reference. Which leaves the
finding with a hole in it, and the honest thing is to state the hole: about
100 mA is flowing on a 2.85 V rail into a **voice-coil motor that nobody is
asking to move**. The saving is measured and reproducible; the physics of it is
not explained. Ohm's law on a VCM coil is a plausible story and remains a story
until the rail is measured directly.

## Step 8 — splitting the hold, before reaching for a probe

"Two regulators and a runtime-PM reference" is three suspects, and the note
written at the time said the next move was to measure the 2.85 V rail directly.
It was not — because the same three phases that priced the hold can also **split**
it, with nothing built and no instrument beyond the gauge already in the PMIC.

The trick is to stop using wireplumber as the holder. A shell can open a device
node and sit on it — `sh -c 'exec 3</dev/v4l-subdev17; sleep 100000'` — which
makes the hold arbitrarily selective. So: nothing held; the actuator's subdev
alone; and the entire rest of the chain *without* the actuator.

| phase | what is held open | median current | median power |
|---|---|---|---|
| **P0** | nothing | 79.7 mA | 0.342 W |
| **P1** | **`/dev/v4l-subdev17` alone** — the `ak7375` | **152.4 mA** | **0.643 W** |
| **P2** | `media0`, `video0`, CSIPHY/CSID/ISPIF/VFE, `imx363` — everything **but** the actuator | 76.4 mA | 0.323 W |

P2 lands on P0. The sensor, the CSI receiver and the VFE front end cost
**nothing measurable** while merely open; the entire hold cost is one lens
motor, +0.30 W on its own. Each phase logged its own state as it started, and
those agree with the currents: `ak7375=active` with both camera rails `enabled`
in P1, `suspended` and `disabled` in P0 and P2.

☠️ **Compare these against the earlier phases in power, not in current.** They
ran at a different state of charge, and the same power draws less current at a
higher terminal voltage — reading 152 mA against the earlier 166 mA as a
*change* would be reading the battery, not the camera.

What this leaves is a much smaller question than the one Step 7 handed over:
not *which of three things*, but why a voice-coil motor that is powered and
commanded nowhere dissipates a third of a watt. And it moves the fix into one
driver: `ak7375_open()` takes the runtime-PM reference and only
`ak7375_close()` drops it, so the motor is up for as long as any descriptor
lives.

☠️ **"Add an autosuspend delay" is the wrong first instinct here**, and it is
worth spelling out because it sounds right: autosuspend acts when a device
becomes idle, and this one never does — the reference is held for the lifetime
of the open. The change has to be to *where the reference is taken*.

## Step 9 — two biases that had to be named

Neither invalidates the comparisons, because both apply identically on both
sides — the *difference* survives, the absolute figure does not:

* **the logger biases its own numbers.** It wakes once a minute and reads the
  current while it is itself awake and running, so its mean is high.
* **"idle" here means idle with the link up.** Every capture ran with WiFi
  associated and SSH open, because that is how the data got off the phone. None
  of these is a measurement of a sleeping phone.

---

## Every claim on this page that had to be retracted

| the claim | what disproved it |
|---|---|
| "pmOS burns twice the current because it never suspends" | the camera hold accounts for the gap between two awake phones; and pmOS suspends fine when asked |
| "`suspend_stats/success = 0` proves it did not sleep just now" | the counter is since boot, and the slot had just rebooted. Differencing it across a window is the fix |
| "wall clock against `/proc/uptime` shows whether it slept" | `/proc/uptime` is boottime and includes suspended time; across a proven 60 s sleep it read 71 s against 71 s |
| "Ubuntu Touch does not suspend either" | not disproved — **withdrawn**, because its only evidence was that broken comparison. It wants re-measuring on the oracle slot |
| "UT cooled ten degrees, so it was doing less" | UT ran overnight, pmOS ran on a summer day |
| "the resumed i2c device is the `aw8898` amplifier" | `media-ctl` names it: `ak7375 0-000c ... Lens`. The amplifier is on another bus with no runtime PM |
| "the two camera regulators are the cost" | held as a candidate rather than a finding, and then confirmed the cheap way: splitting the hold put all of it on the actuator and none on the rest of the chain |
| "the next step is to measure the 2.85 V rail" | it was not — the phases that priced the hold could also split it, with no probe and nothing built |

## What is still open here

Deliberately not listed on this page. See [`../README.md`](../README.md) for
where the numbers stand and [`../../TODO.md`](../../TODO.md) for the rest —
including the direct rail measurement, and the suspend experiment that must not
be run unattended.
