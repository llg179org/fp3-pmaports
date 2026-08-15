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

## Measured 2026-08-14: the SoC never reaches an RPM low-power mode

This is the finding the rest of the page should be read against, and it sits a
layer above every milliamp counted below. **The RPM has not taken this SoC to
`vlow` or `vmin` once since boot — not while idle, and not during a ten-minute
suspend** ([capture](2026-08-14_pmos_rpm-sleep-stats.txt)).

Four `rtcwake` suspends of 60, 120, 300 and 600 s, all successful, wall clock
matching the request to within a second:

| | before | after four suspends |
|---|---|---|
| `qcom_stats/vlow` Count | 0 | **0** |
| `qcom_stats/vmin` Count | 0 | **0** |
| `cluster-pc` (genpd S2) usage | 0 | 5 |
| `cluster-pc` accumulated | 0 ms | **0 ms** |

The cluster does enter its power-collapse state, exactly once per suspend, and
records no residency in it. Meanwhile the RPM-level states are untouched. So
suspending this phone stops the CPUs and leaves the SoC up, which is why the
PMIC's 10.4 mA S3 threshold is never crossed and why `S3_GOOD_OCV` stays
`0x8000` — measured again here, still `0x8000` after all four.

The same shape shows in ordinary idle, without suspending at all. Over 43 566 s
of uptime both clusters sat in **`cluster-gdhs` about 92 % of the time** and
reached `cluster-power-collapse` **4 and 5 times**, against 1.66 and 2.03 million
occasions the governor recorded as "could have gone deeper". Per-CPU
`cpu-power-collapse` residency is 95 %, so the CPUs are not the problem; nothing
above them goes down.

☠️ **It is not a latency-QoS constraint**, which is the obvious first suspect
because `cluster-pc` has a 700 µs exit latency. `/dev/cpu_dma_latency` reads
2 000 000 000 µs, i.e. unconstrained. `tuned` holds the file open without writing
a constraint, which looks alarming in a process listing and means nothing.

☠️ **Do not read `Client Votes` as a vote mask here.** It changes between
consecutive reads (`0x15171517`, `0x13171317`, `0x17131713`) in a way no vote
aggregate would, and `vmin` reports `0x0` throughout. The field is meaningful on
RPMh, not on this generation. The `Count` and `Accumulated Duration` fields are
the ones that carry the finding.

### And the per-master records name the one that never goes down

The SoC-wide counters say the system stayed up; the RPM's per-master records say
who kept it there. Read on the same evening
([capture](2026-08-14_pmos_rpm-master-stats.txt)):

| master | Shutdown count | XO shutdown count | Active cores |
|---|---|---|---|
| **APSS** — the application processor | **0** | **0** | **0x1** |
| MPSS — the modem | 170 | 161 | 0x0 |
| PRONTO — the WLAN subsystem | 284 | 284 | 0x1 |
| LPASS — the audio DSP | 1 | 1 | 0x1 |
| TZ | 0 | 0 | 0x0 |

**The modem and the WLAN subsystem put themselves down hundreds of times. The
application processor has never done it once**, and its active-cores bitmask
still reads `0x1`. VDD_MIN needs every master down, so one master that never
votes is sufficient on its own to explain every zero on this page — the SoC-wide
counters, the unreachable 10.4 mA, and the fuel-gauge anchor that never fires.

TZ reads zero too, which fits rather than complicates: on this SoC the APSS
shutdown is signalled to the RPM through the secure side, and the cluster
power-collapse that would trigger it records five entries and 0 ms of residency.

So the question is now specific enough to work on: **what should send the APSS
sleep vote on mainline msm8953, and why does nothing send it.** One answer has
already been tried and disproved — that mainline never requests the system-level
PSCI state which downstream marks `qcom,notify-rpm`. Adding it works, is accepted
by the firmware, and changes nothing:
[the patch and the measurement](bringup/disproven/README.md). That is a
platform gap, not a tuning problem, and no amount of removing userspace or
lowering the floor addresses it.

☠️ **The module was loaded by hand and `insmod` raised the known `ftrace_bug`
warning**, as a locally built module does on this device. It does not affect
reading debugfs, but the final word belongs to a package build.

### The instrument had to be added first, and it was missing for everyone

`msm8953.dtsi` carried no RPM sleep-stats node, so `/sys/kernel/debug/qcom_stats`
did not exist, even though `CONFIG_QCOM_STATS` was already enabled. The driver
and the hardware were both there; only the description was missing.

The region is the one `msm8996`, `msm8998` and `qcs404` already describe, and the
downstream msm8953 tree confirms it — it puts the offset pointers at `0x290014`
and `0x29001c`, both inside `0x290000 + 0x10000`, which is what the driver's
dynamic-offset scheme reads. That the driver then names its two records `vlow`
and `vmin` rather than producing garbage is the check that the address is right:
those names come out of the region itself.

Deployed DTB-only — the kernel binary was untouched, and the previous device tree
is on the phone as `sdm632-fairphone-fp3.dtb.pre-rpmstats`.

## Later the same evening: the notification path was missing, and now runs

The reason nothing above the CPU clusters ever told the RPM anything is that
**mainline msm8953 describes no MPM**. The MSM Power Manager sits in the
always-on domain, monitors wakeup interrupts while the SoC sleeps, and — in the
mainline driver — is also a power domain whose `power_off` callback is what
hands the vMPM contents to the RPM over a mailbox. Two in-tree SoCs already wire
it exactly this way, `sm6375` and `agatti`, by making the CPU cluster domain a
child of `&mpm`. On msm8953 the cluster domains had **no parent at all**, so
there was no callback to run.

Every value needed to describe it is in the downstream tree and each one was
cross-checked against mainline's own numbers before use:

| what | downstream source | value used |
|---|---|---|
| vMPM slice | `wake-gic@601d4` reg | offset `0x1d4` in `rpm_msg_ram`, size `0x48` |
| RPM→APSS wakeup line | same node's `interrupts` | `GIC_SPI 171`, edge rising |
| mailbox channel | driver's `writel(2, 0xb011008)` | `<&apcs 1>` — bit 1, next to glink-rpm on bit 0 |
| pin map | `mpm_msm8953_gic_chip_data[]` | raw hwirq **− 32** = SPI number |

The −32 conversion is not assumed: all five entries land on interrupt numbers
`msm8953.dtsi` already uses elsewhere (tsens 184, spmi 190, usb 136 and 220,
mdss 72).

**Measured with the node in place**, over a 180 s idle and two `rtcwake` sleeps
of 120 s and 300 s: the MPM domain's `idle_states` usage goes 0 → 1 → 2, one per
suspend, and the cluster's `cluster-pc` gains an `S2idle` count in the same
steps. So the callback runs and the mailbox write happens. The RPM's own view
did **not** move: `vlow` 0, `vmin` 0, APSS `Shutdown count` 0.

That is a narrower result than it looks. It removes "nobody notifies the RPM"
as the explanation, and it reopens the system-level PSCI state recorded as
disproven earlier the same evening — because **that experiment ran without the
MPM**, so the firmware was being asked to collapse a system whose wakeup
configuration had never been handed over.

☠️ Note for anyone reading the counters: the debugfs file is
`/sys/kernel/debug/qcom_rpm_master_stats/<MASTER>`, one file per master — not
`rpm_master_stats`. A `grep` against the wrong path reads as an unbound driver.

### A kernel ordering bug had to be fixed first, and it is upstream's

Making the cluster domains children of the MPM broke cpuidle outright — no
states at all, `/sys/devices/system/cpu/cpu0/cpuidle/` absent, the CPUs left on
plain WFI. The chain:

* `psci_idle_init()` creates a **faux device**, which is probed synchronously
  and has no way to return `-EPROBE_DEFER`.
* Its probe attaches each CPU to the `psci` power domain, so it needs the CPU PM
  domain provider in `cpuidle-psci-domain.c` to have probed.
* That provider is an ordinary platform driver, and it now defers, because the
  cluster domains reference a supplier whose driver probes later.
* The deferred probe is retried by `deferred_probe_initcall()`, a
  `late_initcall`, while `psci_idle_init()` is a `device_initcall` — so it
  always runs first and always loses.

The boot log states all three steps in order: `failed to create CPU PM domains
ret=-517`, then the MPM probing, then `CPU 0 failed to PSCI idle` and `Failed to
create psci-cpuidle device`. Moving the init to `late_initcall_sync` puts it
after the flush and restores cpuidle; on a board where nothing defers, the same
successful init simply happens slightly later. This is not msm8953-specific —
any SoC that puts a domain above its CPU clusters hits it.

## ★ The oracle reframes all of it: this is an idle-depth problem, not a suspend problem

Every measurement above is one-sided. Booting `slot_a` (Ubuntu Touch, downstream
4.9) and reading the same records changes the question outright
([capture](2026-08-14_ut_oracle_rpm-stats.txt)):

| record | oracle (UT), ~200 s uptime | mainline (pmOS), ~700 s |
|---|---|---|
| APSS `numshutdowns` | **0x16df = 5855** | **0** |
| APSS `xo_count` | 0 | 0 |
| APSS `active_cores` | `0x1` (core0) | `0x1` (core0) |
| `[system] system-pc` success count | **8263**, 93.8 s accumulated | n/a |
| deepest state actually entered | system power collapse, ~30×/s | `cluster-pc` **3 times total** |

Two things follow, and both retire earlier readings:

* **`active_cores: 0x1` is not a symptom.** The working system reports exactly
  the same value, so every reading of it as "the RPM thinks a core is up" was
  wrong.
* **The oracle's system power collapse is an *idle* state, not a suspend state.**
  Its residency histogram peaks in the 4–16 ms bucket (7084 of 8263 entries),
  i.e. the SoC collapses and comes back every few milliseconds all day long. It
  is not something a `rtcwake` produces; it is what ordinary idle looks like when
  the topology works.

So the whole evening's framing — "does a suspend reach the RPM" — was aimed one
level too deep. The measurable gap is that **mainline almost never selects the
deepest cluster state at all**: `cluster-gdhs` was entered 41142 times against 3
for `cluster-pc`, and the two `system-pc` entries were the two forced suspends.
The RPM records nothing because nothing is being asked of it thirty times a
second, not because the request is malformed.

That also explains why every "make the request more correct" experiment produced
`Rejected 0` and no change: the requests were accepted, there were just three of
them.

☠️ **Note on the residency numbers we chose.** `system_pc` was given
`min-residency-us = 13000`, derived from the downstream latency figures. The
oracle's own histogram says the state pays for itself at 4–16 ms. A 13 ms floor
excludes most of the window the hardware actually uses, so that number is a
candidate cause rather than a neutral transcription — re-derive it from the
histogram, not from the latency sum.


### And with the display off, the governor says so itself

60 s of idle with the compositor stopped, read off
`pm_genpd/power-domain-cluster0/idle_states`:

| state | min-residency | usages in 60 s | time accumulated |
|---|---|---|---|
| `cluster-gdhs` | 1800 us | **7628** | 55.8 s (mean **7.3 ms**) |
| `cluster-pc` | 2500 us | **0** | 0 |

A mean idle window of 7.3 ms clears `cluster-pc`'s 2500 us threshold with room
to spare even after its 270+430 us latencies, and the state is still never
chosen - `Rejected` is 0 as well, so it was not refused, it was never selected.
The governor's own counters name the fault: **4741 of the 7628 entries (62 %)
are "Below"**, meaning the domain stayed idle longer than the state it was put
into was sized for. It is systematically choosing too shallow a state, which is
exactly the shape the oracle comparison predicted.

The next question is therefore why the CPU domain governor's estimate of the
next wakeup is short, not why the RPM is silent.

## What the remaining floor is not

☠️ **The floor quoted below is not a camera-released floor, and the daemon
subtraction under it proves less than it appears to.** It is the one measurement
on this page with no capture file, and three that do have one disagree with it:
67.6, 79.7 and 82.4 mA with the camera released, against 139–143 mA here. What
reconciles them is that the lens actuator was almost certainly still powered —
checked on 2026-08-14 evening, `wireplumber` held `/dev/video0`, `/dev/media0`
**and** `/dev/v4l-subdev17`, the `ak7375` read `active`, and `focus_absolute`
stood at 930. A single 152 mA consumer dominating the total is also the simplest
explanation for why stopping ten daemons moved nothing. Read the two exclusions
below as sound in method and unproven in this instance; the floor itself needs
re-measuring with the actuator state recorded per sample.

Measured 2026-08-14. The floor is **139 to
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

### The kernel half shipped, and the cost moved to userspace

That change is **in the running kernel**: `fa5d294c`, which `linux-fp3-7.1.3-r53`
pins, is the commit that makes power follow the requested position. So the
`ak7375` is no longer powered by the mere fact of an open file descriptor.

It is still powered, though, and now for a reason the driver is right about.
Checked 2026-08-14 evening: `focus_absolute` stood at **930** — a commanded
position away from rest — so the driver held the coil exactly as designed.
**Nothing returns the lens to rest when the preview stops.** The remaining ~70 mA
is therefore a userspace policy question — who parks the lens, and when — and it
belongs with
[`0101-simple-autofocus.patch`](../../userspace-camera/libcamera/0101-simple-autofocus.patch),
not in the kernel.

☠️ **What that means for the driver's design is the opposite of a complaint.**
Position-following power is only worth anything if something eventually asks for
the rest position. A fix that nobody drives back to zero is a fix that never
fires.

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
| `2026-08-14_pmos_rpm-sleep-stats.txt` | four `rtcwake` suspends of 60, 120, 300 and 600 s with the RPM sleep-stats, cluster genpd residency and the QG S3 witnesses read either side of each. The finding is that every RPM-level counter stays at zero |
| `2026-08-14_pmos_rpm-master-stats.txt` | the RPM per-master sleep records, read once the master-stats node and driver were in place. APSS has a shutdown count of zero; the modem and WLAN are in the hundreds |
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

---

## ★★★ The real cause: a `bool` that should have been an `unsigned int`

*2026-08-14, late night. This is the answer to the question the oracle raised.*

The idle-depth question had a one-word answer, and it was not on this SoC at all.
In `include/linux/pm_domain.h`:

```c
struct genpd_governor_data {
	...
	bool cached_power_down_ok;
	bool cached_power_down_state_idx;   /* <- a state index, stored in a bool */
};
```

`drivers/pmdomain/governor.c` writes a state index into it and reads one back:

```c
	gd->cached_power_down_state_idx = genpd->state_idx;   /* 2 becomes true */
	...
	genpd->state_idx = gd->cached_power_down_state_idx;   /* true becomes 1 */
```

So **any idle-state index above 1 survives exactly one call.** A genpd computes
the right depth once, on the single uncached pass, caches it as `1`, and from
then on every call takes the cached path and hands the governor a `1`.
`cpu_power_down_ok()` starts its search at `genpd->state_idx` and only ever walks
*downwards*, so no state deeper than index 1 can ever be selected again.

The msm8953 cluster domain has three: `cluster-ret`, `cluster-gdhs`,
`cluster-pc`. Index 2 was unreachable from the first second of uptime.

### How it was localised

Three instrumented boots, each about two minutes to build on top of the existing
`.output`:

1. A `trace_printk` in `cpu_power_down_ok()` printing the computed
   `idle_duration_ns`, the starting index and the pick. **1622 decisions,
   `start=1` in every single one**, and 73 % of them had an idle window past
   `cluster-pc`'s 2770 µs requirement (p50 3.5 ms, p90 235 ms). So the
   next-wakeup estimate was never the problem — the search simply began one
   state too shallow. That retired the hypothesis this run started with.
2. A print on both exits of `_default_power_down_ok()`. Every runtime call was
   `CACHED idx=1`; not one fresh computation in a 3 s window.
3. A print on the fresh path only, read straight after boot. **Two lines in the
   whole trace buffer, both `FRESH idx=2 cnt=3`** — the fresh path computes the
   correct index, once, at 0.74 s, and is never taken again. Between `idx=2`
   going in and `idx=1` coming out sat the `bool`.

☠️ The measurement that would have been wrong: reading the *outcome* counters.
`cluster-pc` showed `usage 0, rejected 0` — indistinguishable from "the hardware
refuses it" and from "the window is too short". Only printing the governor's
*input* separated them.

### What it changes, measured

Same phone, display off, 60 s, the only difference being `bool` →
`unsigned int`:

| | before | after |
|---|---|---|
| `cluster-pc`, cluster0 | **0** entries | **14516** entries, 67.3 s |
| `cluster-pc`, cluster1 | 1 entry, 2 ms | 8243 entries, 59.1 s |
| `system-pc` (`power-domain-system`) | **0** | **3531** entries, 34.8 s |
| MPM domain power-off | 0 | 3582 |

The system domain matters twice over: `genpd_power_off()` refuses to power off a
parent unless **every child is already in its deepest state**
(`drivers/pmdomain/core.c`, `child->state_idx < child->state_count - 1`), so with
the clusters pinned at index 1 the level above them was structurally
unreachable — which is why the MPM notification to the RPM, added earlier the
same evening and demonstrably working, still had nothing to notify about.

47 system power collapses a second is the same order as the oracle's 41/s.

### Provenance

Introduced by commit `e94999688e3a` ("PM / Domains: Add genpd governor for
CPUs", Ulf Hansson, 2019-04-11) and carried unchanged through `f38d1a6d0025`
("PM: domains: Allocate governor data dynamically based on a genpd governor",
2022) when the field moved into `struct genpd_governor_data`. It has been a
`bool` for six years. Nothing here is msm8953-specific: **every SoC whose genpd
has three or more idle states has been losing its deepest ones**, silently, with
zero rejected counts to show for it.

☠️ What still does not move: `qcom_stats` `vlow`/`vmin` are both still 0 and the
RPM's APSS master record is still all zeros. Those are the next question, and
they are now a question about the RPM handshake alone, with the AP side doing
its part 47 times a second.

## What is still missing: nobody tells the RPM the AP went to sleep

*Same night, after the genpd fix. This section is **source-based inference plus a
one-sided measurement**, not a two-sided one — the oracle half of the differential
has not been captured yet.*

Measured on the fixed kernel: the AP completes a system-level power collapse
~47 times a second, and the RPM records nothing. `qcom_stats` `vlow` and `vmin`
both read `Count: 0`, and the APSS record in
`/sys/kernel/debug/qcom_rpm_master_stats/APSS` is all zeros.

☠️ The first thing to rule out is the instrument, and it passes: `vlow` also
prints `Client Votes: 0x13111517`, a non-zero value read out of the same SMEM
structure. The reader is live and the structure is populated — the zero counts
are a fact about the RPM, not about the driver.

What the downstream kernel does at that moment, and mainline does not:

* `msm8953-pm.dtsi` marks the system level `qcom,notify-rpm`, and
  `lpm-levels.c` acts on that flag before the PSCI call.
* The action is `rpm-smd.c`'s `msm_rpm_enter_sleep()`: mask the RPM's SMD receive
  interrupt so it cannot wake the AP, then **flush the accumulated sleep-set
  requests** to the RPM. `msm_rpm_exit_sleep()` drains the sleep acks and unmasks
  on the way back up.
* On the oracle those two numbers line up: `[system] system-pc` succeeds 8263
  times and APSS `numshutdowns` reads `0x1ed1` = 7889. Whatever increments the
  RPM's record is the system-pc entry, not an XO vote — APSS `xo_count` is `0`
  on the oracle too.

Mainline's `drivers/soc/qcom/smd-rpm.c` has **no suspend or resume hook of any
kind** — no sleep-set flush, no notifier, no PM ops. It writes every request to
the active set. The sleep-set constant exists (`QCOM_SMD_RPM_SLEEP_STATE`) and
`clk-smd-rpm.c` is its only user.

So the shape of the remaining gap is: the MPM work added the **wakeup** half of
the handshake — telling the RPM which interrupts must bring the AP back. The
**sleep** half, telling the RPM that the AP is down and that its sleep-set votes
now apply, does not exist in mainline for any RPM-generation Qualcomm SoC. That
is why the clusters and the system domain can collapse 47 times a second while
the RPM never drops to vmin.

☠️ Not yet verified, and it is the next thing to capture: the oracle's own
`vlow`/`vmin` counts. Everything above says the RPM *should* be reaching them on
the working system, and until that file is read it is an expectation, not a
control.

## And the deep idle states did not, by themselves, move the current

*2026-08-14, past midnight. A negative result, stated as one.*

The genpd fix takes the AP from never entering `cluster-pc` to entering it
14516 times a minute, and gets the system domain collapsing 47 times a second.
The obvious next question is what that is worth in milliamps, and the first
answer is: **nothing this instrument can resolve.**

First attempt, 26 min per leg, display off, greetd stopped, battery at 100 % and
VBUS at 0:

| leg | slope |
|---|---|
| fixed kernel | 23.7 mV/h |
| same kernel minus the one word | 25.4 mV/h |

☠️ Do not read those two numbers as a result yet — the protocol was not matched,
and two traps showed up while measuring:

* **The gauge reports `current_now = 0` while `status` is `Full`.** With the
  battery full and nothing on VBUS the only signal left is the terminal-voltage
  slope, which is quantised in ~780 µV steps and confounded by post-charge
  relaxation.
* **The control leg's slope depended entirely on how much of its head was
  dropped**: −142, +141, +156 or +25 mV/h for offsets of 0, 150, 300 and 600 s
  from boot. The post-boot voltage recovery is an order of magnitude larger than
  the effect. Only the ≥600 s figure means anything, and the other leg had no
  reboot at all, so the two are not the same measurement.
* ☠️ **And the first leg's raw data is gone** — it was written to the phone's
  `/tmp`, which is tmpfs, and the A/B's own reboot took it. Only the summary
  printed at the time survived.

A matched re-run is in progress: reboot, settle 600 s, log 25 min, both legs
identical, output under `/home/fp3/` so a reboot cannot eat it.

Whatever it returns, the shape of the answer is already constrained by the
section above: the AP-side collapse is real and the RPM never hears about it, so
the SoC rails and the XO stay up. Deeper AP idle with the same rails up is
expected to be a small effect. That is a reason to expect little here, not a
reason to skip measuring it.

### The matched re-run: still no difference, and now it is a real measurement

Same protocol on both legs — reboot, `greetd` stopped, settle 600 s, then 50
samples 30 s apart, written to `/home/fp3/` so a reboot could not eat them. The
only difference between the two kernels is `bool` → `unsigned int`.

| leg | samples | span | ΔV | slope | window |
|---|---|---|---|---|---|
| A2, fixed | 50 | 1474 s | 8.18 mV | **19.97 mV/h** | 4.3497 → 4.3416 V |
| B2, control | 50 | 1473 s | 6.81 mV | **16.65 mV/h** | 4.3603 → 4.3534 V |

**The result is negative, and it does not even point the flattering way**: the
kernel that spends two thirds of its wall-clock in a system power collapse
discharges marginally *faster* than the one that never enters the state at all.
The 3.3 mV/h gap is not a finding — the two legs sit at slightly different
voltages on a non-linear OCV curve, and the gauge quantises at ~780 µV — but it
is comfortably enough to say that **the deepest AP idle states are not what
determines this phone's idle current.**

That is consistent with the section above rather than in tension with it. The AP
collapsing costs the AP's own rail, which is a small share of an idle phone; the
SoC rails, the XO and the memory stay up because the RPM is never told the AP has
gone. Until the sleep half of that handshake exists, deeper AP idle buys close to
nothing measurable.

☠️ Worth saying plainly, because the counters are seductive: 14516 entries a
minute and 47 system collapses a second look like a result. The milliamps are
the result, and they did not move.

### The oracle control for the RPM half, measured 2026-08-15

Booted `slot_a`, let Ubuntu Touch settle, and differenced the APSS record over a
180 s window (`docs/power/2026-08-15_ut_oracle_rpm-master-stats.txt`):

```
T0  uptime 192.35   numshutdowns 0x1da6 =  7590
T1  uptime 372.39   numshutdowns 0x489b = 18587
                    ------------------------------
                    10997 in 180 s  =  61 per second
```

So the downstream kernel has the RPM record an APSS shutdown **61 times a
second**. Mainline with the genpd fix reaches the same order of AP-level collapse
— genpd counts ~47 system power collapses a second — and the RPM records **zero**
of them.

Two details that sharpen the comparison rather than blur it:

* `xo_accumulated_duration` for APSS is `0x0` on the oracle as well, and
  `xo_count` is `0`. The AP never votes the crystal down on either system; what
  the RPM counts for the AP is the shutdown itself. So the missing number on our
  side is not an XO vote we forgot to cast.
* ☠️ **The oracle has no `/sys/kernel/debug/rpm_stats`** — the SMEM-backed
  vlow/vmin file that mainline's `qcom_stats` provides does not exist in the
  downstream 4.9 tree, because that driver is not built there. The vlow/vmin
  counters therefore have **no oracle control at all** and cannot be used as a
  differential. `rpm_master_stats` is the instrument both sides have.

That leaves the statement in the previous section standing and now two-sided:
the AP collapses at a comparable rate on both systems, and only downstream tells
the RPM about it.

### The GPIO wakeup map is deployed, and cannot be shown to work yet

`pinctrl-msm8953` now carries the MPM map (transposed from downstream's
`mpm_msm8953_gpio_chip_data[]`) and the TLMM has `wakeup-parent = <&mpm>`. Every
wake-capable line on this board is in it: volume_up on GPIO 85, the hx83112b
touchscreen on 65, NFC on 17, the SD card-detect on 133, `wcd9335_pin1_irq` on 73.

Deployed from `debug-int/7.1.3` `6cbf488a28f0`, md5-verified on both `Image` and
DTB against the build tree. `dmesg` shows only the one known, expected line —
`failed to map pin 58 as GIC hwirq 136 is already mapped`, which is downstream
mapping both `qusb2phy_dpse_hv` and `qusb2phy_dmse_hv` to the same GIC IRQ.

Then the test, and the test says: **not yet.**

```
rtcwake -m mem -s 20    ->  suspend_stats success 1, fail 0
qcom_mpm (irq 13)       ->  0 before, 0 after
power-domain-system     ->  S2idle 1
```

The suspend works and the system domain does power off, but the wake did **not**
arrive through the MPM — its interrupt never fired. That is the correct
behaviour for s2idle: the GIC stays powered, so it delivers the wake itself and
the always-on controller is never needed. The MPM only becomes the delivering
controller once the SoC actually drops below that, which is exactly the state the
RPM has to be told about.

So the GPIO map is in place and inert, and it will stay inert until the sleep
half of the RPM handshake exists. It is not dead code — it is the second half of
a mechanism whose first half is still missing — but nothing here should be
described as working.

☠️ **`CONFIG_GENERIC_IRQ_DEBUGFS` is off in this config**, so
`/sys/kernel/debug/irq/` does not exist and the obvious check — reading an IRQ's
parent domain after arming its wake — is unavailable. The instrument that works
is the MPM's own interrupt count in `/proc/interrupts`.

## ★★ The RPM answer: mainline's regulators only ever vote the active set

*2026-08-15, early morning. This supersedes the guess in "What is still missing"
above — see the correction at the end of this section.*

`drivers/regulator/qcom_smd-regulator.c` has exactly one write helper, and its
name is the finding:

```c
static int rpm_reg_write_active(struct qcom_rpm_reg *vreg)
{
	...
	ret = qcom_rpm_smd_write(smd_vreg_rpm, QCOM_SMD_RPM_ACTIVE_STATE,
				 vreg->type, vreg->id, ...);
```

Every path into it — `rpm_reg_enable`, `rpm_reg_disable`, `rpm_reg_set_voltage`,
`rpm_reg_set_load` — passes `QCOM_SMD_RPM_ACTIVE_STATE`. **Mainline has no
sleep-set path for RPM regulators at all.** Downstream's
`rpm-smd-regulator.c` carries a second request handle per regulator
(`rpm_vreg->handle_sleep`, created with `RPM_SET_SLEEP`) and sends a matching
sleep vote for every active one.

That single asymmetry accounts for everything measured:

* The RPM ends up holding standing **active** votes for every rail the AP ever
  enabled, and an active vote is by definition one it may not drop. Downstream's
  own comment in `msm_rpm_flush_requests()` states the rule from the other side:
  *"RPM PC would be disallowed if we had pending active requests"*.
* So the RPM never power-collapses: `vlow`/`vmin` stay at `Count: 0`, and the
  APSS `numshutdowns` record never moves, no matter how deeply the AP collapses.
* And `vlow`'s `Client Votes: 0x13111517` — the non-zero field that proved the
  instrument was live — reads naturally as exactly this: the clients holding it
  up.

The interconnect driver, by contrast, gets it right: `icc-rpm.c` aggregates and
sends both `QCOM_SMD_RPM_ACTIVE_STATE` and `QCOM_SMD_RPM_SLEEP_STATE` rates, and
`clk-smd-rpm.c` does the same for clocks. Regulators are the outlier.

### Correcting the earlier guess

The section above ("nobody tells the RPM the AP went to sleep") proposed that the
missing piece was downstream's `msm_rpm_enter_sleep()` — a *signal*. Reading
`msm_rpm_flush_requests()` shows that is wrong: it sends only the **buffered
sleep-set requests** and no distinguished "AP is asleep" message exists. Mainline
sends each request eagerly instead of buffering it, so for clocks and
interconnect the RPM already has the sleep values it needs; nothing about the
buffering matters. The missing thing was never a message. It is the sleep-set
*content* for one subsystem.

☠️ The lesson is the one this project keeps re-learning: a plausible mechanism
read out of one function is not the mechanism. `msm_rpm_enter_sleep()` looked
decisive because it is named for exactly the moment in question, and the thing it
actually does is mundane.

### First probe of that theory: a sleep entry existing is not enough

Throwaway experiment on top of `debug-int/7.1.3` `6cbf488a28f0` (uncommitted, in
the build tree only): mirror every active regulator vote into the sleep set with
an **identical** value, so nothing can brown out, and see whether the RPM needs a
sleep-set entry to merely *exist*.

```c
	ret = qcom_rpm_smd_write(smd_vreg_rpm, QCOM_SMD_RPM_ACTIVE_STATE, ...);
	if (!ret)
		qcom_rpm_smd_write(smd_vreg_rpm, QCOM_SMD_RPM_SLEEP_STATE, ...);
```

Result, display off, 45 s after boot: **no change.** `vlow` and `vmin` both still
`Count: 0`, the APSS master record is still entirely zeros, and the kernel boots
with no regulator or RPM-timeout errors (`dmesg` match count 0).

So existence is not the missing property — the RPM is not looking for "is there a
sleep vote for this resource", it is looking at what the sleep vote *says*, and a
sleep vote identical to the active one holds the rail up exactly as the active one
does. In hindsight that is the only sensible protocol.

☠️ The `Client Votes` field is **not** usable as the signal here: it read
`0x13111517`, then `0x17151715`, then `0x11151115` across three reads with no
deliberate change between them. It moves on its own, so a difference across an
experiment proves nothing. The counters (`Count`, `numshutdowns`) are the
instruments that mean something.

The next probe therefore has to send a sleep value that actually releases
something, which is the part that can brown a rail out mid-sleep — so it must be
one rail with no consumer, chosen deliberately, not a blanket change.

## The regulator sleep-set theory was wrong, and here is what replaced it

*2026-08-15, early morning. Four measurements, three of them negative, and one
that rewrites the previous section.*

### First: the theory pointed the wrong way

The previous section reasoned that mainline's active-only regulator votes leave
the RPM holding permanent votes that block its power collapse. That is backwards.
An RPM resource is aggregated per set: if APSS contributes **nothing** to the
sleep set, APSS is not asking for the rail during sleep, and the RPM is free to
drop it. Mainline's silence is therefore *permissive*, not restrictive — which is
also why mirroring the active votes into the sleep set (the previous experiment)
could only ever make things stricter, and why it changed nothing.

The regulator sleep set is a real gap in mainline, and a real hazard the day the
RPM does collapse, but it is **not** what is holding the RPM up today.

### What downstream actually does before a system power collapse

Read from the vendor 4.9 source on disk, not inferred. On msm8953 the governor is
`drivers/cpuidle/lpm-levels.c` (`CONFIG_MSM_PM=y`; `MSM_PM_LEGACY` is not set),
and the `qcom,notify-rpm` level runs `sys_pm_ops->enter`. ☠️ Two surprises:

* `sys_pm_ops` on this SoC is registered by **`drivers/irqchip/qcom/mpm.c`**, not
  by `rpm-smd.c` and not by `soc/qcom/system_pm.c` — that last one is the RPMh
  (SDM845-class) implementation and never binds here.
* The whole of it is three actions: `msm_rpm_enter_sleep()` (mask the RPM's SMD
  receive IRQ, flush the sleep set), `msm_mpm_enter_sleep()` (write the IPC
  register, move its IRQ affinity), and `system_pm_update_wakeup()` →
  **`msm_mpm_timer_write()`**.

`smd_mask_receive_interrupt()` turned out to be a plain local `irq_mask()` plus an
affinity change — it writes nothing to shared memory, so it is not a notification
to the RPM at all. That leaves the timer as the only thing mainline was missing
outright.

### The one real gap: the vMPM wakeup timer was never written

`msm_mpm_timer_write()` writes the architected timer's compare value into the
**first two words** of the vMPM region. Mainline's `irq-qcom-mpm.c` documents
those words in its own register-map comment as `TIMER0`/`TIMER1`, skips them in
`qcom_mpm_read()`/`qcom_mpm_write()` with the `+ 2` in the offset, and then never
writes them anywhere.

Measured on the running phone, reading the vMPM region through `/dev/mem`:

```
0x1d4: 00000000 00000000 08001000 00080008     <- before, TIMER0/TIMER1 = 0
0x1d4: 46683198 00000000 08001000 00080008     <- after
```

The enable words either side of it are non-zero, so the region and the offsets are
right; the deadline simply was not there. Fixed on `wip/7.1.3/power` by taking
`tick_nohz_get_next_hrtimer()` in `mpm_pd_power_off()`, converting it to counter
ticks and capping it at one second.

**And it did not move the RPM either.** APSS `Shutdown count` still 0, `vlow` and
`vmin` still 0. Nor did timer + sleep-set mirror together.

### What is now known for certain about the AP side

Every AP-side precondition has been checked individually and all of them pass:

| checked | command | result |
|---|---|---|
| the composed PSCI parameter really reaches firmware | `echo 1 > /sys/kernel/tracing/events/power/psci_domain_idle_enter/enable` | **`0x41000353` 88 times in 3 s**, alongside `0x41000053` and `0x40000003` |
| firmware accepts it | `cat /sys/kernel/debug/pm_genpd/power-domain-system/idle_states` | 6233 entries, 130 rejected — 98 % succeed |
| the mailbox is the right one | DT `mboxes = <&apcs 1>`, `qcom,msm8953-apcs-kpss-global` → `msm8994_apcs_data.offset = 8` | writes `BIT(1)` to `0xb011008`, byte-for-byte what downstream's `msm_mpm_send_interrupt()` writes |
| the wakeup deadline is programmed | `/dev/mem` dump of the vMPM region | non-zero, plausible |
| the master-stats reader is not lying | 60 s differential over every master | **MPSS +150, PRONTO +563, APSS +0** |

That last row is the important one and it is the control the earlier write-up did
not have: the instrument counts other masters going down in real time, so APSS
reading zero is a fact about the APSS, not about the driver.

☠️ Also worth recording as an instrument: `psci_domain_idle_enter` lives in the
**`power`** trace system, not a `psci` one — `events/psci/` does not exist and
looking for it reads as "the tracepoint is not compiled in".

### One loose end found on the way

`qcom_mpm interrupt-controller: failed to map pin 58 as GIC hwirq 136 is already
mapped` — pins 49 and 58 are the two QUSB2 PHY sense lines and downstream maps
both to the same GIC interrupt. Ours silently drops the second. Harmless today;
it belongs in the pin-map commit's follow-up.

### Where that leaves the question

The AP requests a system power collapse with the correct parameter, the firmware
reports it performed one, the RPM is told through the correct mailbox, it now has
a wakeup deadline — and it still never records the APSS going down, while it
records the modem and WLAN doing so hundreds of times a minute. Every remaining
explanation is on the far side of the PSCI call, in TZ or in the RPM firmware,
where this kernel has no instrument. The next move is therefore not another
kernel patch but a two-sided capture of the *firmware's* view: the oracle runs the
same TZ on the same silicon, so anything that differs has to be in what the two
kernels leave behind in shared memory before the call.

### The two-sided vMPM capture: identical, and that is the result

*2026-08-15, on the oracle. The capture is
[`2026-08-15_vmpm-two-sided.txt`](2026-08-15_vmpm-two-sided.txt).*

Booted `slot_a` and read the same physical region with the same method. The two
dumps are **structurally identical**: every differing bit in the register words is
a wakeup pin the oracle enables and we do not. There is no extra word, no flag,
no cookie beyond the enable/edge/polarity/status array that mainline fails to
write. The one behavioural difference is that the oracle's `TIMER0` reads back as
zero five seconds later - the value gets consumed - which is the positive control
that the RPM does read those two words.

The same boot also pins the relationship this whole investigation is missing:

| oracle, one boot | |
|---|---|
| `[system] system-pc` success | 10168 (611 failed, 117.5 s total) |
| APSS `numshutdowns` | `0x2619` = 9753 |

The counts track each other one for one. On mainline the left column reads 6233
and the right column reads 0.

☠️ A residency comparison looks alarming and mostly is not, so state it
carefully. The oracle spends 117 s of a ten-minute uptime in system power
collapse (~20 %); mainline, measured with the panel blanked, spends 224.7 s of
396.7 s (~57 %). But the *entry rates* are close - 17/s there against 24/s here -
and the average residency differs the other way round (11.6 ms against 23.7 ms),
which simply says the oracle is woken more often, as a phone running a full UI
and telephony stack would be. The two are not matched runs and the difference is
not evidence about the collapse itself. What remains evidence is the count that
is exactly zero: the oracle's entries produce APSS shutdowns one for one, and
ours produce none.

## The instrument we lacked all night: suspend USBIN and read the gauge

*2026-08-15, ~06:00. This section corrects the one above it.*

Everything in this directory up to here was measured as a **voltage slope**,
because `current_now` reads 0 with a cable attached. That method turned out to be
unusable at this state of charge, and the way it failed is instructive: a paired
same-boot experiment - panel blanked for 20 minutes, then panel on for 20 minutes
- returned **8.31 mV/h with the panel off and 5.13 mV/h with it on**. Backwards.
The pack sits at 99 % on a suspended port, so what the voltage does is *relax*,
and relaxation flattens with time all by itself. Any later leg reads flatter than
any earlier leg, whatever the load. ☠️ That also disqualifies the matched A/B
from earlier tonight: its two legs started at 100 % and 97 % state of charge, so
they were never on the same part of the curve, and **"the genpd fix did not move
the current" is withdrawn as unsupported** - not disproved, unsupported.

The fix is to stop measuring a proxy. `qcom_smbx` makes
`POWER_SUPPLY_PROP_STATUS` writable on the charger supply and maps it straight
onto `USBIN_SUSPEND_BIT` in `USBIN_CMD_IL`:

```sh
echo Unknown > /sys/class/power_supply/pmi632-charger/status   # suspend input
echo Charging > /sys/class/power_supply/pmi632-charger/status  # release it
```

After which `pmi632-charger/online` reads 0, the battery reports `Discharging`,
and `pmi632-battery/current_now` becomes a **direct current reading** - no cable
to unplug, no human at the phone, no curve fitting.

### Why that works, since "measuring discharge on the charger" sounds wrong

It is not measuring discharge *while charging*. It takes the phone off VBUS
electrically, and only the cable stays.

```c
/* drivers/power/supply/qcom_smbx.c */
#define USBIN_CMD_IL        0x340
#define USBIN_SUSPEND_BIT   BIT(0)

case POWER_SUPPLY_PROP_STATUS:
        return regmap_update_bits(chip->regmap, chip->base + USBIN_CMD_IL,
                                  USBIN_SUSPEND_BIT, !val->intval);
```

The write opens the PMIC's input FET. VBUS is still present on the connector,
the USB PHY and the data link sit on the phone's side of that FET and keep
running, but the charging path is broken, so the phone runs off its own pack.
Note the `!val->intval`: `Unknown` is `POWER_SUPPLY_STATUS_UNKNOWN` = 0, so it
*sets* the bit; any non-zero status string clears it again.

Three gates, because each one alone can be fooled and together they cannot:

```sh
[ "$(cat $CHG/online)" = 0 ]              || die "charger still online"
[ "$(cat $BATT/status)" = Discharging ]   || die "battery is '...'"
[ "$i0" -lt 0 ]                           || die "current_now is $i0, expected negative"
```

`online` asks the PMIC, `status` asks the charger state machine, and a negative
`current_now` asks the current ADC itself. All three are in
[`idle-leg.sh`](idle-leg.sh) and [`suspend-leg.sh`](suspend-leg.sh).

☠️ **The cost of the trick: `USBIN_SUSPEND_BIT` lives in the PMIC and survives a
warm reboot.** Left set through a restart it once wedged the bootloader - the
phone enumerated as fastboot and answered no command, a host-side USB reset did
nothing, and it took a held power button to recover. Every script therefore
carries `trap restore EXIT INT TERM`, and nothing reboots while the bit is set.

☠️ **`current_now` is the only real reading here.** `charge_now` is not a coulomb
count on this platform, so this instrument works awake and cannot be carried
across a suspend - see the withdrawal below.

### What that immediately says

| condition | mean current |
|---|---|
| panel on | −151 mA |
| panel blanked | −142 mA |
| panel on again | −163 mA |

☠️ **So the previous section's headline is wrong and is withdrawn.** The panel is
worth roughly 10 mA out of 150, not half the budget. Blanking really does remove
`msm_mdss` and halve the *wakeup count*, and it is still worth doing as part of a
measurement protocol - but wakeup count and current are not the same quantity,
and reasoning from one to the other is exactly the mistake that produced the
claim. The drift between the two panel-on readings (151 → 163 mA) is also larger
than the panel term itself, so even this needs repeating.

The number that matters is the baseline: **an idle Fairphone 3 with the screen
off is drawing about 145 mA.** That is roughly an order of magnitude more than an
idle phone should, and it is now measurable directly, in a minute, per boot.

## And with the panel actually off, the genpd fix saves 9 %

*2026-08-15 morning. Data: [`2026-08-15_ab-current-legs.txt`](2026-08-15_ab-current-legs.txt).*

The A/B was run again with the display gate actually enforced - `idle-leg.sh`
retries the blank until `card0-DSI-1/dpms` reads `Off` and refuses to run if it
never does. Two legs per arm, fresh boot each, 200 samples after a 300 s settle:

| | leg 1 | leg 2 | mean |
|---|---|---|---|
| genpd fix in | −115.9 mA | −122.2 mA | **−119.0** |
| that one commit reverted | −131.1 mA | −129.8 mA | **−130.5** |

The arms do not overlap. **The fix is worth about 11.5 mA of 130, roughly 9 %.**

☠️ And it is the *opposite sign* from the earlier set, which was run with the
panel refreshing at 65 Hz. That earlier set was not noisy and it was not wrong -
it was measuring a different regime. When something wakes the CPU 65 times a
second the idle windows never get long enough for `cluster-pc` to repay its entry
cost, so the fixed kernel pays for transitions and gets nothing back. Turn the
display off and the windows are long enough for the deeper state to win.

The general form of that, which is worth more than this number: **a confound can
be a regime rather than a bias.** No amount of extra samples or interleaving
would have found this one, because both arms were measured correctly - just not
in the state the question was about. The only thing that found it was gating the
precondition and letting the gate fail loudly.

This also settles the phrasing for the upstream submission. The genpd bug is
SoC-independent and the patch stands on its own; on this board it measurably
improves idle current, and that is now a number rather than an expectation.

## ☠️ All of the above is runtime idle: the phone had never suspended

*2026-08-15, ~09:30.*

Everything measured so far, the 9 % included, was taken with the whole session
alive. `/sys/power/suspend_stats/success` read **0** after fifty minutes of
uptime, and `/sys/power/mem_sleep` offers only `[s2idle]`, which on this
platform is the suspend path rather than a fallback for a missing one. The
"~130 mA idle baseline" is therefore runtime idle with `greetd`, pipewire,
wireplumber, five `xdg-desktop-portal`s, gvfsd, avahi and `wpa_supplicant`
running, and a modem talking at 28 `smd-edge` interrupts a second.

That matters for the target as much as for the number. **10 mA is a different
regime, not a smaller figure in this one** - downstream phones reach it in full
suspend with the modem in its own power-save, never in runtime idle. The
subsystem bisect that was queued next would have apportioned a quantity nobody
should be trying to shave.

The AP side, for its part, is not idle-broken: the genpd `interrupt-controller`
domain had been entered 56 048 times and held for 67 % of uptime.

### s2idle works, and the read-only RTC does not stop it

90 s requested through the RTC wakealarm, **91 s slept**, `suspend_stats`
`success` 0 → 1 with `fail` 0, and the WiFi link reassociated on its own. The
RTC time is stuck in 1970 for want of an `offset` nvmem cell (see
[`../TODO.md`](../TODO.md)), but an alarm is *relative* to the counter, so it is
unaffected - which is exactly what makes an unattended suspend leg safe to run.

☠️ Prove that before relying on it. On a platform whose clock cannot be set it
is a perfectly reasonable guess that its alarm is dead too; the guess was wrong
here, and only the two-minute probe could say so.

### ☠️ The first suspend instrument was wrong, and its numbers are withdrawn

`current_now` has to be sampled and nothing samples while userspace is frozen,
so the first version of [`suspend-leg.sh`](suspend-leg.sh) integrated `charge_now`
instead - on the assumption that a µAh-valued attribute counts charge.

It does not. There is no coulomb counter on this platform: `qcom_smbx` takes its
capacity from `drivers/power/supply/adc-battery-helper.c`, which polls every
30 s and looks the voltage up in an OCV table (`power_supply_batinfo_ocv2cap`)
through a moving average. The file's own header says it exists for devices whose
hardware gauge is absent or limited.

| window | what it reported | what it actually measured |
|---|---|---|
| awake, 600 s | 209 mA | the estimator still walking the SoC down after USBIN was suspended - motion unrelated to the load. `current_now` says 130 mA under the same conditions |
| asleep, 601 s | **0 µAh, 0 mA** | a poll worker that does not run while userspace is frozen |

**A unit is not a mechanism.** One `grep` for the provider would have cost less
than the write-up of a wrong result.

And the awake window was in that script purely as a same-instrument control, in
a regime where a second instrument could contradict it. That is the only reason
the asleep reading did not get published as a spectacular sub-2 mA result: **an
instrument aimed solely at the regime nothing can cross-check is unfalsifiable
by construction.** Give a new one at least one window whose answer is already
known.

### ☠️ The second instrument was wrong too, for the same reason - and so was the third

The replacement read `capacity` at both ends of a three-hour suspend, on the
argument that the pack would be fully relaxed after hours asleep, so an
OCV-derived capacity would be at its most trustworthy. The leg ran on
2026-08-15: `slept=10801s`, one suspend, charger restored cleanly. And
`capacity` read **97 % at both ends** - no drop at all over three hours off
VBUS, which taken at face value would mean well under 10 mA.

It is an artifact, and the same artifact as last time. `capacity` is not sampled
when it is read; it is maintained by the poll worker, which does not run while
userspace is frozen. Three hours asleep produced ten pre-suspend samples and
three post-resume ones. It never had a chance to move.

The third attempt was `voltage_ocv`, which looked live - it matched
`voltage_now - current_now × 120 mΩ` to the microvolt at every snapshot, which
reads exactly like an instantaneous load-compensated value. It is not.
`adc-battery-helper.c` settles it:

| attribute | where the value comes from |
|---|---|
| `VOLTAGE_NOW` | `get_voltage_and_current_now()` - **live ADC, every read** |
| `CURRENT_NOW` | `get_voltage_and_current_now()` - **live ADC, every read** |
| `VOLTAGE_OCV` | `help->ocv_avg_uv` - cached, poll worker only |
| `CAPACITY` | that average through the device tree's OCV table |
| `CHARGE_NOW` | `capacity × charge_full / 100` |

`ocv_avg_uv` is the mean of an 8-deep ring (`ADC_BAT_HELPER_MOV_AVG_WINDOW_SIZE`)
filled at `POLL_TIME` = 30 s, so it is a **four-minute trailing average**. At the
`settled` snapshot 90 s after resume, five of its eight slots were still
pre-suspend values and three were taken under the resume transient - one of them
at 725 mA. The number it reported was a blend of two regimes three hours apart.

The three attributes look like three independent opinions and are one, so say it
in a line: **`capacity`, `charge_now` and `voltage_ocv` are the same measurement
under three names, and none of them can cross a suspend boundary.** Everything
the S2 leg produced through them is withdrawn.

### What does survive from the S2 leg

Only the live pair, and only as a bound. `voltage_now` fell from 4.2055 V (at
139 mA) to 4.0383 V (at 198 mA) across the three hours; compensated by hand with
the device tree's 120 mΩ `factory-internal-resistance-micro-ohms`, that is
4.222 V → 4.062 V, a 160 mV drop.

Both ends are biased the **same** way, so 160 mV is an upper bound and not an
estimate: the first was taken 300 s after leaving a CV charger, with surface
charge still elevating it, and the second 90 s after a resume that pulled 725 mA,
with polarisation depressing it and a static 120 mΩ under-correcting a transient.

The bound is still worth something. The sub-20 mA hypothesis needs essentially
the whole 160 mV to be artifact: a 10 mA leg over three hours moves 30 mAh, which
in this region of the table (~10.6 mV per 1 %) is about 11 mV. **So suspend is
not in the 10 mA regime.** How far it sits from the awake 130 mA, this leg cannot
say.

### The instrument that follows from all of this

Two live attributes, no cached ones, and a **slope** rather than a difference - a
slope cancels any constant offset, which is what every bias found so far turns
out to be, provided the sampling conditions are identical at every point. Then
calibrate that slope against a current the ADC measures directly, rather than
against the OCV table:

* **phase A** - N sleeps of T seconds; after each, exactly 20 s of quiet awake
  time, then one live `(voltage_now, current_now)` read. The fixed wake window is
  what makes the polarisation offset the same at every sample.
* **phase B** - the same total time awake and idle, sampled identically, where
  `current_now` gives the true mean current outright.

`I_sleep = I_awake × (slope_A / slope_B)`. The OCV table never enters, and
`dV/dQ` is near-constant across the span this covers (the table gives ~10.6 mV
per 1 % from 86 % down to 68 %), so the ratio holds. Phase A runs first, so both
phases sit in a similar part of the curve.

Phase B is the same-instrument control, and it is not optional: the awake current
is known independently, so phase B has to reproduce ~130 mA. If it does not,
phase A means nothing. That is the third time today a control window is the only
thing standing between a plausible number and a wrong one -
[`suspend-slope.sh`](suspend-slope.sh).
