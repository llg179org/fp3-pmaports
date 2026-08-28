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
| **the ladder** (`night-ladder.sh` + `idle-ab.sh`) | N consecutive one-hour windows, unattended, on the phone. It survives a reboot (rung number on persistent storage), restores the charge input on **every** exit path, and stops at a capacity floor. Built 2026-08-26 after an eight-hour run was lost to an accidental power-off: the run was a transient `systemd-run --collect` unit, the rungs were in tmpfs, and the host was the only thing that knew it existed |
| **`ladder-summary.py`** | what a *night* cost, as against `idle-ab-fit.py`'s what an *hour* costs. Integrates I·V, because `current_now` is current and two runs over different parts of the pack cannot be compared in mA. ☠️ Sums the rungs rather than differencing the endpoints — the pack charges for the ~20 s between two rungs |
| **the start-point tie** (protocol, not a tool) | ☠️ Before a slot switch, on the UT side, **charge input OFF and the pack rested**, record `capacity` AND `voltage_now`; the first rung on the other system must open at that voltage. Without it the two ladders' start points are untied and the comparison inherits a 30-point gauge disagreement it cannot see. Charging inflates the reading — 4.379 V charging against 4.262 V the moment the input was cut, 117 mV of it the charger |
| **the coulomb counter, on one side only** | `cc_soc` + `full_uAh` exist on the 4.9 oracle and **not** on mainline. It is the only hardware-integrated charge measurement available anywhere on this device, and it is the reason the oracle can check an instrument that pmOS cannot |
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

The **matched ladders** that superseded all of the single-window comparisons are
in [`captures/`](captures/): `2026-08-26_ut-night-ladder/` (the oracle, 14:07 →
22:10) against `2026-08-26_pmos-night-ladder/` (23:10 → 07:13), eight one-hour
rungs each, `rung-{1..8}.txt` plus the run's own `ladder.log`. Summarise either
with `tools/ladder-summary.py <dir>/rung-*.txt`; the current numbers they yield
are in [`../README.md`](../README.md).

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

## Step 10 — the subtraction ran out, so the question changed

Steps 1 to 9 all had the same shape: name a consumer, remove it, price the
difference. That works while a consumer dominates. By 2026-08-14 it had stopped
working — ten daemons came out one after another and the floor did not move once,
and the CPU was already idle 99.7 % of the time. A subtraction that subtracts
nothing is not a failed measurement; it is a signal that the thing being looked
for is not in the set being subtracted from.

☠️ **And that null result turned out to be doubly worthless**, for a reason that
had nothing to do with the reasoning. Checked afterwards, the lens actuator was
powered throughout — `focus_absolute` stood at 930, so a single 152 mA consumer
sat under every one of those ten phases. Whatever each daemon was worth, it was
being measured against a total that one unmeasured device dominated. **Record the
state of the known large consumer in every sample, not once at the start**: this
run had a per-phase annotation for the daemon under test and none for the
actuator, which is exactly backwards.

## Step 11 — asking a different question, with a counter instead of a meter

The change that unstuck it was to stop asking *how many milliamps* and start
asking *what state is the chip in*. Those need different instruments: the first
needs a meter and a discharge, the second needs a counter and nothing else. The
second can be read with the cable in, while the phone charges, at any hour,
without a probe.

The counters were already there. `cpuidle` said the CPUs power-collapse 95 % of
the time. The genpd domains said both clusters sit in `cluster-gdhs` about 92 %
of the time and reach `cluster-power-collapse` **five times in twelve hours**,
against two million occasions the governor itself recorded as "could have gone
deeper". So the CPUs were not the problem and had not been for some time; the
level above them never went down.

☠️ **The obvious suspect was wrong, and cheap to exclude.** `cluster-pc` has a
700 µs exit latency, so a tighter latency constraint would forbid it exactly.
`/dev/cpu_dma_latency` reads unconstrained — and `tuned` holds that file open
without writing anything to it, which looks like a smoking gun in a process
listing and is not one. Read the aggregate value, not the list of openers.

## Step 12 — the instrument that was missing for everyone

One level further up, the RPM's own record of whether the SoC reached `vlow` or
`vmin` could not be read at all: `msm8953.dtsi` had no sleep-stats node, so
`/sys/kernel/debug/qcom_stats` did not exist. `CONFIG_QCOM_STATS` was already
enabled and the hardware was already there. **Only the description was missing,
and it had been missing for every msm8953 board in mainline, not just ours.**

Three sibling SoCs describe the same region, and the downstream msm8953 tree
independently agrees on it. The confirmation that the address is right is not the
absence of an error: it is that the driver names its records `vlow` and `vmin`
rather than printing garbage, because those names are read out of the region
itself.

The answer arrived within a minute of the reboot and reframed everything before
it: **zero, and still zero after four suspends of 60, 120, 300 and 600 s.** The
phone stops its CPUs and leaves the SoC up. Every milliamp counted in steps 1 to
9 was counted on a chip that never goes to sleep — which is why the PMIC's
10.4 mA threshold reads like a threshold from another device, and why the fuel
gauge's rest anchor could never fire.

☠️ **`Client Votes` looks like the answer to "who is holding it" and is not.**
It changes between consecutive reads of the same file. The field is an RPMh
concept; on this generation only `Count` and `Accumulated Duration` mean
anything. A field that moves when nothing moved is a field that is not measuring
what its name says.

## Step 13 — the lesson the earlier steps were teaching by omission

Every step from 1 to 9 measured *a consumer*. None of them asked whether the
platform was in the state where consumers matter. Both questions are legitimate
and they are not interchangeable — but the second one is far cheaper, needs no
probe and no discharge, and if it comes back "the chip is fully on", it explains
an entire page of numbers at once.

**Ask what state the machine is in before pricing what is running on it.**

## Step 14 — and then the machine turned out never to have been in that state

Step 13's own lesson, applied to Step 13. `/sys/power/suspend_stats/success` read
**0** after fifty minutes of uptime. The phone had never suspended — not once, in
any session on this page. Every number the investigation had produced, the 9 %
included, describes *runtime idle with a full phosh session alive*: `greetd`,
pipewire, wireplumber, five `xdg-desktop-portal`s, gvfsd, avahi, `wpa_supplicant`,
and a modem talking at 28 `smd-edge` interrupts a second.

`/sys/power/mem_sleep` offers only `[s2idle]`, which on this platform is *the*
suspend path and not a fallback for a missing one — a distinction that had been
read the other way round.

The consequence for the goal is larger than the consequence for the numbers.
**10 mA is a different regime, not a smaller figure inside this one.** The
subsystem bisect queued at the end of Step 12 would have carefully apportioned a
quantity nobody should have been trying to shave.

And s2idle works, which took two minutes to establish: 90 s requested through the
RTC wakealarm, 91 s slept, `success` 0 → 1 with `fail` 0, WiFi reassociating on
its own. The RTC's clock is stuck in 1970 for want of an `offset` nvmem cell, and
it was a perfectly reasonable guess that a clock which cannot be set has a dead
alarm too. The guess was wrong — an alarm is *relative* to the counter — and only
the probe could say so. ☠️ That is the thing to prove before an unattended leg
depends on it, not after.

## Step 15 — three instruments, one failure, and none of them read the driver

With the regime finally right, the question became easy to state and hard to
measure: what does the phone draw asleep? `current_now` has to be sampled and
nothing samples while userspace is frozen, so three successive instruments went
looking for something that survives the freeze. All three failed, and they failed
*the same way*.

| attempt | what it read | what it reported | what it actually measured |
|---|---|---|---|
| 1 | integrate `charge_now` | awake 209 mA, **asleep 0 mA** | an OCV estimator still walking down after USBIN was suspended; then a poll worker that does not run while frozen |
| 2 | `capacity` at both ends of 3 h asleep | **97 % → 97 %**, i.e. under 10 mA | the same worker, given ten pre-suspend samples and three post-resume ones |
| 3 | `voltage_ocv` at both ends | a 160 mV fall | an 8-deep, 30 s-polled ring average — five of its eight slots still pre-suspend 90 s after resume |

The common cause was in the driver the whole time. `adc-battery-helper.c` reads
the ADC only in its work function, and `capacity`, `charge_now` and `voltage_ocv`
are one number under three names. `voltage_now` and `current_now` call
`get_voltage_and_current_now()` on every sysfs read and are the only live pair.

Attempt 3 is the one worth keeping, because it did not look cached. It equalled
`voltage_now - current_now × 120 mΩ` *to the microvolt* at every snapshot, which
is exactly what an instantaneous load-compensated value looks like — and also
what a ring of eight identical readings from a quantised ADC under a steady load
looks like. **A value that reproduces the documented formula is evidence about
the formula, not about when it was evaluated.**

Two lessons, and the second is the expensive one:

- **Several attributes of one device are usually one measurement wearing several
  names.** They present as independent opinions, so agreement between them reads
  as corroboration when it is a tautology.
- **The same failure twice means the next instrument needs its source read, not
  its design improved.** Each attempt replaced a discredited attribute with a
  neighbouring attribute of the same driver without once opening it. Twenty
  minutes of reading would have skipped all three; instead it cost three legs,
  one of them three hours long.

What caught every one of them was the same thing: a **control window in a regime
whose answer was already known**. Attempt 1's awake window read 209 mA where
`current_now` reads 130. Attempt 2's 97 % was contradicted by its own voltage. An
instrument aimed solely at the regime nothing can cross-check is unfalsifiable by
construction.

The constructive half, now in [`../suspend-slope.sh`](tools/suspend-slope.sh):
prefer a **slope** to a difference whenever the endpoints are conditioned
differently — a pack still shedding surface charge at one end, polarisation after
a resume transient at the other, both pushing the same way — and calibrate that
slope against a directly measured current in a second phase, so the OCV table
never enters at all.

## Step 16 — the number arrives, and it is the ratio that matters

2026-08-17. The instrument built in step 15 finally ran a complete leg
(`post-pll-20260817`: 8 suspends of 900 s, every one `slept=901s`, then an awake
control of the same length). Phase A −15.92 mV/h against phase B's −41.18 mV/h
at a directly measured 155.3 mA gives **I_sleep = 60 mA**, ±10 or so — phase A's
fit is the weak one at r² = 0.80 over 23.6 mV of travel.

☠️ **On its own that number is barely an advance, and it is worth saying so.**
What this page already knew was an *upper bound* — 160 mV over three hours, from
which "suspend is not in the 10 mA regime" follows — plus one number, 116 mA,
that had to be withdrawn. Going from a bound and a retraction to 60 mA is an
increment, not a discovery. Four things make the leg worth its day, and none of
them is the digit.

**1. The ratio, not the absolute.** 130 mA awake against 60 mA asleep says that
**roughly half the draw survives freezing the kernel.** That is a fork in the
road, and until now this page could not say which branch it was on: whether
suspend saved 10 % or 90 % decided whether the remaining work was in userspace
or under it. It is under it. Wakeups, timers and daemons are all stopped in
phase A and the phone still draws 60 mA, so nothing is left to win by trimming
them — what remains is *supply*: regulators still enabled, the modem, and RPM
votes that never drop. Step 12's two-sided RPM diff is where that continues, and
it now has a number to be measured against instead of a bound.

**2. The PLL question is closed, and it was the actual blocker.** While it was
open that the `apcs-cpu0-pll` storm might be gated by pack voltage, **no power
measurement on this device could be trusted** — that is precisely why 116 mA was
withdrawn in step 15's wake. A ramp of 26 points from 4.318 down to 3.931 V put
255 failures in 351 325 transitions (7.3 per 10 000) with a fitted change of 3.9
against an uncertainty of 2.9, and what slope there is runs the *wrong* way for
the sag hypothesis. So: not voltage-gated. Two consequences, both practical — a
leg cannot be protected by scheduling it at a full pack, and every leg must
therefore carry its own failure count, which `suspend-slope.sh` now does on
every sample. This leg proved the point immediately: phase B took **137**
failures to phase A's **8**. The contamination that silently ruined the previous
run is now visible in the log while the run is happening. It also does not
invalidate the result, because `I_awake` and `slope_B` both come out of phase B
and a storm that inflates the draw inflates the slope with it — the quotient is
immune to first order. That immunity is the reason the calibration is against a
measured current rather than the OCV table, and it is the thing to protect if
anyone ever proposes to "simplify" the method by dropping phase B.
⚠️ The ramp covers 4.32 → 3.93 V only. The original sighting was at 3.82 V,
just under that edge, and nothing below 3.93 V has been measured.

**3. Three more instruments were caught lying**, none of them needed for this
number and all of them needed for the next. `journalctl -k -b` drops records of
the *running* boot: the `pll=` field went **down** across the phase boundary, 320
to 288, so it lies in the same direction `dmesg` did and every count on this page
is a lower bound. `syncstate-snap.sh` reached 13 of the 39 `state_synced` files
that exist and not one i2c device, so its clean result could not have seen the
thing it was aimed at. And the tarball-reachability check that guards published
commits answered 302 for *every* hash, including a bogus one, because it was
written without `curl -L`.

**4. The front of the day was not a choice.** The phone did not boot — an
`fw_devlink=off` left in `extlinux.conf` hung it before the USB gadget came up,
so nothing host-side could reach it. That time bought a general escape route
rather than a power result: the UBports recovery's root adb, plus `losetup -o`
on the embedded msdos table in `system_b`, makes anything on disk fixable
without booting pmOS at all. See [`../../deploy/README.md`](../../deploy/README.md).

What the day did **not** buy: the amplifier case moved from open to narrower,
not to solved, and an hour went into a `fastboot boot` dead end that the
known-good control — booting the image that is known to work, by the same path —
would have closed in five minutes.

## Every claim on this page that had to be retracted

| the claim | what disproved it |
|---|---|
| "pmOS burns twice the current because it never suspends" | the camera hold accounts for the gap between two awake phones; and pmOS suspends fine when asked. ☠️ **Read the retraction narrowly: the MECHANISM was wrong, and the number came back.** Measured 2026-08-28 through the pack's own discharge curve, pmOS really does move ~2× the charge of the oracle over a matched eight hours — but not for the reason claimed here, and not in `current_now`, which is where this claim was looking |
| "`suspend_stats/success = 0` proves it did not sleep just now" | the counter is since boot, and the slot had just rebooted. Differencing it across a window is the fix |
| "wall clock against `/proc/uptime` shows whether it slept" | `/proc/uptime` is boottime and includes suspended time; across a proven 60 s sleep it read 71 s against 71 s |
| "Ubuntu Touch does not suspend either" | not disproved — **withdrawn**, because its only evidence was that broken comparison. It wants re-measuring on the oracle slot |
| "UT cooled ten degrees, so it was doing less" | UT ran overnight, pmOS ran on a summer day |
| "the resumed i2c device is the `aw8898` amplifier" | `media-ctl` names it: `ak7375 0-000c ... Lens`. The amplifier is on another bus with no runtime PM |
| "the two camera regulators are the cost" | held as a candidate rather than a finding, and then confirmed the cheap way: splitting the hold put all of it on the actuator and none on the rest of the chain |
| "the next step is to measure the 2.85 V rail" | it was not — the phases that priced the hold could also split it, with no probe and nothing built |

| "the floor is 139-143 mA with the camera released" | the camera was **not** released - `focus_absolute` was 930 and the actuator was powered, so the daemon subtraction under it proves much less than it appeared to |
| "the next step is the ak7375 runtime-PM reference" | already shipped: `fa5d294c`, which r53 pins, is that change. The driver holds the coil correctly for a commanded position; what is missing is anything that returns the lens to rest |

| "the ~130 mA is the idle baseline" | it is the *runtime* idle baseline. The phone had never suspended — `suspend_stats/success` was 0 after fifty minutes of uptime |
| "s2idle is a fallback here for a missing deeper state" | it is the only entry `mem_sleep` offers, and it is the suspend path. Proven working: 91 s slept for a 90 s alarm |
| "a µAh-valued attribute counts charge" | there is no coulomb counter. `charge_now` is `capacity × charge_full / 100`, and `capacity` is an OCV table lookup. ☠️ **Refined 2026-08-20**, and the refinement nearly became a third retraction: `charge_now` *does* move while the integer `capacity` stands still, in multiples of 306 µAh = 0.01 % of `charge_full`, so the underlying value has a hundred times the resolution sysfs shows. It is still not charge: over one 582 s discharge `dQ/dt` gave **85.2 mA** against **62.0 mA** from medianed `current_now`, 37 % apart in the direction IR sag predicts. Fine resolution, wrong quantity |
| "capacity did not move over 3 h asleep, so the phone drew under 10 mA" | the poll worker that maintains it does not run while userspace is frozen. It never had a chance to move |
| "`voltage_ocv` is instantaneous — it matches `v - i·R` to the microvolt" | it is an 8-deep 30 s ring average. Matching the formula says the formula is right, not that it was evaluated now |
| "after hours asleep the pack is relaxed, so both endpoints are comparable" | the snapshot happens *after* resume, not while asleep. The second endpoint was read 90 s after a 725 mA resume transient |

| "s2idle only halves the draw because the SoC never reaches VDD_MIN / XO shutdown" | the system power domain *does* collapse under s2idle — genpd counts those entries in their own column, and it goes 0 → 1 around a suspend. The halving needs another explanation |
| "count PLL failures with `dmesg \| grep -c`" | the ring wraps: two reads twenty minutes apart on one boot returned 35 then 34. A loud enough storm evicts its own evidence |
| "then count them from `journalctl -k -b`, which is durable" | it is not. The count fell from 320 to 288 across a phase boundary of the same boot. Take a cursor at the start of the leg and read forward from it |
| "`syncstate-snap.sh` came back clean, so `sync_state()` is not the amplifier's problem" | the conclusion happens to have held, but that run saw 13 of 39 files and no i2c device at all. A null result from an instrument that does not cover the question is not evidence |
| "the tarball check passes, so the pinned commit is still reachable" | without `-L`, GitHub answers 302 for every hash including `deadbeef…`. The check had never once been shown failing |

Added 2026-08-19/20, when the search moved into the RPM masters. The full account
is in [`findings-log.md`](findings-log.md) and
[`leads/lpass-never-sleeps.md`](leads/lpass-never-sleeps.md):

| claim | what it turned out to be |
|---|---|
| "a master that never shuts down is a **sufficient** explanation for `vlow` reading 0" | half wrong, and measured so. LPASS was made to collapse for the *whole* of every suspend and `vlow` did not move. Necessary, not sufficient |
| "stopping the ADSP outright and seeing no LPASS shutdown is a negative result about who holds it" | the stage could not have succeeded either way: the counter counts *handshakes*, and a halted subsystem performs none. It is absent, not asleep |
| "five PMIC rails vote active and never sleep" | four of the five were the USB PHY's, and the census was taken with a cable in the phone. With the controller unbound, one remains — the eMMC's, which cannot be dropped |
| "USB is what stops the audio DSP collapsing" | three alternating rounds, `LPASS +0` on both arms. The one observed collapse had a different cause: the ADSP had been restarted ten minutes earlier |
| "the held ADSP session is the deep-sleep lever" | the leg prices it at ~4 %, against a baseline that reproduces to 1.4 %. A real mechanism worth almost nothing |
| "`ip link add … type rmnet mux_id 1` returned `Invalid argument`, so the kernel refuses it" | the device's `ip` is **busybox**, which never sent the mux-id attribute. Real `iproute2` did it first time. ☠️ A negative from the wrong tool |
| "the package search page says those packages are not in Alpine" | it says so because the scrape was wrong. The APKINDEX has them. ☠️ A failed query is not a negative result |

Added 2026-08-25/27, when the comparison against the oracle was rebuilt. The
full account is in [`findings-log.md`](findings-log.md):

| claim | what it turned out to be |
|---|---|
| "the oracle's floor is 15.3 mA, so pmOS draws 3.5× what it should" | **withdrawn.** One window, 2026-08-24. An eight-rung ladder over 94 % → 69 % put the oracle's floor at 69–77 mA throughout, and rung 5 covers exactly that capture's 4.050 V at 71.0 mA. The goal had been scored against an outlier for two days |
| "the spread in the oracle's readings tracks state of charge" | it does not, and the ladder was built to decide it inside one boot, one cable state, one instrument. Over 25 points of charge and 295 mV neither the floor nor the integrated draw moves. ☠️ The threshold version — "it only lets go lower down" — died on the same data |
| "`s3` and `s4` are enabled on ours with the panel dark, so there is a rail difference" | `regulator_summary` is a **tree**: the indented rows are child regulators, not only consumers. `s3` is up because its child `l3` is (USB PHY), `s4` because `l5` (eMMC I/O) and `l7` (USB PHY PLL) are. Leaf for leaf the rail sets match |
| "the oracle's idle numbers describe the phone with its screen off" | they never did. It never blanks on its own, `setScreenPowerMode("off")` returns `true` with the panel still powered, and `fb0/blank` is half a blank — the LCDB bias rails stay at 5500 mV. ☠️ And the instrument written to fix it, `press-power-key.py`, **switched the phone off** rather than blanking it |
| "pmOS costs 19.5 % more over a night" | in current, yes; in **energy, 12.9 %**. The two ladders ran over different parts of the pack, and at a lower pack voltage the same power draws more current. 6.6 points of the gap were the discharge curve. ☠️☠️ **And the replacement was wrong too, retracted 2026-08-28:** energy is `current_now` × `voltage_now`, so it inherits `current_now`'s fault, and on the oracle that integral is contradicted by the phone's own coulomb counter by 2.056× — sampling wakes a phone that would otherwise sleep. Converted through the pack's **measured** curve, the two ladders are 623–651 mAh against 1308–1335 mAh: **~2×**, not 12.9 %. Two corrections deep, and the thing that settled it was the cell, not another integral |
| "the 94 % → 87 % gap at the start of the pmOS ladder is the boot and two probe rungs" | the arithmetic kills it: 7.2 points is 220 mAh, needing **1202 mA for 11 minutes**, where idle costs 0.9 and even an implausible 800 mA boot costs 4.8. The voltage mapping stands; the time-based justification attached to it was wrong. ☠️ Retracted an hour after publishing it |
| "a constant `voltage_now` offset between the two systems would explain the contested start" | it would not: the +90 mV that puts the start at 93 % puts the end at ~44 %, where 33.5 % was measured. Whatever it is, it is not a fixed calibration bias |
| "the two ladders started from the same pack state because both began at ~94 / 92 %" | the gauges are **30 points apart**, so two similar percentages are not a shared state. The start points were never tied by a measurement, and that is now a protocol step rather than an argument |
| "integrated `current_now` is a charge measurement" | on the oracle it can be checked, and it is **2.056× the coulomb counter** over the same eight hours — too large to be sampling shortfall, which under-counts. The likeliest reading is that the sampling itself wakes the phone. ☠️ On pmOS there is no counter, so this cannot be checked at all. ✅ **Settled 2026-08-28 by a third handle**: the pack's measured voltage→charge curve puts that oracle ladder at 623–651 mAh, beside the counter's 501 and the integral's 1031 — the integral is the outlier, and every figure derived from it was inflated on the oracle side |
| "the panel-off write fails on pmOS — `dpms: Permission denied` proves it" | it proves nothing: the script's `-w` test always says yes to root, so the message is noise. The panel goes down immediately (`bl_power=4`, `dpms=Off`, `waited=0s`). ☠️ The run that "showed" the failure had been killed by the observer's own 200 s timeout, mid-way through a 240 s wait |

## Where the story continues

This page stops at Step 16, and deliberately: it is the narrative of how the
*idle* current was localised, and it is not revised when the device changes.
Everything after it — the RPM handshake, the masters, the LPASS chapter, the four
branches that closed on 2026-08-19 — is in
[`findings-log.md`](findings-log.md), which is the dated record in the order it
happened. The questions still live are one page each under
[`leads/`](leads/README.md), the instruments are in [`tools/`](tools/README.md),
and the unattended harness that now runs the long legs is
[`night/`](night/README.md).

☠️ **If you are picking the work up, none of those is the entry point.**
[`../../STATUS.md`](../../STATUS.md) + [`../../TODO.md`](../../TODO.md) are: they say what is running on the device right now and
what to do next, and it is the only page that does.

## What is still open here

Deliberately not listed on this page. See [`../README.md`](../README.md) for
where the numbers stand and [`../../TODO.md`](../../TODO.md) for the rest —
including the direct rail measurement, and the suspend experiment that must not
be run unattended.
