# The power investigation, in the order it happened

> ⚠️ **AI-generated.** Written by Claude (Opus 5) working under the direction of
> Lajosházi, László Gergely, who reviewed every change and made or reviewed every
> measurement it rests on.

Everything on this page was once on [`../README.md`](../README.md) and was moved
here on 2026-08-19, unedited, when that page was cut back to the current state of
the device. This is the dated record: what was measured on which day, which
theories were held and then disproved, and which questions are still open.

☠️ **It is not revised when the device changes.** A section here is true of the
day it was written and no other. If you want to know what the phone draws now,
[`../README.md`](../README.md) is the only page that answers that; if you want to
know what to do next, that is [`../../TODO.md`](../../TODO.md) (queue order in
[`../../STATUS.md`](../../STATUS.md)).

Companion pages: [`README.md`](README.md) is the narrative of the first half of
the investigation, [`leads/`](leads/) holds the open leads, [`tools/`](tools/) the
instruments, [`captures/`](captures/) the raw data, and
[`disproven/`](disproven/README.md) the hypotheses that died.

---

## ☠️ Open, but no longer a blanket gate: the CPU0 PLL storm

Measured 2026-08-16. `apcs-cpu0-pll failed to enable!` — 266 times in one boot,
each a `-ETIMEDOUT` out of `wait_for_pll()` while schedutil changes frequency.
It overlapped the awake control leg of the S4 slope run — the leg that has to
reproduce a known current and did not (245 mA against ~130).

**It is still happening.** Every slope leg since carries a `pll=` column and
every one of them counts failures; the leg of 2026-08-18 ended at `pll=435`.

**What has changed is that it has been characterised**, and the blanket warning
this section used to carry — treat every number after 2026-08-15 21:49 as
suspect — is now too strong in one direction and not specific enough in the
other:

- **Rate:** 255 failures in 351 325 transitions = **7.3 per 10 000**, over 26
  points from 4.318 V down to 3.931 V. **No voltage dependence** (fitted change
  3.9 ± 2.9, and the sign runs the wrong way for the sag hypothesis). Below
  3.93 V is untested and the original 3.82 V sighting sits just under that edge.
- **What it still spoils: absolute awake currents.** A storm inflates the draw
  while it runs, which is exactly how the 2026-08-15 leg came back at 245 mA.
- **What it does not spoil: slope ratios.** `I_awake` and `slope_B` both come
  out of phase B, so a storm that inflates the current inflates the slope with
  it and the quotient is immune to first order. This is why the calibration is
  against a measured current and not against the OCV table — worth knowing
  before anyone "improves" the method by dropping phase B.

☠️ **The `pll=` counter is a floor, not a total.** It is read from
`journalctl -k -b`, and it has been observed going *down* across a phase
boundary (320 → 288) because the journal had already dropped records of that
boot. A loud enough storm evicts its own evidence — the same failure mode
`dmesg` had, just later.

Full working in Part II below (the run-book's dated body).

## Measured 2026-08-14: the SoC never reaches an RPM low-power mode

This is the finding the rest of the page should be read against, and it sits a
layer above every milliamp counted below. **The RPM has not taken this SoC to
`vlow` or `vmin` once since boot — not while idle, and not during a ten-minute
suspend** ([capture](captures/2026-08-14_pmos_rpm-sleep-stats.txt)).

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
([capture](captures/2026-08-14_pmos_rpm-master-stats.txt)):

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
[the patch and the measurement](disproven/README.md). That is a
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
([capture](captures/2026-08-14_ut_oracle_rpm-stats.txt)):

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
[`0101-simple-autofocus.patch`](../../../userspace-camera/libcamera/0101-simple-autofocus.patch),
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
180 s window (`docs/power/bringup/captures/2026-08-15_ut_oracle_rpm-master-stats.txt`):

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
[`2026-08-15_vmpm-two-sided.txt`](captures/2026-08-15_vmpm-two-sided.txt).*

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
[`idle-leg.sh`](tools/idle-leg.sh) and [`suspend-leg.sh`](tools/suspend-leg.sh).

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

*2026-08-15 morning. Data: [`2026-08-15_ab-current-legs.txt`](captures/2026-08-15_ab-current-legs.txt).*

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

## ☠️ The ~130 mA is runtime idle, not suspend

*2026-08-15.* Every number above this line — the 9 % included — was taken with
the whole session alive and the phone **never once suspended**:
`/sys/power/suspend_stats/success` read 0 after fifty minutes of uptime. So the
"idle baseline" is runtime idle with `greetd`, pipewire, wireplumber, five
`xdg-desktop-portal`s, gvfsd, avahi and `wpa_supplicant` running, and a modem
talking at 28 `smd-edge` interrupts a second.

**10 mA is a different regime, not a smaller figure in this one** — downstream
phones reach it in full suspend with the modem in its own power-save, never in
runtime idle. Do not treat 130 mA as a target to shave.

`/sys/power/mem_sleep` offers only `[s2idle]`, and that is *the* suspend path
here, not a fallback. It works: 90 s requested through the RTC wakealarm, **91 s
slept**, `success` 0 → 1 with `fail` 0, WiFi reassociating on its own. The RTC
clock is stuck in 1970 for want of an `offset` nvmem cell
([`../TODO.md`](../../TODO.md)) but an alarm is *relative* to the counter, so an
unattended suspend leg is safe to run.

The AP side is not idle-broken: the genpd `interrupt-controller` domain had been
entered 56 048 times and held for 67 % of uptime.

How this was arrived at, and the three instruments that had to be withdrawn on
the way, is Steps 14–15 of [`bringup/README.md`](README.md).

## The `apcs-cpu*-pll` failures are not a low-battery effect

*2026-08-16 evening, measured on `7.1.3-r57` with
[`pll-sweep.sh`](tools/pll-sweep.sh). The instruments are
[`pll-sweep.sh`](tools/pll-sweep.sh) and [`pll-vs-voltage.sh`](tools/pll-vs-voltage.sh).*

The RUNBOOK's next step was a fixed cpufreq sweep at high and low battery,
because the 2026-08-15 storm began at 3.82 V — the lowest the pack had been
that session. The high-battery leg alone answers it:

| | |
|---|---|
| battery | **100 %, 4.345 V, `status=Full`** |
| policy0 transitions (kernel's own `stats/total_trans`) | 3608 |
| `apcs-cpu4-pll failed to enable!` | **90** |
| `apcs-cpu0-pll failed to enable!` | 1 |

Ninety failures at the top of the charge curve. A five-round smoke test minutes
earlier, at **4.41 V**, had already produced one in 52 transitions. Whatever
this is, a sagging supply is not a precondition for it — so the correlation the
storm suggested has a simpler reading: phase B of the slope run was the *awake*
leg, where schedutil changes frequency continuously, and phase A was asleep.
The storm tracks **transition rate**, not volts.

☠️ **The denominator in that table is wrong and the instrument needs fixing
before the ramp is run.** `pll-sweep.sh` pins one policy to the userspace
governor and counts *that* policy's transitions, but almost every failure came
from `apcs-cpu4-pll` — the other cluster, still on schedutil, being driven by
the sweep's own CPU load. The failure count and the transition count are
therefore about different clusters. What survives unharmed is the qualitative
result, because it needs no denominator: failures happen in quantity at 4.35 V.
Before the voltage ramp is worth running, the script has to sweep or pin both
policies and break the failures down per PLL.

☠️ Note also which PLL fails. It is overwhelmingly the **big** cluster
(`apcs-cpu4-pll`, 90 against 1), while the 2026-08-15 storm and the WARNING
captured in
[`2026-08-16_apcs-cpu0-pll-lock-failures.txt`](captures/2026-08-16_apcs-cpu0-pll-lock-failures.txt)
were on `apcs-cpu0-pll`. Both fail; the mix depends on what is driving them,
which is one more reason not to read a rate off a run that did not control it.

### The instrument fixed, and a clean high-voltage baseline

`pll-sweep.sh` now pins every other policy to its lowest frequency under the
userspace governor, so the cluster that is not being swept is out of the
experiment rather than in it unmeasured. Re-run the same evening on r58:

| | |
|---|---|
| battery | 100 %, **4.358 V** |
| policy0 transitions | 553 |
| failures, **all on the swept cluster** | 1 × `apcs-cpu0-pll` |
| rate | **18 per 10 000** |

That is the number a voltage ramp has to be read against. It also shows how much
the unpinned version was measuring the wrong thing: the same script before the
fix attributed 90 failures of the *other* cluster to policy0's transition count.


## The r64 baseline holds: asleep 83.4 mA, and the i2c-qup fix costs nothing

*2026-08-22 overnight, kernel `7.1.3-r64` (#65-fp3 — the i2c-qup pinctrl
sleep/default fix on top of the 08-17 RPM fixes). Raw data:
[`2026-08-22_r64_suspend-legs.txt`](captures/2026-08-22_r64_suspend-legs.txt).*

Two legs, run unattended under the night harness with the guardian armed.

**The 3 h OCV leg first** (`suspend-leg.sh`, one unbroken 10 801 s s2idle,
`suspends=1`): OCV 4.3127 → 4.1695 V before→settled, which through the DT table
is ~94.7 % → ~82.4 %, an upper bound of ~125 mA. As the front page says, an OCV
difference is a bound and not a figure — this one started 300 s off a CV
charger at 100 %, so surface charge inflates the "before" end. It excludes the
<20 mA regime and says nothing finer.

**Then the slope leg** (`suspend-slope.sh r64-post-rpm-fixes`, 900 s settle +
8×900 s sleeps + matched awake control):

```
phase A  asleep  8 samples  slope -45.41 mV/h  r2=0.9881
phase B  awake   8 samples  slope -63.07 mV/h  r2=0.9972  I mean 115.9 mA
RESULT   asleep 83.4 mA   (= 115.9 x 0.720)
```

All 8 suspends completed at full duration; the charger and greetd were restored
on exit. Read against the 2026-08-19 "asleep, no cuts" figure of 79.1 mA this
is the same number within the instrument's spread: **the sleeping baseline
reproduces on r64, and the i2c-qup pinctrl change did not move it** — expected,
since a runtime-suspended I2C controller was already idle, but now it is
measured rather than assumed.

Two caveats that keep this from being over-read:

* ☠️ **Do not compare this leg's −45.4 mV/h against the −35.3…−35.8 mV/h
  baseline slopes.** Those phases sat at 4.03–4.07 V; this one at 4.17–4.26 V,
  above the plateau where dV/dQ is steeper. Same systematic the front page
  already flags — slopes compare only within the same region of the curve.
* The `pll=` column earned its place again: phase A accumulated **7** lock
  failures across two hours of sleeping, phase B **168** across the same time
  awake — the storm tracks transition rate, exactly as characterised on
  08-16, and the sleeping phase is essentially untouched by it.

☠️ One instrument note for the next reader: `suspend-slope.txt` on the device
is appended across nights and boots. `slope-fit.py` fits whatever it is given,
and uptime resets between boots make a joint fit of two runs nonsense (it
reported "45 samples over −20.14 h" before the blocks were separated). Cut the
file to one run's block before fitting.

---

## 2026-08-22: what still blocks vlow — the APSS never XO-shutdowns, measured

Capture: [`captures/2026-08-22_vlow-a1-systemd.txt`](captures/2026-08-22_vlow-a1-systemd.txt)
— three 120 s `rtcwake` s2idle windows, `qcom_stats` (vlow/vmin) +
`rpm_master_stats` + `/proc/interrupts` before and after each. Regime check:
`suspend_stats/success` 4→7, one per window, `rtcwake_rc=0` each.

**A1 — per-master picture across a real suspend window** (`rpm_master_stats`,
mainline driver: the DT node and `CONFIG_QCOM_RPM_MASTER_STATS=m` were already
there, only a `modprobe rpm_master_stats` was missing):

| master | XO shutdown count | Shutdown count | during a 124 s window |
|---|---|---|---|
| APSS | **0, always** | ~50 000 | +57…76 collapses, **0 XO shutdowns** |
| MPSS | ~8 000 | ~8 013 | +~300 XO shutdowns (toggles constantly) |
| PRONTO | ~24 700 | ~24 706 | +~10 |
| LPASS | 52, frozen | 68, frozen | 0 (ADSP asleep for good) |
| TZ | 0 | 0 | inert on this platform |

`vlow` needs every master in XO shutdown at once; **the one master that never
gets there is the APSS**, even mid-suspend. vlow `Count` stayed 0 through all
three windows (vmin too). This narrows the earlier LDO lead rather than
replacing it: the APSS sleep set still says "XO on".

**A2 — who holds XO in the sleep set.** `clk_summary`: `bi_tcxo` (the
both-sets RPM vote, unlike active-only `bi_tcxo_a`) is held prepared+enabled by
**c200000.remoteproc (WCNSS), 4080000.remoteproc (MSS), 7824900.mmc,
7864900.mmc, and c0f0000.codec (ahbix-clk)** — 7 holders, constant across the
run (8 by the end: +1 from the wcd9335 codec path). A lifetime `clk_prepare` on
`bi_tcxo` translates to a sleep-set XO vote, so as long as remoteproc/mmc hold
it, the APSS asks the RPM to keep XO on even while suspended. Together with the
LDO no-sleep-vote finding of 08-17 these are the two named reasons vlow cannot
happen today.

**A3 — what keeps waking the AP inside the window** (window 1, 124 s):
modem smd-edge IRQ **+64** (~one per 2 s), rpm smd-edge **+775** (the RPM
request/ack traffic of the resulting wake/sleep churn), `qcom_mpm` +3, wcnss
edge +1, no active `wakeup_sources` after any window. The modem's edge chatter
is the wake driver; the APSS's 57–76 collapses per window are its echo. This is
the mechanism behind the modem-36 % share, now with a rate.

☠️ Instrument note: every ssh-launched capture (four of them: `setsid`,
`nohup`, detached or not) died at the first `rtcwake` — logind kills the
session cgroup when the USB link drops, and `setsid` does not leave the cgroup.
`systemd-run --unit=… --collect` is the one launch that survives suspend.

## 2026-08-22 evening: xo_sleep_off=1 unlocks the APSS XO shutdown — vlow still 0

Capture: [`captures/2026-08-22_vlow-xo-sleep-off.txt`](captures/2026-08-22_vlow-xo-sleep-off.txt),
same three-window instrument as the morning baseline, booted via the
`postmarketOS-xo` extlinux entry (`clk_smd_rpm.xo_sleep_off=1`, the parked
patch that zeroes the bi_tcxo sleep-set vote). Regime check: success 1→4,
`rtcwake_rc=0` each window.

**The lever works.** The APSS, which had never once entered XO shutdown
(morning baseline: count 0 against ~50 000 collapses), now does so
continuously: count 1663 by 124 s of uptime, +74…84 per 120 s suspend window
(~0.7/s). MPSS/PRONTO keep toggling as before, LPASS stays asleep. So the
morning diagnosis was right: the bi_tcxo sleep-set vote was the thing keeping
the APSS out of XO shutdown.

**And it is still not vlow.** `vlow` (and vmin) `Count` stayed 0 through all
three windows. APSS XO shutdown is necessary and measured insufficient — the
remaining named suspect is the 08-17 finding that the LDOs cast no sleep votes
(`qcom_smd-regulator`), which is upstreamable work. The vlow `Client Votes`
byte pattern did change under the param (0x7030105 / 0x10501 vs the baseline's
0x3070307 family) — undecoded, but it moves with the sleep set.

Operationally: the param survived a guard window plus three full windows plus
a desktop session with zero anomalies. The `-xo` entry stays non-default; the
next step that would make it worth pricing on the battery is a slope leg run
under it, against the 79.1/83.4 mA baseline.

## 2026-08-22 late: the suspend-window "modem chatter" is mostly our own RPM traffic; qrtr is silent

Instrument: ftrace function tracer (kprobes and the function profiler are not
in this kernel) on the smd/qrtr call chain across one 120 s disarmed window —
[`captures/2026-08-22_modem-chatter-counts.txt`](captures/2026-08-22_modem-chatter-counts.txt).
Counts: `__qcom_smd_send` **352**, `qcom_smd_edge_intr` **316**,
`qcom_smd_rpm_callback` **306**, `qcom_smd_qrtr_callback` = `qrtr_endpoint_post`
= **4**. The sample lines show the loop directly: `sugov` (the cpufreq
governor) sends a clk vote → the RPM edge interrupts with the ack → repeat,
~3/s through the whole window.

Reading: (1) the dominant smd traffic during "sleep" is **self-inflicted** —
schedutil freq transitions turning into RPM clk votes, which is the same
churn the morning capture saw as rpm-edge +775; (2) the modem edge's ~35
IRQs/window carry almost **no QMI/qrtr** (4 messages in 122 s) — whatever
rides it is a non-qrtr channel (DIAG, DATA/rmnet, time) or channel-state
toggles, so quieting QMI services would not touch it; (3) the wake fix arms
exactly this line, and 35 events/window matches the armed windows ending in
~4–65 s.

Next instrument for naming the channel: a trace filter on
`qcom_smd_channel_intr` cannot print the channel name without kprobe arg
support — the cheap path is enabling `CONFIG_KPROBE_EVENTS` (+
`CONFIG_FUNCTION_PROFILER`) in the next kernel build, which this session
parked rather than building at night.

## 2026-08-22 late: the vote storm is not schedutil's — governor A/B refutes it

Same-boot A/B ([`captures/2026-08-22_governor-ab-sends.txt`](captures/2026-08-22_governor-ab-sends.txt)),
one 120 s window per arm: pinning `performance` collapsed the cpufreq
transitions (41 → 4 across both policies) while `__qcom_smd_send` did **not**
fall (281 → 335). So the ~3/s RPM traffic during suspend is not
frequency-transition votes; the morning payloads name the real producers —
`bmas`/`bslv` (interconnect bandwidth) and `clk` votes issued per wakeup.
The sugov task in the earlier sample was the messenger, not the cause. The
storm rides *each AP wakeup* regardless of governor, which folds this lead
back into "reduce the wakeups" (the modem edge's ~35/window) rather than
"tune cpufreq". Next instrument for naming the modem-edge channel:
`CONFIG_KPROBE_EVENTS` in the next kernel build.

## 2026-08-22 night: the smd channel census — r67 brings kprobes, and the chatter gets names

r67 is a config-only bump (`CONFIG_KPROBES`/`KPROBE_EVENTS`/`FUNCTION_PROFILER`,
same `_commit`), deployed through the usual gates. First instrument on it: a
kprobe on `qcom_smd_channel_intr` decoding `channel->name`
(`+0x0(+0x18(%x0)):string` — the first attempt with a single deref read the
pointer bytes as the string, worth remembering). One 120 s disarmed window —
[`captures/2026-08-22_smd-channel-census.txt`](captures/2026-08-22_smd-channel-census.txt):

    669  rpm_requests        ← our own clk/icc votes and their acks
     35  IPCRTR              ← the modem edge: ~all its ~35 IRQs land here
     33  sys_mon / WCNSS family (one event set across every open wcnss channel)
      2  each DIAG*/DATA*/apr_voice_svc (open/close-level noise only)

Read together with the 4 `qrtr_endpoint_post` hits from the earlier window:
the modem edge's interrupts poke the **IPCRTR channel without delivering qrtr
payloads** most of the time — signal-level traffic (flow-control/read-acks),
not messages. So "quiet the modem's QMI services" remains the wrong lever; the
right question is what generates the signal-level ring at ~one per 2 s, and
whether the AP's own sends are part of the loop (every local write earns a
remote read-ack interrupt back).

## 2026-08-22 night: call-wake and staying asleep are mutually exclusive today

Measured as an A/B around the 99-suspend check on r67: with the modem edge
wake-armed the check fails ("never suspended - woke at 30705, alarm was
30707": the modem's signal-level ring ends the 6 s window early), disarmed it
passes 3/3. Together with the census above this closes the loop: the same
~one-per-2-s IPCRTR signal traffic that proves the wake path works also means
an armed phone re-wakes within seconds of every suspend. **Silencing that
signal ring is therefore the gate to both** re-enabling automatic sleep and
leaving call-wake armed — the r66 patch stays correct (default off, userspace
decides), but the arm-at-boot unit is a trade-off until the ring is named and
quieted. Next probes: a caller-side census of `__qcom_smd_send` toward the
modem edge during a window (is the AP kicking the loop?), and reading what
the signal bits actually toggle (qcom_smd_channel_intr's early exits).

## 2026-08-22 night: the send census names the AP-side producers

Kprobe on `__qcom_smd_send` with channel-name decode plus stacktrace, one
120 s disarmed window — [`captures/2026-08-22_send-census.txt`](captures/2026-08-22_send-census.txt):

    276  rpm_requests  ← stack: sugov ctx → qcom_icc_rpm_set_bus_rate
     31  WLAN_CTRL     ← wcn36xx control traffic, ~one per 4 s
      2  IPCRTR        ← qmi-proxy recv-path acks only

So the AP's own suspend-window traffic has two named producers: interconnect
bus-rate votes cast on every cpufreq transition (the governor A/B showed the
transitions themselves are wakeup-driven), and the WiFi driver's WLAN_CTRL
chatter. The modem edge's ~35 incoming signal pokes remain the outside half.
Next levers, in measurability order: (1) does `wcn36xx` idle its CTRL
traffic with WiFi down (rmmod/ip link down A/B); (2) icc vote coalescing is
upstream work, not a device patch.

## 2026-08-22 night: WiFi down erases the WLAN_CTRL chatter and a third of the vote churn

Same-boot A/B ([`captures/2026-08-22_wifi-ab-sends.txt`](captures/2026-08-22_wifi-ab-sends.txt)),
one 120 s window per arm: `ip link set wlan0 down` takes WLAN_CTRL from 32
sends to zero and `rpm_requests` from 221 to 151 — the WiFi driver's control
traffic is real wake load, and its wakeups carry icc/clk votes with them.
A concrete lever for the sleeping current (a WiFi-down-on-suspend policy or
wowlan tuning), priceable on the battery with the slope harness. Caveat: the
WiFi link is also the USB-independent rescue path, so any policy must re-up
the interface on resume.

## 2026-08-23: a fully-specified sleep set does not unlock vlow either — measured negative

r68 adds a `both_sets=1` experiment knob to `qcom_smd-regulator` (mirror every
active-set write into the sleep set — the downstream shape: all 23 vendor
rails carry `qcom,set = <3>`, none turn off in sleep, `smpa/3` included at
1.225 V, which killed the earlier off-in-suspend idea). Booted with
`clk_smd_rpm.xo_sleep_off=1 qcom_smd_regulator.both_sets=1`, three full 120 s
windows ([`captures/2026-08-23_vlow-both-sets.txt`](captures/2026-08-23_vlow-both-sets.txt)):
**vlow `Count` stays 0.** So the two named blockers were real but not the last
ones — with the APSS XO-shutdown running and the regulator sleep set fully
specified, something else still holds vlow off. Next suspects, in instrument
order: the interconnect/clk sleep-set completeness (the tracepoint shows
bmas/bslv sleep writes exist — diff what the oracle's sleep set contains
against ours, resource by resource, from the rail-census parser), and the
vMPM/TZ side. The vlow `Client Votes` byte-mask churns with the sleep set
(0x5010501→0x10001 across a window) and remains undecoded — decoding it in
the RPM firmware or downstream headers is probably the shortest path to the
name of the blocker.

☠️ Instrument rule earned tonight: since the arm-at-boot unit exists, **every
suspend-window instrument must disarm the modem edge itself** (and restore it
after) — the first r68 capture ran 8–19 s windows against an armed edge and
was silently about the wrong thing.

## 2026-08-23 dawn: with both_sets the suspect list collapses to the interconnect

The rail census re-run under `both_sets=1`
([`captures/2026-08-23_rail-census-both-sets.txt`](captures/2026-08-23_rail-census-both-sets.txt)):
**every PMIC rail now carries a sleep vote** (0 enabled rails held up by an
absent sleep vote — the 08-19 list is cleared), and the survivors with no
sleep vote are **interconnect resources only**: eight bmas/bslv entries at
bw=50000000 (and a few at 0), plus two disabled smpa rails that no DT
declares. The 240 MB/s icc paths and `bslv/0` DO get sleep votes; the 50 MB/s
ones never do — which points at how `icc-rpm` buckets its votes (AMC vs
WAKE/SLEEP tagging, `keep_alive` paths) rather than at any consumer. Since
vlow still reads 0 under this census's own suspend, the interconnect
sleep-set gap is now the best-named remaining blocker candidate — and it is
generic `drivers/interconnect/qcom/icc-rpm.c` territory, i.e. upstreamable.
Next instrument: read icc-rpm's bucket handling against these eight resource
ids, name which paths they are (`interconnect_graph` debugfs), and test a
sleep-set write for them the same way both_sets did for the regulators.

## 2026-08-23 morning: explicit icc sleep-set zeros do not unlock vlow either — the AP-side space is exhausted

r69 adds an `icc_smd_rpm.sleep_init=1` knob (one explicit sleep-set zero for
every RPM-owned interconnect node at probe — the answer to the elision
question of the icc trail: now the RPM has *seen* a sleep vote for every
resource the AP ever votes). Booted with all three knobs
(`xo_sleep_off` + `both_sets` + `sleep_init`), three full 120 s windows
([`captures/2026-08-23_vlow-sleep-init.txt`](captures/2026-08-23_vlow-sleep-init.txt)):
**vlow `Count` stays 0.** Three measured negatives in one night close the
whole AP-sleep-set family: XO released, every regulator voted in both sets,
every interconnect resource explicitly zeroed for sleep — and the RPM still
never enters vlow. What remains is not on this processor: vlow plausibly
requires every master's XO-shutdown *simultaneously* (MPSS/PRONTO toggle
constantly, so the intersection may simply never happen), or an RPM-firmware
precondition the Client Votes mask encodes. Both are cross-master/RPM-fw
questions — the next instruments are a simultaneity measurement (do the
masters' XO-shutdown windows ever overlap?) and the mask decode, and the
levers may live in the modem/wcnss firmware's own sleep configuration, not
in Linux.

## 2026-08-23 morning: simultaneity achieved, vlow still 0 — the last master standing is the TZ

One 120 s window under all three knobs, full master stats with timestamps
([`captures/2026-08-23_xo-simultaneity.txt`](captures/2026-08-23_xo-simultaneity.txt)):
the APSS entered XO shutdown at tick 710403659 (~37 s uptime) and exited at
3036019762 (~158 s) — **one continuous XO-down window spanning the whole
suspend**, with MPSS (81 cycles), PRONTO (5) and LPASS (44) all cycling
inside it. So every master except one was XO-down simultaneously, repeatedly
— and vlow still reads `Count: 0, Last Entered At: 0`. The one master that
has never once entered XO shutdown, in every capture all night, is the
**TZ** (all-zero stats). Either the TZ genuinely holds an XO vote the RPM
waits on, or its msg-ram stats slice is simply inert and the blocker is a
non-master XO consumer (a PMIC clk client — BT/WLAN sleep clock, debug
block) that no master-stats view shows. Next instruments: the downstream
master list and TZ sleep configuration (vendor tree), and the PMIC's clk
buffer request state (`regmap` dump of the pm8953 clk buffers) during a
window.

## 2026-08-23 morning: the oracle control — half an answer, and the TZ acquitted

Slot switch to UT (4.9.218 downstream), reads in
[`captures/2026-08-23_oracle-vlow-control.txt`](captures/2026-08-23_oracle-vlow-control.txt):
**the TZ's master stats are all-zero on the oracle too** — so the TZ never
XO-shutting is normal platform behaviour, not our blocker; the last-master
theory dies with it. The decisive half stays open: UT's own vlow count was 0
through the visit, but UT **never suspended** — `rtcwake -m mem` fails
outright on it (fail:1, its sleep path is autosleep/wakelocks), and the
`7000000.ssusb` wakeup source is held for as long as a USB cable is in, so
with our only measurement link plugged the oracle cannot sleep at all.
**Whether the working system ever reaches vlow is measurable only with USB
physically detached** — the same physical gate as the rail census, so the
two belong in one detached-cable session (WiFi link, morning). Until that
runs, "vlow has never been reached" describes both slots equally, and the
night's three negatives may simply mean both systems idle in the same
RPM state with the cable in.

## 2026-08-23 morning: the Client Votes mask decodes by subtraction — a set bit means "released"

The mask decode did not need the RPM firmware after all. Take one master's
state away at a time and watch which bit leaves with it
([`captures/2026-08-23_votes-decode.txt`](captures/2026-08-23_votes-decode.txt),
[`_votes-decode2.txt`](captures/2026-08-23_votes-decode2.txt); awake sampling,
1 Hz, `qcom_stats/vlow` read alongside `qcom_rpm_master_stats`):

| leg | state | bytes seen |
|---|---|---|
| L0/L2 | everything up | `01 03 05 07` |
| L1 | `wlan0` down, PRONTO still running | `01 03` |
| L3 | ADSP stopped | `11 13 15 17` |
| L4 | ADSP started again | `11 13 15 17` — **bit 4 stays set** |
| L6 | PRONTO stopped outright | `15 17` |

So each byte is the same 8-bit field sampled four times, not four clients —
which is why the two 16-bit halves are so often equal, and why the halves
sometimes appear byte-rotated. And **a set bit means that client has
released**, not that it is voting: bit 4 appears when the ADSP is stopped and
*stays* after it is restarted, matching the long-known fact that an ADSP
restart frees LPASS for the rest of the boot; bit 2 is pinned set once PRONTO
is stopped. Reading the bits that way:

* **bit 0** — set in every sample ever taken, on this system and on the
  oracle: a client that is always released. The TZ, whose master stats are
  all-zero on both systems, fits.
* **bit 1** — toggles continuously, at about the rate MPSS cycles XO
  shutdown (~3/s). MPSS.
* **bit 2** — PRONTO. Toggles while WiFi is up; **pinned clear with `wlan0`
  down**, where PRONTO's XO shutdown count also freezes outright; pinned set
  when PRONTO is stopped.
* **bit 4** — LPASS. Clear until the ADSP is restarted, then set for good.
  The oracle sets it natively — that is the "downstream-only" bit from the
  earlier sample sheet, and it is not downstream-only, it is
  *ADSP-has-released*.
* **bit 3 — never observed set. Not once, on either system, under any knob
  combination.** By elimination it is the APSS, and it is the one client
  that never releases.

☠️ **A caution for the WiFi lever.** `ip link set wlan0 down` was priced as a
win because it erases the WLAN_CTRL chatter and a third of the vote churn.
This capture shows the other side: with `wlan0` down, PRONTO's XO shutdown
count stops advancing at all and bit 2 sits clear — the co-processor parks
*holding* the XO rather than cycling it. Whatever the churn saving is worth,
it is not obviously a deep-sleep win, and the slope leg has to price the
whole thing, not the churn.

**Next, and cheap:** boot with `clk_smd_rpm.xo_sleep_off=1` — the knob that
makes the APSS actually enter XO shutdown — and sample the mask awake. If
bit 3 starts toggling, the model is confirmed and the mask is not the whole
gate (that boot still showed `vlow` 0). If bit 3 stays clear while the APSS
demonstrably XO-shuts-down, then bit 3 is not the APSS and names a sixth
client nobody has counted — which would be exactly what the RPM is waiting
for.

## 2026-08-23 morning: ☠️ the r66 wake patch oopses when an armed edge is torn down

Found by accident, stopping remoteprocs during the mask decode above. On an
edge whose wakeup source has been **armed**, `remoteproc stop` dies with a
NULL dereference
([`captures/2026-08-23_smd-wake-teardown-oops.txt`](captures/2026-08-23_smd-wake-teardown-oops.txt)):

    pc : klist_put+0x28/0xf0
     device_del / device_unregister
     wakeup_source_sysfs_remove
     device_wakeup_disable
     device_pm_remove
     device_del / device_unregister
     qcom_smd_unregister_edge

**Mechanism, read out of the source and confirmed in sysfs.** Arming an edge
registers a wakeup source, and `wakeup_source_sysfs_add()` gives it a device
parented to the edge — visible as a `wakeup` directory that exists only under
an armed edge. `qcom_smd_unregister_edge()` then runs
`device_for_each_child(&edge->dev, NULL, qcom_smd_remove_device)`, and that
callback unregisters *every* child unconditionally, on the pre-existing
assumption that an edge's only children are smd channels. The wakeup device
goes with them — and then goes a second time when `device_del()` on the edge
reaches `device_pm_remove()` → `device_wakeup_disable()`.

Measured both ways: stopping the ADSP with its edge **disarmed** is clean
(legs L3/L4 above did it twice), stopping it **armed** oopses; the modem edge,
armed at boot by `fp3-modem-wake-arm.service`, oopsed the same way. So this is
a regression our own patch introduced — upstream edges are never
wakeup-capable, so they never gain a foreign child.

**Fix:** `device_wakeup_disable(&edge->dev)` before the child walk
(`wip/7.1.3/power` `d0e738c107e3`, all three layers). Making the walk
selective instead is not available: `rpmsg_bus` is `static` in
`rpmsg_core.c`, so a driver cannot test a child's bus. The LKML draft is
regenerated as a single patch carrying both hunks — the second commit fixes a
bug the first one introduced, so upstream should never see them apart.

## 2026-08-23 morning: the mask under `xo_sleep_off` — bit 0 is the APSS, bit 3 is nobody we have named

The experiment proposed above, run the same morning: boot the `postmarketOS-xo`
label (`clk_smd_rpm.xo_sleep_off=1`, verified `Y` in
`/sys/module/clk_smd_rpm/parameters/xo_sleep_off`), sample the mask awake at
1 Hz while the APSS XO shutdown count climbs from 110 to 719 in 40 s
([`captures/2026-08-23_votes-xo-sleep-off.txt`](captures/2026-08-23_votes-xo-sleep-off.txt)).

**Bit 0 is the APSS.** On every ordinary boot it is set in every sample ever
taken; here, as the APSS starts entering XO shutdown in earnest, bytes of
`0x00`, `0x04` and `0x06` appear for the first time — bit 0 goes clear
exactly when the APSS is down. That fixes the polarity for this bit as *set =
that client is up and voting*.

☠️ **And that contradicts the polarity bit 4 shows**, where the bit appears
when the ADSP is *stopped* and stays set after it is restarted. Both
observations are solid and repeated; what is not established is a single
polarity rule covering both, so **the earlier entry's "a set bit means
released" should be read as one candidate model, not a result.** What is
measured is the correspondence — bit 0 ↔ APSS, bit 1 ↔ MPSS, bit 2 ↔ PRONTO,
bit 4 ↔ LPASS — and the correspondence is what the mask is useful for.

**Bit 3 is still never set.** Not on an ordinary boot, not under any of the
three knobs, not on the oracle, and not here, where four of the five masters
are demonstrably cycling. Every master we can name has now moved a bit; bit 3
has not. Whatever it stands for is not one of the five masters the RPM's own
stats enumerate.

☠️ **A limit on all of this: these are awake samples.** The RPM only weighs
vlow when the masters are actually down, so an awake reading cannot show the
state at the decision point. The mask's own shape suggests the fix: the four
bytes are the same field sampled four times, so the register is a short
history ring — **read immediately after a suspend window it should carry
values from inside that window**. That is the next reading to take, and it
costs nothing beyond adding one mask read to the existing suspend recipe.

## 2026-08-23 morning: reading the mask right after a suspend window — and why the ring is a weaker instrument than it looked

Three 60 s `rtcwake` windows on an ordinary r69 boot, modem edge disarmed for
the duration and re-armed after, mask read as the first statement after resume
([`tools/vlow-ring.sh`](tools/vlow-ring.sh),
[`captures/2026-08-23_vlow-ring-post-suspend.txt`](captures/2026-08-23_vlow-ring-post-suspend.txt)).
All three windows were real — `suspend_stats/success` 0→3, 62 s elapsed each.

Post-resume reads: `0x3010307`, `0x1050703`, `0x1030103`. **Bit 0 is set in
every byte of every one of them**, which on this boot is exactly right and
exactly useless: the APSS never enters XO shutdown here (count 0 throughout),
so it was voting for the whole window and the mask says so. Bit 3 stayed
clear, bit 4 stayed clear (no ADSP restart this boot).

☠️ **The ring turns over faster than the instrument.** The second read, one
second later, already shows different bytes every time (`0x5070507`,
`0x1030105`, `0x3010301`). So the four-sample history spans well under a
second of wall time, and even a read issued immediately after resume is
mostly *post*-resume state. The idea that the ring preserves in-window values
survives only if the resume path itself is quick enough, which this cannot
establish.

**Where that leaves it:** the reading worth taking is the same recipe under
`clk_smd_rpm.xo_sleep_off=1`, the one configuration where the APSS actually
goes down during the window. If bit 0 comes back clear there, the mask
genuinely reflects in-window state and bit 3's silence becomes the whole
question. If bit 0 still reads set, the mask is an awake-state register and
cannot answer anything about the sleep decision at all — worth knowing before
anyone builds on it.

## 2026-08-23 morning: the modem's signal ring is not ours — taking the AP-side QMI clients away changes nothing

The remaining suspicion about the ~one-per-2-s modem-edge poke was that an
AP-side client holding an open channel earns flow-control interrupts back even
without sending messages. Tested directly: four 60 s awake windows counting
the modem edge's IRQ line (GIC 174), taking the userspace qrtr consumers away
one at a time ([`tools/ring-source.sh`](tools/ring-source.sh),
[`captures/2026-08-23_ring-source-ab.txt`](captures/2026-08-23_ring-source-ab.txt)):

| leg | state | modem edge (GIC 174) | rpm edge (GIC 200) |
|---|---|---|---|
| A | everything running | +24 | +1894 |
| B | ModemManager stopped | +33 | +2005 |
| C | rmtfs stopped as well | +20 | +1844 |
| D | started again | +31 | +1988 |

**The ring does not care.** With both `ModemManager` and `rmtfs` gone the poke
rate sits inside the same spread as the baseline — if anything B is the
busiest leg. So the modem produces this traffic on its own, and no userspace
policy on our side will quiet it. That closes the "quiet the QMI services"
branch for good; what remains is the modem firmware's own behaviour or the SMD
channel state machine, neither of which is reachable from a device patch.

Practical consequence unchanged and now better founded: **leaving the modem
edge armed costs every suspend window**, and the trade between call-wake and
staying asleep has to be resolved somewhere other than by silencing the modem
— an inhibitor while ringing, or arming the edge only while the screen is off
and no long sleep is wanted.

☠️ Housekeeping from this run: stopping `rmtfs` leaves it `failed` and
`ModemManager` cannot start again without a reboot (leg D ran with the modem
stack down, which is why its numbers are still normal — the ring is the
modem's, not the stack's). Reboot to restore.

## 2026-08-23 morning: the disarmed modem edge stops cleanly — and MPSS finally gets its subtraction leg

Two answers from one run on the still-unfixed r69
([`tools/mpss-leg.sh`](tools/mpss-leg.sh),
[`captures/2026-08-23_mpss-leg-disarmed.txt`](captures/2026-08-23_mpss-leg-disarmed.txt)).

**The teardown diagnosis holds, tested a third way.** Disarm the modem edge
first and the `wakeup` child directory disappears from sysfs immediately
(`wakeup child dir present: NONE`); stopping that same remoteproc then returns
0, leaves the state `offline`, and puts **zero** "Unable to handle kernel"
lines in `dmesg` — on the same kernel where the armed stop oopsed twice. The
wakeup device really is the whole difference.

**MPSS, at last, by subtraction.** With the modem stopped its XO shutdown
count freezes at 968 and the mask settles into `0x17131713` / `0x13171317` —
every byte `0x13` or `0x17`, so **bit 1 is pinned set**. That is the same
signature PRONTO's bit 2 showed when PRONTO was stopped, and the same one
LPASS's bit 4 shows once the ADSP releases.

☠️ **Correction to this morning's earlier entry.** Three bits are now
confirmed by direct subtraction and they agree on polarity: **bit 1 (MPSS),
bit 2 (PRONTO) and bit 4 (LPASS) go *set* when that master is down.** The
claim that bit 0 is the APSS and that "set means up and voting" does not
survive this — it was inferred from a single knob, not from a subtraction, and
it points the opposite way to the three that were. What is measured about
bit 0 is narrower: it is set in every sample on an ordinary boot and clears
only under `clk_smd_rpm.xo_sleep_off=1`. That is a correlation with the knob,
not an identification of a client, and this log should not have called it one.

**So the standing picture is:** three masters own bits 1, 2 and 4; bit 0 moves
only with the XO knob and is unassigned; **bit 3 has never been set in any
sample from either system.** Two clients' worth of the field are therefore
still unexplained, and one of them never releases.

## 2026-08-23: bit 3 is the TZ — the mask is indexed by the RPM's own master slots

Naming bit 3 did not need another measurement, only reading where the RPM
keeps its per-master state. In `msm8953.dtsi` the master-stats blocks sit in
the RPM message RAM one 4 KB slot apart:

| offset | `offset >> 12` | master |
|---|---|---|
| `0x150`  | 0 | APSS |
| `0x1150` | 1 | MPSS |
| `0x2150` | 2 | PRONTO |
| `0x3150` | 3 | **TZ** |
| `0x4150` | 4 | LPASS |

That is the RPM's own indexing, not a DT authoring order — the addresses are
fixed by the firmware's memory layout. And the four bits this port measured by
subtraction land on exactly those indices: **0 ↔ APSS, 1 ↔ MPSS, 2 ↔ PRONTO,
4 ↔ LPASS**. Four of five slots agree, and the one left over is slot 3.

**So bit 3 is the TZ, and the reason it has never been set in any sample is
the reason its master-stats block is all zeros: the TZ does not participate in
this accounting at all.** The oracle shows the same zeros, so this is not
something the port is missing.

☠️ **This retracts the framing that has been carried since the decode**: the
standing unexplained vote was never "something outside the five masters the
RPM enumerates". It is the fifth master, silent. The mask holds five bits for
five masters and nothing else, and the search for a sixth client should stop.

Note the strength of the claim honestly: bits 0, 1, 2 and 4 are identified by
direct subtraction, bit 3 only by elimination against a structural layout.
Nothing on the AP side can make the TZ vote, so there is no experiment
available that would promote it to a measured identification.

## 2026-08-23: the wakeup teardown fix, verified on the device

r70 (`debug-int/7.1.3` @`1afd8034`) is on the phone. The test the unfixed
kernel failed, run again on both edges that failed it:

| edge | armed | `wakeup` child | stop | oops |
|---|---|---|---|---|
| modem (`4080000`, rproc0) | `enabled` | present | `rc=0`, `offline` | **0** |
| ADSP (`c200000`, rproc2) | `enabled` | present | `rc=0`, `offline` | **0** |

Both restart cleanly with a `start` write afterwards, and the boot ends with
`dmesg | grep -c 'Unable to handle kernel'` = 0. On r69 each of these stops
killed the writing shell and left a NULL-deref oops behind.

☠️ **The remoteproc numbers move between boots.** On the boot where this was
first measured the ADSP was `remoteproc1`; on this one `remoteproc1` is the
WCNSS and the ADSP is `remoteproc2`. Address the node by its platform address
(`c200000.remoteproc` for the ADSP, `4080000.remoteproc` for the modem) or read
`/sys/class/remoteproc/*/name` — an index copied from an older capture will
quietly act on a different co-processor.

## 2026-08-23: an amixer write can NULL-deref the WCD9335, and the source says why

The oops that ended the r70 battery was not the smd teardown. Its trace names
one function:

```
pc : slim_rx_mux_put+0x74/0x188 [snd_soc_wcd9335]
     snd_ctl_elem_write -> snd_ctl_ioctl -> __arm64_sys_ioctl
CPU 4  PID 6745  Comm: amixer     WnR = 1, addr 0x0000000000000008
```

`slim_rx_mux_put()` begins, after a same-value early return, with an
unconditional

```c
list_del_init(&wcd->rx_chs[port_id].list);
```

and `wcd->rx_chs[]` is only ever a `memcpy` of the const `wcd9335_rx_chs`
table in `wcd9335_codec_probe()` — whose `list` members are **zero**. The
heads are initialised in exactly one place, `wcd9335_set_channel_map()`, which
runs when the machine driver sets up the DAI, not at probe. Until then
`__list_del()` does `next->prev = prev` with `next == NULL`, which is a write
to offset 8 of NULL: **the faulting address, with `WnR = 1`, exactly.**

So the guard that normally hides this is nothing more than the order things
usually happen in — audio comes up, `set_channel_map` runs, the heads become
valid. Write the mux before that, or in a state where it never ran, and
userspace takes the kernel down through an ordinary `snd_ctl` ioctl.

☠️ **How it was found is worth as much as the finding.** Two mistakes had to
land together. The verification grep for the teardown fix was
`grep -c 'Unable to handle kernel'`, which is a *subset* of what an arm64 oops
prints — the reliable marker is `Internal error: Oops:`, which is what the
`10-health` check looks for and what caught this. And the ADSP was stopped out
from under a selftest battery that was already running, so two destructive
measurements overlapped on one device. The narrow grep is why "zero oopses"
was reported for a boot that contained one.

**Not yet measured:** whether a clean boot reproduces it without stopping the
ADSP first. That is the leg that separates "a missing `INIT_LIST_HEAD` at
probe, reachable any time before audio starts" from "only reachable once the
DSP has gone away". The fix is the same either way — initialise the heads in
`wcd9335_codec_probe()` beside the `memcpy` — but the commit message and the
upstream framing depend on the answer.

### The timeline says the modem did it, not the ADSP — and the codec was already broken

The previous boot's journal settles the attribution, and it is not the one the
entry above assumed:

```
09:48:14  remoteproc0 (modem) stopped        <- armed-edge test, clean
09:48:30  modem is now up
09:48:55  qcom,slim-ngd-ctrl: HW wakeup attempt during SSR
          wcd9335-slim: WCD9335 CODEC version detection fail!
          wcd9335-slim: Failed to bringup WCD9335        (85 wcd9335 lines)
09:48:57  remoteproc2 (adsp) stopped         <- ADSP test, clean
09:49:02  adsp is now up
09:51:00  amixer -> slim_rx_mux_put -> Oops
```

**Restarting the modem takes the SLIMbus link through an SSR, and the WCD9335
does not survive it**: the re-bringup fails outright on version detection. The
codec is then left with a fresh, zeroed `rx_chs[]` — while the machine
driver's `pdata->slim_port_setup` latch is still `true` from the first
successful init and is never cleared, so nothing will call
`set_channel_map()` again. Two minutes later the selftest's amixer writes a
`SLIM RXn Mux` and the zeroed list head does the rest.

So both edge tests really were clean — the oops arrived from a codec that had
already been broken for two minutes when they ran, and the `dmesg -C` window
around each of them honestly contained nothing. What was wrong was the claim
that the *boot* was oops-free, which the narrow grep could not have seen.

**Three separable defects, in increasing depth:**

1. `slim_rx_mux_put()` will deref a zeroed list head — userspace should not be
   able to oops the kernel through `snd_ctl` in any driver state.
   `INIT_LIST_HEAD` beside the `memcpy` in `wcd9335_codec_probe()` closes it,
   and is upstream-shaped.
2. `slim_port_setup` latches for the life of the card but guards state that
   lives in the codec, which can be re-probed underneath it. Clearing it when
   the codec goes away (or simply letting the idempotent `set_channel_map()`
   run every `dai_init`) closes that. ☠️ The latch is inherited from
   `sdm845.c`, so the same hole is upstream.
3. The WCD9335 does not come back after a SLIMbus SSR at all. That is the
   functional bug behind the other two, and the only one that costs audio
   until a reboot.

☠️ **A modem restart therefore costs audio on this board.** Any measurement
that stops `remoteproc0` should be assumed to have taken the codec with it,
and audio checks after one are measuring the wreckage.

## 2026-08-23 night: both_sets re-measured after the r74 recovery — a reproduction, not a new result

After recovering the phone from the r74 no-boot (the `regulator-state-mem`
DTB, see `TODO.md`), `both_sets=1` was booted again on the r73 kernel and run
through three 60 s `rtcwake` windows
([`captures/2026-08-23_bothsets-reproduction.txt`](captures/2026-08-23_bothsets-reproduction.txt),
`tools`-style probe under `systemd-run --collect`). Result: the regulator
rails cast their sleep votes as designed (61 `sleep ldoa`, 1151 `sleep smpa`,
20 `sleep clka` writes at boot), all three suspends succeeded
(`suspend_stats/success` 0→3), and **`vlow Count` stayed 0** throughout.

☠️ **This adds nothing the 2026-08-23 dawn entry did not already establish**
("with both_sets the suspect list collapses to the interconnect"). It is
recorded only as a same-night reproduction and as a discipline note: coming
back to the deep-sleep item after the recovery, the obvious next move —
"apply the regulator sleep set and read vlow" — had already been run in its
runtime-knob form and answered. The AP-side sleep-set family (XO, regulators,
interconnect) remains exhausted; the two live threads are unchanged and both
need a physical or cross-processor step, not another AP-side knob:

- the **USB-detached oracle measurement** — does the working downstream system
  ever reach vlow with the cable out (the cable holds `7000000.ssusb` awake on
  UT, so it cannot be answered on the wire); and
- **bit 3 of the Client Votes mask**, the one bit no named master ever sets.

The post-suspend mask reads this run (`0x5010501`, `0x5010501`, `0x7030703`)
carry bit 0 set throughout, consistent with the APSS never entering XO
shutdown without `xo_sleep_off` — i.e. exactly the awake-register behaviour
the ring-instrument caveat already described.

**The DTB `regulator-state-mem` form still has standing value** — it is the
*upstreamable* mechanism that both_sets fakes — but purely for mainline
correctness, not for vlow (already answered), and it must be applied one rail
at a time because `regulator_register()` treats a failed probe-time sleep vote
as fatal for every rail on the board (the r74 failure).

## 2026-08-24 night — oracle vlow differential: pmOS control leg (in flight)

Running the pmOS-side control for the oracle `vlow` differential (STATUS queue
item 1, live thread A). Cable IN, no discharge — the only question is whether the
RPM aggregate ever enters `vlow`/`vmin` while the AP idles with the display
**genuinely DPMS-off**. Instrument:
[`tools/`](tools/) `vlow-idle.sh` (new tonight), run under
`systemd-run --collect --unit=vlow-idle` so an ssh drop cannot end it. It stops
greetd, pins `card0-DSI-1` `dpms=Off` (verified, not backlight=0), confirms
`msm_mdss` stopped counting, then samples `qcom_stats/{vlow,vmin}` Count +
Client Votes every 30 s for 90 min, restoring greetd on exit.

★ **This build's `qcom_stats` exposes only `vlow` and `vmin` — no
`rpm_master_stats`.** The APSS master record that earlier legs differenced
(`numshutdowns`, XO counts) is not present under `/sys/kernel/debug/qcom_stats/`
on r73. Noted so a future leg does not assume it. `vlow`/`vmin` Count is the
signal the oracle question actually turns on.

Early samples (fresh r73 boot, uptime 178–238 s): `vlow` **0**, `vmin` **0**,
Client Votes fluctuating (`0x1030105`, `0x1050103`, `0x7030703`) — the mask
moves, so the instrument is live. As expected so far.

☠️ **Method trap, measured tonight: a recursive read of debugfs trips the
watchdog and reboots the phone.** `grep -rl -i shutdown /sys/kernel/debug/` (and
`find /sys/kernel/debug -iname '*stat*'`) hung — some debugfs file blocks the
reading task — and the debug layer's watchdog (20 s hardware timeout, started at
probe) reset the device while it was wedged. Confirmed by the `boot_id` changing
under the session and a fresh ~90 s uptime with no panic line. Never sweep the
whole of `/sys/kernel/debug/` on this device; name the exact file. The `boot_id`
check is what caught it, exactly as the runner guard intends.

## 2026-08-24 — the oracle DOES reach deep sleep; and the two builds expose disjoint instruments

Both halves of the runtime-idle differential ran tonight, cable IN, display off,
device reachable on the wire throughout (pmOS on WiFi, UT on USB rndis — the slot
switch is `reboot bootloader` → `fastboot set_active a|b`, no buttons).

**pmOS control (r73, `#74-fp3`), 57 min, 116 samples**
([capture](captures/2026-08-24_vlow-idle-pmos-r73.txt)): `vlow` Count **0**,
`vmin` Count **0** for the entire window; `dpms=Off` verified (not backlight=0),
`msm_mdss` confirmed quiesced; `boot_id` unchanged. The vlow Client Votes mask
fluctuated the whole time (`0x1030105`, `0x7030703`, …) — the instrument is live,
and the mask is never `0`, i.e. some client is always voting the aggregate up.

**UT oracle (slot_a, 4.9.218-perf-ubuntutouch+), 21 min, 22 samples**
([capture](captures/2026-08-24_vlow-idle-ut-oracle.txt), snapshot in
[2026-08-24_ut-oracle-rpm-lpm-snapshot.txt](captures/2026-08-24_ut-oracle-rpm-lpm-snapshot.txt)).
Per-master deltas over the window:

| master | numshutdowns | xo_count |
|---|---|---|
| APSS   | +22161 (17.6/s) | **+0 (0.0/s)** |
| MPSS   | +3953 (3.1/s)   | +3943 (3.1/s) |
| PRONTO | +11315 (9.0/s)  | +11309 (9.0/s) |
| LPASS  | +15119 (12.0/s) | +15029 (11.9/s) |

`lpm_stats` `[system] system-pc` success climbed +22809 (18.1/s). So the working
downstream reaches its deepest per-master and per-system sleep **continuously**
while idle.

### The three things this settles

1. ★ **The oracle unambiguously reaches deep sleep** — its three co-processors
   (MPSS, PRONTO, LPASS) vote the XO down thousands of times per window, and the
   AP power-collapses ~18/s. The "vlow has never been reached" state is *ours*,
   not something both slots share.
2. ★★ **The AP is NOT the differentiator.** APSS `xo_count` is **0 on both
   systems** — the application processor never votes the crystal down on the
   oracle either (it power-collapses, which is a different vote). Everything the
   AP-side sleep-set family chased (XO / regulators / interconnect) was therefore
   never going to be the lever, which is consistent with that family being
   measured exhausted. **The XO votes that matter come from the co-processors.**
3. ☠️☠️ **The two builds expose DISJOINT instruments, so a same-counter
   differential is impossible.** pmOS r73's `qcom_stats` has **only** `vlow` and
   `vmin` (no `rpm_master_stats`); UT's 4.9 has `rpm_master_stats` + `lpm_stats`
   but **no** `rpm_stats`/vlow file at all (re-confirmed tonight, as the
   2026-08-15 note first found). "Does the oracle reach vlow" cannot be answered
   with the vlow counter — it does not exist downstream — but the co-processor XO
   votes and `system-pc` are the downstream evidence that it reaches the
   equivalent depth.

### ★★★ The next lever, concrete and AP-side-readable

The pmOS half is currently **blind to per-master XO votes** — the one number that
would localise the gate. Earlier pmOS work *did* read an APSS "Shutdown count"
from `rpm_master_stats`, so mainline `qcom_stats` can expose it; this r73 build
does not, which points at the FP3 `qcom,rpm-stats` / soc-stats DT node describing
only the aggregate (vlow/vmin) records and not the per-master subnode. **Restore
the master-stats record on pmOS** (DT, power category) and the decisive
comparison becomes possible on the wire:

- if pmOS's MPSS/PRONTO/LPASS **do** vote XO down like the oracle's, the gate is
  the RPM aggregation itself (closed firmware) and "full vlow" is likely not
  reachable from Linux;
- if they **do not**, the gate is co-processor firmware sleep config — exactly
  the standing STATUS item-1 hypothesis — and that names where to look next
  (modem/wcnss/adsp sleep votes), not another AP-side knob.

Either way the AP-side search is closed by measurement, and the next instrument
is a DT change we can make and read ourselves. ☠️ Until that node exists, do not
quote a pmOS "co-processors don't sleep" claim — it is untested, because the
instrument for it is absent.

## 2026-08-24 (same night, correction) — pmOS DOES have per-master XO votes, and its co-processors sleep like the oracle's

☠️☠️ **Retraction of the entry just above.** It claimed pmOS is "blind to
per-master XO votes" and that reading them needs a DT change to restore
`rpm_master_stats`. **Both are wrong, measured wrong within the hour.** The
mainline `qcom_stats.c` per-subsystem path is RPMh-only
(`subsystem_stats_in_smem = true` only for RPMh configs; the FP3's
`qcom,rpm-stats` → `rpm_data` has it `false`) — but that was never the FP3's
instrument. The fork already carries the downstream-style
`drivers/soc/qcom/rpm_master_stats.c` (`CONFIG_QCOM_RPM_MASTER_STATS=m`) with a
`qcom,rpm-master-stats` DT node in `msm8953.dtsi`. It was simply **not
auto-loaded**, and it creates its debugfs dir as **`qcom_rpm_master_stats`**, not
`rpm_master_stats` — so the earlier "no rpm_master_stats on this build" was
looking at the wrong path for an unloaded module.

**Zero-build fix:** `modprobe rpm_master_stats` → `/sys/kernel/debug/qcom_rpm_master_stats/{APSS,MPSS,PRONTO,TZ,LPASS}`
appear immediately (the platform device binds; the module is just not in any
autoload set). ☠️ Make it persistent with a `modules-load.d` entry or
`CONFIG_...=y` on the next build, or it is gone on the next boot.

### ★★★ The measured result overturns the co-processor hypothesis

pmOS r73 idle, per-master XO shutdowns
([capture](captures/2026-08-24_pmos-master-stats-windowed.txt)), against the UT
oracle rates:

| master | pmOS XO rate | oracle XO rate |
|---|---|---|
| APSS   | **0/s** | **0/s** |
| MPSS   | 2.5/s | 3.1/s |
| PRONTO | **9.1/s** | **9.0/s** |
| LPASS  | frozen (asleep since ~34 s, staying down) | 11.9/s (cycling) |

**pmOS's co-processors vote the XO down at essentially oracle-equivalent rates**
(PRONTO is within 1 %; MPSS is close; APSS votes XO on neither). And yet pmOS
`vlow` Count stays **0**. So the gate is **not** "our co-processors don't
sleep" — the hypothesis the retracted entry set up. All the masters that vote XO
on the oracle also vote XO on pmOS.

### What that leaves as the real gate

1. ☠️ **The `Client Votes` mask is NOT where the holder hides — that decode is
   already closed (2026-08-23) and I nearly re-ran it.** The mask is five bits
   for the five RPM masters, indexed by the message-RAM slot layout: bit 0 APSS,
   1 MPSS, 2 PRONTO, **3 TZ**, 4 LPASS. Bit 3 is never set because the TZ does
   not participate (its master-stats block is all-zero on both systems) — it is
   **not** an unexplained sixth client; "the search for a sixth client should
   stop" (see the 2026-08-23 decode entries below and
   [`leads/rpm-sleep-set.md`](leads/rpm-sleep-set.md)). So the mask being
   "never 0" just reflects the masters' up/down churn, and it names no standing
   holder. My proposing to "decode which client never releases" was re-opening a
   closed thread — recorded here as the correction.
2. **The one behavioural difference is LPASS.** On the oracle LPASS cycles
   (XO count climbing 11.9/s); on pmOS LPASS takes one shutdown at ~34 s and
   **stays down** (XO count frozen), which is the LPASS-CLOSED steady state and
   is if anything *deeper*, not shallower. Unlikely to be the gate.

### ★★★ The synthesis: `vlow` = 0 is uncorroborated by any per-master deficit

Both `rpm_master_stats` readers — pmOS's and UT's — are the **same** ported
downstream driver reading the **same** RPM message-RAM, so this is a true
apples-to-apples comparison, not two different instruments. On it, **pmOS matches
the working oracle**: co-processors vote XO down at the same rates, the AP votes
XO on neither, the mask holds no unexplained vote. The mainline `vlow`/`vmin`
aggregate counter reading 0 on pmOS is therefore **not corroborated by any
per-master sleep deficit** — every master we can read is sleeping as it does on
the slot that works. The most likely reading is that `vlow` is a
counter/firmware-record that does not increment on this SoC's RPM the way the
mainline driver names it, **not** evidence of a power defect. The real
power metric was never this counter — it is absolute draw, already measured (the
slope legs: suspend roughly halves the drain, sleep baseline ~79–83 mA), and
that is where an actual regression would show.

☠️ **Two disciplines this cost, both worth keeping.** (a) The retracted entry
reasoned from `qcom_stats.c` source ("RPMh-only") to "pmOS can't show this" and
stopped, when one `modprobe` showed it — read the device before concluding what
it cannot do. (b) I then proposed decoding the mask as the next step without
first reading the closed 2026-08-23 decode — the same "closed in a lead,
invisible from the resume page" trap the runbook warns about. Read the prior
findings before proposing a next measurement.

## 2026-08-24 (later) — ☠️ CORRECTION to the "vlow is a counter artifact" synthesis: the AP never drops XO, even in a genuine suspend

The synthesis above read `vlow`=0 as *uncorroborated by any per-master deficit*
and therefore "most likely a counter artifact, not a power defect". That was
measured in **runtime idle** (cable-in, no forced suspend). Pushed one step
further — forcing real s2idle with `rtcwake -m mem` and reading
`rpm_master_stats` either side — it is wrong, and in an instructive way.

**The suspend genuinely happens.** `suspend_stats/success` increments per cycle;
`suspendseries.sh` shows both CPU clusters reaching their deepest genpd state
(cluster0 S2 `usage` +1580, `time_ms` +18 s over a 60 s window — `cpu-power-collapse`).
So the phone is not "failing to sleep".

**But there is a per-master deficit, and it is the AP.** Across a 120 s
`rtcwake` suspend (`suspend_success` 2→3), snapping
`/sys/kernel/debug/qcom_rpm_master_stats/*`:

| master | XO shutdown count | across the suspend |
|---|---|---|
| **APSS (application proc.)** | **0 → 0** (XO duration 0 → 0) | never enters XO-shutdown, though its `Shutdown count` climbs +303 (cores do collapse) |
| MPSS (modem) | 40799 → 40981 | **+182**, +0.90 s |
| PRONTO (Wi-Fi) | 164189 → 164295 | **+106**, +1.29 s |
| LPASS (audio DSP) | 79 → 79 | frozen — the LPASS-CLOSED steady state (deeper, not shallower) |

`vlow`/`vmin` Count stay 0 throughout. The RPM aggregates to `vlow` (XO off for
the whole SoC) only when **every** master, the AP included, has voted its
resources down. The co-processors do; the AP never does. So **`vlow`=0 is real**
— the application processor holds the XO up even in s2idle — **not** the counter
misreading it named last night.

The mechanism this points at: mainline msm8953 offers **s2idle only** (no
platform "deep"/`mem` suspend_ops). s2idle freezes tasks and power-collapses the
CPU clusters via cpuidle/genpd, but nothing drives the **APSS RPM master** into
the XO-shutdown handshake the way a PSCI system-suspend path would. The AP's XO
vote is the gate on `vlow`.

☠️ **Discipline:** the artifact reading was not wrong for lack of care — it was
right about what it measured (runtime idle, co-procs sleep like the oracle) and
wrong to generalise from it. *Runtime idle is not suspend.* The decisive
instrument was the per-master XO count taken **across a forced suspend**, not the
aggregate counter and not the idle-window per-master rates. Data:
[`captures/2026-08-24_xo-across-suspend-pmos-r73-cablein.txt`](captures/2026-08-24_xo-across-suspend-pmos-r73-cablein.txt).

**Still open — the one experiment that needs the cable physically out.** Whether
the AP holds XO because the USB controller (`7000000.ssusb`) keeps a resource up
with the cable in, or because the s2idle-vs-deep architecture would hold it
regardless. Re-running the identical XO-across-suspend measurement cable-out is
the discriminator: if APSS XO count / `vlow` finally move → USB is the holder
(a concrete, fixable target); if they stay 0 → it is USB-independent and the fix
is a platform system-suspend path. Detector is armed (polls `charger/online`
→ 0 over the Wi-Fi link, then fires the cable-out run); waiting on the unplug.

### The cable-out discriminator — ☠️ OVERCLAIM, see correction below: the cable is not the variable, but this does NOT rule out the USB controller

Ran the identical XO-across-suspend measurement on battery (`online=0`,
`ibat=-159607 µA`, `suspend_success` 3→4 so the suspend was real):

| | APSS XO count | vlow Count |
|---|---|---|
| cable IN  | 0 → 0 | 0 → 0 |
| cable OUT | 0 → 0 | 0 → 0 |

Same result both ways. The USB controller (`7000000.ssusb`) is **not** what keeps
the AP's XO vote up: the AP never enters XO-shutdown in s2idle whether the cable
is in or out (its `Shutdown count` climbs +988 across the cable-out window —
cores collapse — but XO count stays a hard 0). MPSS (+45) and PRONTO (+115) drop
XO regardless, as before.

So the deep-sleep gate is **USB-independent and architectural**: mainline
msm8953 is s2idle-only, and nothing drives the APSS RPM master into the
XO-shutdown handshake. The fix is a platform system-suspend path (or driving the
XO-shutdown vote from the deepest cpuidle/genpd state), not a USB autosuspend or
wakeup tweak. Data:
[`captures/2026-08-24_xo-across-suspend-pmos-r73-cableout.txt`](captures/2026-08-24_xo-across-suspend-pmos-r73-cableout.txt).

☠️ This does **not** close the "is it USB" branch — see the correction below (the USB controller stayed active regardless of the cable). The remaining oracle question — does the
**downstream** (UT 4.9) AP enter XO-shutdown when it genuinely suspends? — would
say whether this is a mainline regression against a working baseline or a limit
of the SoC's s2idle path itself; it needs the UT slot and the same across-suspend
snap, not another pmOS run.


### ☠️ Correction to both 2026-08-24 entries above (cable back in): two overclaims

Read the two entries above with these two retractions.

1. **"The AP never drops XO" is not a new finding — it was measured 2026-08-22.**
   TODO.md's deep-sleep section already carries "the APSS has never once entered
   XO shutdown (count 0 against ~50 000 power collapses)" from that day. Today's
   forced-suspend runs *re-confirm* it; their real worth is undoing last night's
   own "counter artifact" synthesis, which was itself a regression against the
   2026-08-22 knowledge — not a discovery. And the mechanism line **"the fix is a
   platform system-suspend path" is superseded**: a working XO lever already
   exists — booting `clk_smd_rpm.xo_sleep_off=1` (the parked patch,
   `postmarketOS-xo` extlinux entry) makes the APSS enter XO shutdown ~0.7/s —
   and `vlow` is **still** 0 after it. So the AP's XO vote is one necessary
   condition, not the last gate; the remaining named blocker is the **LDO sleep
   votes** (`regulator-state-mem`, one rail at a time, per
   [`leads/rpm-sleep-set.md`](leads/rpm-sleep-set.md)).

2. **The cable-out A/B does NOT close the "is it USB" branch.** Measured after
   the run (state is unchanged by the cable): `7000000.usb` and `79000.phy` are
   both `power/control=on`, `runtime_status=active`, `runtime_suspended_time=0` —
   dwc3's unconditional `pm_runtime_forbid()` keeps the USB controller **active
   regardless of the cable**. So both my cable-in and cable-out runs had the USB
   controller up; they show the **cable itself is not the variable**, but they
   cannot rule the USB *controller* in or out. The correct experiment, already
   specified in TODO.md's deep-sleep section, is `control=auto` on both nodes
   **and then** detach — that was **not** done. The branch stays open. The
   cable-out capture is still a valid on-battery record that the AP holds XO with
   no charger attached; it just is not the USB discriminator I labelled it.

## 2026-08-24 (UT-oracle across-suspend) — ★★★ the AP-never-drops-XO is a MAINLINE REGRESSION, not an SoC limit

Booted slot a (UT, 4.9.218-perf-ubuntutouch) and asked the downstream oracle the
one question that decides whether pmOS's `vlow=0` is fixable: **does the
downstream APSS master enter XO shutdown across a genuine `mem` suspend?** Same
`rpm_master_stats` driver both sides, so it is apples-to-apples.

**Answer: yes — so the mainline behaviour is a regression.**

- Downstream (UT), CONFIRMED `mem` suspend (echo mem exit 0, 7 s and 12 s real
  sleeps): **APSS `xo_count` 0x0 → 0x2**, exactly matching the two completed
  suspends. The AP *does* vote its XO down in a real suspend.
- Mainline (pmOS r73), CONFIRMED `rtcwake -m mem` suspends (`suspend_success`
  increments): APSS `xo_count` stays a hard **0**.

→ pmOS `vlow=0` is because the mainline msm8953 **s2idle** path never drives the
APSS RPM master into XO shutdown, whereas the downstream **PSCI mem-suspend**
path does. This is a fixable mainline gap, not SoC- or s2idle-inherent. It sits
alongside the already-known **LDO sleep-vote** gap (the AP XO vote is one
necessary condition, not the last gate — `xo_sleep_off=1` already forces APSS XO
on mainline and `vlow` is still 0).

Getting the downstream to suspend on demand was the whole fight, and each layer
is itself a measured fact (full trace in
[`captures/2026-08-24_xo-across-suspend-ut-oracle-slotA.txt`](captures/2026-08-24_xo-across-suspend-ut-oracle-slotA.txt)):
1. downstream honours wakeup sources even on a direct `/sys/power/state` write;
2. `7000000.ssusb` stays an active wakeup source **through a physical unplug**
   (same dwc3 "USB stays active regardless of cable" as pmOS) — cable-out alone
   never suspended it;
3. with ssusb wakeup disabled it *still* aborted every time — a steady ~5
   wakeups/s from the **modem IPC router** (`ipc_rtr_smd_ipcrtr` /
   `NasModemEndPoint`) re-aborted the suspend;
4. `rfkill` covers only BT/WLAN; the modem is ofono-managed (`/ril_0`,`/ril_1`).
   Powering both modems off (ofono `Powered=false`) finally let it complete two
   suspends before traffic resumed. Modems + ssusb wakeup restored afterwards;
   device left healthy (98 %, slot a).

**Caveat kept honest:** downstream reached XO shutdown only with the modem
powered off; the mainline side has **not** yet been re-run with the modem
quiesced (pmOS suspended via rtcwake with the radio up). The comparison is
completed-suspend vs completed-suspend, which is the right axis, but a mainline
re-run with modems off would remove the last asymmetry. `active_cores=0x1` in
every snapshot is only because snapshots are post-resume, not evidence about the
suspended state.

---

## 2026-08-24 (one-rail regulator-state-mem) — ★★ the mechanism casts a real sleep vote and boots; the all-20 no-boot is rail-specific, not inherent

Follow-up to the all-20-rails commit (`arm64: dts: qcom: sdm632-fairphone-fp3:
specify the RPM sleep set for every rail`, r74). That commit added
`regulator-state-mem { regulator-on-in-suspend; }` to **all 20 rails** and the
resulting kernel **did not boot**. The open question was whether
`regulator-state-mem` itself is unusable on this board (the whole
sleep-vote mechanism dead) or whether one specific rail among the twenty breaks
boot when it gets a probe-time sleep vote.

**Answered by a one-rail bisection probe.** Rebuilt the DTB from the working base
(no state-mem) with `regulator-state-mem { regulator-on-in-suspend; }` added to
**only `pm8953_s3`** (nothing else). Deployed DTB-only (extlinux `fdt` line,
lk2nd honours it — `/sys/firmware/fdt` confirmed as the one-rail DTB: exactly 1
`state-mem` + 1 `on-in-suspend` node). Three Step-0 criteria, all met:

1. **Boots** — ~16 s to userspace, boot_id `1a2202e0`.
2. **The sleep vote is actually cast at probe** — the `qcom_rpm_smd_write`
   tracepoint (armed via `trace_event=…:qcom_rpm_smd_write`) shows
   `sleep smpa/3 swen=1` at `t=0.276084` (SMPS group A id 3 = s3; `swen`=software
   enable, value 1). This is measured, not assumed: the probe-time
   `suspend_set_initial_state()` → `.set_suspend_enable` path fired.
3. **Suspend still works** with the vote active — `rtcwake -m mem -s 10`
   completed, `/sys/power/suspend_stats/success` 0 → 1. (RTC reads 1970 on this
   board, but rtcwake's relative alarm still armed; the earlier *detached*
   attempts read success=0 only because the wifi drop during suspend tore down
   the nohup'd shell before it recorded — a foreground run is clean.)

**Conclusion.** `regulator-state-mem` is fully usable here; the all-20 no-boot is
**one (or a few) specific rails**, not the mechanism. The state requested is
identical in both cases (`on-in-suspend` only, no voltage, no rail actually
changes) — so the difference is purely *which/how-many* rails get a probe-time
vote, a clean bisection target.

**But on-in-suspend carries no power benefit** — the rail stays on; only the vote
is made to exist. Neither the one-rail nor a bisected working subset would lower
draw. A real win needs `off-in-suspend` / lower `suspend-microvolt` on rails that
are genuinely unused across suspend (bigger, riskier work), *and* it is gated
behind the primary blocker: the AP never drops XO across suspend
([2026-08-24 UT-oracle](#2026-08-24-ut-oracle-across-suspend--the-ap-never-drops-xo-is-a-mainline-regression-not-an-soc-limit)),
without which the RPM never aggregates to vlow no matter how the LDOs vote.

**Disposition.** The all-20 no-boot commit (`e59893af` wip/power → `4cf51780`
integration → `84241a07` debug-int, pinned by the r74 package) is **reverted** —
a no-benefit change must not ship, and a no-boot one certainly must not be the
package's pinned commit. The mechanism proof stays here and in git history; the
one-rail DTB stays on the device (`/boot/sdm632-fairphone-fp3.dtb-1rail-s3`) for
further per-rail bisection if the off-in-suspend direction is picked up later.

Capture: `sleep smpa/3 swen=1 @ t=0.276084` (ftrace, one-rail-s3 boot `1a2202e0`).

---

## 2026-08-24 (mainline vlow blocker, localized) — ★★★ APSS never releases its XO vote; the blocker is the AP-side RPM sleep-set XO (MMC + codec), not the LDOs and not PSCI/OSI

Went after the top priority — why mainline never reaches `vlow` — from the AP
side, with the correct per-master field this time. Measured on slot b (r73 +
one-rail-s3 DTB, boot `1a2202e0`), across a genuine suspend
(`rtcwake -m mem -s 15`, `suspend_stats/success` 1 → 2). Raw:
[`captures/2026-08-24_apss-xo-shutdown-count-zero-mainline.txt`](captures/2026-08-24_apss-xo-shutdown-count-zero-mainline.txt).

**The decisive per-master number.** `/sys/kernel/debug/qcom_rpm_master_stats`:
APSS **`XO shutdown count: 0`** — the AP has *never once* entered XO shutdown —
while `Shutdown count: 39218` advances (core/cluster power-collapse works, since
the r64 handshake fix). Every other active master drops XO fine: MPSS 5502,
PRONTO 19148, LPASS 48. `qcom_stats` `vlow`/`vmin` stayed 0 across the suspend
(0 → 0 while success 1 → 2). So the SoC-wide low-power aggregate is gated by the
AP alone.

**A hypothesis I nearly wrote up as fact, and the measurement that killed it.**
cpu0 cpuidle shows only WFI + cpu-pc, and dmesg says
`psci: [Firmware Bug]: failed to set PC mode: -1` /
`CPUidle PSCI: failed to create CPU PM domains ret=-517`. Read alone, that is
"the firmware refuses OSI, so deep idle never happens" — clean, plausible, wrong.
The genpd `idle_states` **usage counters** say the opposite: `power-domain-system`
enters `system-pc` (0x42000353) **50933** times (2 during s2idle), the clusters
enter `cluster-pc` ~150k times each. The `ret=-517` was `EPROBE_DEFER`, retried
and recovered; OSI deep idle **works**. cpuidle/PSCI is not the blocker. (The
boot log line is not a steady-state measurement — the usage counter is.)

**Where the gap actually is.** The AP reaches `system_pc` but the RPM still does
not count an APSS **XO** shutdown, because the AP never releases its XO/TCXO vote
in the RPM **sleep set**. Located the holders in `clk_summary`: the root `xo`
(19.2 MHz, enable 7) is held via `bi_tcxo` by the two remoteprocs (own masters,
fine), the **two MMC controllers** (`7824900`/`7864900.mmc`) and the **codec
ahbix** (`c0f0000.codec`) — the last three are AP-side, so their vote lands in the
AP's sleep set. Confirmed the sleep vote directly on the `qcom_rpm_smd_write`
tracepoint: `sleep clk0/0 … 45 6e 61 62 … 01 …` = CXO `"Enab"=1` in the sleep
context (measured, not inferred).

**What this reorients.** The `vlow` blocker is the **AP-side RPM sleep-set XO
vote**, held by the SD/eMMC controllers and the codec ahbix through the
sleep-voting `bi_tcxo` branch rather than the active-only `bi_tcxo_a`. It is
**not** the LDO regulators (why the regulator-state-mem thread could never move
`vlow`) and **not** cpuidle/PSCI/OSI (which works). Next: make those AP-side
consumers drop their sleep-set XO vote (runtime-PM across suspend, or the
active-only clock), then re-read APSS `XO shutdown count` and `vlow`. Vendor
oracle: `/mnt/1TB/Fp3-Sailfish/hadk22/kernel/fairphone/sdm632`.

**☠️ Reconciliation, same day (do not over-read the above).** Checked against the
prior `clk_smd_rpm.xo_sleep_off=1` measurement before concluding: that lever
already forces APSS into XO shutdown and `vlow` **still stayed 0**, and the LDO
sleep-set candidate is separately killed (`both_sets=1`). So the AP-side XO vote
localized here is **necessary, not sufficient** — fixing the MMC/codec holders
will make APSS XO-shutdown naturally but will not by itself reach `vlow`. The net
new value of today's work is (a) disproving the PSCI/OSI "[Firmware Bug]"
hypothesis (system_pc *is* entered, 50933×) and (b) naming the natural XO holders
for upstream correctness. The open `vlow` frontier remains the **USB controller**
`control=auto`+detach test (STATUS queue item 1), not the XO vote and not the LDOs.

---

## 2026-08-24 (USB controller eliminated) — ★★★ the last named vlow frontier is closed; every named candidate is now exhausted

Ran the `control=auto` + physical-detach test that STATUS had left open. An
autonomous device-side watcher armed `control=auto` on `7000000.usb` + `79000.phy`,
waited for the cable to be unplugged, measured across a real `rtcwake -m mem`
suspend, then restored `control=on`. Raw:
[`captures/2026-08-24_usb-controller-not-the-vlow-blocker.txt`](captures/2026-08-24_usb-controller-not-the-vlow-blocker.txt).

With `control=on` the dwc3 never runtime-suspends, so every earlier suspend
carried an un-collapsed USB controller — it "was never tested". This time, after
detach, `7000000.usb` **did** runtime-suspend (`susp_time` 44 → 659 ms across the
suspend) and so did the phy. Result across the suspend (success 2 → 3):
**APSS XO shutdown count stayed 0, `vlow`/`vmin` stayed 0.** So the USB controller,
fully suspended, is **not** the `vlow` blocker.

That closes the last named frontier. The state of the search: **every named
candidate is exhausted** — LDO sleep set (killed), AP XO vote (necessary-not-
sufficient: `xo_sleep_off=1` forces it, `vlow` still 0), cpuidle/PSCI/OSI (works,
`system-pc` entered 50933×), USB controller (eliminated here). The `vlow` blocker
is something not yet on the list. The sharpest unresolved thread: even forcing
*every* master's XO vote down (`xo_sleep_off=1`) leaves `vlow` at 0 — which is
consistent with a genuine non-XO holder, but also with mainline `qcom_stats`
reading the wrong RPM stats region/format for msm8953. That region/format check
was set aside earlier as "real, not artifact"; now that all masters can be made to
vote XO down and the counter still will not move, it is worth a direct check
before assuming a hidden holder.

**Region/counter sub-question, answered same day.** Before chasing "wrong RPM
stats region", dumped the full `qcom_stats/vlow` record: `Count`/`Last Entered`/
`Accumulated Duration` all 0, but **`Client Votes: 0x7050705`** — non-zero and
clean. A misaligned region would not produce a tidy votes mask beside all-zero
duration fields, so the driver **is** reading a valid, live RPM stats region:
`vlow`=0 is real, not a counter artifact. Combined with the already-closed
Client-Votes decode (2026-08-23: no mystery holder), the region/counter
explanation is out. What is left is at the **RPM protocol/handshake level** —
why the RPM never triggers `vlow` entry even with valid votes and every master
made to drop XO (`xo_sleep_off=1`) — which needs a downstream-vs-mainline RPM
message-sequence comparison during suspend, a much larger reverse-engineering
effort than any single lever. That is the honest frontier as of 2026-08-24.

---

## 2026-08-24 (the non-XO `vlow` holder, NAMED) — ★★★★ mainline pins the backbone bus/mem clocks and NoC bandwidth in the RPM **sleep set**; the RPM cannot collapse the backbone while they are up, XO or no XO

The frontier above asked the one open question: with valid votes and every master
forced to drop XO, **what non-XO resource keeps the RPM out of `vlow`?** It was
answered by dumping the *entire* mainline RPM sleep set from a from-boot
`qcom_rpm_smd_write` trace and decoding the final value of every resource — the
first time the whole sleep aggregate (not just the XO/regulator slice) was read.

**Method.** Booted r73 on the `postmarketOS-sleepset` label (working r73 kernel +
the confirmed-booting `1rail-s3` DTB + `trace_event=qcom_smd_rpm:qcom_rpm_smd_write
trace_buf_size=8M`, **no** `both_sets` contamination), boot `67a43246`. Dumped the
ring, took the **last** write per resource (that is the value the RPM currently
holds), and confirmed it survives a genuine suspend (`rtcwake -m mem -s 12`,
`suspend_stats/success` 0 → 1). Raw:
[`captures/2026-08-24_sleepset-backbone-clocks-pinned-mainline.txt`](captures/2026-08-24_sleepset-backbone-clocks-pinned-mainline.txt).

**The decoded sleep set** (key FourCC → LE32 value; `4b487a00`="KHz", `456e6162`=
"Enab", `766c766c`="vlvl", `62770000`="bw"):

| resource | type / meaning | final **sleep** vote | verdict |
|---|---|---|---|
| `smpa/2` "vlvl" | VDDCX corner (rpmpd + pm8953_s2) | **0** | ✓ drops — not the holder |
| `smpa/7` "vlvl" | VDDMX corner | **0** | ✓ drops — not the holder |
| `clk0/0` "Enab" | MISC_CLK 0 = **bi_tcxo / XO** | 1 | the known XO holder |
| `clk2/0` "KHz" | MEM_CLK 0 = **bimc** (DDR backbone) | **211 200 kHz** | ☠️ pinned |
| `clk1/0` "KHz" | BUS_CLK 0 = **pcnoc** | **87 500 kHz** | ☠️ pinned |
| `clk1/1` "KHz" | BUS_CLK 1 = **snoc** | **87 500–100 000 kHz** | ☠️ pinned |
| `bmas/*`,`bslv/*` "bw" | icc-rpm NoC **bandwidth** | **0x0e4e1c00 ≈ 240 MB/s** | ☠️ pinned |

So the rails (Cx/Mx) correctly reach 0 in the sleep set — but the **backbone
clocks (bimc/pcnoc/snoc) and the NoC bandwidth are pinned at their active idle
values**, and stay there across a real suspend (measured before *and* after:
bimc `00 39 03 00`, pcnoc/snoc `cc 55 01 00`, bw `00 1c 4e 0e`, unchanged;
`vlow`/`vmin` Count 0 → 0). `vlow` is defined (downstream `rpm_stats` binding) as
the RPM **lowering or powering down the backbone rails Cx/Mx *and* the XO** — it
cannot do that while the AP's sleep set still demands bimc at 211 MHz and 240 MB/s
of NoC bandwidth. **This is why `xo_sleep_off=1` alone never moved `vlow`:** it
drops the XO but leaves the backbone clocks and bandwidth up, so the RPM still has
no permission to collapse the backbone.

**Root cause, read from source (two mirroring bugs, one per subsystem).**
1. `clk-smd-rpm.c:280 to_active_sleep()` — for any clock **not** marked
   `active_only`, the **sleep-set rate is set equal to the active rate**
   (`*sleep = *active`). `bimc` (MEM_CLK), `pcnoc`/`snoc` (BUS_CLK) are not
   active_only, so whatever rate they run at while the AP is idle is *also* voted
   into the sleep set. There is **no suspend hook** in the driver to lower it —
   the sleep vote just mirrors the last active rate forever. (The existing
   `xo_sleep_off` param is the *only* escape, and it is hard-coded to the XO clock
   alone via `clk_smd_rpm_is_xo()`.)
2. `interconnect/qcom/icc-rpm.c` — bandwidth is aggregated per context
   (`agg_clk_rate[QCOM_SMD_RPM_ACTIVE_STATE]` vs `…SLEEP_STATE`), but a consumer
   whose path request is tagged `QCOM_ICC_TAG_ALWAYS` (the common default) counts
   in **both** contexts, and nothing re-tags or drops it at suspend. So an
   always-on NoC path (CPU↔DDR, storage, etc.) leaves a nonzero **sleep**
   bandwidth vote that pins the NoC up.

**Why downstream (4.9, reaches deep sleep) differs — this is the "final handshake"
the frontier was chasing, and it is a *content* difference, not a wire-protocol
one.** Downstream RPM-SMD (`drivers/soc/qcom/rpm-smd.c`) does **not** send sleep
votes eagerly. Every sleep-set request is **buffered** in an rb-tree
(`msm_rpm_smd_buffer_request()` → `tr_root`) and physically transmitted to the RPM
only by `msm_rpm_flush_requests()`, called from `msm_rpm_enter_sleep()` **at the
moment the AP commits to system power-collapse** (with the SMD RX interrupt
masked). The buffered sleep values are the ones the AP wants applied *while it is
actually asleep* — for the AON bus masters that is a minimal/zero bandwidth,
because the msm-bus driver keeps a separate sleep-context vote that drops when the
AP suspends. Mainline has neither the buffer nor the flush nor the suspend-time
re-vote: it wrote the sleep set once, at probe/vote-change time, mirrored from the
active rate, and never revisits it. **The downstream AP's "enter sleep" step
rewrites the sleep set to the truly-idle backbone floor; the mainline AP never
does, so the RPM's sleep set permanently describes a running backbone.**

**Status of the claim.** Measured and source-confirmed that the backbone
clocks/bandwidth are pinned nonzero in mainline's sleep set across a real suspend,
and that Cx/Mx are not. **Not yet proven by construction** that zeroing them is
sufficient for `vlow` — that is the decisive next experiment: a sibling of
`xo_sleep_off` that forces the sleep-set vote to 0 for the non-active_only
BUS/MEM clocks (and, if needed, the icc sleep bandwidth), run **together with**
`xo_sleep_off=1`, then re-read `vlow`. Risk is the same class as `xo_sleep_off`
(gating the backbone during an s2idle the AP may need to resume through) — so it
goes on a **non-default** label with the documented reboot-and-unset recovery. If
`vlow` moves, the fix is upstreamable: either mark these clocks active_only for
this platform, or add a real suspend-time sleep-set drop (the mainline equivalent
of the downstream flush). Category: **power**.

Captures: `captures/2026-08-24_sleepset-backbone-clocks-pinned-mainline.txt`
(decoded final sleep set) and the in-run suspend witness above.

---

## 2026-08-24 (sleep_bw_off experiment #1) — ★★★ the blunt "zero the backbone sleep votes always" boot-loops, and that failure CORROBORATES the finding: the RPM applies the sleep set during idle, and zeroing the backbone bandwidth visibly collapses the display

Built the decisive lever: `icc_smd_rpm.sleep_bw_off`, a sibling of
`clk_smd_rpm.xo_sleep_off`, that forces the SLEEP-context per-node bandwidth
(`bmas`/`bslv`) **and** the bus-clock sleep rate (bimc/pcnoc/snoc, via
`qcom_icc_update_provider`) to **0** for every RPM-owned NoC node. Full r73
rebuild (envkernel), hand-deployed as `/boot/vmlinuz-sleepbw` on a **non-default**
label `postmarketOS-sleepbw-exp`, armed with
`clk_smd_rpm.xo_sleep_off=1 icc_smd_rpm.sleep_bw_off=1` + the tracepoint.

**Result: it does not boot — it boot-loops with a garbage (random-colour-noise)
display**, observed on the physical screen (reboot cycle: garbage → reset →
garbage). No SSH, no clean userspace. Recovered cleanly via the cross-slot route
(fastboot `set_active a` → UT → loop-mount `system_b` pmOS `/boot` at offset 1 MiB
→ revert `default` to `postmarketOS-prev` → `set_active b` → reboot; pmOS r73 back
in ~24 s). ☠️ Note for next time: `fastboot devices` never listed the device
during the loop (too-brief window), but a **blocking** `sudo fastboot set_active a`
caught it the moment the user held vol-DOWN+power; and `fastboot` needs `sudo`
here (no udev rule — `fastboot devices` prints nothing as non-root).

**Why this is a result and not just a failed build.** `xo_sleep_off=1` alone is a
known-good, boots-fine knob (measured before). The **new** breakage is
`sleep_bw_off`, and a *garbage display* is the signature of the display/MDSS
losing its NoC bandwidth / DDR path. So the failure says two concrete things:
1. The RPM **applies the sleep-set backbone votes during ordinary idle windows**
   (the AP WFIs between boot tasks), not only across a full suspend — otherwise a
   sleep-only vote could never affect a booting system.
2. Zeroing the backbone sleep bandwidth **actually collapses the backbone** — the
   lever has real teeth. It collapsed it at the wrong time (panel still on, so the
   display still needs that bandwidth), which is why it looked like corruption.

That is exactly the **keepalive** problem Konrad Dybcio's upstream "SMD RPMCC
sleep preparations" series exists to solve: some consumers (here the display while
the panel is on) must keep an active/always vote so the backbone is *not* dropped
under them. A blanket "zero all sleep bandwidth, always" violates that invariant
during runtime; it is only correct **once the display and the other AON consumers
have themselves suspended** — i.e. scoped to the actual suspend sequence, which is
precisely what downstream's `msm_rpm_flush_requests()` (fired at power-collapse,
after everything else is down) achieves and what this blunt param does not.

**Corrected next experiment (the upstreamable shape).** Do not force the sleep
votes globally. Instead re-vote the backbone sleep set to 0 **inside the icc
provider's own suspend callback** (`dev_pm_ops.suspend`/`.suspend_noirq` — these
*do* run on this device's s2idle path, unlike `syscore_ops`, and they run *after*
`dpm_suspend` has already turned the display off and let it release its
bandwidth), restoring the saved values on resume. That makes the zeroing safe
(nothing on-screen to starve), scopes it to real suspend, and is the mainline
equivalent of the downstream flush. Then re-read `vlow`/`vmin` across an
`rtcwake -m mem` suspend. Web scan (2026-08-24) found no existing issue/fix for
this on RPM/SMD SoCs; the closest upstream work is Dybcio's active_only/keepalive
prep (MSM8996/8998/SM6375) and the ICC restructure — infrastructure, not a
reached-`vlow` result.

Device state after: r73, `default postmarketOS-prev`, fallback net intact, the
`vmlinuz-sleepbw` + `postmarketOS-sleepbw-exp` label left in place (non-default,
inert) for the corrected rebuild.

---

## 2026-08-24 (sleep_bw_off experiment #2 — the CONCLUSIVE one) — ★★★★★ every AP-side sleep vote driven to the deep-sleep floor + every master in XO shutdown, and `vlow` STILL 0 → the blocker is NOT a vote, it is the RPM sleep-entry HANDSHAKE

Rebuilt `icc_smd_rpm.sleep_bw_off` as a **suspend-scoped** hook instead of the
blunt always-on form: `qcom_icc_rpm_suspend_late()` rewrites every RPM-owned
node's sleep-set bandwidth **and** the bus-clock sleep rate to 0, and
`qcom_icc_rpm_resume_early()` restores them (wired via an exported `qnoc_pm_ops`
on `qnoc-msm8953`'s `.driver.pm`; `suspend_late` runs after `dpm_suspend` has
already suspended the display, with IRQs still on so the RPM ack path works, and
it fires on this SoC's s2idle path). **This kernel boots cleanly** — confirming
experiment #1's boot-loop was purely the runtime application of the sleep set,
not a probe/boot problem.

**Measured on the device** (boot `ae5c4633`, `xo_sleep_off=1` +
`icc_smd_rpm.sleep_bw_off=1`, across a genuine `rtcwake -m mem -s 15`,
`suspend_stats/success` 0 → 1;
[capture](captures/2026-08-24_sleepbw-suspend-hook-all-votes-zero-vlow-still-0.txt)):

- The hook **fired**: the `qcom_rpm_smd_write` tracepoint shows, from the
  `rtcwake` task during the suspend, `sleep clk1/0`, `sleep clk1/1`,
  `sleep clk1/2`, `sleep clk2/0` all written **`00 00 00 00`** (bimc/pcnoc/snoc
  sleep rate → 0), and the `bmas`/`bslv` `bw` sleep votes written **0**.
- So during the s2idle window the **entire AP-side sleep set was at the
  deep-sleep floor**: XO `Enab`=0 (xo_sleep_off), bimc/pcnoc/snoc rate 0, NoC
  bandwidth 0, Cx (`smpa/2`) level 0, Mx (`smpa/7`) level 0.
- And **every master entered XO shutdown**, read from
  `qcom_rpm_master_stats`: APSS `XO shutdown count` 2436 (+18 across the
  suspend), MPSS 289, PRONTO 696, LPASS 47, TZ 0 (inert). APSS `Shutdown count`
  2679 — the AP genuinely power-collapses.
- **`vlow` Count: 0. `vmin` Count: 0.** Unchanged across the suspend.

**This exhausts the vote hypothesis.** Over the whole investigation every AP-side
sleep-set contribution has now been individually driven to its deep-sleep value
and *combined* in one run — XO (xo_sleep_off), the LDO/SMPS enables+levels
(both_sets, and Cx/Mx reach 0 natively), the interconnect bandwidth, and the
backbone bus/mem clocks — while every co-processor master independently reaches
XO shutdown. If a nonzero sleep vote were the gate, `vlow` would have moved. It
did not. **The remaining blocker is not any resource vote; it is the RPM's
sleep-entry trigger** — the step that tells the RPM "the AP is now entering sleep,
switch to the sleep set and re-aggregate for the backbone-collapse (`vlow`)
mode."

**What downstream does that mainline does not (the named handshake).** Downstream
4.9 `rpm-smd.c` buffers all sleep-set requests and, at the deepest cluster level,
`msm_rpm_enter_sleep()` (a) **masks the SMD RX interrupt** — signalling the RPM
that the AP will no longer service messages, i.e. is going down — and (b)
**flushes the buffered sleep set as one batch** (`msm_rpm_flush_requests()`).
Mainline `qcom_smd-rpm` has neither: it writes each sleep vote eagerly at
vote-change time and has no cpuidle/s2idle hook that ever tells the RPM the AP is
entering sleep. The votes are all present and correct; the RPM simply never
switches to acting on them for `vlow`, because from its point of view the AP
never announced the transition. (On PSCI the SPM/SAW→RPM hardware handshake is
firmware-driven and identical on both slots, so it is not the differentiator; the
software SMD-RX-mask + flush is.)

**Status of the deliverables.**
- The icc suspend-scoped sleep-set drop (`qcom_icc_rpm_suspend_late/resume_early`)
  is a genuine, upstreamable correctness improvement (it is what should lower the
  backbone in the sleep set), and it works — but it cannot reach `vlow` alone
  because the handshake is missing. Kept in the tree
  (`drivers/interconnect/qcom/icc-rpm.c` + `msm8953.c` `.pm`), default-off param.
- The next real step is to implement the mainline equivalent of
  `msm_rpm_enter_sleep`: from the s2idle/cpuidle path, mask the qcom_smd-rpm RX
  interrupt (and/or assert whatever "AP entering sleep" the RPM expects) so the
  RPM adopts the sleep set. That is a substantial, novel addition to
  `drivers/soc/qcom/smd-rpm.c` + a cpuidle hook, not a one-liner — and it is now
  the *single* identified blocker, the vote-space having been ruled out by
  construction.

Device restored to clean r73 (`default postmarketOS-prev`); the suspend-hook
kernel + `postmarketOS-sleepbw-exp` label remain in place (non-default, inert) as
the diagnostic vehicle.

## 2026-08-24 (continued) — ★★★★★ vlow read RAW on the working oracle: it is 0 there too. The target was a phantom; the deep-sleep item CLOSES

The "handshake is the single remaining blocker" conclusion above had one
untested premise: that the working system ever reaches `vlow` at all. The
counter "does not exist downstream" as a debugfs file — but the *record*
exists: it lives in RPM message RAM, written by the same RPM firmware on both
slots, at the address mainline `qcom_stats` reads (`qcom,rpm-stats`,
phys `0x290000`, dynamic offset at `+0x14`). A ~30-line mmap reader
(`tools/rpmstats_raw.py` — `read(2)` on `/dev/mem` EFAULTs on this config,
`mmap` works) reads it on **both** systems, bypassing the disjoint-instrument
problem for good.

**Validation (pmOS r73):** raw read matches debugfs `qcom_stats/vlow`
byte-for-byte, including the live Client Votes mask. Instrument proven, and
proven against its own kernel-side decoder.

**The oracle leg (UT 4.9.218, slot a, cable in, screen off, ~10 min idle
window 13:38:57→13:48:57):** during the window the oracle demonstrably did its
full continuous deep sleep —

| master | delta over the window |
|---|---|
| APSS numshutdowns | **+34 603** (~58/s; xo_count 0, as always) |
| MPSS xo_count | +1 779 (~3/s) |
| PRONTO xo_count | +4 997 (~8.3/s) |
| LPASS xo_count | +7 745 (~13/s) |

— and the RPM's own record throughout: **`vlow` count=0, last_entered=0,
accumulated=0; `vmin` all-zero** (Client Votes churning: `0x1110105` →
`0x1051505`, so the record is live, not stale). Captures:
[`2026-08-24_ut-master-stats-idle-before.txt`](captures/2026-08-24_ut-master-stats-idle-before.txt),
[`2026-08-24_ut-master-stats-idle-after.txt`](captures/2026-08-24_ut-master-stats-idle-after.txt).

### What this settles

1. ★★★★★ **The working downstream system never enters `vlow` either.** With
   tens of thousands of AP power collapses and thousands of co-processor XO
   shutdowns in the very window, the RPM never once aggregated to `vlow`
   (or `vmin`). `vlow`=0 is **platform behaviour on this device/firmware**,
   not a pmOS defect. There is nothing to fix.
2. **The "missing handshake" thread closes too — nothing is blocked by it.**
   The code audit this afternoon already weakened it: the RPM-observable part
   of the downstream sleep entry (vMPM wakeup-time write + IPC doorbell) exists
   and provably works on mainline (the 1s-cap fix's measured effect *is* the
   RPM honouring the vMPM deadline), while `msm_rpm_enter_sleep`'s two halves
   (GIC-level SMD RX mask + batch flush) are **AP-local and invisible to the
   RPM**. The oracle measurement now confirms it from the other side: the
   downstream system *has* the handshake and still never reaches `vlow`.
   No `smd-rpm.c` s2idle driver work is warranted; that planned next step is
   cancelled.
3. **The success criterion was met before this entry.** Oracle-equivalence in
   every readable per-master metric was already measured (co-proc XO rates
   match; AP collapses; genuine s2idle works), and the real power metric is
   absolute draw: sleep baseline 79–83 mA, modem-cut 43 mA. The remaining
   deep-sleep work is the **modem-lead** (TODO), not any RPM mode counter.

☠️ **Discipline, again the same shape as 08-16 and last night:** a target
inherited from a counter's *name* ("deepest mode, so reaching it = success")
was chased through the entire AP-side vote space before anyone checked whether
the reference system ever produces it. The two-sided rule applies to the
*goal*, not just the mechanism: before adopting a metric as a target, measure
it on the oracle. The raw-mmap reader is the instrument that should have
existed three weeks ago — the debugfs asymmetry ("no such file downstream")
was allowed to stand in for "unknowable downstream".

Device restored to slot b, clean r73 default. ☠️ Operational note (user-supplied):
after a slot switch to UT, ssh comes up **only after the user logs in and
replugs USB** — ask for it in advance next time; the "no-touch" reconnect times
hold for plain reboots only.

## 2026-08-24 (scope caveat on the closure, added same night)

One corner the closure entry above did not cover, stated so it cannot be
mistaken for covered: the oracle window measured **runtime idle** (cable in;
UT's `7000000.ssusb` wakeup source blocks suspend on the wire), not a genuine
downstream `mem` suspend. Earlier the same day a forced downstream suspend
(modems powered off + ssusb wakeup disabled) measured APSS `xo_count` 0 → 2 —
so downstream *suspend* is a state the idle window did not sample, and whether
`vlow` increments **there** remains unmeasured. It does not reopen the item:
daily-use oracle depth (continuous system-pc + co-proc XO cycling) is what the
port is held against, and that is where `vlow` is now proven never to occur.
If anyone wants the last corner: re-run `tools/rpmstats_raw.py` around the
forced-suspend recipe on slot a (needs the modem-off + wakeup-disable steps
from the 2026-08-24 UT-oracle entry, and a user login + USB replug after the
slot switch).

## 2026-08-24 (night) — the modem lead opens: MPSS XO-duty differential launched

With `vlow` closed, the top power item is the modem's ~36 mA (79.1 → 43.3 mA
asleep, named "modem processor off" after the `rmtfs -P` contamination was
found). First uncontaminated instrument launched tonight on r73, cable in,
no discharge needed: `modem-xo-duty` (systemd-run --collect), two genuine
`rtcwake -m mem` 90 s suspends per arm, arms = radio normal vs
`mmcli --set-power-state-low`, readout = MPSS XO count/duration either side of
each suspend from `qcom_rpm_master_stats`. Log:
`/var/tmp/modem-xo-duty-20260824.log` on the device. Question it answers:
does radio state gate whether MPSS sleeps across an AP suspend (the 2026-08-20
census saw MPSS hold XO up in 5 of 6 suspend arms). Results in the next entry.

## 2026-08-24 (night, +1h) — ★★★ modem-xo-duty result: radio-low makes the MPSS sleep CONTINUOUSLY and lets the AP suspend run to term

The differential ran clean (4/4 suspends `success` 0→4, radio restored to `on`
at exit, capture
[`2026-08-24_modem-xo-duty.txt`](captures/2026-08-24_modem-xo-duty.txt)).
MPSS across each suspend, from `XO total duration` (19.2 MHz ticks → s):

| arm | asked | wall | MPSS XO-off | XO transitions |
|---|---|---|---|---|
| normal 1 | 90 s | **~11 s** | 6.7 s | 27 |
| normal 2 | 90 s | **~47 s** | 29.5 s | 119 |
| radio-low 1 | 90 s | 97 s | **102.9 s** | 8 |
| radio-low 2 | 90 s | 97 s | **97.0 s** | 6 |

Two findings, both firsts:

1. ★★★ **With the radio on, the modem terminates the AP's suspend early** —
   both radio-normal suspends ended at a fraction of the asked 90 s (11 s,
   47 s), while both radio-low suspends ran full term. This is the pmOS twin
   of the UT-side observation ("~5 wakeups/s from the modem IPC router aborted
   every suspend attempt") — same mechanism, now measured on mainline.
2. ★★★ **`mmcli --set-power-state-low` flips the MPSS from chopped XO cycling
   (~2.5 transitions/s, ~60 % XO-off duty) to essentially continuous XO
   shutdown** (6–8 transitions per ~97 s, XO-off ≥ 100 % of the window — the
   >window figure is the pre-snap gap; the sign is what matters). The modem
   with the radio up never settles; with the radio low it goes down and stays
   down.

**What it does NOT yet say:** the mA price. Radio-low is airplane mode by
another name — the phone is unreachable — so this is the *mechanism* arm, not
the fix. The next instrument is the night slope-leg with radio-low held for
the whole leg: if its phase-A slope lands near `nomodem-20260819` (−22.62 vs
baseline −35.77), most of the modem's ~36 mA is radio/paging activity, and the
tuning question becomes paging/DRX config rather than killing the radio. Also
untested: whether the early-abort behaviour alone (suspends that never run to
term) accounts for part of the sleeping-draw gap on normal nights.

☠️ Method note: `rtcwake -m mem -s 90` on this RTC (epoch 1970) sets the alarm
correctly, but a suspend that *ends early* still exits `rtcwake` with rc=0 —
wall-clock the window (`date +%T` around it) or the abort is invisible.

☠️ One more trap from the same run: the `--set-power-state-low` →
`--set-power-state-on` round trip leaves the modem **disabled** (it started
`registered`/`attached`); an explicit `mmcli -m any --enable` is needed to
re-register. Restored and verified (registered, 75 % signal). Any scripted leg
using power-state-low must end with `--enable`, not just `--set-power-state-on`.

### 2026-08-24 afternoon — the pricing leg is ARMED: radio-low slope leg running under the night harness (cable out)

The operator unplugged the cable and the radio-low arm went from "next" to
"running" (`radiolow-20260824`, commit `edf35f4`). Three things had to be true
first, and two of them were findings of their own:

1. ☠️ **The device's `preflight.sh` and `queue.sh` were STALE** — the 2026-08-23
   boot-default gate rewrite and the audible-job refusal existed only in the
   repo. The on-device gate still string-matched `= postmarketOS` and FAILed on
   the (correct, frozen-r73) `postmarketOS-prev` default. Synced repo → device;
   the repo is the source of truth for the harness, and "PASSES since the
   rewrite" is only true on a device that *has* the rewrite.
2. **`preflight.sh` gained a `nocable` argument** for discharge nights armed
   with the cable physically out: the charger gate becomes a note (`online=0`
   is the declared state, not evidence of a leftover USBIN suspend) and stays a
   hard FAIL by default. Corollary in the job file: **no `@charge` lines with
   the cable out** — a charge wait can only time out.
3. **`radio-low-leg.sh`** (deployed to `/root/`, source in `night/`): arms
   `mmcli --set-power-state-low`, then gates on ONE probe suspend before
   spending hours — wall-clock ≥75 s of 90 (rtcwake rc lies, see above) AND
   MPSS XO off ≥60 s. Every exit path restores `--set-power-state-on` **and**
   `--enable` (the disabled-modem trap above, now encoded).

**The gate passed cleanly: probe suspend wall 92 s of 90, MPSS XO off
87 624 ms** — the radio-low arm demonstrably took before the leg was allowed to
start. Descent phase running (rested 4.205→4.166 V toward the 4.030 V target),
guardian + queue under systemd, host supervisor pulling to
`night/runs/radiolow-20260824/` every 5 min. The readout to come: phase-A slope
vs `baseline-20260819` (−35.77 mV/h) and `nomodem-20260819` (−22.62 mV/h) —
that difference is the radio's mA price.

### ★★★★ 2026-08-24 evening — the radio is priced, and it does NOT need the modem powered off

The `radiolow-20260824` leg completed clean (rc=0, 6/6 phase-A suspends all
full-term at 901–902 s of a requested 900, cable out, pack 100 %→81 %).
Capture: [`captures/2026-08-24_radiolow-slope-leg.txt`](captures/2026-08-24_radiolow-slope-leg.txt).

| leg | phase-A slope | r² | derived |
|---|---|---|---|
| `baseline-20260819` (radio up) | −35.77 mV/h | — | 79.1 mA |
| `baseline-20260822` (r64) | — | — | 83.4 mA |
| **`radiolow-20260824`** | **−18.68 mV/h** | 0.9874 | **40.8 mA** |
| `nomodem-20260819` (services cut ⇒ modem OFF) | −22.62 mV/h | — | 43.3 mA |
| phase B (awake control, same leg) | −50.75 mV/h | 0.9994 | I_awake 110.8 mA |

**The result: `mmcli --set-power-state-low` buys the whole ~36 mA that powering
the modem processor off buys** — 40.8 mA against a 79–83 mA baseline, with the
modem still loaded, still owned by ModemManager, and one command away from
being back on the network. The mechanism is the one the XO-duty differential
named this morning: with the radio up the MPSS chops the crystal and aborts the
AP's suspends outright; radio-low lets it hold XO-shutdown and the suspends run
to term.

☠️ **Read "slightly better than modem-off" as "at least as good", not as
better.** The radio-low slope is 0.826 of the `nomodem-20260819` slope, i.e.
nominally 2.5 mA under it — but those are different legs on different days, the
nomodem leg's cut was the `rmtfs -P` contamination path, and a single leg's
phase-A slope has not been characterised for run-to-run scatter at this
resolution. The defensible claim is that the two are indistinguishable, and
that is already the interesting one: **the saving does not require the modem
processor to be down.**

☠️ **This is a mechanism, not yet a fix.** Radio-low is airplane mode by another
name: no calls, no data, no paging. What it establishes is *where* the 36 mA
lives — in RF/registration activity, not in the modem being loaded, and not in
host services. The fix direction is therefore modem power-save configuration
(PSM / eDRX / the paging cycle the network negotiates), which is config and
possibly network-side, not an AP-side kernel patch. The next measurement is
whether a power-save mode that keeps the phone *registered* reproduces any part
of this.

Method notes that held: the probe gate (wall-clock ≥75 s of 90 AND MPSS XO off
≥60 s) passed at 92 s / 87.6 s before the leg was allowed to spend four hours;
the `nocable` preflight mode armed correctly with the cable out; every exit path
restored the modem (`registered`, `power state: on`) without intervention.

### ★★★★★ 2026-08-24 late evening — the goal is restated, and the oracle idles below our phone asleep

The project owner set the objective plainly: **bring pmOS's consumption down to
the UT level or below.** This entry is the measurement that gives that a number,
and the instrument work that made it possible.

**1. The vendor gauge has a real coulomb counter, and a decoy beside it.**
`bms/cc_soc` (downstream QG, UT only) integrates: implied **97.3 mA** against a
medianed `current_now` of 103.4 discharging, and **1.079** against delivered
charge while charging — both controls bracketing 1.0. `bms/charge_counter` does
not: over 453 s at ~103 mA it **did not move at all**, and it steps in exactly
1.00 % of `charge_full` — the same OCV-lookup construction as pmOS's
`charge_now`, which fails the identical test at 1.37. One run produced a
known-positive and a known-negative side by side, which is the cheapest form
this check ever takes.

**2. There is no "UT sleeping current" to compare against, because the oracle
does not sleep.** The full documented recipe (ssusb wakeup disabled, BOTH ofono
modems `Powered=false`, the `wakeup_count` handshake) over a 603 s window gave
**2 completed suspends out of 120 attempts**, 93 s asleep — 15 % of the window.
Solving `93·I_sleep + 510·I_awake` for plausible awake values swings the sleep
term from 70 mA to 5 mA across a 15 % change in the awake term. The sleep term
has no leverage; the measurement is not available at this ratio. (This matches
the morning's XO capture, whose working windows were 7–12 s.)

**3. So the comparable regime is IDLE — and the oracle idles at 29.7 mA.**
Panel **off**, radio up, WiFi associated, on battery, 60-minute window,
`cc_soc` −97 counts = 29.68 mAh:

| | draw | how |
|---|---|---|
| **UT idle, panel off** | **29.7 mA** | cc_soc, 60 min, ±0.3 mA |
| pmOS idle, panel off | 58–63 mA | medianed `current_now`, 2026-08-19 |
| pmOS **asleep**, radio low | 40.8 mA | slope leg, same day |

**The oracle sitting awake beats our phone asleep.** That reframes the track:
the gap to close is **idle depth**, not suspend depth, and the target is a level
rather than a mode. It is also consistent with everything already measured — the
oracle's runtime idle collapses `system-pc` ~18/s and its co-processors shut the
crystal down thousands of times per window; it has no need to suspend.

☠️ **The first reading of the oracle's idle was 22 mA and it was wrong by a
third** — one 10-minute window on a pack still relaxing from an earlier load,
where a single counter step is worth ±1.8 mA. The hour-long window gives 29.7.
The error flattered the oracle, which is the direction to distrust, and the
lesson is the one this log keeps re-learning: a convenient number measured once
is a hypothesis.

☠️ **The two sides are still measured by different instruments** (sampled
`current_now` here, an integrator there), which is a comparison with a seam in
it. [`tools/idle-ab.sh`](tools/idle-ab.sh) was written to remove it: one script,
one protocol, either phone, reporting the floor (p10) and the median on both and
the integrated value where a counter exists. The matched pair is the next
measurement.

Capture: [`captures/2026-08-24_ut-coulomb-and-sleep-attempt.txt`](captures/2026-08-24_ut-coulomb-and-sleep-attempt.txt).

### ★★★★ 2026-08-25 morning — the gap measured by one instrument: pmOS is ~4x the oracle, and it is a WAKEUP problem

The matched pair the goal needs, both sides run by
[`tools/idle-ab.sh`](tools/idle-ab.sh), panel proven dark on both, compositor
running on both, WiFi associated, radio up, on battery:

| | floor (p10) | median | integrated | voltage slope |
|---|---|---|---|---|
| **UT** (4.9.218) | 15.3 mA | 30.1 mA | **32.2 mA** (`cc_soc`) | 43.0 mV/h |
| **pmOS r73** (7.1.3) | 54.3 mA | 148.0 mA | — (no counter) | 133.7 mV/h |

**~3.5x on the floor, ~4.5x on the average**, and since pmOS has no coulomb
counter the voltage slope is the independent witness at 134 against 43 mV/h.
☠️ The two slopes sit on different parts of the OCV curve, so that is
corroboration, not a conversion.

**The shape matters more than the ratio: pmOS's floor is close to its documented
58-63 mA, but its median is three times its own floor**, where UT's median is
barely twice its floor. So this is not a load that burns continuously — it is
something waking the phone often. First instrument, 20 s of differenced
`/proc/interrupts` with the panel dark: `IPI1` (function call) **1927/s**,
`arch_timer` 1037/s, rescheduling 948/s, and — with the panel off —
**`msm_mdss` 79/s** plus `dsi_isr` 20/s, while the CPU sits 82-100 % idle.
Nothing is computing; something is knocking.

Captures: [`2026-08-25_pmos-idle-ab-run1.txt`](captures/2026-08-25_pmos-idle-ab-run1.txt),
[`run2`](captures/2026-08-25_pmos-idle-ab-run2.txt),
[`UT`](captures/2026-08-24_ut-idle-ab-60min.txt).

#### ☠️☠️ Three instrument failures in one session, and the third produced a false accusation

Worth recording together, because they rhyme: **each time the tool built to
prevent an error committed it.**

1. **The panel gate asked instead of proving.** The first pmOS hour was run with
   the script believing it had blanked the screen; the compositor holds DRM
   master, so the `dpms` write returned EACCES and the tool measured on. Fixed
   by stopping the compositor, retrying, and *aborting unless the panel can be
   proven off*.
2. **The proof read a property, not the hardware — and I condemned a good run on
   it.** Run 1 was banner-ed INVALID on its header saying `dpms=On`. Measured
   afterwards: there is exactly one dpms node and the panel's own `bl_power`
   reads **4 = FB_BLANK_POWERDOWN**. The backlight *was* down; the fb blank had
   worked while the compositor-owned DRM property still said On. The banner is
   withdrawn in the capture. That the two runs agreed to 0.4 mA on the floor was
   the evidence, and I explained it away instead of following it.
3. **`systemctl stop greetd` does not stop the compositor.** `greetd` reads
   `inactive` while `phoc` and `phrog` keep running under its user. So both pmOS
   hours ran with the compositor up — which is, by luck, exactly the UT
   configuration, and is why the pair above is comparable at all. The clause was
   in the protocol and silently did nothing.

The rule all three point at is one this log already has and I did not apply:
**a gate that has not been watched failing has proved nothing**, and its proof
must be the hardware's own state, never the software's description of it.

---

# Part II — the run-book's dated body (2026-08-15 → 2026-08-24), moved here unedited on 2026-08-24

The run-book (`RUNBOOK.md`) was created as "the resume point — what to do next"
and accreted two thousand lines of dated measurement entries instead: a second,
parallel dated log of the same investigation, overlapping this one nowhere. On
2026-08-24 it was split by the knowledge boundary (state → `STATUS.md`, tasks →
`TODO.md`, instruments → `../README.md`, dated record → here) and deleted. Its
body follows **unedited**, in its own internal order — including its then-current
"Next step" / "Where the question stands" sections, which are themselves dated
snapshots now and are superseded by `STATUS.md`/`TODO.md`.

## Where the question stands

The search moved three times on 2026-08-14 and landed outside this SoC:

1. *Does a suspend reach the RPM?* — wrong level.
2. *Does anything notify the RPM?* — nothing did; mainline msm8953 described no
   MPM. Added, and the notification demonstrably runs.
3. *Why does the governor never select the deepest cluster state?* — **answered**:
   `genpd_governor_data::cached_power_down_state_idx` is declared `bool`, so a
   cached state index of 2 comes back as 1 and the search, which only walks
   downwards, can never reach index 2 again. Six years old, not msm8953-specific.
   Fixed; `cluster-pc` 0 → 14516 per minute, `system-pc` 0 → 3531. Written up in
   [`README.md`](../README.md) under "The real cause".
4. *Why does the RPM record nothing?* — **answered 2026-08-17**: `system_pc`
   named affinity level 1 in its PSCI parameter, so TZ never performed the APSS
   handshake. `0x42000353` fixes it and the RPM now counts APSS shutdowns; a
   second change stops the AP being woken once a second by our own vMPM
   deadline cap. Both landed. Detail under "Next step".
5. **Current: the RPM records the AP going down, but still never enters `vlow`
   or `vmin`.** A master being down is necessary and not sufficient — the RPM
   aggregates over resource votes as well. The question is now which rails are
   still voted active-set while the phone sleeps.

   ★★★ **2026-08-24 — the oracle differential ran, and it moves the search off
   the AP for good.** pmOS r73 runtime-idle (57 min, display off): `vlow`/`vmin`
   Count stayed **0**. UT oracle runtime-idle (21 min): its three co-processors
   (MPSS/PRONTO/LPASS) vote the XO down thousands of times/window and `system-pc`
   collapses ~18/s — the working slot reaches deep sleep continuously. Decisive
   detail: **APSS `xo_count` is 0 on *both* systems** — the AP never votes the
   crystal down on the oracle either, so the AP is not the differentiator.

   ★★★ **Correction, same night: pmOS's co-processors DO vote XO down, at
   oracle-equivalent rates — the gate is the RPM aggregate, not the masters.**
   The per-master instrument was there all along: `modprobe rpm_master_stats`
   (module is `=m`, not auto-loaded) → `/sys/kernel/debug/qcom_rpm_master_stats/`
   (that dir name, not `rpm_master_stats`). Measured on pmOS r73 idle: PRONTO
   9.1/s XO (oracle 9.0/s), MPSS 2.5/s (oracle 3.1/s), APSS 0 (both), LPASS
   asleep-and-staying-down. So "restore rpm_master_stats" was a **wrong** next
   lever — it already exists, and it shows the co-processors sleeping fine while
   `vlow` stays 0. ☠️ **And the mask decode is already CLOSED (2026-08-23): five
   bits for five masters, bit 3 = TZ (inert), no mystery holder** — do not
   re-open it. **The synthesis: `vlow`=0 is uncorroborated by any per-master
   deficit** — both `rpm_master_stats` readers are the same ported driver on the
   same RPM message-RAM, and on it pmOS matches the oracle (co-procs vote XO, AP
   does not, on both). So the runtime-idle reading was
   "`vlow`=0 is a counter artifact, not a defect". ☠️ **That was corrected the
   same day by a forced-suspend measurement** (`rtcwake -m mem`, `rpm_master_stats`
   either side, `suspend_success` incrementing): the **APSS still never enters XO
   shutdown** across a genuine suspend (count 0), while MPSS/PRONTO drop XO freely
   and `vlow` stays 0. The RPM aggregates to `vlow` only when the AP votes XO down
   too, so **`vlow`=0 is real, not an artifact** — re-confirming the 2026-08-22
   finding (runtime idle is not suspend). A working XO lever already exists
   (`clk_smd_rpm.xo_sleep_off=1` → APSS enters XO shutdown, `vlow` still 0), so
   the remaining named blocker is the LDO sleep votes. ★★★ **2026-08-24
   (UT-oracle across-suspend, slot a): the AP-never-drops-XO reading above is a
   MAINLINE REGRESSION, not an SoC/s2idle limit — and it overturns "the AP is not
   the differentiator" for the SUSPEND axis.** At idle the oracle AP also shows
   `xo_count` 0; but across a genuine downstream `mem` suspend it went **0 → 2**
   (echo mem exit 0, 7 s + 12 s), while mainline stays 0 across confirmed
   suspends. So on the suspend path the AP *is* exactly where mainline regresses.
   Forcing the downstream to suspend needed the modem powered off (ofono
   `Powered=false`): ~5 wakeups/s from the modem IPC router aborted every attempt
   and `7000000.ssusb` stayed active through a physical unplug. Caveat: mainline
   not yet re-run with modems off. Capture:
   `captures/2026-08-24_xo-across-suspend-ut-oracle-slotA.txt`. ☠️ The 2026-08-24 cable-out
   A/B did **not** close the "is it USB" sub-question: cable in-vs-out is
   identical, so the cable is not the variable, but `7000000.usb` stayed active
   (`control=on`, `runtime_suspended_time=0`) in both runs — the controller test
   is `control=auto`+detach, not done. Full write-up + captures in
   `findings-log.md` (2026-08-24 entries + the correction to both) and
   `captures/2026-08-24_xo-across-suspend-pmos-r73-cable{in,out}.txt`.

## The LPASS question is CLOSED (2026-08-21), and here is where it went

Kept here because it was previously recorded only in a working note that this
page never pointed at — which on 2026-08-23 cost a re-run of the whole bisect
and a retracted conclusion. Detail:
[`leads/lpass-mclk-gate-state.md`](leads/lpass-mclk-gate-state.md).

**Two root causes, both fixed and both in the kernel the phone runs:**

1. `msm8916-wcd-digital` called `clk_prepare_enable(mclk)` unconditionally at
   probe; on msm8953 that mclk is a q6afe clock, i.e. an ADSP request held for
   the lifetime of the driver. Fixed by moving it into DAI startup/shutdown —
   `ASoC: msm8916-wcd-digital: hold mclk only while a stream runs`.
2. A second latch: `qcom-ngd-ctrl` silently dropped every core
   reconfiguration-sequence message, which is where the generic SLIMbus teardown
   sends NEXT_DEACTIVATE_CHANNEL / NEXT_REMOVE_CHANNEL. `enable_stream` had a
   real implementation and there was no `disable_stream`, so the ADSP never saw
   a **TX (source)** channel removed and held the XO vote forever. RX never
   latched. Fixed by porting the downstream `SLIM_USR_MC_CHAN_CTRL` recipe —
   `slimbus: qcom-ngd-ctrl: implement disable_stream so the ADSP releases the
   channel` (`cff137fdef8e` on `debug-int/7.1.3`, shipped in r63).

**How to read the instrument, because it is ambiguous and has now misled once:**
`Shutdown count` going flat means *either* pinned awake *or* asleep and staying
down. The disambiguators are `Last XO shutdown enter` vs `Last XO shutdown exit`
and `Active cores bitmask` — `enter > exit` with `cores 0x0` is asleep.
`tools/lpass-trace.sh` prints the verdict; never quote the count alone.

**Verified on r73, 2026-08-23:** clean boot, LPASS cycles during bring-up, takes
its last shutdown at ~34 s of uptime and reads `ASLEEP cores=0x0` from there on.
☠️ An ADSP restart re-introduces the latch for that boot (post-SSR re-attach) —
so any measurement taken after an SSR is measuring that, not steady state.

☠️ **And it is not the `vlow` gate.** Measured twice, on 2026-08-21 and again on
2026-08-23 with the ADSP `remoteproc` stopped outright: `vlow`/`vmin` `Count`
stay 0 either way. The gate is still unidentified.

## Next step

★★★★ **2026-08-17: the RPM handshake is fixed. One hex digit.**

`system_pc` asked the firmware for **affinity level 1** — the same level the
cluster states use — so TZ aggregated up to a cluster and never performed the
APSS handshake with the RPM. Downstream composes the parameter rather than
spelling it out, and the recursion bumps the affinity level once per cluster
level that leaves its default: once for the system cluster (mode 3 at shift 8)
and once for the L2 cluster (mode 5 at shift 4) — **`0x42000353`**, not
`0x41000353`. Our four lower rungs already matched that composition bit for bit,
which is what makes the top one's mismatch believable rather than a guess.

Measured on the device, one 91 s suspend each side:

| | before (`0x41000353`) | after (`0x42000353`) |
|---|---|---|
| APSS `Shutdown count` | **0**, all boot | 633 → **724** (+91) |
| APSS transition timings | all zero | `sleep 12232` / `wake 12386` |
| `power-domain-system` S2idle | 3 (kernel-side only) | 0 → **92** |
| `vlow` / `vmin` Count | 0 | **0** |
| `XO shutdown count` | 0 | **0** |

So the application processor now tells the RPM it is down, and the RPM believes
it. That is the gap this page has been chasing since 2026-08-14, and it was one
nibble in one property. Landed as `0314fee3ce35` on `wip/7.1.3/power`, cherry-
picked to `integration/7.1.3` and `debug-int/7.1.3`, all three pushed.

**Two things are immediately visible in that table, and both are the next work:**

1. **91 shutdowns in 91 s — it wakes every second.** That is our own
   `MPM_MAX_SLEEP_NS = NSEC_PER_SEC` clamp in `mpm_write_wakeup()`: the RPM is
   never asked to keep the AP down for longer than a second, so it does not.
   Downstream applies **no clamp at all** — it writes the broadcast timer's CVAL
   verbatim, and deliberately writes all-ones when no timer is armed, meaning
   "no scheduled wake, rude wakeup only". So a far-future deadline is the
   vendor's own encoding and demonstrably not refused. ⚠️ Note also that
   downstream reads the **memory-mapped** timer frame's CVAL while we compute
   from `arch_timer_read_counter()`; if `CNTVOFF` is non-zero those are different
   counter domains, which would be a silent, total failure. Check that before
   trusting a longer deadline.
2. **`vlow`, `vmin` and XO shutdown are still 0.** The AP going down is
   necessary, not sufficient: the RPM aggregates across all masters *and* all
   resource votes. The next suspect is sleep-set vote coverage — which rails are
   still voting active-set — not this path.

⚠️ **No current number yet.** The RPM counters moving is not the same as the
draw falling, and this page has been wrong in exactly that way before. Until a
leg is run, the honest statement is that the handshake works, not that the phone
saves anything.

★★★ **Answered: with the display genuinely off, the genpd fix is worth ~9 %.**
Two legs per arm, fresh boot each, 200 samples after a 300 s settle, display gate
enforced: **−119.0 mA with the fix, −130.5 mA without**, arms non-overlapping.
The earlier panel-on set had the opposite sign and was also correct - it was a
different regime, not noise. Full write-up in [`README.md`](../README.md), data in
[`2026-08-15_ab-current-legs.txt`](captures/2026-08-15_ab-current-legs.txt).

★★ **But the 130 mA is the wrong regime, found 2026-08-15.** The phone had
**never suspended**: `/sys/power/suspend_stats/success` read 0 after 50 minutes
of uptime, and `mem_sleep` offers only `[s2idle]`. Everything measured so far
describes *runtime idle with a full phosh session alive* - `greetd`, pipewire,
wireplumber, five `xdg-desktop-portal`s, gvfsd, avahi, wpa_supplicant - and a
modem talking at 28 `smd-edge` interrupts a second. A phone's night is s2idle,
and no number had ever been taken there.

**s2idle works.** Probed: 90 s requested via the RTC wakealarm, 91 s slept,
`success` 0 → 1, `fail` 0, WiFi reassociated on its own. The RTC time is stuck
in 1970 (no `offset` nvmem cell, `docs/TODO.md`) but an alarm is *relative*, so
it is unaffected - which is what makes an unattended suspend leg safe.

☠️ **Three battery instruments have now failed, all for one reason.** There is
no coulomb counter here. `qcom_smbx` gets everything from
`adc-battery-helper.c`, whose poll worker runs every 30 s and maintains an
8-deep moving average - i.e. a four-minute trailing one - and **that worker does
not run while userspace is frozen**. So:

| attribute | live? |
|---|---|
| `voltage_now`, `current_now` | **yes** - straight to the ADC on every sysfs read |
| `voltage_ocv`, `capacity`, `charge_now` | no - one cached number under three names |

The casualties, in order: integrating `charge_now` gave **209 mA** in an awake
control window where `current_now` reads 130, and **exactly zero** asleep;
`capacity` read **97 % at both ends** of a 3 h suspend; `voltage_ocv` looked
instantaneous (it equals `voltage_now - current_now × 120 mΩ` to the microvolt)
but is the ring average, five of whose eight slots were still pre-suspend 90 s
after resume. Every number from all three is withdrawn. In each case the
**control window is the only thing that caught it**.

What the S2 leg still supports, from the live pair alone: compensated
`voltage_now` fell 4.222 V → 4.062 V over 3 h. Both ends are biased the same way
(surface charge at the start, resume polarisation at the end), so 160 mV is an
**upper bound**. But a 10 mA leg would move only ~11 mV, so **suspend is not in
the 10 mA regime** - that much is solid. Full reasoning in [`README.md`](../README.md).

### S4 ran, 2026-08-15 18:55 → 23:16 — the ratio holds, the calibration does not

The leg completed unattended: settle 900 s, `phase A done suspends=8 of 8`,
every cycle `slept=901s of 900s`, phase B's eight windows, charger and greetd
restored by the trap. 90 % → 72 %, which is the worst case predicted before it
started (564 mAh if nothing ever slept). Logs:
[`2026-08-15_S4-slope.txt`](captures/2026-08-15_S4-slope.txt) and
[`2026-08-15_S4-curlog.txt`](captures/2026-08-15_S4-curlog.txt).

**Suspend is not in question this time.** The dense logger took 213 samples
during phase B and only 55 during phase A, over the same 1.79 h — it was frozen
for the missing ones. A sampler that stops counting *is* the proof that
userspace was down, and it is independent of anything the slope says.

**What the fit gives:**

| phase | slope of compensated V | r² | dense-logger current |
|---|---|---|---|
| settle | −60.3 mV/h | 0.28 ☠️ not a line | 146 mA |
| A (asleep) | −42.3 mV/h | 0.93 | (frozen) |
| B (awake) | −89.1 mV/h | 0.97 | 245 mA |

So **asleep the phone draws 0.475 of what it draws awake**, and that ratio rests
on two clean straight lines. Multiplying it out gives 116 mA — and that number
is **withdrawn**, because the control fails.

☠️ **Phase B measured 245 mA where ~130 mA was expected — the fourth control
failure in a row, and the first one that is not obviously the instrument's
fault.** Checked immediately afterwards, with the panel dark and every CPU at
0 %, the phone drew −249, −127 and −253 mA on three reads two seconds apart. It
really is in a ~210-250 mA regime tonight, so phase B is not misreading; the
**~130 mA reference** is what does not reproduce. Until that is explained, no
absolute sleep current can be quoted, only the ratio.

Two candidates, neither yet tested, and the first is ours:

- **the instrument drives the load it measures.** Every reading crosses WiFi —
  the 30 s dense logger, and the SSH session watching it. The skill already
  states that a periodic sampler measures the load at the instant it is itself
  running; here it may also be *keeping the radio associated*. The test is a
  run whose samples go to a file with no network at all, fetched afterwards.
- **the 130 mA figure was taken in a different regime.** It comes from
  runtime-idle with a live session, not from a stopped greetd, and the swing
  between 127 and 253 mA within four seconds says something is duty-cycling.
  Bracket it: measure awake-idle three ways (session up, greetd stopped, greetd
  stopped and WiFi down) before using any of them as a calibration.

The ratio is the durable result and it is worth stating on its own: **suspend
halves the drain, and no more than halves it.** Whatever the absolute figure
turns out to be, s2idle on this device is not the order-of-magnitude win it is
on a phone with a working low-power state — which is a bigger finding than the
number would have been.

### ← PARKED FOR THE NIGHT, 2026-08-15 13:40 (superseded by the run above)

☠️ **This branch is a night job and must be treated as one.** A slope leg takes
the phone off VBUS, blanks the display and suspends it for hours, so it makes the
device unusable for any other work. It was started at 13:30 in the middle of a
working day and had to be aborted at 13:40, during its settle phase, before phase
A began. Nothing was measured. **Do not start one while the phone is wanted for
anything else** - schedule it when the device is free for the night.

Aborted cleanly: `slope1` and `curlog` stopped, USBIN restored (`online=1`,
battery `Charging` at +129 mA), no wakealarm armed, `greetd` back. Partial data
in [`2026-08-15_S3-slope-aborted.txt`](captures/2026-08-15_S3-slope-aborted.txt) - only
the settle phase, but it does show the relaxation shape: current settling to
~140 mA and the compensated fall slowing from 22 to ~3.7 mV/min over 900 s, i.e.
surface charge still shedding at the end of the settle. That biases a phase-A
slope steeper, so **it inflates the sleep current rather than hiding it** - the
safe direction, but a longer settle would be better.

**To resume, at night:**

```sh
ssh fp3@192.168.100.17 'echo <pw> | sudo -S sh -c "
  : > /home/fp3/suspend-slope.txt
  systemd-run --unit=slope1 --collect /home/fp3/suspend-slope.sh S4 900 8
  systemd-run --unit=curlog --collect sh -c \"/home/fp3/curlog.sh > /home/fp3/curlog.txt\""'
```

Runs ~4.3 h. The phone is unreachable during phase A *by design* - WiFi drops in
s2idle, so a failed ping is it working, not broken.

```sh
ssh fp3@192.168.100.17 'cat /home/fp3/suspend-slope.txt'
```

Every line carries `phase=`, `t=` (uptime, s), `v=` and `i=`, all live ADC. Do
not do the arithmetic by hand - fetch both logs and run the reducer, which also
uses the dense `curlog.txt` for phase B's mean current (the load swings
140-490 mA, so 8 spaced samples estimate it badly):

```sh
scp fp3@192.168.100.17:/home/fp3/{suspend-slope,curlog}.txt docs/power/
docs/power/slope-fit.py docs/power/suspend-slope.txt docs/power/curlog.txt
```

It fits compensated voltage `v + |i| × 120 mΩ` against `t` per phase and prints
`I_sleep = mean(|i|) over phase B × slope_A / slope_B`. `slope-fit.py --selftest`
proves the fitter on a synthetic run of known ratio and on scatter that must fail
the straight-line gate.

☠️ **Check phase B first, before looking at phase A at all.** It is the control:
its `mean(|i|)` must come out near 130 mA and its slope must be a clean straight
line. If phase B does not reproduce the current we already know, the method is
broken and phase A is meaningless - that has now happened three times running.

Then check the `A<n> slept=` lines: each should read ~900 of 900. A
systematically short sleep means something is waking it and phase A is not
measuring suspend. And check the `phase=settle` lines - if compensated voltage
is still visibly falling at the end of the 900 s settle, surface charge had not
finished shedding and the first phase-A points are contaminated (the slope fit
should then drop them).

Also verify the charger came back: `cat /sys/class/power_supply/pmi632-charger/online`
should read 1. ☠️ If it reads 0 the EXIT trap did not run - clear
`USBIN_SUSPEND_BIT` (`echo Charging > .../status`) **before** any reboot.

Prediction on record, **not** a measurement: 60-110 mA, because the genpd
`interrupt-controller` domain was already collapsed 67 % of the time *while
awake* at 130 mA, so most of that draw is not the AP and suspending it cannot
remove it.

**Then** bisect whatever is left by subsystem with `idle-leg.sh` - one leg with
WiFi down, one with the modem stopped, one with `pd-mapper` disabled. That is
worth doing only once the suspend number says how much of the 130 mA is session
noise rather than platform floor.

☠️ **10 mA is a different regime, not a smaller number.** Downstream phones
reach it in full suspend with the modem in its own power-save, never in runtime
idle. Do not treat the 130 mA as a target to shave.

**The RPM question is parked, not open.** Every AP-side precondition is verified
and the two-sided vMPM dump is structurally identical; what remains is past the
PSCI call, in TZ or RPM firmware, where this kernel has no instrument.

**Upstream:** the genpd patch can now say plainly that it measurably improves
idle current on an SDM632 phone. The cpuidle-psci ordering patch is unaffected.
The vMPM timer commit (`wip/7.1.3/power` `97951baf7a85`) stays on the fork - it is
a real omission but still changes nothing measurable.

**Also still open:** GPIO wakeup map inert until the RPM takes over; the regulator
sleep set must exist *before* the RPM ever collapses; `_commit`/`pkgrel` still pin
`162f27abc328` and should move to the current `debug-int/7.1.3` tip.

☠️ **Two traps this cost:** never reboot with USBIN suspended (the bit is in the
PMIC, survives a warm reboot, and wedged the bootloader into a fastboot that
answered nothing - it took a held power button). And `systemctl stop greetd`
returns before the compositor releases DRM master, so a single write to
`fb0/blank` is silently undone.

## Device and tree state

* Phone on `slot_b`, running a hand-deployed `Image` from `debug-int/7.1.3`
  `6fd035d9501a` (build #18, `/home/fp3/Image.fix`; the A/B control is
  `/home/fp3/Image.control`, the same tree with 162f27abc328 reverted),
  not a package build. Backups in `/boot`: `vmlinuz.pre-mpmtimer`,
  `vmlinuz.genpdfix`, `vmlinuz.base-mpm`, `vmlinuz.pre-mpm`.
* The oracle is `slot_a` (Ubuntu Touch); `fastboot set_active a|b` switches, and
  `ut-ssh` reaches it.
* Kernel work is the `power` category: `wip/7.1.3/power` → `integration/7.1.3` →
  `debug-int/7.1.3`, all pushed to `fork`.
* **A package build has not been run for any of this**, so `_commit` in
  `linux-fp3/APKBUILD` still predates it. Do that before calling anything
  shipped.

## Instruments, with the paths that cost time to find

| question | command |
|---|---|
| did the SoC reach a low-power mode | `grep Count /sys/kernel/debug/qcom_stats/{vlow,vmin}` |
| which master never goes down | `cat /sys/kernel/debug/qcom_rpm_master_stats/APSS` — ☠️ one file per master, and the directory is `qcom_rpm_master_stats`, not `rpm_master_stats`; needs `modprobe rpm_master_stats` |
| how deep does idle actually get | `cat /sys/kernel/debug/pm_genpd/power-domain-cluster0/idle_states` |
| the same on the oracle | `ut-ssh 'cat /sys/kernel/debug/rpm_master_stats'` and `.../lpm_stats/stats` |
| what is waking the CPUs | two `/proc/interrupts` snapshots differenced — ☠️ stop the compositor first, or `msm_mdss` at 65/s makes the run meaningless |
| has the phone ever suspended | `grep -H . /sys/power/suspend_stats/*` — `success` is the only honest answer; `cat /sys/power/mem_sleep` says which path |
| current while suspended | `docs/power/bringup/tools/suspend-slope.sh` — ☠️ **only `voltage_now`/`current_now` are live**; `capacity`, `charge_now` and `voltage_ocv` are one cached number the frozen poll worker maintains, and all three lie across a suspend. Use a slope of compensated `voltage_now`, calibrated against an awake control |
| does the RTC alarm wake it | `echo 0 > /sys/class/rtc/rtc0/wakealarm; echo +90 > …` then `echo mem > /sys/power/state` — ☠️ prove this **before** relying on it to bring an unattended leg back |

### Why suspend only halves it: there is no `deep` state

Measured 2026-08-15, minutes after the S4 leg:

```sh
cat /sys/power/state      # freeze mem disk
cat /sys/power/mem_sleep  # [s2idle]
```

`mem_sleep` offers **s2idle and nothing else**, so `echo mem > /sys/power/state`
— what the leg ran, and what `suspend_stats` counted 8 of — is s2idle. Tasks
freeze and the CPUs go idle, but the SoC never reaches VDD_MIN or XO shutdown,
because that needs every subsystem to have dropped its RPM votes for clocks,
regulators and buses. One driver still holding one vote is enough to prevent it,
and mainline msm8953 registers no `deep` (`PM_SUSPEND_MEM`) platform op at all.

This is the same fact as the 0.475 ratio, seen from the other side, and it means
the ratio is close to the ceiling of what this suspend path can give. Chasing it
by tuning userspace is the wrong lever; the lever is a `deep` state, which means
the RPM vote path. Before any of that, get the awake baseline honest (above) —
a ratio against a wrong reference cannot say how much is left on the table.

#### ☠️ Correction, 2026-08-16: the paragraph above is wrong, and so is its lever

The *observation* stands — `mem_sleep` really is `[s2idle]` only — but the
inference drawn from it does not. Two things were assumed and neither survived
being measured.

**1. s2idle does reach the system power collapse here.** genpd counts entries
made from the s2idle path in a separate column, so this is directly readable
rather than argued. Around one 20 s RTC-woken suspend:

```sh
cat /sys/kernel/debug/pm_genpd/power-domain-system/idle_states
```

| domain | state | `S2idle` before → after |
|---|---|---|
| `power-domain-system` | S0 | 0 → **1** |
| `power-domain-cluster0` | S2 | 0 → **1** |
| `power-domain-cluster1` | S2 | 0 → **1** |

So the claim that "the SoC never reaches VDD_MIN or XO shutdown" is not what the
counters say: the *system* domain collapsed, from s2idle, on the first try. The
mechanism the paragraph reached for — every subsystem dropping its RPM votes —
is evidently already happening, because the domain could not have gone down
otherwise. Whatever else explains the 0.475 ratio, it is not "suspend never gets
deep".

**2. `deep` is not a lever anybody can pull from here.** On arm64 the only
writer of `deep` is `suspend_set_ops()`, and the only caller that can reach it
on this SoC is `psci_init_system_suspend()` in `drivers/firmware/psci/psci.c`
(read on `7.1.3/main`, the base we run):

```c
	if (!IS_ENABLED(CONFIG_SUSPEND))
		return;
	ret = psci_features(PSCI_FN_NATIVE(1_0, SYSTEM_SUSPEND));
	if (ret != PSCI_RET_NOT_SUPPORTED)
		suspend_set_ops(&psci_suspend_ops);
```

`CONFIG_SUSPEND=y` is set, so the absent `deep` means the secure firmware
answered `NOT_SUPPORTED` to the `SYSTEM_SUSPEND` SMC. Every other
`suspend_set_ops()` caller in mainline lives under `arch/arm/mach-*`,
`arch/mips` or `arch/powerpc` — there is no qcom arm64 platform suspend op to
add one from. It is therefore a **TZ firmware fact**, not a kernel or config
one, and it is reachable neither by patching the kernel nor by tuning userspace.

☠️ **And it disposes of the "did a regression take it away?" question.**
Userspace never touches `mem_sleep` — it is written at kernel init, before
systemd exists — so the switch to systemd cannot have removed it, and no
mainline kernel version ever had a non-PSCI route to it on this SoC. Note also
that `psci_init_system_suspend()` logs **nothing** either way, so its verdict
leaves no trace in `dmesg` to grep for; `tests/baseline/sleep-states.txt` is
that trace, and `tests/checks/99-suspend-test.sh` is what notices it changing.

The check also asserts the *depth*, because that is the property that can
actually regress: a suspend that freezes userspace, holds one wakeup source and
never lets the domains go still passes every outward test — screen off, phone
unresponsive, RTC wakes it — while saving almost nothing. The `S2idle` counter
is the only thing that separates those two cases. Proven in both directions on
2026-08-16: PASS live on the device; FAIL with a baseline claiming a lost state;
FAIL with `deep` injected over `mem_sleep` by bind-mount; SKIP against a fixture
with no `S2idle` column.

### ☠️★★★ The awake baseline was not idle: the CPU0 PLL was failing to lock

Found 2026-08-16 while looking for why phase B measured 245 mA. The previous
boot's kernel log carries **266 copies** of

```
apcs-cpu0-pll failed to enable!
WARNING: drivers/clk/qcom/clk-alpha-pll.c:421 at wait_for_pll+0xf4/0x108, CPU#5: sugov:0/113
  wait_for_pll  <- x0 = 0xffffff92 = -110 = -ETIMEDOUT
  alpha_pll_huayra_set_rate
  clk_change_rate / clk_core_set_rate_nolock / clk_set_rate
  _opp_config_clk_single / _set_opp / dev_pm_opp_set_rate
  set_target / __cpufreq_driver_target / sugov_work
```

Every one is the little cluster's PLL (`policy0`) refusing to lock while
schedutil tries to change frequency. Full capture:
[`2026-08-16_apcs-cpu0-pll-lock-failures.txt`](captures/2026-08-16_apcs-cpu0-pll-lock-failures.txt).

**The timing is what matters.** The first is at 21:49:55 and they run to
06:22:55 — several a minute at the start, thinning out later. Phase A finished
around 21:14 and phase B ran to 23:16, so:

| phase | PLL storm |
|---|---|
| settle | no |
| **A (asleep)** | **no — it was over before the first failure** |
| **B (awake control)** | **yes, from ~35 min in to the end** |

So the control leg — the one whose whole job is to reproduce a current we
already know — ran on a CPU whose frequency transitions were failing. That is
the first concrete candidate for 245 mA against an expected 130, and it is
testable rather than a shrug.

☠️ **It does not simply invalidate the ratio, and it does not simply rescue it
either.** The method computes `mean(|i|)_B × slope_A / slope_B`, so an inflated
phase B raises the current *and* steepens the slope, and the two partly cancel.
"Partly" is not a number, so the 116 mA stays withdrawn — but note the error
direction is not knowable without redoing it.

**This also killed the phone.** The previous boot's journal ends mid-line at
06:22:57 with no shutdown sequence at all — no `Reached target Shutdown`,
nothing — after a `mpm_pd_power_off` / `genpd_sync_power_off` warning at
06:22:27 and a PLL failure at 06:22:55. It came back by itself. An abrupt cut
with a preceding clock failure is not a low-battery power-off; a low-battery
power-off is orderly and logged.

**What to do next, in this order:**

1. Find out whether the storm is voltage-dependent. It began at ~3.82 V raw,
   the lowest the phone had been all session, and one more occurred in the
   fresh boot at 3.89 V while charging — so a pure sag explanation is already
   weakened, and it needs the actual test: repeat a fixed cpufreq sweep at high
   and low battery and count failures. `git grep -n "failed to enable"
   drivers/clk/qcom/clk-alpha-pll.c` shows there is no retry there at all.
2. Only then re-run a slope leg. Any leg whose phase B overlaps the storm is
   measuring the storm.
3. Note that this may also be the missing half of the 130-vs-245 puzzle, which
   was previously attributed to the sampler keeping the radio associated. Both
   remain candidates; this one has a log line and the other does not.

### 2026-08-17: running step 1 — the PLL rate against a falling pack

**Method.** `pll-vs-voltage.sh` drives `pll-sweep.sh` repeatedly while USBIN is
suspended, so every point is the same sweep on the same boot, minutes apart,
with only the voltage moving. The rate is failures per **transition**, read from
the kernel's own `total_trans` delta, because a `scaling_setspeed` write the
governor coalesces away exercises nothing and would otherwise be counted as a
transition that survived. `pll-ramp-fit.py` reads the log and fits rate against
voltage.

**How it is run unattended.** Three things that each cost a run before they were
fixed:

* Start it as a **transient systemd unit**, not with `nohup`. A `nohup`-ed job
  under `sudo` over ssh is killed with `Terminated` when the ssh session's scope
  goes away — measured, thirteen minutes lost — and the only reason it did no
  harm is that the script's EXIT trap restored charging on the way out.
* Give the unit `ExecStopPost=` that restores charging, as well as the script's
  own trap. ☠️ `USBIN_SUSPEND_BIT` lives in the PMIC and survives a warm reboot;
  it must never outlive the measurement that set it.
* Cut the ramp on **voltage, not on a clock**. A supervisor watching for the
  threshold ends the run where the science ends, and leaves enough charge for
  whatever runs next.

**Sizing.** Rounds per point is a resolution knob, not a quality knob: the total
number of transitions a night can buy is fixed by wall-clock, so slicing finer
costs nothing in total statistical power and gains voltage resolution. The first
attempt used 5000 rounds and took ~98 minutes per point, which would have
produced two points and no ramp at all; 1500 rounds gives ~12.5 minutes per
point and ~13 500 transitions in it.

☠️ **Count failures from the journal, never from `dmesg`.** The ring buffer
wraps: two `dmesg | grep -c` reads twenty minutes apart on one boot returned 35
and then 34, so the count went *down* while failures were still accumulating. A
leg could report itself clean precisely because the storm had been loud enough
to push its own evidence out of the buffer. `pll-sweep.sh` takes a `journalctl`
cursor; `suspend-slope.sh` now carries a `pll=` field on every sample from the
same source, so each leg says for itself whether it was contaminated instead of
that being reconstructed afterwards.

**Result so far — the top of the pack, and it is flat.** Seven points over
4.318 → 4.137 V, ~13 500 transitions each: 12.6, 7.4, 5.2, 5.9, 8.9, 12.6, 4.4
per 10 000, pooled **8.1 per 10 000** (77 failures in 94 586 transitions). The
fitted change across that span is 7.4 per 10 000 against an uncertainty of 7.8,
so there is no voltage dependence to see here. For comparison the 2026-08-16
baseline was 18 per 10 000 at 4.358 V.

⚠️ That covers only the top 181 mV. The sighting this was run to explain was at
3.82 V, and the ramp had not reached it when this was written — so the claim
that is supported *now* is narrower than the question: **the storm runs at a
full pack too, and does not vary with voltage while the pack is full.** It
already means the storm cannot be explained by sag alone.

**In flight at the time of writing (2026-08-17 morning).** The ramp was cut by
hand at 06:32 after 26 points, because the pack was falling ~0.9 mV/min by then
and reaching 3.80 V would have pushed the leg that follows into the afternoon.
Final ramp numbers: **26 points, 4.318 → 3.931 V (386 mV), 255 failures in
351 325 transitions = 7.3 per 10 000**, fitted change 3.9 against an uncertainty
of 2.9 and `r = +0.47` — no voltage dependence, and what little slope there is
runs the *wrong* way for the sag hypothesis.

⚠️ So step 1 is answered for 4.32 → 3.93 V only. Below 3.93 V is still untested,
and the 3.82 V sighting sits just under that edge. If the storm ever needs a
sharper answer, that is the gap to close.

## Step 2 answered: what the phone draws asleep

The slope leg `post-pll-20260817` ran 06:33 → 10:53 and completed clean: **8
suspends of 8**, every one `slept=901s of 900s`, so nothing woke it early and
phase A really is measuring suspend. Log and fit:
`2026-08-17_pmos_post-pll-slope-leg.txt`.

| phase | compensated V | slope | r² | `current_now` mean |
|---|---|---|---|---|
| settle | 3.9815 → 3.9424 | −156.6 mV/h | 0.63 | 142.1 mA |
| A (asleep, 8×900 s) | 3.9232 → 3.8996 | −15.92 mV/h | 0.80 | 121.5 mA |
| B (awake control) | 3.8677 → 3.7864 | −41.18 mV/h | 0.93 | 155.3 mA |

**I_sleep = 155.3 mA × (15.92 / 41.18) = 60 mA.**

That is the first number for suspend on this device that came off a live
instrument. Read it against the two regimes it sits between: clean awake idle is
~130 mA, and the ~10 mA that the platform ought to reach is still an order of
magnitude below this. **s2idle roughly halves the draw and no more** — so
whatever keeps the phone at 130 mA awake is mostly still running with the
kernel frozen, and that, not the awake figure, is the next thing to chase.

⚠️ Phase A's fit is the weak one (r² = 0.80 over 23.6 mV of travel). The
direction is safe; treat the 60 mA as ±10 rather than as three digits.

**The `pll=` column paid for itself, twice.** Phase A took **8** failures in its
1.79 h; phase B took **137** in the same 1.79 h — a storm ~17× denser in the
awake leg, exactly the contamination that cost the 2026-08-15 run its 116 mA.
This time it is measured rather than reconstructed. And it does *not* invalidate
the result: `I_awake` and `slope_B` both come out of phase B, so a storm that
inflates the draw inflates the slope with it and the quotient is immune to first
order. That immunity is the reason the calibration is against a measured current
instead of against the OCV table — worth keeping in mind before anyone
"improves" the method by dropping phase B.

☠️ **The journal counter is a floor, not a total.** The `pll=` field went
**down** across the phase boundary — 320 at the end of A, 288 at the start of B
— so `journalctl -k -b` had already dropped records of this boot. It lies in the
same direction as `dmesg` did, just later: a loud enough storm evicts its own
evidence. Every count in this document is therefore a lower bound. If an exact
count ever matters, take a cursor at the start of the leg and read forward from
it rather than counting the whole boot.

## 2026-08-17 evening: the AP now sleeps through, and the next layer is named

Removing the one-second cap did exactly what the arithmetic said it would. Same
instrument, same 91 s suspend, one boot apart:

| | with the 1 s cap | cap removed |
|---|---|---|
| APSS `Shutdown count` | +91 | **+1** |
| `power-domain-system` S2idle | +92 | **+1** |
| woke on time | yes | yes (91 s of 90 s) |

So the application processor goes down once and stays down for the whole
suspend, instead of being brought back up every second to pay a 12 ms sleep
transition and a 12 ms wake transition each time. Landed as `ff064e2b608c` on
`wip/7.1.3/power`, cherry-picked and pushed to all three branches; the device
runs it as build `#2` from a hand-installed `/boot/vmlinuz`.

☠️ **A symptom I listed wrongly, corrected from the oracle.** I had counted
APSS `XO shutdown count: 0` among the things still broken. The Ubuntu Touch
capture shows `xo_count: 0x0` and `xo_accumulated_duration: 0x0` for APSS as
well — on the stack that works. Only MPSS, PRONTO and LPASS do XO shutdowns of
their own; the application processor never does. So that field being zero is
normal and proves nothing either way.

**What is genuinely still zero: `vlow` and `vmin`.** Both `Count` and
`Accumulated Duration`, after the AP has begun shutting down properly. The AP
going down is necessary and not sufficient — the RPM aggregates across every
master *and* every resource vote, so the next question is which rails are still
voted active-set while we sleep.

⚠️ **Do not read the `Client Votes` field yet.** Four consecutive reads on an
idle system gave `0x11151715`, `0x13171317`, `0x11131715`, `0x17151715` — always
nibbles from {1,3,5,7}, never stable. Either it is a live racy read or mainline's
`qcom_stats.c` decodes the field differently from the vendor's reader. An
instrument that changes its answer between two reads of an unchanged system is
not yet an instrument.

### Why `vlow`/`vmin` stay at zero: the regulators never vote for sleep

Found in the vendor source and confirmed against our own tree. The RPM keeps two
vote sets, and the vendor driver documents what happens when only one is used —
`drivers/regulator/rpm-smd-regulator.c:225-235`:

> *"For any given regulator, if an active set request is present, but not a
> sleep set request, then the active set request is used at all times, **even
> when the Apps processor is power collapsed**."*

So an active-only vote is not neutral. It is a vote to hold the rail at its
awake value through the collapse. Downstream declares **all 23** pm8953 rails
`qcom,set = <3>` — active *and* sleep — and the `_ao` / `_so` suffixed corner
regulators in `msm8953-regulator.dtsi` exist precisely so CX and MX can drop to
retention while asleep and still be held high while awake.

Our `drivers/regulator/qcom_smd-regulator.c` has exactly one write path and it
is `QCOM_SMD_RPM_ACTIVE_STATE` (line 72). `grep -c SLEEP` on that file returns
**0**. Every rail therefore holds its enable, voltage and load votes while the
application processor is collapsed, and the RPM cannot minimise Vdd against two
dozen standing votes.

★ **This gap only became reachable today.** Until the affinity level was fixed
the AP never collapsed at all, so a sleep-set vote would have had nothing to
take effect at. The bug was there the whole time and could not have been
measured — which is worth remembering before treating "we checked that" as
covering a layer that was unreachable at the time.

☠️ **Do not start by writing sleep votes.** Telling the RPM to drop a rail the
system still needs while collapsed is a hang, not a failed experiment. Two free
checks come first, both from debugfs on a live phone:

| check | what it would mean |
|---|---|
| `pm_genpd/pm_genpd_summary` | `rpmpd.c:1005-1007` clamps CX/MX to `max_state` = TURBO in **both** sets until `sync_state` fires. If that is pinned, it masks any regulator fix |
| `interconnect/interconnect_summary` | five msm8953 paths are `RPM_ALWAYS_TAG`, so their bandwidth is voted into the sleep set; a consumer that forgets to zero its request holds BIMC up |
| `clk/clk_summary` | the mainline stand-in for downstream's `clock_debug_print_enabled(true)`, which Qualcomm calls at suspend for exactly this reason |
| `/sys/class/regulator/*/state` | bounds the problem: which of the 23 rails are even enabled |

And there is no way to read the RPM's *aggregated* state — neither tree has one,
and the vendor's `rpm_send_msg` debugfs is write-only. What is observable is what
the AP sends, which is the answerable question. The cheapest instrument is a
tracepoint in `qcom_rpm_smd_write()` (`drivers/soc/qcom/smd-rpm.c:94`), whose
arguments already carry the state, type, id and payload.

### The first leg after the fixes is WITHDRAWN, and the control is why

`nocap-20260817` completed cleanly — 8 suspends of 8, every one `slept=901s of
900s` — and `slope-fit.py` reports **120 mA asleep** against the pre-fix leg's
60 mA. That number is not reported as a result, because two things about the
leg make it incomparable and both are visible in its own output.

| | `post-pll` (pre-fix) | `nocap` (post-fix) |
|---|---|---|
| phase A voltage span | 3.923 → 3.900 V | **4.268 → 4.178 V** |
| phase B voltage span | 3.868 → 3.786 V | 4.148 → 4.015 V |
| phase A raw slope | −15.92 mV/h | −54.26 mV/h |
| phase A `current_now` mean | 121.5 mA | **256.2 mA** (max 402) |
| phase B `current_now` mean | 155.3 mA | 156.5 mA |

**1. It ran on the wrong part of the discharge curve.** The method assumes
`dV/dQ` is roughly constant between the two phases; the reference leg sat in the
flat region around 3.9 V, this one started at 4.33 V where the curve falls much
faster, and its two phases sit in visibly different parts of it. A steeper mV/h
at a high state of charge is expected for the same current, and the A/B ratio
only cancels that if both phases share a slope.

**2. The wake-window current doubled**, which corrupts the IR compensation the
fit applies: 0.12 Ω × 256 mA is a 31 mV correction where the reference leg
applied 15 mV. There is a plausible mechanism — with the deadline cap gone the
AP now stays down for the full 900 s instead of being resurrected every second,
so the resume transient it wakes into is a different and larger thing, and the
20 s `SETTLE_WAKE` was chosen when no deep sleep was happening.

☠️ **The control is what makes this readable rather than a mystery.** Phase B
came back at 156.5 mA against the reference leg's 155.3 — the method is intact
and the awake regime is unchanged. It is phase A's sampling that moved. A leg
without its awake control would have published 120 mA and called the day a
regression.

**Next, in order, and measure before re-running:** characterise the resume
transient directly (wake from a 900 s sleep, sample `current_now` every 2 s for
180 s) so `SETTLE_WAKE` is set from data rather than from a number that used to
work; then re-run with both phases below ~4.0 V so they share the flat region.

### ☠️ One read of `current_now` is not a measurement

Run to find how long the resume transient lasts, so `SETTLE_WAKE` could be set
from data. It answered a different and more useful question, and it disproved
the hypothesis it was built for. Data:
[`2026-08-17_pmos_resume-shape.txt`](captures/2026-08-17_pmos_resume-shape.txt).

**There is no decaying transient.** 90 reads two seconds apart after a 901 s
deep suspend:

| window | mean | median |
|---|---|---|
| 0–20 s | 159.5 mA | 143.3 mA |
| 20–60 s | 175.0 mA | 141.5 mA |
| 60–100 s | 169.0 mA | 157.3 mA |
| 100–180 s | 170.1 mA | 151.3 mA |

Flat. Waiting longer after a wake buys nothing, so the withdrawn leg's second
explanation — that a deeper sleep means a bigger transient the 20 s settle no
longer covers — is **wrong**, and is retracted here.

**What is true instead: the attribute is enormously noisy.** Those 90 reads have
a standard deviation of **70.5 mA** on a ~150 mA signal, a range of 93 to 450,
and a visibly bimodal distribution — periodic activity beating against the
sampler, the same trap this page already recorded once at a 60 s interval. A
single read therefore carries **±138 mA at 95 %**.

☠️ **And `suspend-slope.sh` took exactly one read per sample, then multiplied it
by 120 mΩ to compensate the voltage.** ±138 mA of current error is **±17 mV** of
injected error, and phase A of the reference leg travels **23.6 mV in total**.
The correction meant to clean the measurement was noisier than the thing it
corrects. That is the real explanation for both the r² = 0.80 on that fit and
the withdrawn leg's phase A reading 256 mA where a 10-sample awake reference
taken the same evening read 129: eight draws from a heavy-tailed distribution.

**Fixed**: every sample now takes 20 interleaved voltage/current reads over 10 s
and uses the **median** — the mean would still chase the bimodality. That is
±31 mA and ±4 mV, which is small against the signal. Voltage gets the same
treatment because it comes off the same ADC in the same call and carries the
same beat. Samples now carry an `nread=` field so a log says for itself which
regime it was taken in.

### The tracepoint answers it: only the LDOs never vote for sleep

Armed the new `qcom_rpm_smd_write` tracepoint across a real 30 s suspend.
2159 events. Trace kept as
`2026-08-17_pmos_rpm-votes.trace` (never committed - the raw ftrace was too large; the
decoded result is in [`leads/rpm-sleep-set.md`](leads/rpm-sleep-set.md)).

| resource type | active | sleep |
|---|---|---|
| `clk2` | 894 | 17 |
| `bslv` (bus slave) | 262 | 106 |
| `bmas` (bus master) | 232 | 102 |
| `smpa` (SMPS corners) | 216 | **208** |
| `clk1` | 60 | 48 |
| **`ldoa` (LDO rails)** | **14** | **0** |

So the source-level guess was too broad and the truth is sharper: `rpmpd` votes
sleep for the SMPS corners, `icc-rpm` for both bus directions, `clk-smd-rpm` for
the clocks. The only hole is the **LDOs**, which is exactly
`qcom_smd-regulator.c` — the one file with a single active-only write path.

The 14 `ldoa` events are seven rails — `l3, l6, l7, l8, l11, l12, l13` — each
enabled once and disabled once during the window, all with key `swen` (`73 77
65 6e`), the RPM's enable key.

☠️ **Read that count as a floor, not a total.** The tracepoint fires on
*changes*. A rail enabled during boot and never touched since has had a standing
active-set vote ever since and emits nothing at all now. Seven rails moved
during a 30 s window; every enabled rail on the phone is holding a vote.

**The fix is therefore narrow and upstreamable**: give `qcom_smd-regulator.c` a
sleep-set write path, sending the sleep request when it differs from the active
one, as `rpm_vreg_aggregate_requests()` does downstream. It is a correctness gap
on every RPM-SMD SoC, not an FP3 quirk — and note this is now backed by a
runtime measurement, not only by reading two trees.

## ☠️☠️ 2026-08-18: the eMMC fell off the bus overnight — READ THIS FIRST

The night of the 17th produced no measurement and one serious finding.

**The leg was truncated by a shell bug of mine** (`sample()` used `i`, which is
also every caller's loop counter), so it ran 32 minutes instead of 4.25 hours.
Fixed and committed; verify with a short dry run —
`suspend-slope.sh dryrun 60 2 120` — and check that the settle rows run
`n=0..14`, phase A `n=0,1`, phase B `n=0,1` before trusting a long one.

**And then the eMMC stopped answering.** At 01:16, hours after the leg ended,
with the phone idle on the charger:

```
mmc0: cache flush error -110
mmc0: mmc_hs400_to_hs200 failed, error -110
mmcblk0: recovery failed!
```

`-110` is ETIMEDOUT. The card did not respond, the controller could not fall
back from HS400, root went `emergency_ro`, and from then until morning the
journal contained nothing but its own failure to write. A reboot cleared it
completely: `Filesystem state: clean`, the card re-enumerated at HS400, and
`fp3-selftest` is back to 27 ok / 3 failed with all three explained (two are the
hand-built kernel and DTB not matching the package, one is the known amplifier
case).

⚠️ **Treat this as caused by our own change until shown otherwise.** It is the
first occurrence in months of work, and it happened on the first night after the
application processor began actually collapsing. One occurrence is not proof of
causation, but the mechanism is plausible and specific: if CX collapses while
the controller is merely runtime-suspended, its registers are lost and it comes
back in exactly this state. Downstream has a `qcom,restore-after-cx-collapse`
property (set for sdm845, not msm8953) and mainline has a `restore_dll_config`
path in `sdhci_msm_runtime_resume()` — both are places to look, neither has been
checked yet.

**What this costs, and what it does not.** It can lose data, so no long
unattended run until it is understood. It does not threaten the port: nothing on
the phone is irreplaceable, every artefact is rebuildable from the repositories,
and the failure recovered on a plain reboot.

### 2026-08-18 morning: the gate passed, and the suspect narrowed

**The instrument is fixed and verified.** `suspend-slope.sh dryrun-20260818 60 2
120` ran the loops it was told to
([`2026-08-18_pmos_dryrun-gate.txt`](captures/2026-08-18_pmos_dryrun-gate.txt)): settle
`n=0,1`, phase A `n=0,1` with `slept=61s of 60s` both times and `suspends=2 of
2`, phase B `n=0,1`, charger restored. Long legs can be trusted again. Run this
gate after any edit to the script - it costs eight minutes and it is the only
thing standing between a shell slip and another wasted night.

**The eMMC suspicion moved from *occurrence* to *duration*.** Four readings,
none of which needed a build:

1. Vendor msm8953 does not set `qcom,restore-after-cx-collapse`. The property
   exists in the vendor tree and is applied to **sdm845 only**, on a platform
   that performs system power collapse constantly. Mainline agrees by a
   different route: `restore_dll_config` is true for the sdm845/sdm670/sc7180
   variant info and false for `qcom,sdhci-msm-v4`, which is what our node is.
2. So "CX collapsed and ate the DLL" is not the mechanism the silicon vendor
   thinks applies to this SoC. It is not disproved, but it is no longer the
   leading candidate, and no patch should be written on it yet.
3. **AP collapse alone does not do it.** Measured this morning on the running
   kernel: APSS `Shutdown count` reached 46 357 in about 43 minutes - roughly
   eighteen collapses a second - with root read-write and `mmc0` at HS400
   throughout. The card survives the event happening; whatever hurt it is not
   the event.
4. What that leaves is the other half of the change: with the vMPM deadline cap
   removed, the processor can now stay down for a **long uninterrupted stretch**
   instead of being poked awake once a second. The failure appeared at 01:16
   with the phone idle on the charger, hours after the leg ended - which is
   exactly the condition that produces the longest collapses of the night.

So the experiment is a soak, not a build: leave the phone idle on the charger
with [`emmc-watch.sh`](tools/emmc-watch.sh) running and see whether it recurs, with the
record on tmpfs this time so that it survives the filesystem it is watching.
Started 2026-08-18 at uptime 2620, `apss_shut=48262`.

☠️ **`rpm_master_stats` is a module and nothing autoloads it.** The DT node is
present and the platform device is created, but with no driver bound
`/sys/kernel/debug/qcom_rpm_master_stats/` does not exist at all. A reader that
does not `modprobe` first gets nothing and can easily read that as "the
processor never collapsed".

### 2026-08-18: why the RPM never turns the crystal off

`vlow` is the RPM's XO-off record, and APSS `XO shutdown count` has been 0 for
every boot of this investigation while MPSS (6116), PRONTO (21278) and LPASS all
shut XO down routinely. So the question "why is `vlow` zero" is the same question
as "what does the application processor hold XO for".

The answer is a standing sleep-set vote, and it is structural rather than
accidental. In `clk-smd-rpm.c` every RPM clock exists twice - a plain one and an
`_a` peer marked `active_only` - and `to_active_sleep()` is the whole difference:

```c
	if (r->active_only)
		*sleep = 0;
	else
		*sleep = *active;
```

`clk_smd_rpm_prepare()` then writes **both** sets. So preparing the plain
`bi_tcxo` asks the RPM to keep the crystal running *while the processor is
asleep*, and the RPM obliges - exactly as the vendor comment quoted earlier in
this page says it will.

☠️ **The table that used to be here named the wrong thing, and it was measured
wrong the same morning it was written - see "who actually holds it" below.**
`clk_summary` lists the devices that hold a clk *handle*, not the devices that
enabled the clock. The proof is in the same output: `gpu@1c00000` appears under
`gcc_oxili_gfx3d_clk`, whose enable count is zero.

☠️ **The tracepoint cannot answer this one.** `bi_tcxo` is `clk0/0`, and no
`clk0` write appears anywhere in the captured trace: the vote was cast once at
boot and never changed, and a tracepoint on the write path only sees changes.
This is the standing-vote blind spot noted when the trace was taken, and here it
is costing a whole resource. `clk_summary` is the instrument for this question,
not the trace.

☠️ **And mainline gave the eMMC controller an XO vote the vendor never took.**
Vendor `sdhc_1` has `iface_clk`, `core_clk`, `ice_core_clk` and nothing else;
mainline's node adds `<&rpmcc RPM_SMD_XO_CLK_SRC>` as `"xo"`. It happens not to
matter here because runtime PM releases it, but it is a difference from the
oracle that was not deliberate.

### Who actually holds it - measured 2026-08-18, and it is neither remoteproc

Two probes on the r60 package kernel
([`2026-08-18_pmos_xo-vote-probe.txt`](captures/2026-08-18_pmos_xo-vote-probe.txt)):

| step | `bi_tcxo` | `apss_xo` | `vlow` | `vmin` |
|---|---|---|---|---|
| baseline | 6 | 0 | 0 | 0 |
| after a 60 s control suspend | 9 | 0 | 0 | 0 |
| after **stopping** modem + ADSP | **9** | 0 | 0 | 0 |
| after a second 60 s suspend | 9 | 0 | 0 | 0 |
| after **unbinding** `qcom-q6v5-mss` | **9** | – | – | – |
| after **unbinding** `qcom_q6v5_pas` | **9** | – | – | – |

Neither stopping the firmware nor unbinding the driver moves the count by one.
So the experiment never changed its own input, and **the suspends in it prove
nothing about the hypothesis** - they were run against an unchanged vote.

The source says the same thing, and would have said it first. On msm8953 `"xo"`
is a **proxy** clock for the modem (`msm8953_mss.proxy_clk_names`), and
`qcom_msa_handover()` drops the proxy clocks as soon as the firmware takes over.
A running modem was never holding it.

What is left is the floor of 6 with everything idle, moving between 6 and 10 with
eMMC activity, and nothing in this instrument can attribute it further. The
question "does the sleep-set XO vote block `vlow`" is therefore still open, and
attribution by elimination has run out of levers: the way to answer it is to
make `bi_tcxo`'s sleep vote zero in the kernel and read `vlow`, not to keep
guessing at who enabled it.

☠️ **Run device probes under `systemd-run`, never in the foreground over ssh.**
The unbind probe was run directly, the ssh call hit its timeout mid-script, and
the script died with the session - leaving the modem and the ADSP unbound with
nothing left running to rebind them. `emmc-watch` survived the same moment
because it was a transient unit.

### ☠️ Six loops that could not fail, 2026-08-18

All three were mine, all three cost only wall-clock, and all three are the same
mistake: **a condition the pre-change state already satisfies**. Written down
because the next one will look just as reasonable.

```sh
until ! pgrep -f 'pmbootstrap.py build linux-fp3'; do sleep 60; done
```
The loop's own command line contains that string, so `pgrep` matched itself. It
was still "waiting for the build" forty minutes after the build finished.

```sh
until ! ssh $DEV 'systemctl is-active slope-dryrun' | grep -q active; do ...
```
`is-active` prints **`inactive`** when the unit is gone, and `inactive` contains
`active`. The loop outlived its unit by an hour.

```sh
ssh $DEV 'sudo sh -c "(sleep 2; reboot) &"'
until ssh $DEV 'uname -r' | grep -q msm8953; do sleep 10; done
```
Two faults at once. The backgrounded `reboot` died with the ssh session, so no
reboot happened at all; and the wait would not have noticed either way, because
the *old* kernel answers `uname -r` exactly like the new one. It reported
"VISSZAJÖTT" against a machine with an uptime of 1 h 49 m.

A fourth, an hour later and the same shape:

```sh
nohup pmbootstrap build ... > build.log &
until grep -q 'Finished building packages' build.log; do sleep 30; done
```
The file still held the *previous* build's log, so the wait was satisfied
before the new build had written a byte, and it reported a finished build
against a package that did not exist. Truncate the log first, and check the
artefact - not the narration.

A fifth, and this one corrupted a measurement rather than just wasting time:

```sh
load_start                      # eight busy cores, to reach the flat region faster
while :; do
	v=$(cat "$BATT/voltage_now")
	[ "$v" -le "$TARGET" ] && break
```
The threshold was chosen for a **resting** pack and tested against a **loaded**
one. Eight cores pull the terminal voltage down by about 360 mV, so the first
check read 3.954 V against a 4.030 V target, declared the descent finished after
sixty seconds, and handed a leg to the slope instrument at 4.238 V - deep in the
steep region the target exists to avoid. Shed the load and let it recover before
every comparison.

**6. Waiting for a file nothing would ever write.**

```sh
until [ -s .../bfki8zinb.output ]; do sleep 15; done
```

The output belonged to the xo-unbind probe, which had already died with its ssh
session. The file was 0 bytes at 08:05 and still 0 bytes when the loop was
killed at 10:05 - two hours of polling for a writer that no longer existed. A
wait needs a liveness check on the *producer*, not only on its product: if the
job is a transient unit, poll `systemctl is-active`, and if it is not a unit,
give the loop a bounded iteration count so it reports failure instead of
waiting forever.

The rule that fixes all six: **wait on something that changes**, and prove it
changed - and make sure the thing you compare against was measured under the
same conditions as the threshold. For a reboot that is `/proc/sys/kernel/random/boot_id`, captured before
and compared after; and schedule the reboot with `systemd-run --on-active=2` so
it survives the session that asked for it.

### ★★★ 2026-08-18: the sleep-set XO vote WAS blocking the processor - and the oracle does not do this

`clk_smd_rpm.xo_sleep_off=1`, r61, one boot, two 60 s suspends
([`2026-08-18_pmos_xo-sleep-off.txt`](captures/2026-08-18_pmos_xo-sleep-off.txt)):

| | before | with `xo_sleep_off=1` |
|---|---|---|
| APSS `XO shutdown count` | **0**, every boot since 2026-08-14 | 100 at 31 s, **1952** at 3.5 min |
| APSS `XO total duration` | 0 | 2 747 593 309 ticks ≈ **143 s** |
| suspends / failures | – | 2 / 0, resume intact |
| `vlow` / `vmin` `Count` | 0 | **0** |

So the mechanism was real: the sleep-set vote written by
`clk_smd_rpm_handoff()` at probe - before any consumer exists, which is why the
write tracepoint never saw it and why unbinding drivers did nothing - was what
kept the application processor from ever shutting the crystal down. Zero that
vote and it shuts it down constantly, and nothing breaks.

☠️ **And that is not the good news it looks like.** The Ubuntu Touch oracle,
running the vendor stack on the same hardware, reports APSS `xo_count: 0x0` and
`xo_accumulated_duration: 0x0` while its MPSS, PRONTO and LPASS all shut XO down
thousands of times
([`2026-08-15_ut_oracle_rpm-master-stats.txt`](captures/2026-08-15_ut_oracle_rpm-master-stats.txt)).
**The vendor's application processor never does this either.** Our pre-change
behaviour matched the oracle exactly; the change makes us diverge from it. So
this is either a saving the vendor leaves on the table, or a vote the processor
is supposed to hold - and nothing measured so far distinguishes those.

`vlow` and `vmin` did not move, which means whatever they record needs more than
the application processor's XO vote.

**What this costs to find out, in order:**

1. **The current.** That is the question this whole page exists for, and there is
   now a fixed instrument and a change worth A/B-ing. A slope leg with
   `xo_sleep_off=1` against one without it answers "does it save anything"
   without needing to know what `vlow` means.
2. **Whether the vendor's RPM ever reaches `vlow` at all.** Not in any capture
   we hold: the UT files carry the master stats and the downstream cpuidle LPM
   histogram, but not the RPM system sleep record, which downstream exposes at
   `/sys/kernel/debug/rpm_stats`. If the vendor also sits at zero, then `vlow`
   is not a reachable state on this SoC and it has been the wrong instrument
   since 2026-08-14 - a possibility that has never been tested.

### Where the sleep-set vote comes from, and why it is not simply a bug

`clk_smd_rpm_handoff()` writes the value into **both** the active and the sleep
set, for **every** clock in the platform's table, at probe - before any consumer
exists. The table contains both peers of each clock, so this includes the `_a`
active-only ones, whose entire reason to exist is that
`to_active_sleep()` gives them `*sleep = 0`.

That has been there since the driver's first commit, `00f64b58874e` (Georgi
Djakov, 2016), whose message says it is based on the codeaurora driver. **The
codeaurora driver does not do it.** Vendor `clk_rpmrs_handoff_smd()` sends no
RPM message at all - it sets the software rate and returns - and then defers to
`rpm_clk_prepare()`, which is otherwise line-for-line what mainline's
`clk_smd_rpm_prepare()` still is, active-only distinction included. So the
unconditional sleep-set write is a divergence introduced in the port, nine years
old, and it is on every SMD-RPM platform: msm8916, msm8974, apq8084, msm8953,
sdm660, sm6115, qcs404 and the rest.

☠️ **That does not make it a bug, and the oracle is why.** The vendor's APSS
never shuts XO down either - `xo_count: 0x0`, zero accumulated duration - so
whatever route it takes, downstream ends up holding an XO sleep vote too.
Mainline reaches the vendor's *outcome* by a mechanism the vendor does not use.
Removing the vote makes us diverge from the outcome, which is the opposite of
the usual direction of a fix, and the only thing that can say whether it is an
improvement is the current.

Worth reporting either way once there is a number; worth nothing as an argument
without one.

### ★ VERDICT: the XO sleep-vote A/B is a clean NEGATIVE, 2026-08-18 20:30

Both legs are in, both fitted with the same `slope-fit.py`, both run on r61 from
the same rootfs, 8 h apart, phase A and phase B in the same voltage windows.

| | experiment `xo_sleep_off=1` | control `xo_sleep_off=N` |
|---|---|---|
| raw file | `2026-08-18_pmos_xo-on-leg.txt` | `2026-08-18_pmos_xo-off-leg.txt` |
| APSS `XO shutdown count` during the leg | **1952** | **0** |
| phase A window | 4.0739 -> 4.0279 V | 4.0560 -> 4.0071 V |
| **phase A slope (asleep)** | **-35.29 mV/h** (r2 0.994) | **-35.44 mV/h** (r2 0.962) |
| phase B window | 3.9937 -> 3.9025 V | 3.9746 -> 3.8859 V |
| phase B slope (awake control) | -71.20 mV/h (r2 0.992) | -66.15 mV/h (r2 0.990) |
| phase B current, measured | 150.1 mA | 161.0 mA |
| derived asleep | 74.4 mA | 86.3 mA |

☠️ **Do not read that last row as a 12 mA win.** Read the row above it instead.
The two *sleep* slopes are **-35.29 and -35.44 mV/h - the same number to 0.4 %**,
measured over near-identical voltage windows, while the XO shutdown count went
from 0 to 1952 between them. The entire 74.4-vs-86.3 gap comes from the
**awake** reference disagreeing between the legs (150.1 vs 161.0 mA, -71.20 vs
-66.15 mV/h), not from anything the sleeping phone did.

So the honest statement is: **making the RPM shut the XO down 1952 times over a
90-minute suspend leg changed the measured discharge rate by nothing at all.**

That is consistent with the structural gate rather than surprising: `vlow` and
`vmin` have read 0 in every capture ever taken here, *including* the leg with
1952 XO shutdowns. The APSS master can drop its XO vote all it likes; the RPM
still never enters a low-power mode, because some other master or some rail keeps
voting. The UT oracle points the same way - the vendor's APSS does not shut the
XO down either, and the vendor phone still idles far below this.

**What this closes:** the XO branch. Do not spend more on `xo_sleep_off`, and do
not carry it as a default (it is not one - the boot label is plain
`postmarketOS`).

**What this opens:** nothing, which is exactly why the decomposition is next. No
mechanism yet accounts for even 20 mA of the ~60 mA, and this leg has just
removed one of the two candidates that looked mechanical. Every patch written
before the budget exists is a guess.

**Method note worth keeping.** The ratio method's weak point showed itself here:
the derived figure moved 16 % between two legs whose sleep behaviour was
identical, purely because phase B differed. When comparing two legs, **compare
the phase-A slopes directly** - same instrument, same window, no division - and
use the derived mA only to give the reader a scale. A ratio hides which half
moved.

### ★★★ CONFIRMED by same-day control: the modem stack costs ~36 mA ASLEEP

Leg `baseline-20260819`, **no cuts**, same pack and same day as
`nomodem-20260819`, launched by `await-charge.sh` at 99 % and run to completion:
**6 of 6 suspends**, `dpms=Off`, raw
[`2026-08-19_pmos_baseline-leg.txt`](captures/2026-08-19_pmos_baseline-leg.txt).

| leg | cut | phase-A slope | r² | phase-B awake | derived asleep |
|---|---|---|---|---|---|
| `xo-on-20260818` | — | −35.29 mV/h | 0.994 | 150.1 mA | 74.4 mA |
| `xo-off-20260818` | — | −35.44 mV/h | 0.992 | 161.0 mA | 86.3 mA |
| **`baseline-20260819`** | **—** | **−35.77 mV/h** | 0.926 | 101.3 mA | **79.1 mA** |
| **`nomodem-20260819`** | **modem stack** | **−22.62 mV/h** | 0.994 | 97.3 mA | **43.3 mA** |

Two things make this a result rather than a claim.

**The baseline reproduced.** Three legs with no cut, across two days and three
different awake controls, gave phase-A slopes of −35.29, −35.44 and −35.77 mV/h.
That is a 1.4 % spread on the quantity being compared, and it is the first time
this instrument has demonstrated its own repeatability.

**The pair is same-day and its awake controls agree.** 101.3 vs 97.3 mA, unlike
the 150-vs-161 mismatch that made yesterday's derived figures incomparable. So
here the derived numbers may be read directly: **79.1 → 43.3 mA, about 36 mA
saved asleep by stopping `ModemManager`, `rmtfs` and `tqftpserv`.**

☠️ **The window difference runs against the finding, not for it.** The control's
phase A sits at 3.97-4.02 V and the cut leg's at 4.06-4.09 V. Lower is deeper
into the plateau, where the same current produces a *flatter* slope - so the
control had the easier half of the curve and still came out steeper. The effect
is real or understated.

⚠️ The control's phase-A fit is the weak one, r² = 0.926 against 0.994 for the
cut leg. Treat 36 mA as ±5, not as three digits.

**What it is not.** It is not a fix - a phone needs its modem - and it is not
yet a mechanism. Awake, the same cut is worth ~2 mA at the floor and ~23 mA in
bursts; asleep it is worth 36 mA. Something in that stack is either keeping the
MPSS out of its own low-power state or waking the application processor
repeatedly, and those two have different fixes. **The next measurement is
wakeup accounting across a suspend**, not a patch.

### ★ RESUME POINT, 2026-08-20 05:00 - READ THIS FIRST

**Nothing is running on the device.** No transient units, no host pollers, no
guardian. The phone was rebooted at 04:48 into a clean autologin session: modem
`registered`, root `rw`, sound card present, charger connected.

☠️ **The night installed 19 packages that are still there** - the ofono stack,
`iproute2`, Qt, `icu-data-full` - and free space on `/` fell from 345 MB to
234 MB. Nothing was enabled and no boot configuration was touched, but a floor
measured after 2026-08-20 is measured on a larger install than one measured
before it. The full inventory is in
[`../../sailfish-native/README.md`](../../sailfish-native/README.md).

## What the night settled

**The ADSP leg came in, and it is a null.** `adsprestart-20260819`, gated on a
probe suspend that showed the DSP collapsing for 30 625 ms of 30 000 before the
four hours were committed. Phase-A slope **−34.32 mV/h** against the baseline's
−35.77, on an instrument whose baseline reproduces to 1.4 % across three legs -
so **4 %, and the window sits lower where the OCV curve is flatter**, which
biases it optimistic. Read it as *at most 4 %, plausibly nothing*.

**And the holder of the ADSP is named — it is upstream's, not ours.**
`c0f0000.codec` is bound to `msm8916-wcd-digital-codec`, the SoC's internal
digital codec, which is not in this phone's audio path.
`msm8916_wcd_digital_probe()` calls `clk_prepare_enable()` on `mclk`
(`LPASS_CLK_ID_INTERNAL_DIGITAL_CODEC_CORE`, supplied by the ADSP over APR) and
on `ahbix-clk`, unconditionally, releasing them only in `remove()`. No runtime PM,
no DAPM gating. ☠️ An earlier version of this page attributed it to this port's
WCD9335 MCLK work; that was wrong and is corrected in
[`leads/lpass-never-sleeps.md`](leads/lpass-never-sleeps.md).

**Four branches closed**, so nobody re-runs them: an ADSP client holding LPASS
(six stages, up to stopping the DSP); the regulator sleep set costing anything
droppable (five suspect rails became one with USB unbound, and that one is the
eMMC's); USB stopping the DSP collapsing (three alternating rounds); and the held
ADSP session being the lever (the leg above).

## Where the numbers stand

| | draw |
|---|---|
| awake idle, panel off, session running | ~58-63 mA |
| the panel, powered at zero brightness | +24.5 ± 6.4 mA |
| asleep, no cuts (`baseline-20260819`) | 79.1 mA |
| asleep, ADSP collapsing (`adsprestart-20260819`) | 70.8 mA |
| asleep, modem stack cut (`nomodem-20260819`) | 43.3 mA |
| every userspace service tested, five of five | zero |

☠️ `mem_sleep` offers **only `[s2idle]`**. "Deep sleep" here means getting the RPM
into `vlow`, and `vlow` has read **`Count: 0` in every capture ever taken on this
device** - including with the audio DSP collapsing for the whole of every suspend.
A master being down is **necessary and not sufficient**, and that is a measured
correction to the claim this investigation carried for several days.

## ★ 2026-08-20 05:45: the modem's 36 % is not AP wakeups, and not our userspace

> ☠️☠️ **UNDER REVIEW SINCE 2026-08-26 — the arm labels in this entry are wrong
> for rounds 2 and 3, and both of its conclusions rest on them.**
>
> `wakeup-census.sh` restarted the cut services with `systemctl start` between
> rounds and never restarted the modem remoteproc, so after round 1 the arms
> labelled "modem up" were **modem-down**. Consequences, in order of how much
> they cost:
>
> 1. **"Six arms, all identical, nothing wakes the AP early" is not a result.**
>    Five of the six were the same condition. The only genuine comparison here is
>    round 1's pair — and it asked for 60 s. On 2026-08-26 a 600 s request with a
>    registered modem slept **9.6 %** of what it asked while the cut arm slept
>    100 %, so something *does* wake the AP early.
> 2. ☠️ **The MPSS table inverts.** Its headline — "the one exception is an
>    UNCUT arm", read as proof that the modem can sleep with the stack running —
>    is exactly backwards: round 2's "modem up" is the arm where the modem had
>    been **powered down**. An MPSS that keeps the crystal off for 80 % of a
>    window in which it is switched off carries no information about the running
>    state.
> 3. **Point 2 below — "cutting the modem stack does not cut the modem" — is now
>    itself in doubt**, and in the opposite direction. It rests on `mmcli`
>    reporting the radio registered on the way back in; on 2026-08-26 stopping
>    the same three services left `remoteproc` **offline** and no modem at all,
>    which a restart did not fix. Whether the difference is the kernel revision,
>    the ordering, or a misread on the day is **not** settled by reasoning, and a
>    fixed census is running to answer it.
>
> Nothing here is deleted — the readings are real and the raw capture carries the
> same correction. What is withdrawn is the inference from mislabelled arms.


Two censuses, twelve suspends, `tools/wakeup-census.sh`. Raw:
[`captures/2026-08-20_wakeup-census.txt`](captures/2026-08-20_wakeup-census.txt)
and [`captures/2026-08-20_mpss-census.txt`](captures/2026-08-20_mpss-census.txt).

**The AP side is a clean negative.** Six arms, alternating modem-up / modem-cut,
60 s asked each: **every one elapsed 62 s** with `suspends=+1` and no wakeup
source's active count moving. Nothing wakes the application processor early, with
the modem stack running or stopped. So the 36 % is **not** paid in resumes.

**The modem side does not confirm the other hypothesis either:**

| round | arm | MPSS shutdowns | XO off |
|---|---|---|---|
| 1 | modem up | +0 | 0 ms of 61 000 |
| 1 | modem cut | +0 | 0 ms of 62 000 |
| 2 | **modem up** | **+3** | **49 442 ms of 62 000** |
| 2 | modem cut | +0 | 0 ms of 62 000 |
| 3 | modem up | +0 | 0 ms of 62 000 |
| 3 | modem cut | +0 | 0 ms of 62 000 |

Five of six arms show the MPSS never going down across the suspend — and **the one
exception is an uncut arm**. Cutting our userspace never made the modem sleep.

Two things follow, and the second is a criticism of the original result:

1. **The modem is capable of it.** In that one arm it kept the crystal off for
   80 % of the suspend, so nothing structural prevents it. What gates it is not
   our host software.
2. ☠️ **"Cutting the modem stack" does not cut the modem.** `systemctl stop
   ModemManager rmtfs tqftpserv` stops *host* services; the radio stays powered,
   registered and attached throughout — `mmcli` says so on the way back in.
   Whatever the 36 % is, it is not "the modem being off". `rmtfs` and `tqftpserv`
   are the interesting two, because they serve the modem's own filesystem and TFTP
   requests: stopping them changes what the modem *does*, not whether it runs.

☠️ **n is 3 per arm and one positive.** This narrows; it does not name. What it
removes is the two explanations that were easiest to reach for.

## ★ 2026-08-20 11:16: the first rmtfs ab-leg ran clean and is a lead, not a result

`ab-leg.sh rmtfs-20260820 "rmtfs" 6 900` — dry run passed first (4/4 arms,
cut applied and restored), then the real leg: descent 4.39 → 4.03 V, **12 of 12
suspends slept 901–902 s of 900**, charger and greetd restored on exit. Raw:
[`captures/2026-08-20_ab-leg-rmtfs.txt`](captures/2026-08-20_ab-leg-rmtfs.txt).

| arm | n | median mV/h |
|---|---|---|
| CUT (rmtfs stopped) | 6 | **−16.33** |
| FULL | 6 | −73.02 |

Difference +56.7 mV/h in CUT's favour — 78 % of FULL — **but the within-arm
scatter is 97 mV/h and the standard error of the difference 56, so it is inside
2 SE and the fitter itself refuses it.** Several CUT arms measured *rising*
voltage: post-descent relaxation reaches well past the 20 s settle, and a 900 s
suspend does not integrate it away.

Two mechanical notes from this run: `TARGET` in `ab-leg.sh` is now
env-overridable so a dry run can skip the descent (a priced leg leaves the
default), and the leg was launched under `systemd-run --collect` so it survives
both the suspends and the SSH drops.

**Next: the same leg, stronger** — longer suspends halve the relative
relaxation noise and more anything helps the median: `ab-leg.sh rmtfs2-<date>
"rmtfs" 8 1800` (~8.5 h of arms) once the pack is back above the 4.2 V /
95 % start gates. If +56.7 mV/h is even half real, 8 × 1800 s puts it past 2 SE.

### ★★ 2026-08-20 19:30: the second leg is a clean null, and the instrument failed its power budget

`ab-leg.sh rmtfs2-20260820 "rmtfs" 8 1800` ran 11:40 → 19:26; every arm slept
1802–1803 s of 1800; ended safely on the 3.8 V floor after cycle 8's CUT arm
(8 CUT / 7 FULL arms, charger restored). Raw:
[`captures/2026-08-20_ab-leg-rmtfs2.txt`](captures/2026-08-20_ab-leg-rmtfs2.txt).

| arm | n | median mV/h |
|---|---|---|
| CUT | 8 | −40.44 |
| FULL | 7 | −39.27 |

**Difference −1.16 mV/h (3 % of FULL).** The first leg's +56.7 did not
reproduce — it was the noise its own fitter refused to accept.

☠️ **But the null is weak too, and that is the real finding.** A 36 %-of-sleep
effect is ~14 mV/h at these slopes, and the per-suspend scatter is ~87 mV/h —
so this design would need ~40 arms per side to resolve the effect it was built
to chase. Per-suspend slopes on a gauge whose single reads scatter ±138 mA are
intrinsically this noisy; the instrument that *did* detect the 36 %
(`nomodem-20260819`) integrates a whole 4 h phase into one fitted line.
**Pricing the three services separately therefore costs a slope-leg each**, the
very cost `ab-leg.sh` was invented to avoid — the invention ran and failed its
power budget. What the alternation still excludes: any *fast-acting* rmtfs
effect bigger than ~90 mV/h.

Next: `slope-leg.sh <tag> rmtfs` overnight — same instrument and protocol as
`nomodem-20260819`, one cut for the whole leg, compared by phase-A slope
against `baseline-20260819` (−35.77) and the nomodem leg.

### ★★★ 2026-08-21 00:15: rmtfs alone carries about half the modem's cost — and the effect is slow-acting

`slope-leg.sh rmtfsslope-20260820 rmtfs` ran overnight and completed clean
(6 of 6 sleeps, phase B control intact, charger restored). Raw:
[`captures/2026-08-21_pmos_rmtfs-slope-leg.txt`](captures/2026-08-21_pmos_rmtfs-slope-leg.txt).

The phase-A ladder, the comparison the instrument is built for:

| leg | cut | phase-A slope | vs baseline |
|---|---|---|---|
| `baseline-20260819` | — | −35.77 mV/h | — |
| `adsprestart-20260819` | ADSP collapsing | −34.32 | ≤4 % |
| **`rmtfsslope-20260820`** | **rmtfs only** | **−28.46** (r²=0.99) | **−20 %** |
| `nomodem-20260819` | all three | −22.62 | −37 % |

**So rmtfs alone buys about 20 % of the sleeping draw — roughly half of the
trio's 37 % — an order of magnitude past the instrument's 1.4 % spread.** The
remainder sits in `ModemManager`/`tqftpserv` or in the combination.

**And this names the shape of the mechanism.** The ab-leg alternation, which
re-applied the same cut for 30-minute windows, measured a clean null on the
same service the whole-leg cut prices at 20 %: **the effect needs time to
appear.** Whatever the modem does when its filesystem service is gone, it
takes longer than half an hour to settle into it. That is a property the
mechanism hunt can use — and it is why both results are right.

⚠️ Two honesty notes: the phase-A window (3.98→3.94 V) sits lower than the
baseline's (4.09→4.06), which biases the ratio optimistic — the direction and
order of magnitude are safe, the third digit is not. And phase B's control
came in at 124.1 mA against the usual ~150; the derived asleep figure
(71.6 mA) is therefore less comparable across legs than the slope ratio is.

Next, in order: the same whole-leg cut for `ModemManager` and for `tqftpserv`
(one night each), and only then the mechanism question — what rmtfs's absence
makes the modem stop doing, with `qcom_rpm_master_stats` (MPSS shutdowns, XO
duration) read across the sleeps of whichever leg shows the saving.

### ☠️☠️ 2026-08-21 05:00: `rmtfs -P` — stopping rmtfs POWERS THE MODEM DOWN, and it rewrites every "service cut" above

Found while recovering the phone after the second overnight leg: `ModemManager`
would not start (`msm-modem-uim-selection` looping on "node with id 0 not found
in QRTR bus"), because **the modem remoteproc (`4080000.remoteproc`) was
offline** — and had been since 23:25. The cause is in the unit file:

```
ExecStart=/usr/bin/rmtfs -r -P -s
```

`-P` powers the modem processor down when rmtfs exits. `systemctl stop rmtfs`
is therefore not a service cut — **it is a modem shutdown**. And the modem does
not come back when rmtfs restarts; it stays down until someone writes `start`
to the remoteproc (which is what the recovery did; after that MM starts and the
radio registers again — `pd-mapper` keeps failing with "no pd maps available",
noted as an open question).

What this rewrites, leg by leg:

* **`nomodem-20260819` (−37 %)** cut all three services, so it powered the
  modem down. Its honest name is *modem-off*, not "modem stack cut". The ~36 mA
  is what the **modem processor being off** is worth — unusable as a fix, since
  the phone needs the modem, but finally a named mechanism.
* **`rmtfsslope-20260820` (−20 %)** also powered the modem down at the cut.
  Same state, measured lower — the two legs disagree by more than the
  instrument's spread, and the differing voltage windows are the suspect.
* **`mmslope-20260821` (−27 %)** is **contaminated**: the modem was already
  offline for its entire duration (never rebooted after the rmtfs leg). It
  measured *modem-off + MM stopped*, not "MM alone". Its number must not be
  read as ModemManager's price.
* **The ab-leg null and the "slow-acting effect" story are both re-explained,
  and the story is retracted.** The first CUT arm powered the modem down; the
  rmtfs restart between arms did not bring it back; so every subsequent arm —
  CUT and FULL alike — ran modem-off. Identical states, null by construction.
  Nothing here ever measured a slow-acting effect.
* **The 2026-08-20 05:45 census line "the radio stays powered, registered and
  attached throughout" needs re-reading** — it was taken across stop/restart
  cycles of all three services and `mmcli` answered on the way back in. With
  `-P` in the unit, what exactly the modem was during those arms is now an
  open question, not a fact.

The method lesson is the same one the USB census taught, one layer deeper:
**"stop a userspace service" is not a bounded intervention until every side
effect of the stop is enumerated.** `-P` was in the unit file all along; nobody
had read it.

What a valid service-pricing now requires: the modem verified `running` at cut
time and at leg end (one `cat /sys/class/remoteproc/*/state` in the leg
preamble and epilogue), and **rmtfs never stopped** while pricing anything
other than modem-off itself.

### ★★★ 2026-08-21 09:20: the first VALID service price — ModemManager alone is ~10 %, not 27 %

Leg `mmslope2-20260821`, run exactly to the validity rule above: only
`ModemManager` cut, `rmtfs` untouched, and the mpss verified `running` in the
preamble, at every monitor poll, **and in the epilogue**. 6 of 6 suspends
completed, rc=0, charger restored. Raw:
[`captures/2026-08-21_pmos_mm2-slope-leg.txt`](captures/2026-08-21_pmos_mm2-slope-leg.txt).

| phase | window | slope | r² | `current_now` mean |
|---|---|---|---|---|
| A (asleep, MM cut, modem RUNNING) | 3.9472 → 3.9037 V | **−32.23 mV/h** | 0.9693 | 133.1 mA |
| B (awake control) | 3.8714 → 3.7996 V | −55.06 mV/h | 0.9885 | 144.3 mA |

Read against the phase-A ladder: baseline −35.77, this leg −32.23 — **the
ModemManager daemon with the modem alive is worth about 3.5 mV/h, ~10 % of
sleeping draw.** The earlier `mmslope` leg's −26.13 (−27 %) is confirmed void:
most of what it "measured" was the `-P`-powered-down modem it inherited from
the rmtfs leg before it. The adsprestart leg put per-leg reproducibility at
≤4 %, so ~10 % is above the noise floor but only just — it is a real but
minor cost, and it does **not** carry the modem's 36 %.

What this decides: **the modem's ~36 % (nomodem −22.62 vs baseline −35.77) is
the modem processor itself being up, not any one userspace daemon.** MM is
~10 %; the remainder is the MPSS's own floor (XO holds, RPM votes cast by the
modem as an RPM master). A tqftpserv leg is now unlikely to find more than
noise — the interesting instrument is `qcom_rpm_master_stats` around sleeps:
does the MPSS ever XO-shutdown while registered, and if not, is that a
network/config question (PSM, eDRX, band) rather than an AP-side one.

### ★★ 2026-08-21 09:31: the MPSS duty-cycles during AP suspend — XO held ~37 % of the time

Answered the same morning, on the charger (this probe counts shutdowns, it does
not need a discharge leg). Snapshots of `qcom_rpm_master_stats` around one
`rtcwake -m mem -s 300`, modem registered throughout. Raw:
[`captures/2026-08-21_pmos_mpss-xo-suspend-probe.txt`](captures/2026-08-21_pmos_mpss-xo-suspend-probe.txt).
Tick rate is the 19.2 MHz XO (verified: the APSS timestamp delta over the
307 s wall window is 5.90e9 ticks).

| master | Δ shutdowns | Δ XO-off time | share of the 307 s window |
|---|---|---|---|
| MPSS | +745 | +194.0 s | **63 % off, 37 % holding XO** |
| PRONTO | +31 | +303.7 s | ~99 % off |
| APSS | +89 | 0 | never XO-shutdowns (vendor identical) |
| LPASS | **+0** | +0 | still never sleeps |

So the modem is **not** a master that never sleeps — it wakes ~2.5×/s
(745/300, faster than a bare 1.28 s LTE paging cycle, so more than paging is
running) and holds the crystal ~113 s out of every 300. That residency is the
mechanism behind the remaining ~26 % (36 % modem-off minus ~10 % MM): it is
**network/protocol territory — paging cadence, PSM/eDRX — not an AP-side kernel
defect.** The AP-side avenues on the modem are closed; what would move it is
carrier/modem configuration, which is out of scope for this bring-up.

Two standing facts restated by the same capture: the LPASS took zero new
shutdowns across the suspend (the never-sleeps lead is still the open AP-side
item), and the APSS never XO-shutdowns by design — matching the oracle.

### ★★★ 2026-08-21 midday: the LPASS sleeps PERMANENTLY once the audio-card boot path is out

The never-sleeps hunt ran the same day as a live-removal ladder plus a
module-blacklist bisection over ~6 reboots. Every live removal failed —
userspace audio (pipewire/pulseaudio, socket-masked and autospawn-off),
our watchers (fp3-voiced/spkwatch/ringwatch), the SMGR sensor stack, the
sound card, the internal codec, even the SLIMbus NGD controller: with all
of them gone the LPASS still would not take a shutdown, and an ADSP SSR in
that fully stripped state released it within 10 s (2 → 17 shutdowns). So
the holding state lives **inside the ADSP**, is created once at boot, and
no AP-side handle removal releases it — only firmware restart, or not
creating it in the first place.

The blacklist bisection then found the creator. With
`snd_soc_apq8016_sbc` + `snd_soc_msm8916_digital` + wcd9335 + NGD + smgr
all blocked at boot, the LPASS enters XO shutdown ~75 s into boot and
**stays there indefinitely** (`Active cores bitmask: 0x0`, last-enter >
last-exit, counters static because nothing wakes it). The full q6/APR
module stack was loaded on that boot — **the q6 protocol layer is
exonerated**; the culprit is in the card/codec/wcd9335/NGD probe group
(bisection of that group in progress below).

☠️ **Method trap that cost several reads: a static shutdown counter is
ambiguous.** "Count stopped growing" means *frozen awake* only if
last-XO-exit > last-XO-enter; when last-enter is the newer timestamp the
master is DOWN and staying down — the success case reads identically to
the failure case in the count column. Always capture the full stats
block, never just the two counts.

☠️ And a permanent LPASS sleep did **not** move `vlow` (still 0, client
votes 0x1050105) — LPASS was necessary, not sufficient. The LDO
active-only sleep-set gap (`leads/rpm-sleep-set.md`) remains the next
named blocker.

### ★★★ 2026-08-21 12:10: the codec fix works — and a SECOND, later latch showed itself

The culprit was pinned to `msm8916-wcd-digital` (codec loaded with the card
blocked → frozen awake from ~27 s; codec blocked → sleeps forever), i.e. the
probe-time unconditional `clk_prepare_enable(mclk)` — on msm8953 mclk is the
ADSP's own q6afecc `LPASS_CLK_ID_INTERNAL_DIGITAL_CODEC_CORE`, so the enable
is a standing AFE clock request. The one-way behaviour (releasing the clock
live does not help, only SSR does) means the DSP **latches awake on the first
request**, so the fix is to never make it at probe: mclk moved into the DAI
startup/shutdown path. Kernel commit `4b09b2158dd8` on `wip/7.1.3/power`
("ASoC: msm8916-wcd-digital: hold mclk only while a stream runs"),
hot-swap-deployed as `snd-soc-msm8916-digital.ko` (clang-built test vehicle,
vermagic-matched; the ftrace WARN it may log is the known toolchain-mismatch
artifact, not a defect).

Rebooted with the FULL stack restored (card, wcd9335, NGD, smgr, pipewire,
pulseaudio, watchers): **LPASS took 56 shutdowns in the first two minutes**
against 2-for-the-whole-uptime before. The fix is proven necessary.

☠️ **And then a second latch fired.** At ~38.8 s (ADSP ticks) the LPASS
froze awake again — during session bring-up (pulseaudio's UCM profile probe
opens every PCM around 24 s; the exact trigger between 24–52 s is not yet
pinned). Same one-way signature: no PCM open afterwards, mclk enable-count 0,
NGD runtime-suspended, and stopping watchers/iio-sensor-proxy/snsregd or
removing the smgr modules releases nothing. The aw8898's DAPM widgets
(IN/SPK PA/OUT) read On with the BE DAI off — worth chasing, but not the
ADSP holder by itself. The UT oracle plays audio and still sleeps 4344×, so
mainline is missing some teardown the vendor stack performs after audio use.
**Open follow-up: find what the first audio-path use leaves behind in the
ADSP** — candidates: q6afe port start/stop asymmetry, q6adm/q6asm session
teardown, an ADSP-internal object created on first APR audio traffic.

☠️ Every live-removal negative from the earlier round was confounded: the
codec latch was present on all those boots, so "removing X does not release
LPASS" said nothing about X. With the codec fixed, live removals get their
meaning back — and the second latch has already been probed clean of the
sensor stack and our watchers.

Audio regression: `speaker-test` runs; `fp3-selftest --only speaker-amp`
FAILs with the **documented pre-existing aw8898 death signature** (amp not
answering on I2C) — the patch touches only the internal codec, and this is
the known open bug, not a regression. The wcd9335 acoustic path needs an
`--acoustic` run with a human when convenient.

☠️ Recovery notes from the live-removal round: rebinding the sound card
after an unbind fails with `genirq: Flags mismatch irq 143` → `-EBUSY`
(wcd9335 never frees its SLIM Slave IRQ on teardown — itself a bug worth
fixing); only a reboot restores audio. The greetd-user pipewire masks do
nothing — since the 2026-08-16 autologin the session user is fp3, and
`systemctl mask` on our /etc-installed watcher units fails ("File exists");
`systemctl disable --now` is the working form. A plain `blacklist` line
does not stop dependency-loads by name — `install <mod> /bin/false` does.

### ★★★ 2026-08-22 10:30: the SECOND latch is GONE — it was the missing disable_stream teardown

Measured on the first ordinary boot of the r64 package kernel (`#65-fp3`,
built 2026-08-21 18:29, the first *installed* kernel carrying both the mclk
fix `4b09b2158dd8` **and** the SLIMbus `disable_stream` fix `dbb414e0be28`),
full stack up — card, wcd9335, NGD, smgr, pipewire, pulseaudio, watchers,
autologin session:

* At 82 min uptime the LPASS sat in XO shutdown (last-enter > last-exit,
  `Active cores bitmask: 0x0`), 66 XO shutdowns / 81 shutdowns taken, and a
  45 s two-point sample showed the counters static **in the down state** —
  the success signature, per the static-counter trap above.
* Live trigger test: 5 s of `speaker-test` through the default path, then
  one read 30 s later — **+3 XO shutdowns, back down** (enter > exit,
  bitmask 0x0). Audio use no longer pins the ADSP.
  cmd: `speaker-test -t sine -f 440 -l 1`, then
  `grep -E 'count|enter|exit|Active' .../qcom_rpm_master_stats/LPASS`.

So the "second latch" of 2026-08-21 12:10 needs its attribution corrected:
that boot ran the *pre-r64* kernel with only the mclk fix hot-swapped as a
`.ko` — its SLIMbus controller still dropped the stream-teardown messages,
so the first PCM open over SLIMbus left the ADSP holding the channel and an
XO vote forever. That is exactly the defect `dbb414e0be28` (and upstream's
pending disable_stream patch, see `lkml-drafts/`) fixes, and with it in the
booted kernel the latch is unreproducible. The open follow-up "find what the
first audio-path use leaves behind in the ADSP" is **closed: a SLIMbus
channel + XO vote, released by disable_stream**. The q6afe/q6adm/q6asm
teardown-asymmetry candidates were never the culprit.

Standing consequence for the ladder: with both latches fixed in the package
kernel, the LPASS now duty-cycles on an ordinary boot with the full audio
stack — the "LPASS never sleeps" lead is closed end-to-end.

## Next, in order

**The instrument for it is written and unarmed:**
[`tools/ab-leg.sh`](tools/ab-leg.sh) + [`tools/ab-leg-fit.py`](tools/ab-leg-fit.py).
One descent, then the arms **alternate** — one suspend with the cut, one without,
repeating — so drift, temperature and the OCV curve's shape act on both equally
and no cross-day control is needed. Both arms from one pack.

☠️ **Run the dry run after any edit**: `ab-leg.sh dryrun-ab "rmtfs" 2 60`.

☠️ **The obvious analysis is wrong and a synthetic test caught it before any
device time was spent.** Regressing all of one arm's samples against time is
contaminated: between two CUT suspends the FULL arm ran and discharged the pack,
so that discharge lands in the CUT fit's gaps. On data built with a true 11.6 mV/h
difference, the whole-arm regression reported **2.1**. The fitter therefore
compares **per-suspend** slopes, and it was proved on three known answers — a real
37 % effect (found), identical arms (refused), and one usable suspend per arm
(refused, after that case crashed it).

☠️ **A null from this leg means "no fast-acting difference".** The cut is
re-applied from cold every cycle, so an effect that needs ten quiet minutes to
appear cannot show up in a 900 s alternation.

☠️ **And there is no fast instrument to do it with.** `charge_now` was tested as a
way to price a state in fifteen minutes instead of four hours
([`captures/2026-08-20_coulomb-probe.txt`](captures/2026-08-20_coulomb-probe.txt)):
it has 0.01 % resolution, which was the hopeful part, but it is an OCV lookup and
not a coulomb count — `dQ/dt` read 85.2 mA where medianed `current_now` read 62.0,
37 % apart in the direction sag predicts. **Sleeping currents still cost a slope
leg**, so a three-way service cut is three legs, and the way to afford it is the
alternating-arms-within-one-descent design, not a cheaper meter.

1. **The modem's 36 %, now narrower.** AP wakeups are excluded and a userspace
   cut does not move the MPSS, so the next question is which of the three
   services carries it — and `rmtfs` is the first suspect, because it answers the
   modem's own filesystem requests and stopping it changes what the modem does
   rather than whether it runs. A three-way `freq-probe`-style cut, one service at
   a time, prices them separately. **Partly answered 2026-08-21 09:20: MM alone
   is ~10 %; the bulk of the 36 % is the MPSS itself. Next instrument is
   `qcom_rpm_master_stats` around sleeps, not another service leg.**
2. **What else votes.** The regulator branch and the master branch are both
   closed, so what is left is another master or a standing resource vote. ☠️ The
   `qcom_rpm_smd_write` tracepoint is blind to a vote cast once at boot and never
   changed - `clk_summary` is the instrument for those, not the trace.
3. **Confirm and fix the internal codec's clocks** - one `unbind` and a 30 s
   suspend confirms it; the fix is runtime PM or DAPM gating in
   `msm8916-wcd-digital.c`. Upstreamable. ☠️ Not scheduled for its current: ~4 %.

☠️ Still no patch on any of this. Four mechanically plausible branches have now
closed, two of them because someone asked what *else* was true of the phone at
the time - and the answer both times was a USB cable.

### ★★ The modem stack is the first thing to move the SUSPEND number, 2026-08-19 08:20

Leg `nomodem-20260819`, `slope-leg.sh` with `ModemManager rmtfs tqftpserv` cut,
started from a full pack. **6 of 6 suspends, every one `slept=902s of 900s`** -
nothing woke it early. Raw: [`2026-08-19_pmos_nomodem-leg.txt`](captures/2026-08-19_pmos_nomodem-leg.txt).

| phase | window | slope | r² | `current_now` mean |
|---|---|---|---|---|
| A (asleep) | 4.0879 → 4.0592 V | **−22.62 mV/h** | 0.9938 | 94.0 mA |
| B (awake control) | 4.0308 → 3.9634 V | −50.86 mV/h | 0.9973 | 97.3 mA |

Both fits are the best this instrument has produced.

**Compare phase-A slopes directly, per the rule the XO A/B paid for:**

| leg | cut | phase-A slope | window |
|---|---|---|---|
| `xo-on-20260818` | — | −35.29 mV/h | 4.074 → 4.028 V |
| `xo-off-20260818` | — | −35.44 mV/h | 4.056 → 4.007 V |
| **`nomodem-20260819`** | **modem stack** | **−22.62 mV/h** | 4.088 → 4.059 V |

**The sleeping discharge rate fell by 36 %.** And the direction is conservative:
today's window sits 30-50 mV *higher*, where the OCV curve is steeper and the
same current would produce a *faster* voltage fall. The effect is real or
understated, not inflated by the window.

Converted to current it is 43-55 mA asleep against 68-86 mA for the two legs of
2026-08-18, depending on which leg's awake control is used to calibrate - call
it **25-30 mA saved asleep**, and do not quote a third digit.

☠️ **The awake control is 97.3 mA and the figure this instrument has always
reproduced is ~155 mA.** By the rule written on the fitter itself, that is where
you stop and ask why. The answer is consistent rather than alarming: `freq-probe`
measured the modem cut as worth ~2 mA at the *floor* but ~23 mA at the *median*,
i.e. the modem stack's cost is bursts, not baseline - and a discharge slope
integrates bursts. The awake slope fell 23 % (−66.15 → −50.86 mV/h) in the same
leg, which is the same story from the other instrument. It still means **this
leg's derived mA cannot be compared with yesterday's derived mA**; only the
slopes can.

☠️ **This needs a same-day control before it is a result.** Every comparison
above is against legs from a different day. The one experiment that settles it
is `slope-leg.sh` with no cut, run next, on this pack and this boot sequence.
Until then the honest claim is: *a leg with the modem stack cut discharged 36 %
more slowly asleep than two legs without it, taken the day before.*

### ☠️ The vlow vote mask is live, and a before/after reading of it proves nothing

`qcom_stats/vlow` carries a `Client Votes` field. Read before the leg it was
`0x17131715`; read after, with the modem stopped, `0x15111511` - which looked
like the modem's bits clearing, and would have been a genuine instrument on the
structural gate.

It is not. Re-read three times over thirty seconds with every service running
again, it gave `0x15111511`, then `0x13171511`, then `0x17131713`. **The mask is
an instantaneous sample and it fluctuates on its own.** A single before/after
pair of it means nothing; using it at all would need repeated sampling at
suspend entry.

`Count` remains **0** in both, as in every capture ever taken on this device.
The gate did not open, even in the leg that saved 25-30 mA.

### ★ RESUME POINT, 2026-08-19 04:15

**Running on the device:** `slope.service` -
`slope-leg.sh nomodem-20260819 ModemManager rmtfs tqftpserv`, started 04:10 from
a full pack (100 %, 4.329 V). Descent, 1800 s settle, 6x900 s asleep, 6x900 s
awake control. Ends about **08:15**. A host poller checks every 4 minutes and
exits when the unit does.

☠️ **Nothing else may touch the device until it finishes** - no `apk`, no
`episode-watch.sh`, no CPU-heavy anything. Phase A is measuring suspends; a
wakeup a minute would be measuring the instrument.

**Why the modem cut.** Awake it is worth 2 mA (`freq-probe`), so any difference
asleep is attributable to the *sleep-vote* path rather than to awake load - and
MPSS is one of the masters whose vote the RPM waits on. Every other candidate
the ladder tested came back zero.

Baseline for it, captured 04:08: `qcom_stats/vlow` **Count 0**,
`Client Votes: 0x17131715`. As it has been in every capture ever taken here.

**Order for what remains** (the user reversed it; the install still has to
precede the legs that need it):

| # | what | how long |
|---|---|---|
| 1 | *(running)* deep-sleep slope leg | → 08:15 |
| 2 | redo ladder stage S5 - "wifi costs 0.6 mA" was measured inside the anomaly and is void | ~25 min |
| 3 | Sxmo install: `apk add --simulate` first, read for `Purging`, then boot-fallback check | ~30 min |
| 4 | four `de-compare.sh` legs, one boot each | ~2 h 45 |

**New and not yet deployed:** `episode-watch.sh`. On 2026-08-18 the idle floor
doubled for ~44 minutes, silenced the PLL storm entirely, and cleared on its
own; the ladder mis-attributed it and the controlled probe exonerated the cut,
leaving it unexplained with nothing watching for it. This samples current
(median of nine reads), cpufreq residency, transition counts and the PLL failure
count once a minute to tmpfs, bounded to 48 h. Deploy it **after** the slope
leg, and never during one.

### Superseded - the A leg, started 2026-08-18 08:5x

`leg3` is a transient systemd unit on the device. To see where it is:

```sh
ssh fp3@172.16.42.1 'sudo systemctl is-active leg3'
ssh fp3@172.16.42.1 'sudo tail -20 /var/log/leg3-20260818.txt'   # descent
ssh fp3@172.16.42.1 'cat /home/fp3/suspend-slope.txt'            # the leg itself
```

When it finishes, fit it and compare against the reference:

```sh
scp fp3@172.16.42.1:/home/fp3/suspend-slope.txt docs/power/2026-08-18_pmos_xo-on-leg.txt
python3 docs/power/slope-fit.py docs/power/2026-08-18_pmos_xo-on-leg.txt
python3 docs/power/slope-fit.py docs/power/2026-08-17_pmos_post-pll-slope-leg.txt   # 60.1 mA
```

☠️ **Read phase B first.** If its directly-measured awake current is not the
figure already known (~155 mA), the ratio means nothing and the leg is void -
that check is what withdrew the leg of 2026-08-17.

☠️ **Read the settle rows before trusting phase A.** The descent runs eight busy
cores, which took the pack from 29.4 °C to about 38 °C, and a cooling pack reads
a falling voltage that has nothing to do with charge leaving it. `SETTLE_OFF` is
1800 s for this leg specifically to burn that off; the settle rows are what say
whether it was enough.

**Then the control leg**, which is the whole point. The script for it exists:
`docs/power/bringup/tools/leg3-control.sh`, installed as `/root/leg3-control.sh` - `leg3.sh`
with the guard inverted, the tag `xo-off-20260818`, the log
`/var/log/leg3c-20260818.txt`, and two guards the A leg did not need (see
below). Neither number means anything alone.

Full sequence, in order, and none of the steps is optional:

```sh
# 1. Charge back up. The A leg started its descent at 4.266 V and ended the
#    run near 3.9 V; leg3-control.sh refuses to start below START_MIN=4.200 V
#    because a control that begins on a half-empty pack sits on a different
#    part of the discharge curve, which is exactly what withdrew 2026-08-17.
ssh fp3@192.168.100.17 'cat /sys/class/power_supply/pmi632-battery/voltage_now'

# 2. ☠️ Check the charger is actually taking. suspend-slope.sh suspends USBIN
#    and the bit lives in the PMIC across a warm reboot.
ssh fp3@192.168.100.17 'cat /sys/class/power_supply/pmi632-charger/online'
# if 0:  echo Charging > /sys/class/power_supply/pmi632-charger/status

# 3. Switch the boot label back and reboot. This is also the step that undoes
#    the experiment-as-resting-state, so it has to happen anyway.
sudo sed -i 's/^default .*/default postmarketOS/' /boot/extlinux/extlinux.conf
sudo reboot                       # allow ~5 min; r60/r61 have both been slow

# 4. Confirm the fact, not the label.
cat /sys/module/clk_smd_rpm/parameters/xo_sleep_off        # must read N
cat /proc/cmdline                                          # no xo_sleep_off=1
sudo modprobe rpm_master_stats     # nothing autoloads it

# 5. Run it as a transient unit. ☠️ A foreground ssh command dies with the
#    session; that is how the xo-unbind probe left the modem unbound.
sudo systemd-run --unit=leg3c --collect /root/leg3-control.sh
sudo systemd-run --unit=emmc-watch --collect /root/emmc-watch.sh
```

The script moves `/home/fp3/suspend-slope.txt` aside by itself this time
(`.pre-xo-off-20260818`), because that file is append-only across runs and
still holds the A leg's samples. Read phase B first, then the settle rows,
then compare - the same order as for the A leg.

☠️ `/home/fp3/suspend-slope.txt` is append-only across runs and the aborted
first attempt wrote settle rows under the same tag. It was moved to
`suspend-slope.pre-xo-leg.txt` before this leg started; `leg3-control.sh` now
does that move itself rather than trusting anyone to remember it.

**Boot state right now:** `default postmarketOS-xo`, which is r61 plus
`clk_smd_rpm.xo_sleep_off=1`. The plain `postmarketOS` label is the same kernel
without it, and `postmarketOS-fallback` is r60. Put the default back to
`postmarketOS` when the A/B is done - the experiment must not become the
resting state.

### What the leg is, started 2026-08-18 09:00

`leg3.sh` on the device, as a transient unit: ride the pack from 4.379 V down to
4.030 V - the flat part of the curve, which is what withdrew the leg of
2026-08-17 - then hand over to `suspend-slope.sh xo-on-20260818 900 6`. Six
15-minute sleeps and six awake controls, roughly five hours end to end with the
discharge.

☠️ It refuses to start unless `/sys/module/clk_smd_rpm/parameters/xo_sleep_off`
reads `Y`. A leg that cannot say which side of an A/B it measured is worth
nothing, and the tag in the sample lines is a promise while the parameter is the
fact.

The control leg is the same script from the plain `postmarketOS` boot label,
which has to be run before the two can be compared. Neither number means
anything alone.

After this leg the phone sits at the greeter, because `suspend-slope.sh` stops
`greetd` and restarting it does not restart the session - reboot before reading
`03-autologin`.

**Order of work from here:**

1. ~~Dry-run the fixed instrument~~ — **done 2026-08-18, passed.**
2. eMMC soak running. AP collapse alone is excluded; the open question is
   whether a *long* collapse does it. If it recurs, the separation is cheap:
   restore the vMPM deadline cap alone and the AP still collapses, just never
   for long.
3. The next slope leg.
4. The XO vote above, which now looks like a bigger lever than the LDOs: the
   RPM cannot enter `vlow` at all while any sleep-set XO vote stands, and no
   amount of regulator work changes that.

☠️ **Do not mirror the active vote into the sleep set and expect anything.**
The RPM already treats a missing sleep-set request as "use the active one at all
times", so writing the same numbers into both sets is a no-op by construction.
What is needed is a sleep vote that is *lower* than the active one, which in
mainline terms means `regulator-state-mem` subnodes and `set_suspend_*` ops in
`qcom_smd-regulator.c` - a design, not a one-liner.

### The LDO layer, read against the vendor source - 2026-08-18, offline

The tracepoint run said the LDOs are the only RPM clients that never vote for
sleep (14 active / 0 sleep). The source says why, and the vendor tree on disk
says what the missing mechanism looks like.

**Mainline sends no sleep-set request for any regulator, ever.**
`drivers/regulator/qcom_smd-regulator.c` contains exactly one
`qcom_rpm_smd_write()`, in `rpm_reg_write_active()`, and it is hard-coded to
`QCOM_SMD_RPM_ACTIVE_STATE`. There is no sleep path to be missing a case in;
the concept is absent from the driver.

**The vendor expresses it in the binding.** In
`hadk22/kernel/fairphone/sdm632/drivers/regulator/rpm-smd-regulator.c`,
`qcom,set` is a *mandatory* per-node bitmask - `BIT(0)` active, `BIT(1)` sleep -
and probe fails without it. The driver creates two RPM handles
(`handle_active`, `handle_sleep`) and aggregates the two sets separately.

**And the FP3's own DT uses all three values.** From
`arch/arm64/boot/dts/qcom/msm8953-regulator.dtsi`:

| node | `qcom,set` | meaning |
|---|---|---|
| `pm8953_s2_level`, `pm8953_s7_level` | 3 | both sets |
| `pm8953_s2_level_ao`, `pm8953_s7_level_ao`, `pm8953_l7_ao` | 1 | active only |
| `pm8953_s7_level_so` | 2 | **sleep only** |

That is the same shape `clk-smd-rpm` uses for clocks, where every RPM clock has
a plain node and an `_a` `active_only` peer. One physical rail, up to three
regulator nodes, and the consumer picks its set by picking the node. Mainline
collapses that to one node per rail which is, in write terms, permanently
active-only.

☠️ **Do not build the obvious change.** Mirroring the active request into the
sleep set is a no-op by construction: a resource with no sleep-set request has
its active request used at all times, so an explicit mirror produces the same
aggregate. That is the same reasoning that made the XO experiment worth
building only because it wrote a *lower* sleep value, not an equal one.

The informative change is an explicit sleep-set request with `swen=0` for rails
nothing needs in suspend - and it is not blanket-safe, because
`regulator-always-on` rails and anything the modem or memory needs across
suspend must keep their vote. So the next step is data, not code: **the list of
the 14 rails still holding an active vote at suspend entry**, which the
`qcom_rpm_smd_write` tracepoint already collects. Take it after the A/B legs;
the device is committed until then.

### The A leg landed: 74.4 mA with the sleep-set XO vote zeroed

`docs/power/bringup/captures/2026-08-18_pmos_xo-on-leg.txt`, r61 booted from the
`postmarketOS-xo` label (`clk_smd_rpm.xo_sleep_off=1`), `leg3.sh` from
4.266 V down to 4.018 V under load, 1800 s settle, then six 900 s sleeps and
six awake windows. All six suspends completed (`slept=901s of 900s`), the
script exited rc=0 and restored the charger.

```
phase A  4.0739 -> 4.0279 V   slope -35.29 mV/h   r2=0.9938   I mean 137.6 mA
phase B  3.9937 -> 3.9025 V   slope -71.20 mV/h   r2=0.9922   I mean 150.1 mA
RESULT   asleep 74.4 mA   (= 150.1 x 0.496)
```

**The control passes.** Phase B's directly-measured awake current is 150.1 mA
against the 155.3 mA this instrument has returned before, so the method is
intact and the awake regime is unchanged. Two early phase-B windows read 101
and 126 mA and briefly looked like the awake baseline had moved; they were
settling, and the six-window mean is what counts. A partial phase is not a
phase.

☠️ **Do not compare this to the reference leg's 60.1 mA.** That was a different
day, a lower state of charge and an earlier kernel. And within this leg the two
phases do not share a region: phase A sits at 4.03-4.07 V, above the plateau,
while phase B is at 3.90-3.99 V inside it. That is the same systematic that
withdrew 2026-08-17, much milder here but pointing the same way - it inflates
phase A's mV/h and therefore the computed sleep current, so 74.4 mA is an upper
bound rather than a figure.

**Which is exactly why the number that matters is the difference.**
`leg3-control.sh` rides down to the same 4.030 V target from the same 99%
start, so its two phases land in the same two regions and the systematic
cancels in the A-vs-control comparison even though it does not cancel inside
either leg.

## 2026-08-22 — the PLL enable-failure fix landed (v2), measured clean

`apcs-cpu0/cpu4-pll failed to enable!` (35 warnings in a 94-minute r64 window;
~18 per 10000 frequency transitions): sugov reprograms a cluster's PLL from the
other cluster, and if the owner power-collapses mid-latch the SPM gates the PLL
and the lock poll times out. Fix on all three fork layers
(`wip/7.1.3/power` a05596e933a5 / `integration/7.1.3` 43711fd59d49 /
`debug-int/7.1.3` c5a18f94965e): a clk-notifier holds a **global
cpu_latency_qos** request at 0 (WFI only) across PRE→POST_RATE_CHANGE plus an
`smp_call_function_any()` kick.

☠️ **The first version used per-CPU dev_pm_qos and deadlocked on every boot** —
sysrq-w caught the ABBA live: the notifier held `clk_prepare_lock` and wanted
the CPU device's dev_pm_qos mutex, while the msm GPU devfreq's min_freq QoS
notifier held that mutex and called back into `clk_set_rate`. Every clk op
(sdhci runtime PM included) queued behind it and the wedge looked like storage
death. Evidence: `/mnt/1TB/Fp3-Sailfish/pll-deadlock-20260822/`; the v1 tips
are kept as `archive/pll-v1-deadlock-*`. cpu_latency_qos has no notifier chain
(kernel/power/qos.c) — spinlock only — so it is safe under clk_prepare_lock.

Validation on r65 (#66-fp3), power collapse enabled throughout:

```
30 min bursty load, both clusters (pll-v2-meas.sh):
  27720 freq transitions (7965 c0 + 19755 c4), 24916 power-collapse entries
  PLL enable failures: 0        (baseline predicts ~50 for this window)
plus a 37-min idle window earlier the same boot: 0 failures (r64 idle: ~14)
```

cpuidle sanity: state1 usage kept climbing during and after the run — the QoS
request does not stick outside the rate-change window.

## 2026-08-24 — night slope-legs were gated on the boot label; gate now fixed

Ran `night/preflight.sh` on r73 to decide the sanctioned alternative (a clean
r73 s2idle baseline). **Result: FAILED on exactly one gate —**
`boot-default: default label is 'postmarketOS-prev', expected postmarketOS`.
Every other gate passes (root-rw, space, tmpfs, boot-fallback, charger, battery
100 %, no-stale-units, **rpm-stats** [now persistent via modules-load.d],
counters-live APSS+331/MPSS+54/PRONTO+198 in 20 s, mem-sleep s2idle, dpms
writable, mmc-clean). So the instruments and the pack are ready; the only blocker
is the label.

The r74 recovery deliberately left `default postmarketOS-prev` (clean r73), and
there is no plain `postmarketOS` label any more. Reconciling that is a
**boot-config change** — repeats every boot, no console — and is exactly the kind
of edit that bricked r74, so it is **not** an unattended-night task. Two clean
options for when the user is awake: rename the default back to `postmarketOS`, or
teach `preflight.sh` to accept `postmarketOS-prev`. Until then the guarded night
queue correctly refuses to arm, and no battery-draining leg was started.

☠️ Note the reframe from the same night makes an r73 absolute-power re-baseline
lower-stakes than it looks: `vlow`=0 turned out uncorroborated by any per-master
deficit (pmOS co-processors sleep like the oracle's), so the deep-sleep question
is not blocked on getting this leg — the real figure of merit is the mA baseline
already held (~79–83 mA, r64).

**Resolved the same day (took the second option).** Rather than a boot-config
edit — the class of change that bricked r74 — I taught `preflight.sh` what the
gate was really for. The old check string-matched `default = postmarketOS` and,
tellingly, **never verified the default's kernel file existed at all** — only its
name. The new `boot-default` gate resolves the default label's `kernel`/`fdt`
lines out of `extlinux.conf` and requires (a) the kernel be a **frozen, named
snapshot** (`vmlinuz-<tag>`), never the bare live `vmlinuz` symlink whose
contents are whatever was installed last and may not boot — that is precisely the
`postmarketOS-sleepset` → r74 trap — and (b) that both files exist non-empty.
Version-free, and stronger than the name it replaced.

Proven on all five branches against the real label layout before deploy: `-prev`
and `-bothsets` PASS (frozen `vmlinuz-r73`), `-fallback` PASS, `-sleepset` FAIL
(live symlink) **even when its files exist and are non-empty** — the guard is the
unproven-kernel identity, not mere file absence — and a nonexistent default FAILs
on the missing kernel line. Then run live on r73: **`PREFLIGHT OK — the night may
be armed`**, `boot-default` now reading `default 'postmarketOS-prev' -> frozen
vmlinuz-r73 (+ dtb-r73), both present`. The queue can arm on the next unattended
night with the cable out; nothing was armed now (cable in, operator present).

## 2026-08-24 night — `vlow` CLOSED (the target never occurs on this platform); the runbook's open thread is the MODEM LEAD

The deep-sleep item this runbook has orbited for three weeks is closed: the
RPM's own `vlow`/`vmin` records, read raw from message RAM on **both** slots
with `tools/rpmstats_raw.py`, are 0 on the working UT oracle too — across a
10-min window in which the oracle demonstrably slept at full depth. Definitive
account + scope caveat: findings-log 2026-08-24 "(continued)" and the caveat
entry after it. Do not start another `vlow` measurement; the counter is not a
figure of merit on this device.

**The figure of merit is the mA baseline** (asleep 79–83 mA; modem-off 43 mA),
and the open thread is the modem's ~36 mA. Protocol, in order (detail in
TODO "Deep sleep — CLOSED" section):

1. ✅ `modem-xo-duty` — MPSS XO duty across genuine s2idle, radio normal vs
   `mmcli --set-power-state-low`. Cable-in, ~10 min, no discharge. **Done
   2026-08-24: radio up = every suspend aborts early (11 s / 47 s of 90) with
   the MPSS chopping the crystal ~2.5 transitions/s; radio low = full-term
   suspends with MPSS XO off essentially the whole window.** Capture:
   `captures/2026-08-24_modem-xo-duty.txt`.
2. Night slope-legs, uncontaminated (☠️ remember `rmtfs -P` = modem shutdown):
   radio-low whole-leg, then true modem-off via remoteproc stop.
   **(a) radio-low ARMED and running 2026-08-24 ~14:55** (`radiolow-20260824`,
   `night/radio-low-leg.sh` + `jobs-radiolow.txt`, preflight `nocable` mode,
   probe gate passed: wall 92 s of 90, MPSS XO off 87.6 s); (b) remoteproc-stop
   leg still to come.
3. Mechanism readout on whichever leg saves: MPSS XO duration + shutdown count
   across the sleeps.

---

## ★★★★★ 2026-08-25 — the idle gap named: our own PLL guard was the biggest waker on the phone

The matched pair (entry above) said the gap to the oracle is **wakeups, not a
continuous load**. This entry names the wakers. Every number here was taken on
pmOS r75, panel proven off (`bl_power = 4`, DRM CRTC `enable=0 active=0`,
`dpms=Off`), WiFi up, radio up, one ssh session, `top` reporting 96 % idle.

### ☠️ First, a correction to the entry above

The IRQ evidence quoted there — `IPI1 1927/s`, `arch_timer 1037/s`,
`msm_mdss 79/s with the display off` — was **taken with the display on**. Redone
with the CRTC proven off:

```
arch_timer                   54.3/s
Rescheduling interrupts     151.1/s
Function call interrupts    119.9/s
msm_mdss, dsi_isr             0     (they do not appear at all)
```

The display pipeline **does** shut down properly; the `msm_mdss` lead was a
measurement artifact of my own making. What survived the correction is the IPI
traffic, and that turned out to be the real finding.

☠️ The lesson is the one this log keeps re-learning: *a rate is only a fact
together with the state it was sampled in.* Record the state in the same
command that records the rate.

### The AP is not the problem — it is being woken

`cpu-power-collapse` residency over an 11 063 s uptime: **10 860 s = 98.2 %**,
with no process consuming CPU. The cores do reach the deepest state they have.
But cpu0 alone entered it **691 180 times = 62/s**. It is not residency that is
missing, it is the *entry/exit cost*, paid hundreds of times a second.

### The waker: our own `clk: qcom: apcs-msm8953` PLL guard

`ipi_send_cpu` tracepoint, 10 s, idle:

| callsite | count / 10 s | rate |
|---|---:|---:|
| `wake_up_if_idle+0xf0` | 1283 | **128/s** |
| `ttwu_queue_wakelist+0x10c` | 978 | 98/s |
| `irq_work_queue+0x50` | 188 | 19/s |
| `generic_exec_single+0x58` | 172 | 17/s |

`wake_up_if_idle` is the `wake_up_all_idle_cpus()` path, which
`cpu_latency_qos_apply()` calls on **every change of the aggregate**. Confirmed
directly with the `pm_qos_update_request` tracepoint:

```
pm_qos_update_request   458 / 10 s   (229x value=0, 229x value=-1)  -> 45.8/s
cpu_frequency           916 / 10 s   -> 22.9 transitions/s
```

Perfectly balanced hold/release pairs, one pair per frequency transition. The
source is `apcs_hold_cluster()`, added 2026-08-22 to stop the CPU PLLs failing
to relock when the owning cluster power-collapses mid-latch. It took a **global**
`cpu_latency_qos` request — so a guard meant to protect a few microseconds of
PLL relock on one cluster was:

* **the largest single source of wakeups on the phone**, two thirds of all IPI
  traffic, poking all eight CPUs 46 times a second; and
* barring **both** clusters from power collapse for the duration of each hold.

☠️ The mechanism was right and the measurement behind it (18 failures per 10 000
transitions, gated entirely by power collapse) still stands. What was wrong was
the *scope* of the instrument used to apply it. A global constraint used to
express a local requirement is a bug even when it works.

**Fix:** `clk: qcom: apcs-msm8953: hold only the retuned cluster out of idle` —
disable everything deeper than WFI in the owning cluster's cpuidle devices
instead. That flag is read by `cpuidle_select()` on the CPU itself, so it costs
no IPI and constrains no other CPU. `cpu_latency_qos` is kept only as a fallback
for the window before cpuidle registers, and the path taken at PRE is recorded so
the same one is undone at POST. Lock order `clk_prepare_lock -> cpuidle_lock`
closes no cycle (unlike the per-CPU `dev_pm_qos` version, which deadlocked).

### The second waker: a diagnostic harness nobody removed

`sched_wakeup`, 10 s: **1951 wakeups**, of which the top woken tasks were
`sugov:4` (331) and `sugov:0` (297) — the cpufreq churn above — and then
`spkwatch` (96) with its `sh`/`tr`/`sed`/`cat` children.

`spkwatch` is the 1 Hz shell sampler written during the speaker-amp
investigation. Its cost, read off systemd:

```
spkwatch      365.75 s of CPU over 14 024 s of uptime  = 2.6 % of a core, permanently
fp3-powerlog   22.37 s
ringwatch       1.82 s
```

**2.6 % of a core, forever, for a question that was answered in August.** It also
did an i2c transfer every second, which is why `gcc_blsp2_qup2_i2c_apps_clk` was
among the enabled clocks at idle.

Disabled (`disable --now`): `spkwatch`, `ringwatch`, `fp3-powerlog`, plus
`avahi-daemon` and `cups`, which serve nothing on this phone and which the
oracle does not run either — so they were also an unfairness in the matched pair.

Immediately, with no kernel change yet:

| | before | after | |
|---|---:|---:|---|
| `sched_wakeup` / 10 s | 1951 | **1172** | −40 % |
| `cpu_frequency` / 10 s | 916 | **440** | −52 % |

The cpufreq halving is the interesting one: fewer task wakeups means fewer
utilisation updates means fewer transitions — so the two fixes compound rather
than overlap.

☠️ **Process lesson.** Both of these were *ours*. The instrument left running
after the experiment, and the guard whose blast radius nobody measured. Neither
would have been found by looking harder at Qualcomm's code. Before hunting a
platform for a power gap, subtract what the port itself is doing to it.

### What is NOT the problem (ruled out here)

* **Display** — CRTC off, DSI runtime-suspended, no MDSS interrupts. Four
  housekeeping clocks stay enabled (`gcc_mdss_axi/ahb` at rate 0,
  `vsync_clk_src`/`gcc_mdss_vsync_clk` at 19.2 MHz); low value, left alone.
* **schedutil rate limiting** — `transition_latency` is 1 ms so the rate limit is
  ~10 ms, allowing 100 transitions/s; the measured 22.9/s was never near it. The
  transitions are real demand, not a governor artifact.
* **Sleep inhibitors** — all eight are `delay` mode; the two `block` ones only
  claim the power key. Nothing was blocking suspend.
* **journald** — the journal did not grow at all over 20 s at idle.
* **The RPM sleep-set layer** (`wip/7.1.3/power`) — already written, already on
  the running kernel, and it does **not** apply here: `on-in-suspend` and
  `both_sets` only make the sleep vote *exist* at the active value. A saving
  needs `off-in-suspend` / a lower suspend voltage on genuinely-unused rails,
  which is separate work.

## ★★★★★ 2026-08-25 (continued) — the aggregate: the wakeup problem is SOLVED, the floor is what is left

r76 (`#77-fp3`, `debug-int/7.1.3` `5aafd59e`) carrying the cluster-local idle
hold, with the diagnostic harness disabled and `sleep-inhibitor` slowed from
10 Hz to 30 s. One `idle-ab` hour, same protocol as the matched pair: panel
proven off (`bl_power=4`, waited 0 s — `loginctl lock-session` now does it),
compositor up, WiFi up, radio up, one ssh session, on battery, all four
experiment knobs default-off.

| | floor (p10) | median | mean | ΔV over 3600 s |
|---|---:|---:|---:|---:|
| pmOS r73 run 1 | 53.9 | 157.3 | 146.2 | 139 mV |
| pmOS r73 run 2 | 54.3 | 148.0 | 141.3 | 132 mV |
| **pmOS r76** | **52.9** | **98.3** | **114.7** | **99 mV** |
| UT 4.9 (oracle) | 15.3 | 30.1 | 32.2 (coulomb) | 43 mV |

**The median fell 35 %, from ~152 to 98.3 mA. The floor did not move at all**
(53.9 / 54.3 → 52.9). That is exactly the predicted shape: both fixes removed
*wakeups*, and neither touched anything that draws current continuously. A
result that had moved the floor would have meant we did not understand what we
changed.

☠️ The voltage drop is **consistent but not independent evidence** here: the r76
leg started at 4.294 V against 4.224 / 4.170, i.e. on a pack still relaxing from
a full charge, which moves the voltage for reasons of its own. Flagged before the
run started, not after seeing the number.

### The number that says the job is done

Median ÷ floor is the burstiness of the load — how much the phone costs above
what it costs to just sit there:

| | median / floor |
|---|---:|
| pmOS r73 | **2.75x** |
| pmOS r76 | **1.86x** |
| UT oracle | **1.97x** |

**pmOS now bursts less than the oracle does.** The entry above identified the gap
as "wakeups, not a continuous load"; that half of the gap is closed, and what is
left is a pure level difference: 52.9 mA against 15.3 mA of floor.

### What this reorders, again

The remaining gap is **~38 mA of continuous draw**, and none of the instruments
used today can see it — tracepoints count events, and this is not an event. The
next pass needs a different class of instrument: what is powered that need not
be. The leads already on record, in the order their evidence justifies:

1. **Rails — WEAKER THAN FIRST WRITTEN, see the correction below.** Ten
   regulators carry a non-zero enable count at idle: `s3` 984 mV, `s4` 1036 mV,
   `s5` 795 mV, `l3` 925 mV, `l5` 1800 mV, `l7` 1800 mV, `l8` 2900 mV, `l13`
   3125 mV, the `vph_pwr` input, and `lcdb_dummy` (a fabricated regulator, so it
   draws nothing). That is close to a minimal set, and it makes a large rail
   saving unlikely. Still worth one diff against slot a — the oracle answers it
   without a build, the same move that settled the charger's `I_TERM` question
   in twenty minutes on 2026-08-12 — but it is no longer the leading candidate.

   ☠️ **The "66 regulators enabled" figure published earlier in this entry was
   mine and it was wrong.** It came from `awk '$3>0'` over
   `regulator_summary` without reading the header: the columns are
   `use open bypass opmode voltage current min max`, so that counted the `open`
   column — consumers that called `regulator_get`, not rails that are powered.
   The same mistake nearly cost a second lead: the camera rails (`cam_af_2p85`,
   `cam_io_1p8`, `cam2_dig_1p2`) show `open` counts and read as "the focus motor
   is powered at idle", which would have been alarming given the 2026-08-08
   AF-rail bug. Their `use` is 0 and camss is runtime-suspended. **Read the
   header before the data.**
2. **The modem.** Priced at ~36 mA asleep (2026-08-24) and untested at idle.
   `mmcli --set-power-state-low` is a mechanism, not a fix; the open question is
   whether PSM/eDRX reproduces it while staying registered.
3. **Clocks.** 37 enabled at idle with the panel dark, including the debug UART
   at 3.6864 MHz (`console=ttyMSM0,115200` is on the cmdline and there is no
   serial port on this phone to read it).

☠️ Do **not** start with a kernel patch this time. Every hypothesis above is a
question about what the hardware is doing, and the oracle can answer all three
without a build.

---

## ★★★ 2026-08-25 afternoon — the oracle census: two leads dead, one born, and the oracle's own idle number is now in doubt

Three questions were queued against slot a, to be answered without a build. All
three were asked. What came back was not what the queue predicted, and the last
of them put the *premise* of the whole comparison in question.

### The switch, and a tool that does not work here

`qbootctl -s 0` cannot set the slot on this phone: it looks for
`/dev/bsg/ufs-bsg0` and this is eMMC, and the `-i` flag its own help advertises
("still write the GPT headers even if the UFS bLun can't be changed") is not in
its option string, so passing it prints the help. The documented route is the
one that works — `fastboot set_active a` from the host, after
`systemctl reboot --reboot-argument=bootloader`.

☠️ And the reboot has to be started with `systemd-run`: a `sudo sh -c "(sleep 1;
reboot bootloader) &"` did nothing at all and the phone was still up 90 seconds
later with the same uptime — the same trap the runbook already records for
long-running captures, in a place nobody thought to look for it.

### 1. The debug UART is not the difference — DEAD

Ubuntu Touch runs `gcc_blsp1_uart1_apps_clk` at the same **3 686 400 Hz** and
carries `console=ttyMSM0,115200,n8` **plus** `earlycon=msm_serial_dm,0x78af000`
on its cmdline, and idles where it does anyway. The clock census came out the
opposite way from the guess as well: **43 enabled clocks on the oracle against
37 on ours**. The oracle runs *more* clocks, not fewer.

Two other cmdline differences are worth recording, neither yet priced:
`lpm_levels.sleep_disabled=1`, and `trace_event=...regulator_enable,
regulator_disable trace_buf_size=64M` — the oracle ships with regulator tracing
compiled in and enabled.

### 2. The modem does not move the oracle's floor — ANSWERED

Four legs, 30 minutes each, `idle-ab.sh`, panel forced down, same protocol:

| leg | floor (p10) | median | mean | coulomb (`cc_soc`) |
|---|---:|---:|---:|---:|
| A — both modems on, `/ril_0` registered on LTE | 30.8 | 46.7 | 59.9 | 52.5 |
| B — both modems `Powered=0` | 31.1 | 55.5 | 72.2 | 68.5 |
| A′ — modems back, control | 31.1 | 58.4 | 76.5 | 72.7 |
| C — modems on, **no polling at all** | 31.1 | 50.0 | 64.3 | 54.4 |

**The floor does not move: 30.8 / 31.1 / 31.1 / 31.1 mA.** A modem sitting
registered on LTE contributes nothing to the oracle's continuous draw — and the
continuous draw is exactly what we are hunting on our side.

☠️ **There are two modems.** `list-modems` shows `/ril_0` and `/ril_1`, and
disabling only `ril_0` leaves `ril_1` powered. A "modem off" leg run that way
would have been half a modem, and its null result would have read as "the modem
does not matter". Also: the ofono scripts emit **NUL bytes**, so `grep` reports
"binary file matches" and swallows the output — `tr -d '\000'` and `grep -a`.

☠️☠️ **The B-vs-A difference in the median and the coulomb integral was me.**
The control leg A′ came out *higher* than the "expensive" modem-off leg, i.e.
the trend was monotonic across the session and had nothing to do with the radio:
52.5 → 68.5 → 72.7. `journalctl` on the phone counted **74 ssh logins in 70
minutes** — my own waiter loops, each one an ssh connection plus PAM plus sudo
plus polkit (`polkitd` 33.7 s and `dbus-daemon` 42.9 s of CPU during the run).
The clean leg C, with the phone untouched for the whole window, came back at
54.4. **My instrument was worth 18.3 mA**, and `idle-ab.sh`'s own header says in
as many words: *do not poll it over that session while it runs; every packet is
a wakeup, and on the UT side the wakeups ARE the phenomenon.* This is the
`spkwatch` lesson of the same morning, arriving from the host side instead of
the device side. The floor survived only because p10 samples the quiet gaps
between the pokes.

### 3. The rail diff — ranked last, and the only one that produced a lead

The `use>0` sets are mostly the same (`l3` 925 mV, `l5` 1800, `l7` 1800, `l8`
2900, `l13` 3125, `s5`). Two SMPS are enabled on ours with the panel dark and no
audio playing, and are **not in the oracle's enabled set at all**:

| rail | pmOS | UT | what the downstream DT hangs off it |
|---|---|---|---|
| `s3` | enabled, 984 mV | absent | `qcom,mipi-csi-vdd` (camera CSI) **and** `mdss_dsi` `vdda` |
| `s4` | enabled, 1036 mV | absent | `cdc-vdda-cp`, `cdc-vdd-pa` — the codec charge pump and PA |

Both are our own layers, mdss and audio. ☠️ The pmOS figures behind this are a
live read from the morning, not a saved capture; the matching capture is the
first thing to take on the way back, and until it exists this is a lead.

### ☠️☠️★ What broke the premise: the oracle has never been measured with its screen actually off

The oracle's panel **never blanks on its own**. `powerd`'s inactivity action is
not set to `display-off`, and it holds **no inhibitor at all** while staying lit
(`powerd-cli listsysrequests` prints three empty lists). It sat fully powered at
`brightness=37` for 25 minutes. Setting the policy by hand
(`powerd-cli settings inactivity display-off …`, rc=0) changed nothing either.
`com.canonical.Unity.Screen.setScreenPowerMode("off", r)` returns **`true`** for
two of its six reason codes — with the panel still powered.

Writing `4 > /sys/class/graphics/fb0/blank` does drop the MDSS clocks and the
backlight. But it is only half a blank, and two witnesses say so:

- the PMI632 **LCDB bias rails stay up**: `lcdb_ldo` (`use=5`) and `lcdb_ncp`
  (`use=1`), both at **5500 mV**, with the panel "off";
- `show_blank_event` **flips back to `panel_power_on = 1`** on its own within
  minutes — the compositor undoes the write.

☠️ And `show_blank_event` is itself not trustworthy as the sole witness: it read
`panel_power_on = 1` while **zero** MDSS clocks were enabled, which the display
block cannot be. It reports the last blank *event*, not the hardware. On this
kernel the unambiguous witness is the enabled-MDSS-clock count.

So a `press-power-key.py` was written (uinput, `KEY_POWER`, one 120 ms tap) to
produce a real screen-off the way the compositor will accept one. **It worked,
and the host `dmesg` is the proof** — the compositor reacted, `usb-moded`
switched the gadget off RNDIS, and the phone went silent on every path:

```
usb 1-5: USB disconnect, device number 52
rndis_host 1-5:1.0 fp3ut: unregister 'rndis_host' ... RNDIS device
usb 1-5: new high-speed USB device number 77 ... idProduct=0afe
usb-storage 1-5:1.0: USB Mass Storage device detected
```

WiFi went with it. The phone is up (the gadget is enumerated) and answers
nothing, which is what a **suspended** phone looks like.

**The consequence, and it is not small.** Every UT idle number this
investigation has ever quoted — the 15.3 mA floor of 2026-08-24 included — was
taken with the framebuffer blanked, the LCDB bias rails powered, and the
compositor free to undo the blank. The oracle has never been measured in the
state a phone is actually in with its screen off, and if a real screen-off
suspends it, then "UT idles at 15 mA *awake*" is a claim about a state that
does not exist. The 3.5× floor ratio rests on that number.

Also still unexplained: **today's oracle floor is 31.1 mA against yesterday's
15.3**, four legs agreeing tightly, minimum sample 30.2 against 14.3. The LCDB
bias rails are the obvious suspect and will not be named as the cause until
they have been measured off.

**Next, and the order matters:** a real screen-off leg on the oracle (needs one
power-key press to get the link back first), then the same one on ours, then the
`s3`/`s4` capture on the way back to slot b.

### ☠️☠️ CORRECTION, same evening: the phone had not suspended — it had been switched off, by me

The section above reads the loss of RNDIS and WiFi as "what a suspended phone
looks like". It was not. The user went to the phone and found it on the
**offline-charging screen** — a green battery icon at 100 %, the display of a
device that is powered down. `press-power-key.py`'s single 120 ms tap **shut
the phone off**, and it took a held hardware button to bring it back.

The cause is certain: nothing else happened in that second. The mechanism is
not proven. The most likely one is that the **release was never seen** — a
compositor may bind a freshly created uinput device only after the press has
gone by, and `UI_DEV_DESTROY` half a second later tears the device down with
the key still logically held. A held power key is a long press, and a long
press is a shutdown. The tool now releases twice and waits five seconds before
destroying the device, and it carries a ☠️ saying that fix is a hypothesis and
has not been validated.

**What this retracts.** "A real screen-off suspends the oracle, and therefore
every UT idle figure describes a state the phone is not in" — the second half
of that claim still stands on its own evidence (the LCDB rails at 5500 mV with
the panel "off", and `show_blank_event` flipping back to 1), but the *suspend*
half has no evidence at all now and is withdrawn. So is the reading of the
`dmesg` gadget switch: RNDIS going away and `Linux File-Stor Gadget` appearing
is what a phone that powered down onto a charger does, not a suspend.

**What is untouched**, because none of it depends on this: the modem does not
move the oracle's floor (30.8 / 31.1 / 31.1 / 31.1 mA), the debug UART is not
the difference, the `s3`/`s4` rail lead, and the 18.3 mA my own polling cost.

**Still open, and now with no instrument for it:** whether the oracle's panel
can be taken down *with the compositor's agreement*, and what the LCDB bias
rails are worth. Today's oracle floor of 31.1 mA against yesterday's 15.3 also
remains unexplained.

☠️ The shape of this mistake is the one this log keeps recording: an
observation ("the phone answers nothing") was read through the hypothesis that
was in hand ("a real screen-off suspends it") instead of being checked against
the cheapest alternative ("it is off"). One look at the phone settled it in a
second, and the phone was in the room.

## ☠️☠️ 2026-08-25 evening — the `s3`/`s4` lead is DEAD, killed by reading the dump correctly, and the rail census closes with "no difference"

The matched capture was taken on the way back to slot b, in both panel states
(`captures/2026-08-25_pmos-census-panel-{on,dark}.txt`). It does not confirm the
lead. It explains it away, and the explanation is another version of the
morning's mistake.

**`regulator_summary` is a TREE, not a list.** The indented rows under a rail
are not only its consumers — they are also its **child regulators**. Read that
way, with the panel dark:

```
    s3            1    7  ...   984mV        <- use = 1
       1b00020.camss-vdda   0                <- released
       1a94000.dsi-vdda     0                <- released
       l3            1    2  ...  925mV      <- CHILD, use = 1
          79000.phy-vdd     1                <- the USB QUSB2 PHY holds it
    s4            2    5  ...  1036mV        <- use = 2
       l5            3 ...                   <- CHILD: 7824900.mmc-vqmmc (eMMC I/O)
       l7            1 ...                   <- CHILD: 79000.phy-vdda-pll (USB PHY PLL)
```

So `s3` is not held by the camera or by the display — **both of its direct
consumers read 0**. It is up because its child `l3` is up, and `l3` is held by
the USB PHY. `s4` is up because `l5` (eMMC I/O!) and `l7` (USB PHY PLL) are its
children. Neither has anything to do with mdss or with the codec. The
`cdc-vdda-cp` / `cdc-vdd-pa` provenance came from the *downstream* device tree
and does not describe what holds these rails on our kernel.

The voltages agree with this reading: our `s3` sits at **984 mV, its declared
minimum** (`min 984 max 1240`), where the oracle raises it to **1225 mV** when
its display is up. A rail at its floor is a rail nobody is asking anything of.

**And with the tree read correctly the whole rail census closes as a
difference.** The leaf sets match: `l3`, `l5`, `l7`, `l8`, `l13`, `s5` on both.
The only rails the oracle has that we do not are `lcdb_ldo` / `lcdb_ncp` at
5500 mV — the display bias, which **it** keeps up and we do not. That is the
oracle spending more, not us.

☠️ **Same error, third time in one day, and it is worth naming precisely.**
"66 rails enabled" read the `open` column as `use`. The near-miss on the camera
rails read `open` as `use` again. This one read a tree as a list. All three are
the same failure: **acting on a dump's shape without reading what the shape
is.** The cost here was three documents published with a lead in them and a
slot switch spent to confirm it.

### Where that leaves the hunt

Everything the census was supposed to find is now excluded. The modem does not
move the oracle's floor, the debug UART is identical on both, the clocks are
*more* numerous on the oracle, and the rails match leaf for leaf. **~38 mA of
continuous draw remains, with no candidate.**

And the number the whole target rests on is itself unresolved: the oracle's
floor measured **31.1 mA** today across four legs (minimum sample 30.2) against
**15.3** on 2026-08-24 (minimum 14.3). Until that factor of two is explained,
"pmOS idles at 3.5× the oracle" is not a measurement, it is two measurements
that disagree. That, not another subsystem hypothesis, is the next thing to
settle.

## 2026-08-25 night — a plan built from the published PM playbook, and what the playbook forbids given our constraint

The census left the continuous draw with no candidate, so this is a deliberate
reset: instead of another hypothesis of our own, work the standard developer
playbook for idle power and see which of its instruments we have simply never
run. Sources are listed at the end of the section and cited inline.

### The constraint decides the plan before anything else

The requirement is **idle consumption as low as possible, incoming calls still
arriving, and a fast return to active**. That rules two of the biggest levers
in the cellular playbook out on correctness grounds, not on effort:

- ☠️ **PSM is unusable here.** In Power Saving Mode the UE closes the AS
  connection while keeping its NAS registration, and is **not reachable for
  paging** until the periodic TAU timer (T3412) brings it back; only during the
  Active Timer (T3324) window after that is it pageable [1][2][5]. A phone that
  cannot be paged does not ring. This retires the "PSM/eDRX reproduces the
  radio-low saving while staying registered" question left open on 2026-08-24
  in its PSM half.
- **eDRX is borderline and is not ours to set.** eDRX keeps paging but stretches
  the cycle, so a mobile-terminated call can be delayed by up to one cycle
  [3][4]. It is granted by the network, configured over AT/QMI, and only short
  cycles are compatible with "the phone rings promptly". It stays a maybe, not
  a plan.
- ★ **Fast wake is a per-device property, not a global one** — and the kernel's
  own PM QoS documentation says so: it recommends `dev_pm_qos_expose_latency_
  limit()` and the per-device `/sys/devices/.../power/pm_qos_resume_latency_us`
  **instead of** a system-wide constraint through `/dev/cpu_dma_latency` [6].
  That is exactly the correction this port shipped as r76 this morning, arrived
  at from a measurement rather than from the document. Worth recording that the
  two agree, and worth using the per-device knob deliberately for the modem
  rather than rediscovering the global one.

### What the playbook has that we have never run

1. **Wakeup-source accounting — the canonical instrument, and we have not used
   it once.** `/sys/kernel/debug/wakeup_sources`, or the stable-ABI
   `/sys/class/wakeup/<name>/`, carries `active_count`, `event_count`,
   `wakeup_count`, `expire_count`, `active_time`, `total_time`, `max_time`,
   `last_change` and **`prevent_suspend_time`** [7][8][9]. That last column is
   literally "who stopped the system going to sleep, and for how long", and the
   autosleep model — sleep whenever no wakeup source is held, wake on the modem
   — *is* the shape the requirement above describes [7].
2. **A runtime-PM audit against the documented failure list.** Every device
   whose `power/runtime_status` reads `active` at idle while `power/control` is
   `auto` is a candidate; the documented ways a device gets stuck are unbalanced
   `get`/`put`, a missing `pm_runtime_mark_last_busy()` under autosuspend, and a
   callback returning something other than `-EAGAIN`/`-EBUSY`, which latches an
   error state [10]. This is a mechanical sweep, not a hypothesis.
3. **cpuidle residency, differenced.** `/sys/devices/system/cpu/cpu*/cpuidle/
   state*/{name,time,usage}` over a window says where the idle time actually
   goes [11]. This is the one instrument that measures a **level** rather than
   an event, which is precisely what the census said we lacked: time parked in
   WFI instead of power collapse is continuous draw with no event signature.
4. ★ **A new, cheap, checkable difference: our rails are never told their
   load.** `regulator-allow-set-load` sets `REGULATOR_CHANGE_DRMS` so the core
   may call `set_load()`, and the RPM uses the load to choose HPM vs LPM/PFM
   [12][13]. `drivers/regulator/qcom_smd-regulator.c` **does** implement
   `rpm_reg_set_load()` (checked in our own tree, `.set_load` is wired into both
   `rpm_smps_ldo_ops` and `rpm_smps_ldo_ops_fixed`) — but **the FP3 device tree
   sets `regulator-allow-set-load` on no rail at all**, while
   `msm8953-xiaomi-common.dtsi`, `msm8953-motorola-potter.dts`,
   `msm8953-huawei-milan.dts`, `msm8953-lenovo-kuntao.dts` and
   `msm8953-flipkart-rimob.dts` in the same tree do. So our rails run in their
   default mode whatever the load.
   ☠️ **Honest magnitude: this is not 38 mA.** HPM→LPM on an LDO is worth tens
   to a few hundred µA, so across the five rails we actually have enabled this
   is plausibly 0.5–2 mA. It is on the list because it is nearly free and
   because it is a real difference from every other board, not because it can
   close the gap.
5. **ftrace wakeup attribution**, with the caveat the source itself gives:
   `power/wakeup_source_activate` fires *after* the system is already awake, so
   it names the holder and not the cause; the cause is in
   `irq/irq_handler_entry` and `timer/timer_start`, and both need filters or
   they drown the buffer [14].

### Tonight, in order

0. **(running) The headless floor.** `systemctl isolate multi-user.target` —
   greetd and phosh gone, 43 → 39 running units, ssh and both links intact.
   ☠️ The compositor's death turned the panel back **on** (`bl_power` 4 → 0),
   the 2026-08-19 trap exactly; blanked by hand and proven three ways
   (`bl_power=4`, `dpms=Off`, zero active CRTCs). Bounds what userspace above
   the kernel can possibly be worth. Prior from the 2026-08-18 ladder: ~0.
1. **The three censuses above at idle**, headless and with the GUI, saved as
   captures. Cheap, and none of them needs a build.
2. **An autosleep-shaped leg**: suspend with the modem armed as a wakeup source,
   measured over a long window with the existing night harness. ☠️ Not without
   that harness — the 2026-08-18 eMMC drop off the bus happened on the first
   night the system went genuinely deep, and the harness exists to catch its
   consequence.
3. **The `regulator-allow-set-load` A/B** only if 1–2 leave room. It needs a DT
   change and a build, so it goes on the **non-default** boot label, next to the
   `postmarketOS-headless` one added today.
4. **Morning, and it needs a human:** one incoming call, to prove the phone
   still rings. No amount of idle current is worth a phone that does not ring,
   and this cannot be self-tested.

### Sources

1. Rohde & Schwarz, *Power saving methods for LTE-M and NB-IoT devices* —
   https://scdn.rohde-schwarz.com/ur/pws/dl_downloads/premiumdownloads/premium_dl_brochures_and_datasheets/premium_dl_whitepaper/Power-saving-methods-for-LTE-M-and-NB-IoT-devices_wp_en_3609-3820-52_v0100.pdf
2. Nordic Semiconductor, *Power saving techniques* (nRF Connect SDK) —
   https://nrfconnectdocs.nordicsemi.com/ncs/3.0.2/nrf/protocols/lte/psm.html
3. Qoitech, *How to configure and evaluate eDRX for cellular IoT* —
   https://www.qoitech.com/blog/how-to-configure-and-evaluate-edrx-for-cellular-iot/
4. Onomondo, *eDRX and PSM for IoT* —
   https://onomondo.com/blog/edrx-and-psm-for-lte-low-power-iot/
5. Link Labs, *LTE eDRX and PSM explained* —
   https://www.link-labs.com/blog/lte-e-drx-psm-explained-for-lte-m1
6. Linux kernel, *PM Quality Of Service Interface* —
   https://docs.kernel.org/power/pm_qos_interface.html
7. Legato, *Manage Device Power* —
   https://docs.legato.io/15_10/how_to_power_mgmt.html
8. Ubuntu Wiki, *DebuggingKernelSuspend* —
   https://wiki.ubuntu.com/DebuggingKernelSuspend
9. LKML, *[PATCH v4] PM / wakeup: show wakeup sources stats in sysfs* —
   https://lkml.rescloud.iu.edu/1907.1/07435.html
10. Linux kernel, *Runtime Power Management Framework for I/O Devices* —
    https://docs.kernel.org/power/runtime_pm.html
11. CNX Software, *Idle CPU power management: cpuidle* —
    https://www.cnx-software.com/2026/04/20/idle-cpu-power-management-cpuidle/
12. Linux kernel DT binding, *regulator.yaml* —
    https://www.kernel.org/doc/Documentation/devicetree/bindings/regulator/regulator.yaml
13. LKML, *[RFT PATCH v2 2/2] regulator: core: Don't err if allow-set-load but
    no allowed-modes* — https://lkml.rescloud.iu.edu/2208.3/01028.html
14. ix5.org, *Android Kernel Suspend Debugging and Tracing* —
    https://sx.ix5.org/info/post/android-kernel-suspend-debugging-and-tracing/
15. Linux kernel, *System Sleep States* —
    https://docs.kernel.org/admin-guide/pm/sleep-states.html
16. postmarketOS pmaports MR !2187, *modemmanager: quick suspend/resume patches*
    — https://gitlab.com/postmarketOS/pmaports/-/merge_requests/2187

☠️ Two of the pages the search surfaced could not be read and nothing here
rests on them: the eLinux *Debugging Embedded Linux (Kernel) Power Management*
PDF and the ArchWiki *Power management/Wakeup triggers* page both returned an
Anubis access-denied interstitial rather than content.

## ★★★ 2026-08-25 evening — the search space collapses: six exclusions, no finding, and the ADSP priced at last

The night plan's first three items were run. None of them found the draw, and
that is the result: after today the ~38 mA has almost nowhere left to be on the
AP side, and two hypotheses that had stood for weeks are now priced and dead.

### Userspace above the kernel is worth ZERO — measured on the floor, not on a marginal

`systemctl isolate multi-user.target` on the running system: greetd and phosh
gone, 43 → 39 running units, both links intact. Same protocol, same untouched
window, panel proven dark three ways (`bl_power=4`, `dpms=Off`, zero active
CRTCs).

| | floor (p10) | median | mean |
|---|---:|---:|---:|
| r76, full GUI (today's aggregate) | **52.9** | 98.3 | 114.7 |
| r76, **headless** | **52.9** | 101.3 | 116.2 |

**Not one tenth of a milliamp.** This confirms the 2026-08-18 ladder, but from
the floor directly rather than from marginals, inside one boot, with the panel
proven down — which is exactly what that ladder could not claim.

☠️ Two traps in getting there, both of which would have inverted the answer:
the compositor's death turns the panel back **on** (`bl_power` 4 → 0), the
2026-08-19 trap again; and `idle-ab.sh`'s own EXIT trap un-blanks the panel, so
anything run immediately after a leg samples a lit screen. The first census run
was thrown away for exactly that and repeated.

### The CPUs are already as deep as this platform goes

cpuidle residency differenced over 60 s, headless, panel dark — the one
instrument in the playbook that measures a **level** rather than events, and
the one this investigation had never run:

```
cpu0  WFI 0.24s   cpu-power-collapse 59.50s
cpu1  WFI 0.79s   cpu-power-collapse 59.42s
...
cpu7  WFI 4.41s   cpu-power-collapse 55.53s
```

**All eight cores spend ~99 % of wall time in the deepest state the driver
offers.** "Parked in WFI, therefore drawing continuously" is dead. And the
wakeup-source table is clean: **no source has a non-zero `prevent_suspend_time`
or `active_since`** — nothing is holding the system awake.

### The always-on ADSP is NOT the draw — the 2026-08-19 finding is now priced

RPM master stats, differenced over 60 s, headless, panel dark, on r76:

| master | 60 s |
|---|---|
| APSS | **+920 shutdowns** — the r76 fix working, and cpuidle agrees |
| MPSS | +156 shutdowns, XO off 41.3 s of 60 |
| PRONTO | +540 shutdowns, XO off 44.6 s of 60 |
| TZ | no change |
| **LPASS** | **nothing at all — zero shutdowns, zero XO time** |

That reproduces 2026-08-19 on a much later kernel: the ADSP never sleeps, where
the oracle logged 4344 shutdowns. With everything else excluded it was the
obvious candidate, and a Hexagon that never sleeps is the right order of
magnitude. So it was measured, A-B-A, 30 minutes each, untouched:

| leg | floor (p10) | p25 | min sample | median |
|---|---:|---:|---:|---:|
| A — ADSP running | 52.9 | 53.9 | 51.4 | 101.3 |
| B — **ADSP stopped** (`remoteproc2` → offline) | **56.3** | 57.1 | 55.2 | 106.3 |
| A′ — ADSP restarted, control | 54.6 | 55.1 | 52.6 | 100.4 |

The A/A′ bracket is **52.9–54.6** and B sits **above both**. Stopping the ADSP
does not save; it costs about 2 mA. ⇒ **`lpass-never-sleeps` is a true fact
about the RPM handshake and is worth no current.** It stays interesting for the
`vlow` story it once explained, and it is off the power list.

☠️ Caveat kept: with the ADSP down the wcd9335 SLIMbus driver retried
continuously (`Failed to write config e4: -12`), so leg B may carry retry churn
rather than a clean ADSP-off state. The direction is not in doubt — there is no
saving here — but the +2 mA is an upper bound on the cost, not a measurement of
the ADSP itself. WCNSS and MPSS are separate remoteprocs and were untouched;
WiFi and the modem stayed up throughout.

### What is left after today

Excluded, each by measurement: **userspace**, **the CPUs**, **wakeup
blockers**, **the modem** (on the oracle's floor), **the rails** (leaf sets
match), **the debug UART and the clock count** (the oracle runs more), and now
**the ADSP**. Seven exclusions, zero findings.

The honest reading is that the remaining draw is not visible to any AP-side
instrument this port has, which points at SoC-level RPM-managed resources — and
the one concrete difference still standing there is the *mode* question, not
the on/off question: our device tree sets `regulator-allow-set-load` on no rail
while five other msm8953 boards in the same tree do, so the RPM is never told a
load and cannot choose LPM. Recorded with its honest magnitude in the night-plan
section above: 0.5–2 mA, not 38.

☠️ **And the target number is still unsettled**, which now matters more than any
subsystem: the oracle's floor read **31.1 mA** across four legs today against
**15.3** yesterday. Until that factor of two is resolved we do not know whether
the gap is 38 mA or 22, or whether half of it is an artefact of how the oracle
was measured.

## ★★★★ 2026-08-25 18:06 — PROVEN: an incoming call raises this phone from s2idle, and it rings

The goal states the constraint as "idle consumption as low as possible, incoming
calls still arriving". The second half had never been demonstrated. It has now,
end to end, on r76.

Method: the night queue and guardian stopped, the charger restored, then a
single controlled suspend with a 420 s RTC backstop as the only other way out —
so an early wake could only come from something else. The operator dialled the
phone from elsewhere and did not observe it; the phone recorded its own answer.

```
# uptime spanned: 113.6s of a 420s backstop      <- NOT the RTC backstop
# suspend_stats success=1 -> 2, fail=0           <- one clean suspend
# backlight before: bl_power=4   after: bl_power=0   <- the panel came back on

18:06:14 kernel: PM: suspend exit
18:06:15 [modem0/call0] call state changed: unknown -> ringing-in (incoming-new)
18:06:15 fp3-voiced[1032]: call 0 state=ringing-in (was -)
18:07:16 [modem0/call0] call state changed: ringing-in -> terminated (unknown)
```

**The suspend ended at 18:06:14 and the modem announced the incoming call one
second later; the phone rang for 61 seconds.** The whole chain works: network
paging → the modem's SMD edge as an armed wakeup source → s2idle resume →
ModemManager → `fp3-voiced`. **Resume-to-ring is one second.**

That closes the correctness half of the goal: whatever is done to the idle
current from here, this configuration — asleep, radio up, `remoteproc1:smd-edge`
`power/wakeup=enabled` — is reachable.

### ☠️☠️ Both instruments I chose for this came back EMPTY on a call that worked

The evidence above is from the journal. The two things the test was actually
built around said nothing, and each failure is worth keeping:

1. **`/sys/class/wakeup/*/wakeup_count` does not attribute an s2idle wake.**
   Every source read **+0** while the phone had plainly been raised. Those
   counters track events announced with `pm_wakeup_event()`; an interrupt can
   break the s2idle loop without announcing one. ⇒ For s2idle the instrument is
   the **`/proc/interrupts` diff across the suspend**, not the wakeup-source
   table. `tools/call-wake-test.sh` now takes it.
2. **`mmcli --voice-list-calls` was read one second too early.** The resume
   landed at 18:06:14 and the call object appeared at 18:06:15, so the script
   printed *"No calls were found"* about a call that then rang for a minute. A
   negative from an instrument sampled before the event exists is not a
   negative. It now settles and re-reads, and prints the journal lines too.

Had the operator not called at a moment I could correlate against, "no wakeup
source fired, no calls found" would have read as a clean failure of the wake
path. **Two instruments agreeing on nothing is not evidence of nothing** — it
was evidence that both were wrong for this question.

Capture: `captures/2026-08-25_call-wakes-phone-from-suspend.txt`.

---

## 2026-08-26, 00:45 — the A-B-A finished, rc=0 on all three legs, and the headline is not a current

`night-20260825-aba`, r76, one descent, `SLOPE_SLEEP=600 SLOPE_CYCLES=4
SLOPE_SETTLE=600`. Legs A (radio up, nothing cut) → B (`ModemManager rmtfs
tqftpserv` cut) → A′ (nominal control). Queue: 3 jobs, 0 failed, 4 h 30 m.
Guardian: 905 lines, **zero actions** — no eMMC event, no pack emergency.

### ★ The finding: with the radio up, the phone does not sleep

Not "sleeps and draws more". Does not sleep. Requested 4 × 600 s per leg:

| leg | modem | actually slept | of requested |
|---|---|---|---|
| **A** | up, registered | 50 s, 89 s, 32 s, 59 s = **230 s** | **9.6 %** |
| **B** | stack cut | 601, 602, 602, 602 = 2407 s | **100 %** |
| **A′** | (still down — see below) | 601, 602, 602, 602 = 2407 s | **100 %** |

This is the 2026-08-24 MPSS XO-duty result arriving from a completely different
instrument, and now on r76: with the radio up every suspend aborts early. It is
a **categorical** difference, not a slope, and it reframes the whole modem lead —
the "~36 mA the modem costs" is not a co-processor burning current beside a
sleeping AP, it is **an AP that is not allowed to stay asleep**.

### ☠️ Which makes the comparison this night was designed for unmeasurable

You cannot compare *sleeping* currents when one arm does not sleep. Leg A's
phase-A window is 271 s against the others' 1896 s, and `slope-fit.py` flags its
own fit: **r² = 0.7433, "not a straight line"**. Its 52.0 mA is therefore **not a
result** and must not be quoted. The tool caught this without being asked, which
is the second time its phase-B control window has earned its place.

✅ **The method itself is sound** — the awake control passed on all three legs:
98.6 / 106.5 / 105.9 mA measured directly, r² 0.9951 / 0.9978 / 0.9993. The
instrument is fine; the experimental design is what broke.

### ☠️☠️ A′ was not a control — `restore()` reported success and restored nothing

Predicted from reading the code at 20:30 the evening before, and it happened
exactly as predicted. `slope-leg.sh`'s `restore()` is

```sh
for s in $CUTS; do systemctl start "$s" 2>/dev/null; done
```

and this project's own trap says `systemctl stop rmtfs` **powers the modem down**
while `systemctl start` does **not** bring it back — that needs an explicit
`remoteproc` start. So leg B left the modem off, `restore()` looped three
`systemctl start`s, swallowed their outcome, and A′ ran as a **second treatment
leg wearing the control's name**.

Confirmed after the fact three ways, and the third is the one that matters:

1. `remoteproc1 4080000.remoteproc` → `offline`;
2. `systemctl is-active ModemManager` → `inactive`;
3. ★ **A′'s own sleep durations** — 601/602/602/602, matching B and not A.

(3) is the strongest because it is *the quantity being measured*, not a
side-channel. A control leg that reproduces the treatment's signature has
announced itself; no external check was needed.

### What B vs A′ leaves undetermined

Both slept full-term with the modem down, in the same voltage band, an hour
apart. Fitted asleep current:

| leg | phase-A slope | r² | asleep |
|---|---|---|---|
| B (all three services stopped) | −27.73 mV/h | 0.958 | **46.5 mA** |
| A′ (rmtfs + tqftpserv running, modem dead) | −33.17 mV/h | 0.993 | **55.3 mA** |

**8.8 mA apart, 19 %.** Two readings, and this night cannot choose between them:

* `rmtfs`/`tqftpserv` polling a downed modem really costs ~9 mA; or
* the leg-to-leg scatter of this instrument is ~9 mA, in which case it cannot
  resolve effects of that size at all.

Distinguishing those is *precisely* what the control leg existed to do. Losing it
did not only cost the A-B answer — it cost the ability to interpret the
accidental comparison that replaced it. **A control leg is not redundancy; it is
what makes every other number in the run mean something.**

### Recovery, and the state the phone is in

`echo start > .../remoteproc1/state` → `running`, but `mmcli -L` still found
nothing and `pd-mapper` stayed `failed`. A reboot was needed; after it the modem
enumerates about 60 s in (`/org/…/Modem/0`), with `ModemManager`, `rmtfs` and
`tqftpserv` active. ☠️ `pd-mapper` is **still** `failed` — that is its own
long-standing open item, not fallout from this run. Charger input was restored
**before** the reboot, per the standing PMIC rule.

Captures: `captures/2026-08-26_aba-{slope-A,slope-B,slope-Aprime}.txt`,
`…_aba-leg-*.txt`, `…_aba-guardian.log`.

---

## ☠️☠️☠️ 2026-08-26 — the rule that would have saved last night was written down on 2026-08-21, in this file, and never put into a single tool

Chasing the destroyed A′ control leg back through the tools produced something
much worse than a bug. **This project already knew.** On 2026-08-21 this file
recorded the mechanism, retracted four legs on the strength of it, and wrote the
fix out in words:

> What a valid service-pricing now requires: the modem verified `running` at cut
> time and at leg end (one `cat /sys/class/remoteproc/*/state` in the leg
> preamble and epilogue), and **rmtfs never stopped** while pricing anything
> other than modem-off itself.

Five days later, `night/jobs-2026-08-25.txt` cut `rmtfs` to price "the modem
stack", `slope-leg.sh` verified nothing at either end, and the night's control
leg was lost to **exactly** the failure this paragraph describes. Nothing new
was learned by paying for it a second time.

### The tools, audited 2026-08-26

Every tool that stops a service was checked for whether it knows about the
remoteproc. Four stopped `rmtfs` or `ModemManager` with no awareness at all:

| tool | how bad | now |
|---|---|---|
| `slope-leg.sh` | **fatal** — destroyed the 2026-08-25 A′ control | fixed: remoteproc start + `mmcli` verify + a log line that names any later leg as invalid |
| `wakeup-census.sh` | **fatal** — it *alternates*, so after round 1 every "MODEM UP" arm was modem-down | fixed: verify between rounds, and **abort** rather than run mislabelled arms |
| `ab-leg.sh` | **fatal and worst by design** — interleaving is its entire reason to exist | fixed: verify after each uncut, abort on failure |
| `idle-ladder.sh`, `freq-probe.sh` | restore-only damage (single arm, monotonic ladder) | guard added — ☠️ **and this cell said so for two hours before it was true.** The row was written with the other three; `grep -c remoteproc` on both files returned **0**. Checking a claim about your own work is the same move as checking one about the device, and it is the one people skip |

☠️ **A fourth result is misattributed by the same mechanism.** `freq-probe.sh`'s
header records that at idle-ladder stage S4, "with `ModemManager`/`rmtfs`/
`tqftpserv` stopped", the idle **floor doubled** from ~85 to ~170 mA, the
sample-to-sample variance collapsed, and the `apcs-cpu0-pll` warning storm went to
**exactly zero** for the 40 minutes S4 and S5 lasted — all three reverting when
the services came back. The observation is real and is not withdrawn. Its **name**
is wrong: that stage had the modem **powered off**, so the honest label is
*modem-off*, and every ladder stage after the `rmtfs` one inherited that state.
`idle-ladder.sh` now says so in its own output when the restore fails.

☠️ **`ab-leg.sh` deserves its own line.** Its `CUT` arm runs *first*, so the
modem is down before the first `FULL` arm ever happens: both 2026-08-20 captures
contain **one condition sampled 15 and 8 times**, not two arms. The 2026-08-21
entry above already retracted their null. What nobody did was change
`cut_off()`, which was still `for s in $STOPPED; do systemctl start "$s"; done`
when it was read this morning.

### ★ The witness, and it was in the output all along

`ab-leg.sh` prints `slept=Ns of Ms` on every arm. Both 2026-08-20 captures read
**1802 s of 1800** and **901 s of 900** — every arm, `CUT` and `FULL` alike. As
of 2026-08-26 we know a registered, radio-up phone sleeps **9.6 %** of what it
asks. A full-term `FULL` arm is therefore self-evidently not a `FULL` arm.

**The contamination was legible in the raw capture from the day it was taken.**
It needed no extra instrument, no re-run and no cleverness — only a reason to
look at the column, which arrived five days later from an unrelated measurement.
That is the argument for printing the *state* beside every result, even when
nobody has asked what it is for.

### The method finding, which outranks the power finding

This is the "a rule that lives only behind a link does not fire" failure with the
last excuse removed: the rule was not behind a link, not in a skill, not in an
upstream document. It was **in bold, in our own findings log, with the exact
command to run**. It still did not fire, because a findings log is read when you
are looking for a finding, and nobody is looking for a finding at the moment they
schedule a night run.

**A rule stated in prose is a wish. A rule in a script is a rule.** Where a
measurement has a validity precondition, the precondition belongs in the tool as
a gate that can fail and say why — and the retraction that discovers it is not
finished until that gate exists. The 2026-08-21 entry ended by *stating* the
requirement; it should have ended by *implementing* it, and this entry is what
that cost.

☠️ **Self-correction to the commit earlier this morning** (`4af923e`, "the
2026-08-20 wakeup census had mislabelled arms"): the *mechanism* it describes —
stopping `rmtfs` powers the modem down — was not discovered this morning. It was
established on 2026-08-21 and is written above. What this morning genuinely adds
is narrower and still worth having: that the census's **six-arm conclusion** and
its **MPSS table** are affected (the 2026-08-21 note flagged only one sentence of
that entry), and that the MPSS table's headline **inverts**, since its one
crystal-off arm is the one where the modem had been switched off. The commit
message reads as a fresh discovery of the mechanism. It was not.

### What this does to last night's leg B

Leg B cut `ModemManager rmtfs tqftpserv`, so by the 2026-08-21 rule its honest
name is **modem-off**, not "the modem stack cut" — a state this project priced a
week ago. The night therefore re-measured a known state, lost its control, and
its one genuinely new result came from a column nobody was designing around: the
sleep durations. **The instrument that answered was not the instrument that was
aimed.**


---

## ☠️☠️ 2026-08-26 04:13 — the "radio up means it cannot sleep" law is FALSIFIED one hour after it was published

An instrumented single suspend, run to find *which* interrupt terminates the
short ones, instead terminated the claim:

```
# wprobe 04:02:40  uptime=1637
# modem:  /org/freedesktop/ModemManager1/Modem/0  (registered, lte, home)
SLEPT=601s of 600
```

**Modem up, registered, cable in — full term.** Against five consecutive aborts
earlier the same night: leg A's 50 / 89 / 32 / 59 s of 600 each, and the census's
67 s of 600.

**So the abort is conditional, and I published it as categorical.** The entry
above and the STATUS block both said "with the radio up, the phone does not stay
asleep", from n=5 in one direction and no attempt to break it. That is the
project's own recurring failure — a first-sample confirmation removing the reason
to keep looking — arriving from me rather than from an instrument.

**What survives, stated at the strength the data supports:**

* the abort is real and large when it happens (67 s of 600 requested);
* it has **never** been seen with the modem cut (0 of 6 such arms);
* it is **not** the wake-armed modem edge — every rpmsg edge read `disabled`;
* it is not universal with the radio up: 1 of 6 radio-up suspends ran full term.

**Candidate variables, none tested.** The aborting arms were ~11 min after boot;
the full-term one ~27 min. Leg A was on battery, the other two cable-in. The
modem's registration age differs the same way as uptime. The next measurement is
therefore not another census but **a rate**: n suspends of the same length, modem
up, one condition at a time, so "sometimes" acquires a number.

### Two other things this probe returned, and one contradicts an exclusion

```
# wakeup_sources with nonzero prevent_suspend_time:
   tcpm-source-psy-…:typec@1500        prevent=14357
   pmi632-battery                      prevent=924382
   pmi632-charger                      prevent=13296
   …:pmic@0:rtc@6000                   prevent=970747
```

☠️☠️ **CORRECTED 2026-08-26 05:4x — exclusion 6 was never in doubt; I misread a
column.** `/sys/kernel/debug/wakeup_sources` has ten fields and
`prevent_suspend_time` is the **tenth**; my probe's awk tested `$9`, which is
`last_change` — a timestamp in milliseconds, nonzero for anything that has ever
fired. The four "offenders" below are last-change stamps, and the original
headless capture (`captures/2026-08-25_pmos-pm-census-headless.txt`) shows the
real column reading **0 for every source**, exactly as the exclusion said.

**Exclusion 6 stands. The seven are seven.** ☠️ And this is the third
column-misread of the same session — after `regulator_summary` read as a flat
list when it is a tree, and a `grep --include` pattern that matches basenames
rather than paths. All three produced a confident wrong answer from a correct
command. **Read the header before indexing by position**, every time; the header
is one line and the retraction is not.

The withdrawn text, kept so the error is legible:

> ~~Exclusion 6 of the seven — "no source carries a nonzero
> `prevent_suspend_time`" — does not reproduce.~~ Four do. They are cumulative
since boot rather than per-suspend, so this is not yet a finding either way; what
it is, is a published exclusion that the very next look contradicted. It must be
re-measured as a delta across one suspend before it is either restored or
withdrawn, and until then it should not be counted among the seven.

`pm_wakeup_irq` reads back unreadable on this kernel, so the s2idle waker still
has no direct AP-side witness — consistent with what the call-wake test found on
2026-08-25. Two interrupt lines appeared that the census did not show, `140`
(+38) and `141` (+12); their names have not been read yet.

---

## 2026-08-26 ~05:4x — a PREDICTION, written before the running series is read

The `srate.sh 8 600` series is in flight and its output has not been looked at.
Recording the hypothesis first, because the alternative — reading the data and
then explaining it — is the failure this same file recorded twice today.

**The six radio-up suspends, laid out by every variable that differs:**

| run | uptime at suspend | power | how the modem got up | slept, of 600 |
|---|---|---|---|---|
| leg A ×4 | ~15 700 s (4.3 h) | **battery** | boot | 50 / 89 / 32 / 59 |
| census UP | 686 s (11 min) | cable | boot | 67 |
| wprobe | 1 637 s (27 min) | cable | ☠️ **`remoteproc start` + `systemctl restart ModemManager`**, 950 s earlier | **601** |

**Two candidate variables die immediately.** *Time since boot* dies on leg A,
which aborted 4.3 h into its boot — the aborts are not an early-boot artifact.
*Cable versus battery* dies on the census's UP arm, which aborted with the cable
in, exactly like the full-term probe.

**What is left splits the six cleanly, 5–1.** Every aborting suspend had a modem
brought up **by the boot**. The single full-term one had a modem brought up
**by hand**, minutes earlier, by writing `start` to the remoteproc after the
census's cut arm had powered it down. A modem re-launched mid-session is not
obviously in the same state as one launched by the normal boot path — different
service ordering around it, `pd-mapper` already in its permanent failure, and no
guarantee it re-applied whatever power-save or paging configuration it had.

**So, as a falsifiable prediction:**

1. The running series shares the probe's condition — same session, same
   hand-restarted modem. **It should sleep full term in most or all 8 rounds.**
   If instead it aborts, this hypothesis is dead on arrival and the split is
   something else or simply noisy.
2. **After a reboot**, with the modem brought up the normal way, suspends should
   **abort again**. That is the decisive test and it is one reboot plus one
   suspend, so it is cheap.

☠️ If (1) holds and (2) does not, the honest reading is *not* "the hypothesis
half-worked" — it is that the split is coincidence over n=6 and the rate is what
matters. Written down here so that reading cannot be quietly revised afterwards.

## ☠️ 2026-08-26 05:35 — the phone has been unreachable for ~75 minutes and I cannot tell why

Stated plainly because the two possibilities call for opposite actions and
nothing available here distinguishes them.

**What is known.** `suspend-rate.sh 8 600` was started at ~04:20 under
`systemd-run --collect`: eight suspends of 600 s with a 30 s gap between them.
Last confirmed contact was at launch. Since then, on both links:

* no FP3 on the host's USB bus at all (`lsusb`, watched every 2 s);
* no RNDIS interface on the host;
* `ping` to the WiFi address: 100 % loss.

**The two readings, and why they are indistinguishable from here.**

1. **Running exactly as designed.** Eight rounds at 630 s each is 84 minutes, so
   the series is due to end ~05:44. The phone is unreachable for 600 s at a time
   by construction, and ☠️ **the 30 s gap is shorter than this device's own USB
   gadget recovery** — measured ~39 s for RNDIS after a reboot. A host watching
   at 2 s intervals would still see nothing, because there is nothing to see.
2. **Wedged in a suspend that will not end.** Same observation, exactly.

**Weak evidence for (1), not proof:** the debug layer starts the watchdog at
probe and `panic=10` is on the command line, so a hang *outside* suspend would
produce a reboot cycle and the gadget would reappear. That says nothing about a
hang *inside* s2idle, where the watchdog is stopped for the duration.

**What this costs, and it is the transferable part.** The measurement was safe —
it cuts nothing, touches no charger, and cannot leave the phone in a bad state.
What it is not is **observable**. An unattended instrument that makes its subject
indistinguishable from a dead one removes the operator's ability to decide
whether to intervene, which on a phone with no console and nobody in the room is
the only decision left. `suspend-rate.sh` now defaults its gap to **150 s**, and
its header says the gap is a *safety* parameter rather than a settling time.

**If it is not back by ~05:50** — comfortably past the series' own end — the
reading flips to (2), and recovery needs a held power button, which is the one
class of action nobody here can perform.

---

## ★ 2026-08-26 05:38 — prediction (1) confirmed 8/8, and the MPSS crystal is acquitted

The series recorded before it was read (previous entry) said: *the running
`srate` shares the wake probe's condition — a hand-restarted modem — so it should
sleep full term in most or all 8 rounds.*

```
# round uptime_s slept_s asked_s modem_state cap mpss_xo_delta
1 2340 602 600 registered 100 1496
2 2972 602 600 registered 100 1516
...
8 6764 602 600 registered  96 1462
```

**Eight of eight, 602 s of 600, modem `registered` in every round.** Combined
with the earlier data the radio-up suspends now stand at **5 aborted / 9 full
term**, and the split is still exactly along how the modem came up.

### ★★ The bonus result: the MPSS crystal churn does NOT cause the abort

`mpss_xo_delta` was recorded per round for a different reason and answers a
question that was being circled:

| | XO shutdowns | window | rate |
|---|---|---|---|
| census UP arm (**aborted** at 67 s) | 179 | 67 s | **2.7 /s** |
| srate rounds 1–8 (**full term**) | 1462–1521 | 600 s | **2.4–2.5 /s** |

**The same rate, either way.** The modem chops its crystal ~2.5 times a second
whenever the radio is up, and the application processor sleeps straight through
it in nine suspends out of nine. So the XO churn is a *constant of the radio-up
state*, not the mechanism — and the 2026-08-24 reading that paired "radio up"
with "suspends abort early" and "MPSS chopping the crystal" bundled two
independent facts. One of them is a cause candidate; the other is scenery.

☠️ That is the third candidate to die on this lead in one night, after the armed
wake edge (all edges `disabled`) and time-since-boot (leg A aborted 4.3 h in).
The remaining hypothesis is the pre-registered one and it has a decisive,
one-reboot test.

### What is left, and the test

**Prediction (2), untested:** after a reboot, with the modem brought up by the
normal boot path, suspends should abort again. If they do not, the 5–9 split is
coincidence and the honest answer is that the rate depends on something not yet
recorded — as written down *before* this result, so that reading cannot be
revised now.

Capture: `captures/2026-08-26_suspend-rate-8x600.txt`.

---

## ★★★ 2026-08-26 06:02 — prediction (2) confirmed, and the phenomenon is a DECAY

A one-shot systemd unit ran the same series 240 s after a **normal boot**, with
the modem brought up by the boot path:

| round | uptime | slept, of 600 | MPSS XO | XO per second asleep |
|---|---|---|---|---|
| 1 | 262 s | **50 s** | 126 | 2.52 |
| 2 | 462 s | **168 s** | 408 | 2.43 |
| 3 | 780 s | **356 s** | 898 | 2.52 |

**The aborts came back.** Both registered predictions held. But the shape is
something neither of them called: **50 → 168 → 356 s, monotonically increasing.**
Put beside the rest of the night — full term at uptime 1637, and 8 of 8 full term
from uptime 2340 — this is not a binary state at all. **It is a decay, and it is
essentially gone by ~20–25 minutes after boot.**

That is a much better object than the hypothesis that predicted it. A binary
"boot modem vs restarted modem" would give a constant abort length; a decay says
something is *draining* — a queue, a retry backoff, a registration procedure, a
timer that stops being rearmed.

☠️ **And the MPSS crystal is acquitted a second time, more strongly.** Its
shutdown count divided by the time actually asleep is **2.52 / 2.43 / 2.52 per
second** — identical to the 2.4–2.5 measured across eight full-term sleeps. It
tracks how long the AP was down and nothing else.

### ☠️ A correction I owe: I excluded battery-vs-cable on bad grounds

The pre-registered entry killed that candidate with one line — *"cable versus
battery dies on the census's UP arm, which aborted with the cable in"*. That arm
was at **uptime 686**, which this result places squarely **inside the decay
window**. Its abort is explained by the decay, so it says nothing about the
cable, and **the candidate was never actually excluded.**

This matters because leg A is the one observation the decay does *not* explain:
it aborted at 50/89/32/59 s **4.3 hours into its boot**, with no upward trend,
and it is the only run of the night taken **on battery**. So either the decay
restarts, or there is a second mechanism, and the difference leg A carries is
the charger.

**Running now:** the identical 3 × 600 s series, well past the decay window, with
USBIN suspended — the one condition leg A had and every full-term run did not.
☠️ A `deadman` systemd timer restores the charger after 70 minutes regardless of
what the script does, because the suspend bit lives in the PMIC and survives a
reboot.

**Prediction, registered before that series is read:** if battery-vs-cable is the
second mechanism, it should abort at leg-A-like durations with **no upward
trend**. If it sleeps full term, then leg A's aborts are unexplained and the
decay is the only established phenomenon.

---

## ★★★★ 2026-08-26 06:1x — the aborts come back ON BATTERY, at an uptime where the cable-in phone slept through

The registered prediction for this leg was: *if battery-vs-cable is the second
mechanism, it should abort at leg-A-like durations with no upward trend.*

Two of three rounds in, with USBIN suspended and everything else identical:

| round | uptime | slept, of 600 | cable-in phone at the same uptime |
|---|---|---|---|
| 1 | 1 345 s | **161 s** | — |
| 2 | 1 656 s | **36 s** | **601 s (full term)**, wake probe at 1 637 s |

**Round 2 is nineteen seconds of uptime away from the cable-in probe that slept
the whole 600, and it slept 36.** And the direction is wrong for a decay: 161 → 36
is *down*, matching leg A's 50/89/32/59 and its absence of any trend.

### So there are two separate things, and the second one is ours

1. **A post-boot decay**, cable in: 50 → 168 → 356 → full term by ~1 600 s.
2. **Something about running on battery** — which on this bench means **the
   USBIN suspend bit**, not a physically absent cable — that brings the aborts
   back at any uptime.

☠️☠️ **If (2) holds, it reaches back through the whole project.** Every sleeping
measurement here — `suspend-leg.sh`, `suspend-slope.sh`, `slope-leg.sh`, the
A-B-A, `radiolow-20260824`, `nomodem-20260819` — suspends USBIN by design, so
that the sample is the phone and not the cable. If suspending USBIN is itself
what keeps waking the phone, then every one of those legs measured a device being
woken by its own charger input, and the "asleep" numbers are not asleep numbers.

**That is a large claim and it is not yet made.** What exists is two rounds and a
contrast against a different boot. The charger and typec wakeup sources
(`pmi632-charger`, `pmi632-battery`, `tcpm-source-psy-…typec@1500`) are the
obvious suspects and are named here only as suspects.

### The control, and its prediction, registered now

As soon as the third round finishes: **restore charging and immediately run the
same suspends again, same boot, same uptime region.** That is the interleaved
control the whole night has been short of.

**Prediction: with charging restored they go back to full term.** If they do not
— if the aborts persist with the cable delivering — then the variable is not
USBIN at all, it is something the battery series did *to* the phone, and the two
mechanisms collapse back into one unknown.

---

## ☠️★ 2026-08-26 06:21 — the control prediction FAILED, and decoding the IRQ map overturned a day's reading

**The prediction, registered beforehand, was wrong.** It said that with charging
restored the suspends would return to full term. Interleaved arms, uptime 2030+:

| round | CABLE | BATTERY |
|---|---|---|
| 1 | **23 s** of 600 | **4 s** of 600 |
| 2 | **76 s** of 600 | **32 s** of 600 |

The cable arms aborted too — on a boot where the *previous* boot had slept 602 s
eight times running at comparable uptimes. So **neither** of the two stories
published in the last two hours survives intact: the "post-boot decay" does not
hold (this boot never reached full term, at any uptime), and "battery vs cable"
is not a clean switch.

**What the interleaving does establish, and it is the only controlled comparison
of the night:** within each round, on the same boot, minutes apart, **battery is
worse than cable both times — 4 s against 23 s, and 32 s against 76 s.** A 3–6×
effect in the same direction twice. That is real; the absolute levels drift
wildly and are not.

☠️ **Not one `wakeup_sources` counter moved in any arm.** The script prints those
deltas before the interrupt ones and printed none, so the wake does **not** travel
the `pm_wakeup_event()` path and the charger drivers are not reporting wakeups.
The suspected mechanism — the PMIC charger waking the phone through the
wakeup-source API — is therefore **not** what is happening.

### ★★ The IRQ map, decoded rather than assumed — and it overturns today's reading

`smd-edge` names four different edges and I had been reading the busiest one as
the modem's. Decoded from the device tree (`GIC_SPI n` → `hwirq n+32`):

| node | GIC_SPI | hwirq | irq | whose edge |
|---|---|---|---|---|
| `/remoteproc` (`rpm-requests`) | 168 | 200 | **24** | ☠️ **the RPM** |
| `remoteproc@a204000` | 142 | 174 | **140** | ☠️ **WCNSS — the WiFi** |
| `remoteproc@4080000` | 25 | 57 | **141** | the modem |
| `remoteproc@c200000` | 289 | 321 | — | the ADSP |

Two things fall out, and both correct entries written earlier today:

1. **irq 24 — the busiest line in every capture — is the RPM's edge, not the
   modem's.** The 2026-08-26 census capture explained `smd-edge +239` in a
   *modem-cut* arm as "part of the resume path". The real explanation is simply
   that the RPM's edge keeps working with the modem powered off. The modem's own
   edge, irq 141, has **334 counts in total** against the RPM's 50 591.
2. ~~★ The one line that appears ONLY in the battery arms — both of them, at
   exactly +36 — is irq 140, WiFi, absent from both cable arms.~~
   ☠️☠️ **WITHDRAWN within twenty minutes, and it was my own tool truncating.**
   `wake-attrib.sh` printed `| head -8`. The eighth line of cable round 1 is
   `IPI5 +39`, so an `irq 140 +36` would rank **ninth and be cut**. "Absent from
   both cable arms" is therefore not supported by this capture at all — it is
   consistent with irq 140 being present in every arm at a similar count.
   The `head` is removed; the run has to be repeated before anything is claimed.
   ☠️ And a second reason for suspicion was visible and I did not act on it:
   the count is **exactly +36 in a 4-second arm and in a 32-second arm**. A fixed
   number, not a rate — which is the signature of a per-transition cost, not of
   something driving the wakes.

**There is no WCNSS lead.** It lasted twenty minutes and died on the paragraph
above. What remains true is only the interleaved battery-vs-cable difference, and
even that has an unkilled confound: the host was **polling the phone over WiFi
every 25 s while this ran**. The repeat runs with the full interrupt list, over
USB only, and with nothing polling during an arm.

☠️ **This is the fourth error of one family in a single session** — a regulator
tree read as a list, `grep --include` matched against basenames, an `awk` field
one column off, and now a `head -8` list read as complete. Every one of them
returned a plausible, well-formed, wrong answer from a correct command, and this
one nearly bought a whole experiment. The rule stated after the third — *read the
header before indexing by position* — needs its sibling: **never conclude
"absent" from a truncated or ranked list.** If a claim is about something NOT
being there, the output it rests on has to be complete by construction.

### The honest state of this lead

Three published stories in one night, each broken by the next measurement:
"radio up means it cannot sleep" (falsified), "it is a post-boot decay"
(not on this boot), "it is the USBIN suspend bit" (battery is worse, but the
cable arms abort too). What has survived every round is smaller and duller:

* the abort is real, large and common;
* it has never been seen with the modem stack cut (0 of 6);
* battery is reproducibly worse than cable within an interleaved round;
* the MPSS crystal churn is scenery — 2.4–2.5 shutdowns per second *asleep* in
  every regime measured, aborted or not, battery or cable;
* nothing reports a wakeup through the wakeup-source API.

☠️ The pattern in my own errors is consistent enough to name: **each story was
published from a run whose conditions I had not varied on purpose.** The
interleaved run — the only one designed to vary one thing — produced the only
claim still standing.

---

## ☠️☠️☠️ 2026-08-26 06:30 — the repeat with the complete list kills the last claim standing, and the instrument with it

Same script, `head` removed, run over USB with nothing polling the WiFi. Four
interleaved arms at uptime 2722+:

| round | CABLE | BATTERY |
|---|---|---|
| 1 | 4 s of 600 | 6 s of 600 |
| 2 | 15 s of 600 | 14 s of 600 |

**Three things, and each one removes something I published tonight.**

1. **`irq 140` is present in every arm** — +35, +33, +34, +34 — cable and battery
   alike. The withdrawal of the WCNSS lead was right, and the complete list
   proves what the truncated one only made plausible.
2. **The battery-vs-cable difference does not reproduce.** 4 vs 6, and 15 vs 14.
   That was the *only* claim I said was still standing after the previous entry,
   and it lasted one repeat. The earlier 23/4 and 76/32 were drift.
3. ☠️☠️ **Most of the interrupt counts are per-cycle constants, not rates.**
   `IPI1` is 1017–1139 in every arm; `irq 11` 216–249; `irq 24` 213–232; `irq
   140` 33–35 — across windows of **4, 6, 14 and 15 seconds**, and earlier across
   windows of 67 and 601. These are the **fixed cost of one suspend+resume**.

### The instrument is the casualty, and that is the useful part

If the deltas are dominated by a per-cycle constant, then **dividing them by the
sleep duration produces a "rate" that is really just 1/duration** — which is why
a short arm appeared to have "9× the interrupt rate" of a long one in the
2026-08-26 census entry. It has no such thing. It has the same interrupts and
less time.

**So the `/proc/interrupts` diff across a suspend cannot attribute an s2idle wake
here, and every reading I built on it tonight is void.** The signature to check
for, in any counter differenced across an event: **does it scale with the window?**
If it does not, it is measuring the event, not the interval — and the same test
would have killed the WCNSS lead an hour earlier without needing the truncation
argument.

### Where this leaves the lead

Four published stories, four retractions, in one night:

| claim | killed by |
|---|---|
| "radio up means it cannot sleep" | a seventh suspend that slept full term |
| "it is a post-boot decay" | this boot never reaching full term at any uptime |
| "it is the USBIN suspend bit" | cable arms aborting too |
| "battery is reproducibly worse than cable" | this repeat: 4/6 and 15/14 |

What survives is exactly two things: **the abort is real and common**, and **it
has never been seen with the modem stack cut (0 of 6)**. Everything else was
built on an instrument that turns out to measure the suspend, not the sleep.

☠️ **And the phone is getting worse within the session** — 356 s at uptime 780 on
this boot, 4–15 s at uptime 2722. Something degrades. Whether that is the repeated
USBIN toggling, accumulated state, or the sixteen suspends already run is not
established, and *cannot* be with the instruments in hand.

**The next step is not another indirect measurement.** `pm_wakeup_irq` names the
waking IRQ directly, r77 is built and verified to carry `CONFIG_PM_DEBUG=y`, and a
reboot also resets whatever has degraded. Deploying it is the only move that is
not another guess.

---

## ★★★★★ 2026-08-26 06:45 — THE WAKER IS NAMED: IRQ 141, the modem's SMD edge, 4 of 4

r77 (`#78-fp3`) shipped `CONFIG_PM_DEBUG=y`, so `/sys/power/pm_wakeup_irq` exists
for the first time. Four suspends on a fresh boot, cable in, modem registered:

| round | uptime | slept, of 600 | `pm_wakeup_irq` |
|---|---|---|---|
| 1 | 47 s | 6 s | **141** |
| 2 | 113 s | 9 s | **141** |
| 3 | 182 s | 62 s | **141** |
| 4 | 304 s | 5 s | **141** |

And the kernel says it in its own words, once per suspend:

```
PM: suspend-to-idle
Timekeeping suspended for 8.081 seconds
PM: Triggering wakeup from IRQ 141
PM: resume from suspend-to-idle
```

**IRQ 141 is `hwirq 57` = `GIC_SPI 25` = `remoteproc@4080000/smd-edge` — the
modem's SMD edge.** Not the RPM's (irq 24), not WiFi's (irq 140), not the ADSP's.

### Why every earlier instrument missed it

☠️☠️ **It is the quietest line in the table.** 334 counts in total, against the
RPM edge's 50 591 — and **exactly one per suspend**, because ending the suspend is
all it does. Hours went into ranking interrupt deltas by magnitude. **A ranking
instrument is structurally blind to the rare event, and the rare event was the
cause.** It sat below every truncation and would have been unremarkable in an
untruncated list too.

☠️ And the instrument that names it directly was read as "empty" for two days.
`pm_wakeup_irq` was not returning nothing — it **did not exist**, gated behind one
Kconfig symbol. **An absent file and a file saying "nothing" are the same bytes
and opposite facts.**

### The mechanism, and it explains the whole night

The rpmsg edges all read `disabled` in `power/wakeup` — this is **not** an armed
wake source. That is precisely why it aborts: an interrupt that fires during
s2idle while *not* registered as a wake source is treated by the kernel as an
unexpected wakeup and **terminates the suspend**. `PM: Triggering wakeup from
IRQ 141` is that path.

So: **the modem sends something to the AP over its SMD edge while the phone is
asleep, and because that edge is not a wake source, the kernel aborts.** Every
observation of the night falls out of this:

* **modem stack cut → 100 % full-term sleep, 0 of 6 aborts** — no modem, no SMD
  traffic, nothing to abort on;
* **the abort length varies wildly and unpredictably** — it is however long until
  the modem's next message, which depends on what the modem is doing;
* **the MPSS crystal churn is scenery** — 2.4–2.5 shutdowns per second asleep in
  every regime, unrelated to the messages;
* **"post-boot decay" and "battery vs cable" were both noise** — they were
  sampling the interval between modem messages under different labels.

☠️ Four stories were published and retracted tonight before this. Every one came
from an instrument that counts activity, asked to answer a question about a
trigger. **Counting characterises a steady state; it does not find a cause.**

### What this opens, and it is not small

The r66 arm knob makes this edge a *proper* wake source, which is what lets a
call raise the phone — but arming it does **not** stop the aborts, it only
relabels them. The real question is now upstream-shaped and specific:

**what is the modem sending, and does the AP need to wake for it?** `qcom_smd` is
upstream and every SMD-era Qualcomm SoC has these edges. If the traffic is
routine flow-control or a keepalive, the fix is on the AP side; if it is real
data, the fix is modem configuration (the PSM/eDRX/paging direction).

**Next measurement, and for once the instrument is obvious:** capture the rpmsg
channel and payload for the message that arrives immediately after
`PM: suspend-to-idle` — the wake now has a timestamp, an IRQ and a driver to
trace from.

Capture: `captures/2026-08-26_pm-wakeup-irq-names-the-waker.txt`.

## ★ 2026-08-26 08:00 — re-measuring the oracle, and the reference that was never in doubt after all

The goal is scored against Ubuntu Touch, so the oracle's number is half of it.
On 2026-08-25 afternoon that half fell over twice: "panel proven dark" turned out
to have been proven with the *backlight*, which on the oracle is not a witness,
and the same day's inventory read the panel bias rails still sitting at 5500 mV
through a `blank=4` — so the standing conclusion was that **UT had never been
measured with the screen genuinely off**, and that the 15.3 mA floor described a
state the phone is not in when its screen is dark. Re-measuring it needed three
things that did not exist: a way onto `slot_a` without a human at the phone, a
witness the panel cannot lie to, and a way back.

### ☠️ `qbootctl` cannot switch slots on this device, and its own help says it can

`qbootctl -s a` aborts:

```
Unable to open '/dev/bsg/ufs-bsg0': No such file or directory
Is CONFIG_SCSI_UFS_BSG is enabled in your kernel?
SLOT _a: Failed to set active
```

That is a UFS path on an eMMC phone. Its help text advertises exactly the flag
for this case — `-i  still write the GPT headers even if the UFS bLun can't be
changed` — and the flag **is not implemented**: `getopt` answers `unrecognized
option: i`. `0.2.2-r1` is the newest in Alpine edge, so there is no upgrade out
of it. *A help text is documentation, not a capability.* Reading works fine, so
`qbootctl` stays useful as an independent check on what something else wrote.

The mechanism it was failing to reach is a GPT attribute write, so
[`tools/gptattr.py`](tools/gptattr.py) does it directly. The layout is
Qualcomm's, not AOSP's — priority 48–49, active 50, tries 51–53, successful 54,
unbootable 55 — and it is **not taken on faith**: `dump` XORs the `_a` against
the `_b` attribute of every slotted pair and prints which fields differ. On this
phone exactly one bit differs across every well-formed pair, **bit 50**, which
identifies `active` as what the bootloader actually reads. So the write flips
that bit and nothing else, rather than rewriting priority/tries/successful the
way a full `set_active` would — the change stays minimal, reversible, and does
not invent state. `qbootctl` then read back `Current slot: _a`, from its own code
path, before anything was rebooted.

☠️ The XOR check also earned its keep immediately: it flagged bits outside the
`active` field as differing, and the culprit was **`modem_a`, marked
`unbootable=1 prio=0 tries=0`** where every other `_a` partition reads
`prio=3 tries=7 ok=1`. We did not create that and do not know its reason. A full
`set_active` would have silently cleared it; this one left it alone.

### ☠️ The reboot that never happened, and ten minutes spent polling for it

`fp3-ssh "sudo sh -c '(sleep 2; reboot) &'"` returned cleanly and **did nothing**
— the backgrounded subshell dies with the ssh session. The phone was then polled
for ten minutes for an Ubuntu Touch that was never booting, and the silence read
exactly like a slow boot. The tell was free and was not looked at: `uptime` came
back at **5924 s** on the same kernel. `systemctl reboot --no-block` works,
because PID 1 does the work rather than a child of the dying session.

This is the same lesson as the `stop rmtfs` one, in a cheaper form: **a step
whose effect is not checked is not a step**, and the cost is not the failed
step — it is the interval afterwards spent interpreting its absence as something
else.

### ★ The panel WAS provable off, and the earlier reading was the wrong file

With [`tools/panel-witness.sh`](tools/panel-witness.sh) printing every candidate
side by side, one write of `4` to `/sys/class/graphics/fb0/blank` moved all of
them at once:

| witness | before | after |
|---|---|---|
| `fb0/show_blank_event` | `panel_power_on = 1` | `panel_power_on = 0` |
| `leds/lcd-backlight/brightness` | 25 | 0 |
| `lcdb_ldo` `state` / `enable` | `enabled` / 1 | **`disabled` / 0** |
| `lcdb_ncp` `state` / `enable` | `enabled` / 1 | **`disabled` / 0** |
| `lcdb_ldo` **`microvolts`** | 5500000 | **5500000** |

The last row is the whole correction. **`microvolts` reports the rail's
*configured* voltage and does not move when the rail is switched off** — so a
reading taken from it shows 5500 mV through a panel that is fully powered down.
That is almost certainly where "`fb0/blank` is only a half blank, the LCDB stays
at 5500 mV" came from, and with it the conclusion that the oracle had never been
measured dark. **The actuator was working; the witness was the wrong file.**

☠️ Note what this is *not*: it is not a claim that the 15.3 mA figure is right.
It removes one reason to disbelieve it. The oracle's floor also read 31.1 mA on
2026-08-25 against 15.3 the day before, and nothing here touches that.

### ☠️ The instrument proved the panel dark at the door and never looked again

`idle-ab.sh` gated on the panel once, before the window, and then sampled for an
hour without rechecking — so a panel relit by the display stack mid-window would
have been read as the phone drawing more current, on the exact question the
instrument exists to settle. It now carries the panel state in **every sample**
and prints a closing verdict, refusing to report a floor from a window the panel
was not off through. ☠️ The rail paths are resolved once at startup rather than
per sample: matching a regulator by name means ~200 file opens, and at one sample
every 5 s that is the instrument competing with a subject measured in tens of mA.

### ★★★ The oracle's floor is not a constant — 15.3, 31.1, 69.9 mA, and both instruments agree

With the panel provably off for all 721 samples of a 3601 s window, the oracle
read **floor 69.9 mA, median 125.9 mA, integrated 61.0 mA** — against the 32.2 mA
this project has been scoring the goal on. Running the same fitter over all three
`idle-ab.sh` captures the oracle has ever produced:

| run | start V | start `cc_soc` | floor (p10) | median | integrated |
|---|---|---|---|---|---|
| 2026-08-24 | 4.050 V | 7628 (≈76 %) | **15.3** | 30.1 | **32.2** |
| 2026-08-25 | 4.276 V | 9848 (≈98 %) | 31.1 | 50.0 | 54.6 |
| 2026-08-26 | 4.315 V | 9916 (≈99 %) | **69.9** | 125.9 | **61.0** |

**The two readings move together** — both rise by a factor of two to four across
the three runs.

☠️☠️ **And the conclusion first drawn from that is WITHDRAWN, within the hour, on
this project's own written rule.** What was published here was: *"`current_now`
is a shunt reading and `cc_soc` is a coulomb counter; they share no layer, so
this is not a gauge nonlinearity near full charge — the oracle really did draw
more."* **They share the whole layer.** On the oracle both come out of the same
PMI632 QG block behind the same current-sense front end; one is its instantaneous
output and the other its accumulator. *Two instruments that use one layer are one
instrument*, which is written down in this project in those words, and their
agreeing says nothing about a fault in the layer they share. The gauge
nonlinearity was dismissed for a reason that does not exist.

It is dismissed in the moment it was most convenient to dismiss it, too: a
gauge that over-reports near full charge would explain the entire table at once,
and would mean the 32.2 mA reference is fine.

What can be said without that step is narrower and still uncomfortable:

* **The reference the goal is scored against varies by 4.5× between measurements
  of the same phone in the same nominal state**, and every high reading is at a
  near-full pack.
* ★ **pmOS does not do this.** The same instrument over the three pmOS captures,
  taken at 4.224 / 4.170 / 4.294 V, gives floors of **53.9 / 54.3 / 52.9 mA** — a
  1.4 mA spread. So whatever the variation is, it is specific to the oracle side:
  either the oracle's idle genuinely has states, or the downstream QG gauge
  behaves in a way our mainline gauge does not. ☠️ Note the pmOS runs never went
  above 4.294 V, so they do not probe the region where the oracle's readings
  climb — this is a difference between two sets of measurements, not yet a
  controlled comparison.

Distinguishing the two needs a measurement neither gauge can bias, and the
obvious one is the pack itself: **charge back to full on an old boot and measure
again.** If the number climbs back with the pack, it is state of charge (real or
gauge); if it stays down, it was boot recency all along. That is the experiment
now queued, because it is the only one that separates them.

Everything in this project that cites "UT idles at 32.2 mA" is citing the lowest
of three, taken at the lowest pack voltage of the three, and never repeated. The
15.3 mA floor beside it is the p10 of that same single run.

☠️ Note also that today's median (125.9) sits at **twice** its own integrated
value, where on 2026-08-24 the two agreed (30.1 vs 32.2). A median far above the
coulomb-counter average means the sampled instants are not representative of the
window — the phone is quiet between samples and busy at them, which is what it
looks like when **the sampler itself is what wakes the phone**. On the day the
two agreed, that was not happening. Whatever else is different between these
runs, the phone's idle *structure* differs too, not just its level.

What is confounded and what separates it: today's window began 3 minutes after
boot, at 99 % on the cable, where 2026-08-24 began settled at 76 %. Boot recency
and charge state move together across these three runs and cannot be told apart
from them. A second window on the same boot at uptime 66 min, same protocol,
separates the boot half of it — and is running.

Capture: `captures/2026-08-26_ut-idle-panel-proven-off-window1.txt`.

### ★★ Boot recency is excluded: two windows on one boot, 3 min and 66 min apart, agree to 1.5 mA

The first window of the day began three minutes after the oracle booted, which
made "the phone was still settling" the cheapest explanation for its 69.9 mA
floor. It is wrong. A second identical window on the same boot, started at
uptime 66 min, panel off for all 721 samples:

| window | uptime at start | start `cc_soc` | floor (p10) | median | integrated |
|---|---|---|---|---|---|
| 1 | 3 min | 9916 (≈99 %) | 69.9 mA | 125.9 mA | 61.0 mA |
| 2 | 66 min | 9738 (≈95 %) | **71.6 mA** | 124.2 mA | **64.3 mA** |

1.5 mA apart on the floor, 1.7 mA on the median. Boot recency does not move this
number at all, and the oracle at 61–64 mA integrated is a **reproducible** state,
not a startup transient.

So of the two explanations, one is gone and the other is unproven: the readings
still track the pack, and the only low reading this project has ever taken of the
oracle is the 2026-08-24 one at 76 % SoC. ☠️ Both of today's windows sit at 92–99 %,
which is a narrow band — "it tracks the pack" is at this point a correlation
across days, not something measured inside one boot.

[`tools/soc-ladder.sh`](tools/soc-ladder.sh) walks the pack down on this boot,
one 1-hour window at a time, and turns that correlation into a curve or kills it.
☠️ It cannot decide *real draw versus gauge artifact* — there is no second
instrument on the oracle side, both readings being the same QG block behind one
current-sense front end — but it can decide whether the effect exists inside one
boot, one cable state and one instrument, which none of the three historical
captures could.

Captures: `captures/2026-08-26_ut-idle-panel-proven-off-window{1,2}.txt`.

## ★★ 2026-08-26 12:26 — the ladder's first two rungs: the state-of-charge hypothesis does not survive its own first test

The only surviving explanation for the oracle's 4.5x spread, as of this morning,
was state of charge: every high reading sat in a 92-99 % band and the single low
one (2026-08-24, floor 15.3 mA, integrated 32.2 mA) was taken at 4.050 V on
another day. `soc-ladder.sh` exists to decide it inside **one boot, one cable
state, one instrument** — eight consecutive one-hour `idle-ab.sh` windows while
the pack walks itself down.

Two rungs are in. With the two windows measured earlier this morning that makes
four consecutive hours, panel provably off in every sample of all four:

| window | v start -> end | cc_soc at start | floor (p10) | median | integrated |
|---|---|---|---|---|---|
| w1 | 4.315 -> | 9916 (99 %) | 69.9 | 125.9 | 61.0 |
| w2 | 4.282 -> | 9738 (95 %) | 71.6 | 124.2 | 64.3 |
| ladder 1 | 4.228 -> 4.182 | 9528 (92 %) | **71.9** | 123.4 | **62.5** |
| ladder 2 | 4.170 -> 4.149 | 9332 (89 %) | **71.9** | 127.0 | **62.7** |

The fitter's own gap line between the two ladder rungs reads **`+0.0 mA`**.

**So over 99 % -> 89 %, and 4.315 V -> 4.149 V, the oracle's floor does not
move.** If the state of charge were what separates 32.2 mA from 62-64 mA, ten
points of it and 166 mV should have shown a slope by now, and there is none —
the four numbers are flat to within the width of a single window's noise.

☠️ **This does not yet kill the hypothesis; it kills the easy version of it.**
What remains possible is a threshold rather than a slope — something that only
lets go lower down, and the 2026-08-24 reading was taken at 4.050 V, below every
point on this ladder so far. The ladder walks to ~78 %, which crosses into that
region, so the next rungs are the ones that decide it. What is already excluded
is "the current tracks the pack" as a smooth relationship, which is how it has
been stated here since this morning.

And the alternative it strengthens is the uncomfortable one: **that the
2026-08-24 measurement differed in something other than charge** — a different
day, a different set of services awake, a different registration state — in
which case the number the goal has been scored on since then is not a property
of the oracle at all. Nothing in the captures identifies what that would be yet.

The rungs are being kept at `/tmp/ladder-N.txt` on the phone; the run has six
windows left and ends about 18:20.

## ★★★ 2026-08-26 22:20 — the full eight-rung ladder: state of charge is dead as an explanation, and so is the threshold version of it

The 12:26 entry above reported two rungs and said the next ones would decide it.
They have. The ladder was restarted at 14:07 as a reboot-surviving systemd unit
(`night-ladder.sh`, after the first attempt was lost to an accidental power-off)
and ran all eight rungs to term, finishing 22:10:24 with the charge input
restored. One boot, one cable state, one instrument, 8 × 3600 s, panel off
throughout.

| rung | v start -> end | floor (p10) | median | integrated |
|---|---|---|---|---|
| 1 | 4.262 -> 4.156 | 76.6 | 129.4 | 58.9 |
| 2 | 4.172 -> 4.139 | 75.2 | 131.8 | 64.3 |
| 3 | 4.132 -> 4.109 | 70.5 | 128.7 | 62.8 |
| 4 | 4.099 -> 4.075 | 71.7 | 128.2 | 62.5 |
| 5 | 4.068 -> 4.050 | **71.0** | 122.6 | **63.1** |
| 6 | 4.044 -> 4.012 | 71.3 | 120.2 | 64.0 |
| 7 | 4.011 -> 3.978 | 69.0 | 128.2 | 62.8 |
| 8 | 3.981 -> 3.967 | 72.3 | 121.3 | 63.4 |

**94 % -> 69 %, 4.262 V -> 3.967 V, and neither number moves.** The floor sits
between 69.0 and 76.6 mA with no monotonic trend, and the integrated draw
between 58.9 and 64.3 mA — a spread narrower than one window's own noise. If
charge were what separates 32.2 mA from 62-64 mA, 25 points of it and 295 mV
would have shown it.

☠️ **And the threshold version dies on rung 5.** The 2026-08-24 reading — floor
15.3 mA, integrated 32.2 mA — was taken at 4.050 V, which was below every point
the 12:26 entry had. Rung 5 spans 4.068 -> 4.050 V, exactly there, and reads
**71.0 mA floor / 63.1 mA integrated**. Same pack voltage, same phone, same
instrument, 4.6× apart. There is no region of the pack where the oracle draws
15 mA.

So the surviving explanation is the uncomfortable one stated on 2026-08-25:
**the 2026-08-24 capture differed in something other than charge** — a different
set of services awake, a different registration state, something not yet named —
and therefore **the 15.3 mA oracle floor that THE GOAL has been scored against
since then is not a property of the oracle.** The reproducible oracle figure, now
across ten consecutive hours today plus the two windows this morning, is
**69-77 mA floor / 59-64 mA integrated**. Against pmOS's own 52.9 mA floor /
98.3 mA integrated from 2026-08-25, the floor gap is not 3.5× against us — it is
**in our favour**, and what remains is the burst behaviour, not a continuous-draw
deficit. ☠️ That reframing rests on the 08-24 capture being an outlier rather
than the others being one; what makes it the outlier is that it is a single
window and these are ten.

Next: the same ladder on pmOS, from the same pack mark. The pack is being charged
back to the UT rung-1 state (94 %, 4.394 V, cable attached) **on the UT side**
before the slot is switched, so pmOS boots onto a pack already at the mark rather
than starting its rung 1 after a long charge under a different power stack.

Captures: `captures/2026-08-26_ut-night-ladder/rung-{1..8}.txt` + `ladder.log`.

## ★★★★ 2026-08-27 08:00 — the matched pmOS ladder: the gap over eight hours is 12.9 % of energy, and it is entirely burst, not floor

The oracle's eight rungs (2026-08-26 14:07-22:10) were answered by eight of our
own, 23:10:33 -> 07:13:41, from the same pack mark: the pack was charged back to
94 % / 4.394 V **on the UT side** before the slot switch, so pmOS booted onto a
pack already at the mark rather than measuring after a long charge under a
different power stack. Panel provably off in every sample of all sixteen rungs.

| | UT (oracle) | pmOS | pmOS vs UT |
|---|---|---|---|
| **energy** (I*V integrated) | **525.6 mW** | **593.5 mW** | **+12.9 %** |
| current (integrated) | 129.0 mA | 154.1 mA | +19.5 % |
| floor (p10), rung mean | 72.2 mA | 56.9 mA | **-21 %** |
| median, rung mean | 126.3 mA | 161.8 mA | +28 % |
| `capacity` over the run | 94 -> 69 (25 pt) | 92 -> 63 (29 pt) | +14 % |
| voltage over the run | 295 mV | 442 mV | see below |
| coulomb counter | 62.7 mA / 16.4 % | **not available** | - |

**The shape is the one the wakeup work predicted.** Our floor is 21 % BELOW the
oracle's and has been since the 2026-08-25 fixes; our median is 28 % above it.
pmOS sits quieter and wakes more expensively, and the net over a night is
**12.9 % more energy** - not the 3.5x that the retracted 15.3 mA figure implied,
and not a continuous-draw deficit at all.

☠️ **Four ways to get this number wrong, all of them live here:**

* **mA is not the comparison.** `current_now` is current, and the two ladders did
  not cover the same part of the pack - pmOS spanned 4.150 -> 3.708 V against the
  oracle's 4.262 -> 3.967 V. At a lower pack voltage the same power draws more
  current, so mA-to-mA hands pmOS a penalty it did not earn: **+19.5 % in current
  is +12.9 % in energy**, and 6.6 points of the "gap" were the discharge curve.
  `ladder-summary.py` now integrates I*V for exactly this reason.
* **mV/h is not the comparison either**, and it is the worst of the three: 442 vs
  295 mV looks like a 50 % difference and is mostly the Li-ion curve steepening
  below 3.9 V, where only pmOS ran.
* **`capacity` is not one instrument.** The oracle's percentage comes from the
  downstream QG stack, ours from our own mainline gauge - the one that needed
  four separate fixes in August. Two different estimators are being subtracted.
* ☠️☠️ **The coulomb counter does not exist on our side.** pmOS mainline exports
  no `cc_soc` and reports `full_uAh=?`, so the one hardware-integrated
  measurement is oracle-only. On the oracle, where both exist, they disagree by
  **2.056x** over the same eight hours (integrated 1030.6 mAh vs coulomb
  501.2 mAh) - and in the direction that rules out sampling shortfall, because
  too few samples under-count. The likeliest reading is that **the sampling
  itself wakes the phone**: a sysfs read every ~5 s brings it up, so `current_now`
  measures the awake-and-idle draw while the counter integrates in hardware with
  sleep included. That ratio **must not be carried over to pmOS to "correct" its
  figure** - it is a property of how often a system wakes, which is the very
  thing under comparison. Every number in the table above is therefore
  integrated-against-integrated, never integrated-against-coulomb.

Standing consequence: **getting a coulomb counter on the mainline side is now the
highest-value instrument work in this area.** Without it, our absolute draw is
known only through an estimator that the oracle proves can be off by 2x, and the
comparison survives only because both sides are read the same wrong way.

Secondary, and cheap to check next: the pmOS floor rises monotonically across the
run, 54.9 -> 58.4 mA, while the oracle's does not (76.6 -> 72.3, drifting down).
Over a 442 mV drop a constant-power load would raise current by ~11 %; the
observed rise is 6.4 %, so this is consistent with a flat load and needs no
separate explanation - but it is worth restating in mW before anyone hunts it.

Captures: `captures/2026-08-26_pmos-night-ladder/rung-{1..8}.txt` + `ladder.log`,
against `captures/2026-08-26_ut-night-ladder/`. Tool: `tools/ladder-summary.py`.

## ★★★ 2026-08-27 09:00 — the awake bursts have a period on pmOS and none on the oracle: ~81 s

The ladders left a specific question behind: our floor is 21 % below the oracle's
and our median 28 % above it, so whatever separates the two systems lives in the
bursts. [`tools/burst-profile.py`](tools/burst-profile.py) asks what those bursts
look like, on data already captured — no device time at all.

| | floor (p10) | median | p99 | samples ≥1.5× floor | excess over floor | autocorrelation |
|---|---|---|---|---|---|---|
| pmOS rung 1 | 55.1 | 153.3 | 354.9 | 66.0 % | **92.8 mA (63 % of the draw)** | **lag 16 = 81 s, r=+0.54** |
| UT rung 1 | 77.2 | 129.4 | 302.3 | 66.7 % | 55.9 mA (43 % of the draw) | none (r=+0.07) |

**Both systems burst on two thirds of their samples — the difference is how big
the bursts are and whether they are scheduled.** On pmOS 63 % of the entire draw
sits above the floor, against 43 % on the oracle, and the pmOS excess carries a
**period the oracle does not have at all**.

**It is a real period, not an alias.** Pooled over all eight rungs the
autocorrelation peaks at lag 16 (81 s, mean r=+0.30) *and* again at lag 32
(162 s), which is its harmonic. The oracle's eight rungs give ±0.03 at both lags —
not a weaker signal, no signal.

☠️ **It is strong in the first four rungs and weak after.** r = +0.54 / +0.49 /
+0.51 / +0.39 for rungs 1-4 (23:10-03:12), then +0.19 / +0.05 / +0.05 / +0.20.
Something ran every ~81 s for about four hours and then largely stopped, or
changed character. Nothing in the rungs' own environment snapshots differs across
that boundary — same three remote processors running, comparable loadavg — so the
cause is not visible in what was captured. ☠️ And `idle-ab.sh` records `wifi: ?`
on this system, so the one obvious candidate for a periodic network task is
exactly the field the instrument does not fill in. That is a gap to close before
hunting.

☠️ **A phase-fold nearly became an over-reading.** Binning every 16th sample makes
all eight rungs look periodic (amplitudes ±11 to ±58 mA), but with 44 samples per
bin and a per-sample σ of ~81 mA the standard error of a bin mean is ~12 mA, so
16 bins produce ~19 mA of spread from chance alone. By that test rungs 4 and 6 are
noise and the fold adds nothing the autocorrelation did not already say. **The
weaker instrument agreed with the stronger one only because it was allowed to.**

☠️ **And a high sample is not a wakeup count.** `current_now` is what the pack
delivered at that instant, ~5 s apart; several wakeups inside one interval read as
one sample, and anything with a period under ~10 s is aliased outright. This can
say "there is an 81 s period" and can never say "there is nothing faster".

**Next, and it needs the phone:** what runs every ~81 s. `systemctl list-timers
--all`, the periodic wakers in `/proc/timer_list`, and the WiFi power-save/scan
interval are the three candidates that fit both the period and the disappearance.
☠️ The phone is on the oracle slot for the gauge cross-check as of 09:00, so this
waits for the switch back.

Tool: [`tools/burst-profile.py`](tools/burst-profile.py).

## ★★★★★ 2026-08-27 09:27 — the two gauges disagree by 30 POINTS on the same pack, and it is probably ours that is wrong

The ladders were compared in `capacity` points all week without anyone knowing
what the two percentages mean relative to each other. Measured now, the direct
way: stop the charge, walk the pack down to the **bottom of the pmOS ladder**
(63 %, not a convenient number), let it settle 300 s, read it, switch slots, read
the same pack on the oracle.

| | reading | source |
|---|---|---|
| pmOS 09:22:51 | **cap=63 %**, ocv 3.735 V, `charge_now/charge_full` = 63.1 % | our mainline gauge |
| UT 09:27 / 09:29 / 09:30 | **cap=33 / 34 / 34 %**, `cc_soc` 3389 → 3434 | the downstream QG |

**Thirty points, on one pack, minutes apart, with nothing between the readings
but a reboot.** The oracle's figure is stable across three reads and its slow rise
is the charger, which was reconnected before the switch.

☠️ **The oracle's two numbers are NOT independent confirmation.** `capacity` and
`cc_soc` are the same PMI632 QG block behind one current-sense front end — this
page established that on 2026-08-26 and it applies here. One witness read twice.

**The one independent handle is the OCV: 3.735 V**, measured after 300 s of rest
with the charge input open. On a cell of this chemistry that is roughly the
25-35 % region; 63 % would want something near 3.85-3.90 V. A 120-165 mV gap is
far more than rest-state IR sag explains. So the evidence points at **our** gauge
being the wrong one, not the oracle's — but "points at" is the correct strength:
the OCV→SoC mapping is pack-specific and this one has not been characterised.

### What this invalidates

* **The `capacity` row of the ladder comparison is void.** "pmOS 92 → 63 (29 pt)
  against UT 94 → 69 (25 pt), so pmOS is 14 % worse" compares two scales that are
  30 points apart. It is withdrawn, and with it the `capacity`-derived runtime
  estimate (32.0 h against 27.6 h).
* **The energy figure is untouched** — 525.6 mW against 593.5 mW comes from
  `current_now` and `voltage_now`, not from either gauge — and the voltage travel
  was already saying the same thing: pmOS fell 442 mV where the oracle fell 295.
* ☠️ **The ladders did not cover the same physical part of the pack**, whatever the
  percentages said. That does not break the comparison (the oracle's own ladder
  proved the floor does not depend on charge state), but every sentence of the
  form "at the same state of charge" written this week needs rereading.

### And this is a user-visible bug, not only a measurement problem

If our gauge says 63 % where the pack holds ~33 %, the phone tells its owner it
has twice the battery it has, and it will do so right up to the point it dies. That
outranks the idle-current work in user impact and belongs in `qcom_smbx`/the QG
path, where four separate gauge faults were already fixed in August.

**What decides it, and nothing short of it will:** one full, instrumented
discharge on pmOS from a known-full pack to shutdown, with `current_now`
integrated over the whole run, against what `capacity` claims at each point. That
also produces the OCV→SoC curve this pack has never had.

Capture: `captures/2026-08-27_gauge-crosscheck.txt`.

## ★★★ 2026-08-27 10:40 — systemd's PSI watch costs ~26 mA of MEDIAN and nothing at all on the floor

The ladders left the awake bursts as the one front that does not wait on the
modem. `burst-source.sh` traced a window and `psi_avgs_work` came out the most
frequent work on the system at **12.88/s** — and the oracle (4.9, upstart) has no
PSI at all, so it is exactly the shape of thing that could separate the two.

**A-B-A', 8-minute windows, panel proven off in all 97 samples of each:**

| leg | PSI watch | `psimon` | pressure fds | floor (p10) | median | mean |
|---|---|---|---|---|---|---|
| A | on | 3 | 11 | 57.5 | 160.2 | 158.6 |
| **B** | **off** | **1** | **6** | 57.8 | **130.2** | 144.1 |
| A' | on | 3 | 11 | 57.2 | 152.9 | 146.2 |

**The floor does not move** — 57.2 to 57.8 across all three, which is what a
wakeup cost should look like: it buys nothing while the phone is already quiet.
The **median** falls 26.4 mA against the mean of the two baselines (156.6), which
is 3.6× the baselines' own spread (7.3 mA).

☠️ **The mean and the median disagree, and that is information.** Baseline means
158.6 / 146.2 (12.4 mA apart), B at 144.1 — a 8.3 mA drop, inside the baselines'
own variation. So this suppresses the *typical* sample without touching the big
bursts. Anyone reading only the mean would find nothing here; anyone reading only
the median would overstate it.

☠️ **Two baseline legs is not a variance estimate.** The "3.6×" rests on a single
difference, n=2. This is a lead worth repeating, not a number to attach a p-value
to or to turn into a default.

### What the knob actually is, after two mis-namings

☠️ **It is not `systemd-oomd`.** Stopping the service does not stop it — the
`.socket` restarts it immediately — and even with the unit `inactive` all three
`psimon` threads and all 11 pressure fds remained. **systemd itself** holds them:
pid 1 and the user manager for their `init.scope`, plus one `memory.pressure`
each for journald, logind, nsresourced, timesyncd and udevd.

The manager-level knob is `DefaultMemoryPressureWatch=no`
(`/etc/systemd/system.conf.d/50-fp3-no-psi-watch.conf`). It needs a **reboot** —
`daemon-reexec` leaves already-started units watching — and it is a **partial**
subtraction: `psimon` 3 → 1, fds 11 → 6. The residue is systemd's own
`init.scope` watches, which this setting does not reach. Whatever the full
subtraction is worth, it is more than the 26 mA measured here.

☠️ **Both mis-namings were caught by a gate, not by a wrong conclusion.** The
first refused to measure a leg where the service had not stopped; the second made
the witness `psimon` rather than `is-active`, and that is what exposed that the
suspect was wrong. A leg gated on `systemctl is-active` would have measured
nothing while reporting everything.

### Instrument notes from the same run

☠️ **The current↔trace correlation was a dead end, and the reason generalises.**
`current_now` is an instantaneous sample every ~5 s; event counts are continuous.
Correlating a snapshot against a 5 s bin cannot work, and searching 13 time shifts
for the best r inflates it — chance alone gives ~+0.25 at n=71. The +0.30s it
produced mean nothing.

☠️ **`burst-source.sh` first duplicated `idle-ab.sh`'s panel logic and the copy
was worse than the original**: it wrote `fb*/blank` but not the DRM `dpms`, so it
aborted on a phone where `idle-ab.sh` took the panel down with `waited=0s` in the
same minute. It now wraps `idle-ab.sh` instead. Duplicating a working instrument
to save one exec is how you get two instruments that disagree.

☠️ Reassuring, and worth recording: the traced window read floor 57.5 / median
144.2 against the ladder's 56.9 / 161.8, so **the tracer's overhead does not
move the floor**.

Captures: `captures/2026-08-27_psi-watch-ab/{A-psi-on,B-psi-off,Ap-psi-on}.txt`,
`captures/2026-08-27_burst-source/`.

## ★★★★ 2026-08-27 11:00 — the pmOS ladder rendered on the oracle's scale: ~2× the charge, and the top of the column is contested

With the gauges known to be ~30 points apart, the pmOS ladder was re-expressed in
oracle percent by mapping its **voltages** through the oracle ladder's own
V→`capacity` points, anchored below by the one cross-check reading.

**The mapping.** From the UT ladder, under load (~126 mA median): 4.262 V→94 %,
4.172→89, 4.132→85, 4.099→82, 4.068→79, 4.044→76, 4.011→73, 3.981→70,
3.967→69. Below that the ladder has no data at all; the single anchor is the
2026-08-27 cross-check — **3.735 V OCV → 33.5 %**, placed at 3.716 V to match the
ladder's under-load voltages (~19 mV of IR sag at 126 mA).

| rung | pmOS `cap` | pmOS V start→end | **UT cap of pmOS** |
|---|---|---|---|
| 1 | 92 % | 4.150 → 4.058 | 86.8 → 77.8 % |
| 2 | 88 % | 4.015 → 3.955 | 73.4 → 67.3 %* |
| 3 | 84 % | 3.982 → 3.884 | 70.1 → 57.2 %* |
| 4 | 80 % | 3.875 → 3.826 | 56.1 → 49.0 %* |
| 5 | 76 % | 3.833 → 3.780 | 50.1 → 42.5 %* |
| 6 | 72 % | 3.788 → 3.737 | 43.7 → 36.5 %* |
| 7 | 68 % | 3.756 → 3.707 | 39.1 → 33.5 %* |
| 8 | 64 % | 3.685 → 3.708 | ~33.5 %** |

\* below 3.967 V the oracle ladder never went; those rows hang off the single
anchor. \*\* measured endpoint.

### The two deltas, side by side

| | UT ladder | pmOS ladder |
|---|---|---|
| own `cap` | 94 → 69 = **25 pt** | 92 → 63 = **29 pt** |
| own voltage | 4.262 → 3.967 = **295 mV** | 4.150 → 3.708 = **442 mV** |
| coulomb | 92.4 → 76.0 = **16.5 %** | none on this system |
| **on the oracle's scale** | 25 pt (by definition) | **86.8 → 33.5 = 53 pt** |

**So over the same eight hours the pmOS ladder moved roughly twice the charge the
oracle's did, while our own gauge reported 29 points against the oracle's 25.**
The voltage travel says the same thing without any mapping: 442 mV against
295 mV, ending 259 mV lower than the oracle ever went.

### ☠️ The top of that column does not add up, and it must be said

The oracle read **94 % at 22:59** with the cable in, immediately before the slot
switch; the pmOS ladder began at 23:10:33. The mapping wants 86.8 % at that
moment — a 7.2-point fall, **220 mAh, which needs 1202 mA sustained for 11
minutes.** A boot does not cost that:

| the 11-minute window | mAh | points |
|---|---|---|
| idle at the UT ladder's 126 mA | 23.1 | 0.75 |
| idle at the pmOS ladder's 162 mA | 29.7 | 0.97 |
| a generous 500 mA boot | 91.7 | 3.00 |
| an implausible 800 mA boot | 146.7 | 4.79 |
| **what the mapping requires** | **220** | **7.2** |

So the start point has two estimates ~6 points apart: **~93 % by the time
budget, 86.8 % by the voltage mapping.** It cannot be resolved from what was
captured, because **the two systems' `voltage_now` readings have never been
compared on the same pack under the same load** — at the cross-check the oracle
was charging.

☠️ **A constant voltage offset is excluded.** Shifting pmOS voltages by the
+90 mV that would put the start at 93 % puts the *end* at ~44 %, where 33.5 %
was measured. Whatever the discrepancy is, it is not a fixed calibration bias.

☠️ **Retracted from the entry of an hour earlier:** I explained the 94 → 87 gap
by "boot and two probe rungs in 11 minutes". The arithmetic above kills that —
idle costs 0.9 points there, and even an absurd boot costs under 5. The mapping
stands on the voltages; the time-based justification I attached to it was wrong.

**What survives regardless of which start is right:** 86.8 → 33.5 = 53 points,
or 93 → 33.5 = 59.5 points. Both are close to twice the oracle's 25, so the
conclusion does not rest on the contested row.

### ★ THE PROTOCOL FIX, for every comparison ladder from here on

The whole ambiguity exists because the two ladders' starting points were never
tied together by a measurement. They can be, cheaply, and it costs one step:

> **Before the slot switch, on the UT side, with the charge input OFF and the
> pack rested, record `capacity` AND `voltage_now`. After the switch, the first
> rung of the pmOS ladder must open at the same voltage — and its own percentage
> is then pinned to that oracle percentage by construction.**

Both halves matter. With the charge input on, the reading is inflated by the
charger and is not the pack (4.379 V charging against 4.262 V the moment the
input was cut — 117 mV of it was the charger). And without the voltage, the
percentage alone cannot be carried across two gauges that disagree by 30 points.

If the first rung does **not** open at that voltage, the difference is real
consumption between the two readings and must be logged as such — not absorbed
silently into the ladder.

## ☠️☠️ 2026-08-27 11:20 — the charge-based 2× and the current-based 1.2× cannot both be true

Putting the two ladders' totals on one page exposes a contradiction that each
measure hides on its own. Same eight hours, same phone, three yardsticks:

| yardstick | UT | pmOS | ratio |
|---|---|---|---|
| `capacity`, on the oracle's scale | 25 pt = 765 mAh | **53 pt = 1622 mAh** | **2.12×** |
| integrated `current_now` | 1030.6 mAh | 1231.8 mAh | **1.20×** |
| energy (I·V) | 525.6 mW | 593.5 mW | **1.13×** |
| coulomb counter | 16.5 % = 505 mAh | none | — |

**If pmOS really moved 1622 mAh in eight hours that is a 203 mA average, and its
own current integral measured 154 mA — a 49 mA hole.** The charge-based and the
current-based readings of the *same run* disagree by a factor of ~1.8, and no
amount of care about which floor or median to quote touches that.

Candidates, none tested:

* **The extrapolated leg of the mapping.** Below 3.967 V the oracle ladder has no
  data and the column is a straight line to one anchor. Five of the eight pmOS
  rungs live entirely down there. If that line is wrong, the 53 points are wrong.
* ☠️ **The pack's real capacity is unknown.** Both gauges compute against
  `charge_full = 3 060 000 µAh`, the *nameplate*. This pack is years old. Every
  "points → mAh" number on this page, on both systems, inherits that assumption —
  and a smaller true capacity shrinks the mAh on **both** sides, so it changes the
  absolute figures without obviously fixing the ratio.
* **The sampling distortion**, already known to be 2.056× on the oracle between
  integrated current and the coulomb counter, and unmeasurable on pmOS because
  there is no counter there.

☠️ **What must NOT be said until this is resolved: "pmOS uses twice the power".**
The charge column says 2.12×, the current and energy columns say 1.13-1.20×, and
they are measurements of one run. The honest statement is that **pmOS is worse by
somewhere between 13 % and 112 %, and the instruments disagree about where in that
range** — which is the same conclusion the missing mainline coulomb counter has
been forcing all day, now with a second, independent demonstration of it.

**What would decide it:** the full instrumented discharge already queued in
`TODO.md` — one run from a known-full pack to shutdown, integrating `current_now`
throughout against what `capacity` claims. That yields the pack's true usable
capacity, the OCV→SoC curve, and the mapping's lower leg, all three of which are
assumptions today.

## ☠️☠️ 2026-08-27 13:00 — the second front opens and the tracer answers "no"

The awake burst is the other half of the pmOS bill: our floor is *better* than the
oracle's on every rung (56.9 vs 72.6 mA) and our median is *worse* on every rung
(162.0 vs 126.3). We sit quieter and we wake more expensively. So: what wakes us?

`burst-source.sh` recorded 360 s with the panel proven dark for all 73 samples,
the charge input cut, and every `workqueue_execute_start` and
`timer_expire_entry` on the same clock as the current — 24 321 events against 71
current samples. Capture and full working:
[`captures/2026-08-27_burst-source/analysis.md`](captures/2026-08-27_burst-source/analysis.md).

The current behaved exactly as the ladder said it would: floor 57.5, median 144.2,
p90 310.7, max 409.4 mA, and **46 of 71 samples (65 %) at or above 1.5× floor**. A
7× swing inside six minutes, reproduced in a window small enough to trace.

**And the event rate does not move with it.** Splitting every event into the 5 s
bin that ends at each current sample, then splitting those bins by whether the
sample was a burst:

| | burst bins (n=46) | quiet bins (n=25) |
|---|---|---|
| events per 5 s bin | **313** | **316** |
| `psi_avgs_work` | 63.2 | 65.1 |
| `vmstat_update` | 17.9 | 19.4 |
| `delayed_vfree_work` | 9.2 | 10.8 |

Every top function at the same per-bin rate, the 1 % total difference pointing the
*wrong* way. A carpet of wakeups that does not change cannot be what makes the
current change. **Counting work is finished as a line of attack on the burst.**

Worth recording separately, because it is a real number about the carpet even
though it is not the burst: `psi_avgs_work` is 4 897 of the ~9 000 workqueue
executions in the window — ~13/s, i.e. roughly 26 cgroups each waking every 2 s —
and it is flat at 105–151 per 10 s bin from end to end. That is consistent with
the A-B-A' that priced the systemd PSI watch at ~26 mA of *median* and nothing on
the floor: a steady tax, not a burst.

☠️ **The trap this nearly walked into.** With 24 321 wakeups in six minutes the
instinct is to rank them and name the top one as the cause — and `psi_avgs_work`
at over half of all workqueue work is a *very* convincing thing to name. The split
by burst/quiet is the only thing that stops it, and it costs one extra pass over
the same file. Rank a trace and you have described the background; split it by the
thing you are explaining and you have tested it.

**What this leaves.** Either the power goes somewhere that is not a running
instruction (a rail, a radio), or the CPU is awake without emitting either
tracepoint — a spin, an RCU stall, an interrupt storm serviced without a
workqueue. One trace cannot separate those. `burst-attrib.sh` was written for this
fork and uses **no tracepoint at all**: CPU-busy from `/proc/stat`, cpuidle
power-collapse residency and WFI usage summed over all eight CPUs, both cpufreq
policies, and the wlan packet counters, all sampled alongside the current. If a
burst carries no CPU-busy and no residency signature, the next instrument is a
rail and not a profiler.

## ★★★ 2026-08-27 13:20 — and it is not the CPU either: the burst spends power with the cores collapsed

`burst-attrib.sh`, written an hour after the trace answered "no", asks the machine
about itself instead of profiling it: CPU-busy from `/proc/stat`, cpuidle
power-collapse residency and WFI usage summed over all eight cores, both cpufreq
policies, the wlan packet counters — **no tracepoint at all**, so it could have
disagreed with the trace and did not. 360 s, panel dark for the whole window,
charge input cut, 180 samples. Working:
[`captures/2026-08-27_burst-attrib/analysis.md`](captures/2026-08-27_burst-attrib/analysis.md).

    floor(p10)=53   median=103   p90=222   max=473 mA      burst 111 / quiet 69

| column | burst | quiet | ratio |
|---|---|---|---|
| **`busy_pct`** | **1.0** | **1.0** | 1.00× |
| **`pc_res_pct`** (all 8 CPUs) | **99** | **100** | 0.99× |
| `wfi_per_s` | 77 | 77 | 1.00× |
| `pc_per_s` | 437 | 453 | 0.96× |
| `f0_kHz` / `f4_kHz` | 1 228 800 | 1 228 800 | 1.00× |
| `wlan_pps` | 2 | 2 | 1.00× |

**A 9× swing in current across which the machine does not move.** The cores are
in power-collapse 99 % of the time *during the burst*, at the same frequency,
waking at the same rate, doing the same 1 % of work. The older census line "the
CPUs are not it" was about the floor; it turns out they are not the burst either.

So the burst is **not code**. That is now established twice by instruments that
share no mechanism — a tracer and a sysfs sampler — which is the only kind of
agreement worth having here, and it is the opposite of the mistake this
investigation has made before, where two witnesses turned out to be one witness
read twice.

**What can spend hundreds of milliamps on this phone without waking a CPU:** the
panel (proven dark, re-proven on every sample), wlan (flat at 2 pps), and the
modem — which is independently the thing that terminates every suspend here
(IRQ 141, the SMD edge). `burst-modem-ab.sh` puts the A-B-A' on exactly that,
using `mmcli --disable` for the RF and never touching the remoteproc, because
restarting that costs audio until the next reboot and a mixer write afterwards
oopses the kernel. If the modem comes back flat too, what is left is a rail that
nothing in `/sys` attributes, and the next instrument is a rail census timed to
the burst — not another profiler.

## 2026-08-27 13:40 — the modem is worth nothing, and the pack voltage says the burst is real

A-B-A' with `mmcli --disable` (never the remoteproc — restarting that costs audio
until reboot), three 360 s `burst-attrib` legs, panel proven dark for all 73
idle-ab samples of every leg. Working:
[`captures/2026-08-27_burst-modem-ab/analysis.md`](captures/2026-08-27_burst-modem-ab/analysis.md).

| leg | modem | floor | median | p90 |
|---|---|---|---|---|
| A | registered | 53 | 99 | 214 |
| **B** | **disabled** | **53** | **97** | **213** |
| A' | registered | 53 | 102 | 213 |

**A↔A' baseline spread 3 mA, A−B difference 2 mA.** The RF is excluded. So the
burst is not code, not the CPU, not wlan traffic, not the panel, and not the
modem.

### ★ And it is real power, on a witness that was in the capture all along

The gauge could have been inventing a 9× swing that nothing in the machine
accompanies — a serious possibility, and the column that settles it had simply not
been read: **the pack voltage sags with the burst, on every leg, at a consistent
implied resistance.** A: ΔI 102 mA / ΔV 16 mV = 156 mΩ. B: 100 / 18 = 179 mΩ.
A': 102 / 20 = 196 mΩ. Medians of interleaved samples, so discharge drift cancels;
156–196 mΩ is entirely plausible for an aged cell plus connector and traces. Real
load, not a reporting artefact.

### ☠️ The bug a button press exposed, and what it would have cost

The operator woke the phone with a key during A' to see which OS was running.
idle-ab handled it correctly — it waited 30 s for the panel to go back down
(`waited=30s` against `0s` on A and B) and all 73 of its own samples were dark.

`burst-attrib`'s sampler, though, starts *before* idle-ab has the panel, and marks
the real start with a `# window_from=` line written at the END of the file,
because the wait is only known when idle-ab returns. `burst-attrib-fit.py` read
the file in one sequential pass and therefore set the cutoff **after** keeping
every row. The filter silently did nothing: A' came back with all 195 samples, the
first sixteen lit.

Fixed with two passes. **A' median 109 → 102, p90 261 → 213.** Uncorrected, the
control leg reads 7 mA worse than A and the ready-made story — "re-enabling the
modem cost something" — is sitting right there waiting to be believed. The general
form: **a mark that is written but not honoured is worse than no mark**, because
the output looks filtered. And it took an unplanned interruption to expose it,
which is an argument for not treating one as contamination on sight.

**Next:** wlan. `wlan_pps` is flat at 2 vs 2 across every burst, and that excludes
*traffic* and nothing else — a radio with power-save off sits in receive whether
or not a packet arrives. Packets are what the interface carries; power is what the
radio spends listening. `burst-wlan-ab.sh` takes the radio down with `nmcli radio
wifi off` and refuses to start if the ssh session is on the wlan link.

## ★★★★ 2026-08-27 14:00 — wlan is worth ~15 mA of median, and the rails say the same thing

First real hit on front two. A-B-A' with `nmcli radio wifi off`, three 360 s
`burst-attrib` legs, panel dark for all 73 idle-ab samples of each. Working:
[`captures/2026-08-27_burst-wlan-ab/analysis.md`](captures/2026-08-27_burst-wlan-ab/analysis.md).

| leg | wlan | floor | median | p90 | burst share |
|---|---|---|---|---|---|
| A | on | 53 | 99 | 221 | 67.6 % |
| **B** | **off** | 53 | **83** | **198** | 53.6 % |
| A' | on | 53 | 98 | 217 | 59.8 % |

**Median: baseline spread 1.0 mA against a 15.5 mA effect — fifteen times the
spread.** p90: 4.0 against 21.0. ☠️ The mean (4.9 vs 6.5) and the energy (23.8 vs
27.4 mW) do **not** clear their own spread, so "wlan costs 27 mW" is not a
measurement; the median and p90 are. Nothing at all on the floor. Same shape as
the PSI watch: it moves the typical sample, not the biggest bursts. B is n=1.

### ☠️ The obvious fix was dead before it was built

"Power save must be off — turn it on" is wrong here. `wcn36xx` with `debug_mask`
= `WCN36XX_DBG_PMC` prints **`Entered BMPS`**: beacon-mode power save works. What
it also prints is churn — **8 entries in 180 s, in clusters**, each implying a
preceding exit, and between exit and re-entry the radio is in full receive. With
`wlan_pps` at 1–3, background broadcast (ARP, mDNS, IPv6 RA) is enough to keep
interrupting it. ☠️ Some of that may be ours: the dev host is on the phone's own
wlan subnet.

### The rail census agrees, at the rail

`burst-rail.sh` (57 regulators, `state` **and** `opmode`, 186 samples): **72 of 81
readings are constant and 9 move with the current.** Three are identifiable from
the `regulator_summary` consumer tree, and they are exactly the right three:
`l9` = `a204000.remoteproc.iris-vddpa` (515 mA requested max), `l19` =
`iris-vddrfa` (100 mA), `l7` = `iris-vddxo`. `a204000.remoteproc` is WCNSS and
`iris` is the WCN36xx transceiver — **the WiFi RF and PA rails**, moving 30 → 17 %
and 31 → 22 % between burst and quiet. Two instruments, two layers, one answer.

☠️ The other four movers — `l1`, `l4`, `s1`, `l18`, all at 43 % against 20-23 % —
have **no consumer listed anywhere in `regulator_summary`** and `num_users` = 0.
They are not attributable from sysfs and are not being guessed at here.

### ☠️☠️ And the first version of that census was wrong in two ways

It printed a confident shortlist (`regulator-dummy`, `l15`, `l2`, `l18`, `l7`,
`l5`) that has been **retracted**:

1. **The labels were off by the gaps.** The capture wrote a bare vector with a
   name list in the header; three regulators have no readable `state`, so the
   vector was 54 long against 57 names and every label after the first gap was
   wrong. The fix is that every reading now carries its own key
   (`regulator.12/state=E`), and the parser refuses to invent one — a key missing
   from a sample is a *hole*, not a value. Names are not unique either: two PMICs,
   so two `l1`, `l2`, `l3`.
2. **The instrument loaded what it measured.** 57 directories × 2 `cat`s = 114
   forks per sample; the run returned **156 samples where 180 were due**, so one
   sweep took over two seconds. The "under 1 ms" figure had been measured with a
   single globbed `cat`, which is not what the loop did. Two `grep -H .` calls per
   sample now, and the re-run returned 186. **Measure the loop you wrote, not the
   one you meant.**

### What is left

With the radio entirely off, leg B still ran a median of **83 mA against a floor
of 53**, 97 of 181 samples still bursts. **~30 mA of burst survives with wlan off,
the modem excluded, the cores collapsed and the panel dark.** The census is
running again with both radios down to see which rails still move.

## 2026-08-27 evening — the awake burst has an owner, and it is the MPSS core

Six instruments had now answered "not me" about the awake current burst: a
tracer, a machine-state sampler with no tracepoints at all, an A-B-A′ on the
modem RF, a rail census whose shortlist had to be retracted, and — first — the
RPM master sampler's own burst/quiet split.

☠️ **That sixth "no" was wrong, and the evidence refuting it was in the same
file.** Splitting the capture by the current and taking each master's median
cannot see a master that is up a third of the time: its median is 0 on *both*
sides. Split by the candidate cause instead — condition on the master and report
the current — and it separates at once, over two independent windows:

| | window 1 | window 2 |
|---|---|---|
| MPSS core up | 33 % of samples | 37 % |
| median with it up | 166 mA | 158 mA |
| median with it down | 74 mA | 67 mA |
| **difference** | **+92 mA** | **+91 mA** |

The 2×2 against PRONTO is close to additive: both down **63 mA**, PRONTO alone
108, MPSS alone 163, both 188. They are not the same variable — they agree on 107
of 189 samples. At ~35 % duty MPSS carries about 32 mA of median, which is the
size of the residual that the wlan cut left behind.

**The method lesson is the exact converse of the one recorded a day earlier.**
That one said: rank a trace and you describe the background, so *split it by the
thing you are explaining*. True — and it made the split-by-effect the only tool
in use, which is blind to any cause that is intermittent rather than intense.
**Split by the effect to test a story; split by the cause to find one.** Both
directions, every time.

Three smaller things fell out of the same evening:

* ☠️ **A rail name is not a rail.** Two PMICs, twenty colliding names — two `l1`,
  two `s3`, two `l9`. The census line "`s1` is the MSS supply, by citation from
  five other msm8953 boards" never established *which* `s1`, and the citation
  resolved a name, not a thing. `burst-rail.sh` now records the parent device.
* ☠️ **`discharge-run.sh` cut the charge input through `input_suspend`** — the
  Ubuntu Touch path, which does not exist on mainline. The write went nowhere.
  A twenty-hour run would have measured a phone on the charger and produced an
  OCV curve from it. Found by reading the node list before the run, not after.
* **LPASS never releases the crystal**: `XO total duration` 9.4 s against 5½ hours
  of uptime, `LPASS_xopct` = 0 in every sample of both windows. Constant, so not
  the burst — but the right shape for the standing `vlow = 0` item, and it belongs
  to the floor.

## 2026-08-27 evening — the oracle comparison was already in the repository

Two interventions had by then ruled out every Linux-side lever on the MPSS
finding: disabling the radio (`mmcli --disable`) and stopping the modem daemon
both left the MSS core's duty cycle at 34–38 %, and the modem's own SMD edge read
zero through the leg where the daemon was stopped. The next question was whether
the oracle pays the same, and that looked like it needed a slot switch.

It did not. `2026-08-24_ut-master-stats-idle-before.txt` / `-after.txt` are a
before/after pair taken on **Ubuntu Touch, slot a, cable in, screen off, over a
565 s awake-idle window** — captured for the `vlow` investigation and never read
for this. Two snapshots of `xo_accumulated_duration` are not a worse instrument
than sampling; for a duty cycle they are a better one, because the difference *is*
the integral.

| master | oracle awake | pmOS awake (3 windows) |
|---|---|---|
| APSS | 100 % | 100 % |
| PRONTO | 23.2 % | 24.7–26.7 % |
| **MPSS** | **6.3 %** | **34.0–36.4 %** |
| **LPASS** | **2.9 %** | **100.0 %** |

PRONTO matches, which is the control that makes the other two readable: the
comparison is not systematically shifted by the different kernels or the cable.

Two gaps, and they are not the same size:

1. **MPSS is awake 5–6× more on pmOS.** The XO *shutdown rate* is about the same
   on both (oracle 3.1/s; pmOS 2.5–3/s), so the modem is not being woken more
   often — **each awake stretch is longer**. At the measured +91 mA that gap is
   worth roughly 25 mA of median on its own.
2. ☠️ **LPASS never sleeps on pmOS at all.** The oracle's ADSP shuts the crystal
   13.7 times a second and is off it 97 % of the time; ours has accumulated
   **9.4 s of XO-off in 5½ hours**. It is constant, so it never showed up in any
   burst analysis — the whole day's instruments were built to find things that
   *change*.

**The lesson is not about the modem.** The measurement that decided the front had
been sitting in `captures/` for three days, taken for a different question, and
the plan of record was to spend a slot switch re-taking it. ☠️ **Before measuring,
grep the captures.** They are indexed by date and question, not by what they
happen to contain.

## 2026-08-28 — the three-yardstick contradiction resolves, and the honest number is ~2×, not 13 %

The 17.94 h discharge was run for the pack's capacity. It also produced the thing
the ladder comparison had been missing since it was taken: a **measured
voltage → charge curve for this pack**, including below 3.967 V, where the oracle
ladder has no data at all and where five of the eight pmOS rungs live.

Reading each ladder's own voltage travel off that curve turns the disputed charge
column into a measurement:

| | oracle ladder 4.262 → 3.967 V | pmOS ladder 4.150 → 3.708 V | ratio |
|---|---|---|---|
| raw terminal voltage, as the ladders recorded it | 623 mAh | 1308 mAh | **2.10×** |
| IR-corrected OCV (R = 175 mΩ) | 651 mAh | 1335 mAh | **2.05×** |

**The 2.12× survives.** It was not an artefact of the missing lower leg, nor of
the single OCV anchor the estimate hung on — the two agree to within 3 %.

Now put the four independent handles on the *same two ladders* side by side:

| handle | oracle | pmOS |
|---|---|---|
| voltage travel through the measured curve | **623–651 mAh** | **1308–1335 mAh** |
| hardware coulomb counter (`cc_soc`) | **501 mAh** | — (mainline exports none) |
| `current_now` integral | **1031 mAh** | ~1218 mAh |

☠️ **The oracle's `current_now` integral is the outlier, and it always was.** Its
own coulomb counter and the pack's own voltage both put that ladder at 500–650 mAh;
the integral says 1031. That 2.056× disagreement was already recorded — with the
right explanation, that **sampling `current_now` wakes a phone that would otherwise
be asleep**, so the integral measures the awake draw and the counter measures the
truth. What was missing was a reason to believe one side over the other. The
voltage now supplies it, from the cell itself.

On pmOS the same two handles agree to 8 % (1218 against 1308–1335) — as they must,
because pmOS barely sleeps, so sampling it costs almost nothing.

**Consequence, and it is the headline of the whole comparison:** the energy figure
of +12.9 % and the current-integral figure of +20 % were **integrated against an
inflated oracle**. Corrected, pmOS costs the pack roughly **twice** what Ubuntu
Touch does over the same eight hours. The earlier note "compare energy, not mA"
was right about mA and wrong about energy: **both** were built on the same
contaminated oracle integral.

☠️ **What this does not license.** The curve is one discharge, at ~110 mA median
and 21–27 °C, against ladders that ran at 126 and 162 mA; a single 175 mΩ was used
for the whole range. The two readings of it bracket 2.05–2.10× and the earlier
estimate said 2.12×, so the *conclusion* is robust, but "2.05×" is not a
three-digit number. And the oracle still has no measured curve of its own — this
one is the pack's, taken on pmOS, applied to both, which is legitimate only
because it is the same cell.

## ★★★★★ 2026-08-28 — T0, the re-pricing: the named terms cover half the gap, and the other half is that pmOS never sleeps at all

The 2× is now a measured number, so every term that was sized against the old
"+12.9 % of 593 mW" has to be re-priced against it. This costs no device time —
it is arithmetic over measurements already taken — and it was run first for that
reason.

**The gap, in the pack's own currency.** Both ladders ran 8.05 h; read through the
measured discharge curve:

| | oracle | pmOS | gap |
|---|---|---|---|
| charge spent over 8.05 h | 623–651 mAh | 1308–1335 mAh | **684 mAh** |
| as an average current | 77–81 mA | 162–166 mA | **85.0 mA** |

**The named terms, converted to the same currency.** ☠️ The gap is an *integral*,
so a term may only be counted at its effect on the **mean**, not on the median —
and for two of the three that is a much smaller and much less certain number:

| term | effect on the median | effect on the **mean** | of the 85 mA gap | established? |
|---|---|---|---|---|
| MPSS awake duty (35.2 % vs the oracle's 6.3 %, × 91 mA) | — | **26.4 mA** | 31 % | ✅ two windows, 1 mA apart |
| systemd PSI watch | 26.4 mA | 8.3 mA (baseline spread 12.4) | 10 % | ❌ inside its own spread, n=2 |
| wlan radio | 15.5 mA | 6.6 mA (baseline spread 4.9) | 8 % | ❌ inside its own spread |
| **sum of point estimates** | | **41.3 mA** | **49 %** | only the first is established |

☠️ Two corrections that pull in opposite directions and roughly cancel: pmOS's
`current_now` integral under-reads the pack by 7–9 %, so these terms should be
scaled up by ~1.08 (→ 44.6 mA, 52 %); and the wlan term is **not** a differential —
the oracle had wlan associated too, so whatever it pays is subtracted from our 6.6
and the honest differential is smaller, possibly zero.

**So the answer to the question T0 was set to ask is: no, they do not cover it.
At least 44 mA — over half the gap, and closer to 70 % of it if only the
established term is counted — is not in any of the three.** That was the trigger to
say so rather than to distribute the remainder over the named terms.

### And the missing term was found in four sysfs reads

```
/sys/power/suspend_stats/success = 0     (uptime 3 h 06)
/sys/power/suspend_stats/fail    = 0
logind IdleAction                = ignore
gsd-power sleep-inactive-battery-type = 'nothing'
```

**pmOS has never suspended once on this boot, and nothing in the stack ever asks
it to.** Not blocked — `systemd-inhibit --list` shows eight inhibitors and every
one of the `sleep` ones is `delay`, none is `block`. Simply never requested. Every
"idle" figure ever taken on this phone, including all sixteen ladder rungs, is an
**awake-idle** figure by construction.

★ **And the residual has the right size for exactly that.** On the oracle, the
distance between what its `current_now` integral says (129 mA — the awake draw,
because sampling wakes it) and what the pack says it actually spent (77–81 mA) is
**48–52 mA**. The residual T0 cannot account for is **44 mA**. Those are the same
quantity within their error bars: *the half of the gap that has no named owner is
the half the oracle wins by being asleep.*

### What this reframes

The remaining work is not a hunt for another 44 mA of leak. It is one trade, and
it was measured and written down on **2026-08-22**, six days before it became the
headline:

* modem SMD edge **armed** → an incoming call raises the phone from s2idle and it
  rings (proven 2026-08-25, resume at 18:06:14, call object at 18:06:15) — but the
  edge's own ~one-per-2-s inbound ring re-wakes the phone within seconds of every
  suspend, so residency is zero;
* modem SMD edge **disarmed** → suspends hold 3/3, and calls do not arrive.

☠️ Today that edge reads **`enabled`** — `soc@0/4080000.remoteproc/…/remoteproc0:smd-edge/power/wakeup`,
the modem's, while the other three smd-edge nodes read `disabled`. So the phone is
in the armed half of the trade and paying for it, with the sleep it buys switched
off anyway at the policy layer.

**The oracle proves the trade is resolvable**, because it does both at once: MPSS
awake 6.3 % of the time, and it takes calls. The one difference left between the
two sides after every Linux-side lever came back flat is the **modem firmware
build** — ours 425464 from the rootfs, the oracle's 325768 from the partition,
against an RPM and TZ that come from that same 2021 metabuild on both. The inbound
ring is the modem firmware's own behaviour: the AP-side send census found only 2
IPCRTR sends on that edge in 120 s, against 276 `rpm_requests` on a different one.

**So one experiment now sits under both fronts at once** — the MPSS awake duty and
the suspend residency — and it is a file copy in the rootfs with a `.bak`, not a
partition write.

## ☠️☠️ 2026-08-28 — T0's residual was an artefact: the oracle does not sleep either, and its "~30 mA" was the low outlier of four

T0, written this morning, closed on a coincidence: the unowned residual (44 mA) had
the same size as the distance between the oracle's `current_now` integral and what
its pack actually spent (48–52 mA), and the entry read that as *the oracle wins the
unexplained half by being asleep*. Two re-reads of material already in `captures/`
break both halves of that sentence.

**The oracle does not sleep on this device.** `2026-08-24_ut-coulomb-and-sleep-attempt.txt`,
in the repository since the 24th, states it in its own conclusion: with the full
documented recipe applied (ssusb wakeup off, both ofono modems `Powered=false`,
`wakeup_count` handshake) UT managed **2 completed suspends out of 120 attempts** in
a 603 s window — 93 s asleep, 15 % of the window. Its author wrote "there is no 'UT
sleeping current' to compare against, because the oracle does not sleep on this
device". So "pmOS never suspends" is a real inefficiency — a phone that slept would
beat both — but it is **not a differential against the oracle**, and it cannot be
the missing term in a pmOS-minus-UT gap.

**And the oracle's idle number is not 30 mA.** Four UT windows exist, all by the
vendor coulomb counter (`cc_soc`, the one gauge that passed both a known-positive
and a known-negative control):

| window | start V | cc_soc Δ | integrated |
|---|---|---|---|
| 2026-08-24, 60 min | 4.051 V | 105 | **32.2 mA** |
| 2026-08-25, 30 min | 4.296 V | 89 | 54.6 mA |
| 2026-08-26 #1, 60 min, panel proven off | 4.331 V | 199 | 61.0 mA |
| 2026-08-26 #2, 60 min, panel proven off | 4.287 V | 210 | 64.3 mA |

Three of the four sit at **55–64 mA**. The one that says 32 is the earliest, the
only one taken on a half-empty pack, and the only one whose own write-up carries a
warning that the pack was still relaxing — and it is the one that got quoted, as
"~30 mA", into the sentence "the oracle idles below our phone asleep". ☠️ **The
flattering outlier is the one that travelled.** It became the headline because it
was the most striking, not because it was the most defensible, and every later
comparison inherited it.

### What the gap actually is, re-stated on the surviving numbers

pmOS never sleeps, so a `current_now` median taken while sampling **is** its true
draw; UT sleeps between samples, so its `current_now` median (125 mA on the 08-26
windows) is an awake-only figure and only `cc_soc` prices the window. Comparing
like with like:

| | idle, panel dark, radio up |
|---|---|
| pmOS (`current_now` median, 08-25, two windows) | 98–101 mA |
| oracle (`cc_soc`, three windows) | 55–64 mA |
| **gap** | **~40 mA (1.67×, not 2×)** |

Against that gap the MPSS differential is not a partial term — it is most of it.
The modem master is awake 34–36 % on pmOS and 6.3 % on the oracle, and an awake
MPSS costs +91 mA measured two independent ways, so the differential is
`(0.35 − 0.063) × 91 ≈ 26 mA` = **~65 % of the 40 mA**. There is no 44 mA orphan
to explain; there is one term, and the rest is within the spread of the windows.

**This does not change what to do next, it sharpens it.** The remaining candidate
under the MPSS duty is the modem firmware build difference (ours 425464 from the
rootfs, the oracle's 325768 from the partition, on an identical 2021 RPM/TZ) — and
that is a rootfs file copy with a `.bak`, not a partition write.

☠️ The methodological item, which is the second time this month the same shape has
cost a day: **an outlier that flatters the other side is still an outlier.** Four
windows existed; the gap was priced off one of them, and the one chosen was the one
that made the problem look biggest. Quote the median of the windows you have, or
say you only have one.

## ★★★★ 2026-08-28 — T1/T2 answered from the discharge already on disk: the OCV table's *shape* is right, its *scale* is not, and there is no cutoff to fix

Both open charger items turn out to be one item, and it needed no new measurement —
only the 17.94 h discharge integrated against the DT.

**T2 first, because it dissolves.** `voltage_min_design` is ignored because nothing
is supposed to act on it in the kernel: `qcom_smbx.c` has no low-voltage cutoff,
`VOLTAGE_MIN_DESIGN` is not even among its properties (only `qcom_smbb.c`, a
different PMIC, exports it), and on mainline the low-battery shutdown is UPower's
policy, driven by `capacity`. So the phone ran to 2.864 V not because a cutoff was
missing but because **the percentage it hands UPower never fell below 35 %** — the
same single defect. There is no separate T2.

**T1, priced against the DT rather than guessed.** The `ocv-capacity-table-0` in
`sdm632-fairphone-fp3.dts` spans `4375600 → 100 %` down to `3000000 → 0 %`, i.e. a
full sweep of that table is a full pack by construction. What this pack actually
delivered across that same span, integrated from `current_now`:

| pack terminal voltage (under ~122 mA) | delivered |
|---|---|
| first below 3.600 V | 1758 mAh (48 % shown) |
| first below 3.500 V | 1984 mAh (41 % shown) |
| **first below 3.400 V** — `voltage-min-design` | **2076 mAh** (39 % shown) |
| first below 3.000 V — the table's 0 % | 2175 mAh (36 % shown) |
| to shutdown, 2.864 V | 2185 mAh (35 % shown) |

**A full sweep of the table yields 2175 mAh against a declared 3 060 000 µAh.** One
table-percent is worth **21.8 mAh on this pack, not 30.6**. That is the whole
defect, and it is a scale error, not a shape error: the table's voltage→relative-SoC
mapping is untouched by it, and the 35 % floor is exactly `1 − 2185/3060`.

☠️ **Do not fix this by editing `charge-full-design-microamp-hours`.** It is a
*design* value, the OCV table was characterised against it, and this is one aged
2019-era pack — writing a measurement into a nameplate property makes the gauge
right on this phone and wrong as a statement about the hardware, and it is
unsendable upstream. The correct fix is the one T1 already named: learn
`charge_full` separately from `charge_full_design` and integrate the gauge against
the learned value, which is what every real gauge does and what the vendor's own
`cc_soc`/`full_uAh` pair does downstream.

Usable capacity to the declared cutoff is **2076 mAh**, and that is the number a
learned `charge_full` should converge to.

## ☠️ 2026-08-28 — the oracle's 6.3 % MPSS duty has no recorded radio state

The single established term in the whole gap — the MPSS duty differential, now
carrying ~65 % of it — rests on exactly one pair of files,
`2026-08-24_ut-master-stats-idle-before.txt` (13:39:38) and `-after.txt` (13:49:03),
565 s apart. Both are 72 lines of raw master-stats and **neither records whether the
modem was registered, disabled, or powered off.** They were captured for the `vlow`
investigation, for which the radio state did not matter, and were later re-read for
a question where it is the entire variable.

What can still be said from inside the files: PRONTO ran at 23.2 %, so WiFi was up
and the phone was not in flight mode — that rules out the crudest confound but not
an individually disabled modem, and the same session was running `Powered=false`
experiments on both ofono modems later the same day.

So the comparison that reads "the oracle's modem is awake 6.3 % of the time and
ours 34–36 %" may be comparing a registered modem against a disabled one. ☠️ **A
capture re-read for a question it was not taken for must be checked against the
variables that question cares about**, and this one was not.

**It does not block the next step, and that is why the next step is the firmware
swap rather than a slot switch.** Loading the partition's 325768 build on pmOS
tests the same lever from our own side: if our MPSS duty drops, the story holds
whatever the oracle was doing at 13:39 on the 24th; if it does not, the oracle
window has to be retaken with `mmcli`/ofono state recorded in the capture itself
before anything further is built on 6.3 %.

## ★★★ 2026-08-28 — the two sides now agree on one arithmetic, and it leaves nothing over

Putting the corrected numbers side by side, the whole idle picture closes on the
terms already measured, with no unnamed remainder:

| | mA | how it was measured |
|---|---|---|
| SoC floor — MPSS *and* PRONTO both down | **63** | pmOS, 2×2 conditional median, `burst-master.sh` |
| oracle idle, whole-window integral | **55–64** | UT, `cc_soc`, three windows |
| pmOS idle, sampled median | **98–101** | pmOS, `current_now`, two windows |
| MPSS duty differential, 35.2 % vs 6.3 %, × 91 mA | **26** | conditional split by cause, two windows 1 mA apart |

`63 + 26 = 89`, against a measured 98–101; and the oracle sits **at the floor**.
So the reading is: *the oracle idles at what this SoC costs when its two radios'
cores are asleep, and pmOS idles at that same floor plus a modem core that is awake
five to six times as often.* The ~10 mA still unaccounted is inside the spread of
every term in the table and is not worth a hypothesis.

☠️ These are not the same *kind* of number and the agreement must not be quoted as
a proof: 63 is a conditional median over samples where two bitmask bits were clear,
55–64 is an unconditional integral over an hour, and 98–101 is an unconditional
median. A conditional median excludes the very bursts an integral includes. Read it
as a consistency check that no large term is missing — which is what it is good
for, and what T0 wrongly concluded the opposite of this morning.

## ☠️☠️★★★ 2026-08-28 — the modem-firmware candidate is dead: both systems run the *same* build, and the difference was a metadata file read against an image

The swap was staged and about to run. Reading the images first killed it.

| witness | says |
|---|---|
| `modem_b/verinfo/ver_info.txt`, `"modem"` field | `MPSS.TA.3.1.c1-00026-8953_GEN_PACK-1.**325768**.1.329896.1` |
| `modem_b/image/modem.b12`, compiled-in `QC_IMAGE_VERSION_STRING` | `MPSS.TA.3.1.C1-**425464**` |
| `modem_b/image/modem.b12`, compiled-in GEN_PACK string | `…GEN_PACK-1.356774.1.**425464**.1` |
| our rootfs `modem.mbn`, same two strings | `MPSS.TA.3.1.C1-425464` / `…GEN_PACK-1.356774.1.425464.1` |
| `modem_a` (the slot the oracle boots), compiled-in string | `MPSS.TA.3.1.C1-425464` |

**Both partitions and our rootfs copy carry the same modem build.** The `325768`
that the 2026-08-27 entry read as "the oracle's firmware" is the **metabuild**
number — `ver_info.txt` reports `Meta_Build_ID: SDM632.LA.2.1-00015-STD.PROD-1.325768.0.329896.1`
and its `"modem"` field simply mirrors it. It is package metadata written at flash
time, not a statement about the image beside it. ☠️ And our own image contains the
string `GEN_PACK-1.325768.1.329896.1` too, among a dozen other embedded build
strings — so grepping for it would have "confirmed" the difference from either side.

☠️ **The error is the one this log keeps recording in new costumes: two witnesses at
different layers, read as one comparison.** A metadata file on one side and the
binary's own version string on the other are not two readings of the same thing.
The rule that would have caught it: *ask the same question of both sides with the
same instrument.* Here that is one command — `strings -a … | sed -n
's/^QC_IMAGE_VERSION_STRING=//p'` — and run against both it answers in seconds.

**The swap was not performed** (there is nothing to swap), the rootfs is untouched,
and no `.bak` exists. `modem-fw-swap.sh` stays in the tree with this finding in its
header, because the next person to notice `ver_info.txt` will have the same idea.

### What this leaves

Every candidate under the MPSS duty differential is now spent: three Linux-side
levers flat, the modem's own SMD edge silent in the daemon-less leg, and now the
firmware identical. That promotes the item flagged this morning from a caveat to
**the top of the list**: the oracle's 6.3 % was measured in a 565 s window whose
radio state was never recorded, and the same session ran both ofono modems
`Powered=false` later that day. Before anything further is built on that number it
has to be retaken on slot a with `mmcli`/ofono state written into the capture — and
if the oracle's modem was disabled, the differential this whole line of work rests
on does not exist.

## ★★★★★ 2026-08-28 — radio-low puts the MPSS core at *exactly zero*, which rescues the oracle's 6.3 % from the hole flagged this morning

A-B-A′ on `mmcli -m 0 --set-power-state-low`, measured as **master duty** rather
than current (`burst-master-knob.sh`, 3 × 360 s, 186/186/184 samples) —
[`captures/2026-08-28_radiolow-master-ab/`](captures/2026-08-28_radiolow-master-ab/):

| leg | state | current median | **MPSS cores up** | PRONTO cores up |
|---|---|---|---|---|
| A | `on` | 128.0 mA | **51.6 %** | 25.8 % |
| B | **`low`** | **57.5 mA** | **0.0 %** | 24.2 % |
| A′ | `on` | 88.5 mA | 29.3 % | 23.9 % |

☠️ **A and A′ are 22 points apart, so this is not a clean two-sided A/B** — the
modem's duty is not stationary on the ten-minute scale, and any *shift* measured
against this baseline would be worthless. What survives that objection is that leg B
is not a shift but a **floor**: the MPSS core bitmask was clear in 186 of 186
samples. Zero has no spread. (PRONTO is flat across all three legs at 24–26 %, the
control that says nothing else moved.)

Two things follow, and the second is the one worth the run.

**1. The modem duty is the whole idle difference.** With the modem core down the
current median is **57.5 mA**, which lands inside the oracle's own `cc_soc` band of
55–64 mA. pmOS with the modem up idles at 98–101. So there is no residual "pmOS
overhead" hiding behind the modem term — take the modem's awake time away and this
phone idles where the oracle idles.

**2. ★ It closes the hole in the oracle's 6.3 % from our own side, with no slot
switch.** This morning's worry was that the 565 s UT window never recorded its
radio state, and that the same session ran both ofono modems `Powered=false` — in
which case the 6.3 % would be a powered-down modem and the differential would not
exist. But a powered-down modem reads **0.0 %**, as leg B just demonstrated on this
very SoC. **6.3 % is not 0 %.** The oracle's modem was up and doing something 6.3 %
of the time; ours is up 30–50 %. The differential is real.

☠️ Note the distinction the run also makes: `mmcli --disable` did *not* move the
duty (36/34/34 % on 2026-08-27) while `--set-power-state-low` takes it to zero.
"Disabled" only stops the radio's use; "low" powers the core down. A knob that
looked like the same lever was measuring a different layer — which is exactly the
mistake the firmware `ver_info.txt` reading made this afternoon, in the other
direction.

### The question this leaves is now sharp

Both systems run the same modem firmware on the same SoC with the same RPM and TZ,
both have the modem powered and registered, and one keeps its modem core down 94 %
of the time while the other keeps it down 50–70 %. That is not a firmware
difference and not a Linux-side power lever: it is **what the two stacks ask the
modem to do** — attach state, DRX/paging cycle, and which QMI services hold it.
`mmcli -m 0` reports `packet service state: attached` on pmOS; whether the oracle
attaches a bearer at idle is the first thing to compare, and unlike the duty itself
it is a one-line read on each side.

## ★★★★★ 2026-08-28 — the cost is **LTE**, and 2G reproduces the oracle's 6.3 % on our own phone

A-B-A′ on the access technology (`--set-allowed-modes`), MPSS duty as the measure,
3 × 360 s, 184 samples each —
[`captures/2026-08-28_2gonly-master-ab/`](captures/2026-08-28_2gonly-master-ab/):

| leg | access tech | current median | **MPSS cores up** | PRONTO | edge IRQ/s |
|---|---|---|---|---|---|
| A | `lte` | 98.5 mA | **34.8 %** | 24.5 % | 34.7 |
| B | **`gsm, gprs`** | **54.0 mA** | **6.5 %** | 12.5 % | 35.0 |
| A′ | `lte` | 101.0 mA | **34.2 %** | 19.6 % | 35.6 |

A and A′ agree to **0.6 points** and 2.5 mA — unlike the radio-low run this is a
clean two-sided A/B, and the phone stayed **registered and able to receive calls**
throughout leg B.

**6.5 % is the oracle's 6.3 %.** The number that has anchored this whole
investigation as "what a well-behaved modem costs" is reproduced on *our* phone, on
*our* kernel, on *our* stack, by one change: leaving LTE. And at 54.0 mA the median
lands **below** the oracle's 55–64 mA `cc_soc` band.

☠️ **2G is an instrument here, not a proposal.** The networks are being switched
off; nothing about this suggests shipping a 2G-only phone. What it buys is that the
cost now has a name and a layer.

### The question this turns into, and it is not the one we had this morning

**Was the oracle on LTE during its 565 s window?** Its capture records no radio
state at all — that was flagged this morning as a hole about *power* state, and
`--set-power-state-low` closed that half (a powered-down modem reads 0.0 %, and
6.3 % is not 0 %). But **access technology was never in the capture either**, and
it is now the deciding variable:

- oracle on **LTE** at 6.3 % → there is a real LTE idle-configuration difference to
  find, and it is worth everything spent on it;
- oracle on **2G/3G** at 6.3 % → the "oracle is five times better" result collapses
  into "the oracle was on a cheaper RAT", and the comparison has to be rebuilt.

Either way the next measurement is the same and it is one line on the oracle side:
`access tech`, beside `signal quality` and the serving cell. ☠️ This is the third
variable in a row that the 08-24 window did not record; the retake must write the
modem's full state into the capture rather than beside it.

### ★★ And it decouples the two fronts — which kills a plan made an hour ago

`edge_irq_per_s` is **34.7 / 35.0 / 35.6** across the three legs. The modem SMD
edge rings at the same rate on LTE and on 2G, while the core's awake duty moves by
a factor of five. So the ~1-per-2-s IPCRTR signal ring is **not** what keeps the
core awake, and it is **not** RAT-dependent.

The plan written into `TODO.md` this afternoon assumed the opposite — that if the
modem stopped waking, the ring would stop too, and suspend residency would come
back with it. **It will not.** The awake-duty front and the suspend-residency front
are independent, and each needs its own fix. That is worse news than it looks: the
consumption target is reachable without touching the ring, but the *responsiveness*
target — sleeping while still able to take a call — is a separate problem that this
result does nothing for.

## 2026-08-28 — three things ruled out before the slot switch, and the hypothesis that is left

**3G does not exist here.** The `3gonly` A-B-A′ aborted on its own guardrail: with
`--set-allowed-modes=3g` the modem went `searching` for 40 s and then sat at
`enabled` with an empty access technology for the rest of a 64 s probe. The
operator has switched UMTS off. So the RAT ladder on this network is **LTE or 2G**,
with nothing in between, and the 2G leg is the only comparison available.

**No data flows over the cellular link.** `rmnet_ipa0` is `DOWN` with **zero bytes
in either direction** across a 60 s window, `ipa_lan0` is down, and `mmcli
--list-bearers` returns nothing. The modem is EPS-attached and idle. Whatever costs
28 points of duty, it is not user traffic.

**And "enabled but unregistered" is not the control it looked like.** The 29.3 %
leg of the radio-low run was a modem *searching* for a network, which is expensive
work in its own right. The only clean pair is **LTE registered 34.8 %** against
**2G registered 6.5 %**.

### What is left

Both legs: same modem, same firmware, same stack, same kernel, idle, attached, no
traffic, decent signal (76–84 %). One is five times the other. Two readings survive:

1. **This modem simply costs 5× on LTE.** LTE idle keeps a wider receive chain and
   a different DRX rhythm than GSM paging, and 35 % may be what an LTE-camped
   MSM8953 modem costs — in which case **the oracle's 6.3 % means the oracle was
   not on LTE**, and the entire "the oracle is five times better" result is a RAT
   difference that no amount of pmOS work can close.
2. **Something in our LTE setup keeps the modem out of RRC idle** — a short paging
   DRX, a standing QMI indication registration that survives the client, a
   measurement report cadence. Then there is a real fix, and it is userspace.

☠️ These are not distinguishable from this side of the phone. **One line on the
oracle decides it: its access technology.** That is the slot switch, and it is next.

☠️ Note against reading 1 too quickly: stopping ModemManager did not move the duty
(38/36/37 %), but a QMI client's indication registrations live in the *modem* and
are not necessarily released when the client dies — so that null result does not
acquit the stack either. Only a boot with the client never started would, and even
that leaves the modem unregistered, which is its own expensive state.

## ★★★★★ 2026-08-28 — the oracle does LTE at 6.1 % **with a live data connection**, and that settles the question the wrong way round

The slot switch, with one instrument (`modem-window.sh`) run on both systems inside
half an hour — [`captures/2026-08-28_modem-window-both/`](captures/2026-08-28_modem-window-both/):

| | pmOS (slot b, r78) | oracle (slot a, UT 4.9.218) |
|---|---|---|
| window | 600 s | 600 s |
| access technology | **`lte`** | **`lte`** |
| registration | `registered` | `registered` |
| EPS attach | `packet service state: attached` | `ConnectionManager Attached = true` |
| **data context** | **none** — `rmnet_ipa0` DOWN, 0 bytes, no bearers | **active** — `/ril_0/context1 Active = 1`, `rmnet_data2`, 10.124.125.20, `internet.vodafone.net` |
| **MPSS awake** | **34.8 %** | **6.1 %** |
| LPASS awake | 100 % | 3.0 % |
| operator / cell | (not read) | One HU, MCC 216 MNC 70, CellId 1470762 |

**6.1 % reproduces the 2026-08-24 figure of 6.3 % to within a fifth of a point** —
and this time the capture carries `Technology = lte` and `Status = registered` in
the same file as the counters, so the number is no longer hostage to an unrecorded
variable. That was the whole point of building one instrument for both sides.

### What this kills, and what it leaves

**Killed: "this modem simply costs 5× on LTE."** The same modem, the same firmware,
the same operator and cell, twenty minutes apart, does LTE at 6.1 % under one stack
and 34.8 % under ours. The cost is not intrinsic to LTE on this hardware.

**Killed the other way round: "pmOS keeps something up that the oracle doesn't."**
The oracle is doing *more*, not less — it holds an established PDP context with a
real address on `rmnet_data2`, while pmOS has no bearer at all and an interface
that is `DOWN` with zero bytes through it. **The cheaper system is the one with the
data connection running.**

That inverts the search. The question is no longer what we hold that they release;
it is **what they set up that we never do**. The obvious candidate is the one the
process list names: the vendor stack runs `netmgrd` and `ipacm` to build the IPA
data path, and the modem is told the AP's path exists. On pmOS the IPA hardware is
probed (`7900000.ipa`, driver `ipa`) but nothing ever brings a channel up. A modem
whose data path was never completed has an obvious reason to stay out of deep idle
DRX, and it is exactly the shape of thing that costs power while sending the AP
nothing — which is what the SMD-edge census found in August.

☠️ Signal is not the explanation and points the wrong way if it were: ofono reports
`Strength = 12–15`, ModemManager `78 %`. Whatever the scaling, the oracle is not
reading *stronger*, and a weaker signal costs a modem more, not less.

### The next measurement, and it is cheap

**Connect a data context on pmOS and re-measure the duty.** If bringing up
`internet.vodafone.net` takes MPSS from 34.8 % toward 6 %, the fix is that pmOS
should establish the context — userspace, no kernel change, and it would take the
idle draw from 98–101 mA to about 57 without touching 2G or the radio state.

## 2026-08-28 — the matched pair also says the LPASS fix did not free the crystal

Read out of the same two `modem-window.sh` captures, which is the first time the
two systems' LPASS records have been compared side by side over a matched window:

| | pmOS (r78) | oracle |
|---|---|---|
| LPASS `XO total duration` over 600 s | **0** — literally never | 582.1 s |
| LPASS awake | **100 %** | 3.0 % |

☠️ **The audio-clock fix is in the kernel that produced this.** `ASoC:
msm8916-wcd-digital: hold mclk only while a stream runs` is on `debug-int/7.1.3`
and shipped in r78, and the LPASS master still does not shut the crystal down for a
single tick in ten minutes. So either something else holds it, or the fix addresses
a different holder than the one that matters — and the lead page's closing line
("solved and priced") is true about the *clock* and false about the *outcome*.

It stays a correctness item rather than a lever on today's numbers: stopping the
ADSP outright was priced at ~4 % against a 98 mA baseline. But that pricing was
taken when the modem term dominated. If the modem work lands and idle falls to
~57 mA, the same 4 mA is 7 % of what is left, and it becomes worth reopening —
with the measurement above as the entry point rather than the shipped patch.

## ☠️ 2026-08-28 — the PDP-context hypothesis is dead within the hour

The inversion suggested an obvious mechanism: the oracle holds an established data
context and we hold none, so bring one up and see. It was set up on pmOS in one
command — `mmcli -m 0 --simple-connect="apn=internet.vodafone.net"` succeeded,
`rmnet_ipa0` came up with a `qmapmux0.0` mux, and the modem read `connected`.

**Flat, all three legs:** connected **35.0 %**, disconnected **36.0 %**,
reconnected **36.8 %** (`captures/2026-08-28_bearer-master-ab/`), against 34.8 %
measured with no bearer at all forty minutes earlier. The data context is worth
nothing, and the edge ring does not move either (36.2 / 35.6 / 37.4 per second).

☠️ **And the current column of that leg is unusable** — the phone was charging, so
`cur_mA` is charge current and its p10 reads 0.0. The duty is the measure here and
that is why this instrument records the bitmask rather than the meter; a run built
on the current column would have had to be thrown away.

So the difference is not the bearer, not the RAT, not the firmware, not the power
state, not traffic, not signal, and not any Linux-side lever tried. What is left is
**what the two stacks say to the modem over QMI** — and specifically the
possibility that ModemManager leaves standing indication registrations (signal
thresholds, serving-system change reports) that the modem services on its own
schedule.

☠️ The 2026-08-27 "ModemManager stopped" null result (38/36/37 %) does **not**
acquit that: a QMI client's registrations live in the *modem*, and killing the
client does not necessarily release them. The test that separates the two is a boot
where ModemManager never runs at all, with the modem brought online by hand — and
that is next.

## ☠️★★★ 2026-08-28 — ModemManager is acquitted: the modem does it with no client at all

The test the 2026-08-27 null result could not perform. ModemManager **masked** and
the phone rebooted, so on this boot no client has ever configured this modem; the
radio was brought up by hand with a single
`qmicli -d qrtr://0 --dms-set-operating-mode=online`, and it registered on **LTE
within 10 s**. Nothing else was sent — no indication registrations, no signal
thresholds, no bearer.

| window | span | **MPSS awake** | edge IRQ/s |
|---|---|---|---|
| first | 234 s | **29.1 %** | 39.1 |
| second | 372 s | **37.1 %** | 41.0 |

Same band as every LTE measurement on this system (33.3 / 34.8 / 34.2 / 35.0 /
36.0 / 36.8 %). **A modem that no userspace client has ever spoken to, beyond being
told to come online, keeps its core awake a third of the time.**

So the search inverts a second time, and this is the sharper statement of it:

> It is not that pmOS asks the modem for something expensive. It is that the vendor
> stack asks it for something *cheap*, and we never ask.

The candidate the evidence names, and it is on the working side: `qrtr-lookup` on
pmOS lists an **IPA control service (49)** offered by the modem with nobody talking
to it, the IPA hardware is probed (`7900000.ipa`, driver `ipa`) and no channel is
ever brought up — while the oracle runs `ipacm` and `ipacm-diag` and holds
`rmnet_data2` fully established. A modem whose hardware data path was never
negotiated has a reason to keep its core serviceable.

☠️ **The decisive test is on the oracle, not on us**: stop `ipacm` there and
re-measure. Proving a mechanism by removing it from the system that works is
stronger than adding a guess to the system that does not — and it is the only
direction available, because pmOS has no `ipacm` to start.

## ☠️ 2026-08-28 night — an instrument failure caught by its own printout, and one hypothesis killed off the data already taken

**The AP-sleep hypothesis dies without an experiment.** The obvious structural
difference left was that the oracle's AP sleeps between samples and ours never
does, which would make its modem's idleness a consequence rather than a cause. It
is not: **APSS reads `XO off 0.0 s`, awake 100 %, in every window on both systems**
— the oracle's application processor is awake exactly as continuously as ours. The
data to kill this was in the same captures as the MPSS numbers and had simply not
been read. (The 2G leg on pmOS says the same thing from the other side: 6.5 % duty
with our AP just as awake.)

**And an instrument failure worth writing down.** The first `ipacm` A/B was run by
setting `setprop ctl.stop vendor.ipacm`, and the `getprop` status obligingly
reported `[stopping]`. It never stopped: a `ps` in the same command block printed
**2** ipacm processes, and they were still there fifteen minutes later. The status
property records the request, not the outcome — the same shape as `show_blank_event`
reporting `panel_power_on = 1` with zero MDSS clocks enabled, and as the knob whose
state command watched `power state` while the knob changed registration.

☠️ **A state that says "stopping" is a request, not a result.** The rule the tools
already carry for knobs — refuse to label a leg until the state command *confirms*
the change — has to be applied to the witness as well as to the knob, and here the
witness was the wrong field. The corrected leg kills the process outright and
verifies the count is zero and stays zero.

The 8.0 % / 6.6 % pair from the first attempt therefore measures nothing about
`ipacm`; both legs had it running. It is kept only as two more samples of the
oracle's LTE duty, which is what it actually is.

## ☠️ 2026-08-28 night — `ipacm` is definitively not it

The corrected leg, with the processes actually killed and verified at **0** and
still 0 fifteen seconds later, `rmnet_data0` and `rmnet_data2` still up:

| oracle leg | MPSS awake |
|---|---|
| `ipacm` + `ipacm-diag` running (baseline) | 8.0 % |
| both **killed**, verified | **6.4 %** |

Flat, and if anything lower. **The IPA control daemon is not what keeps the
oracle's modem asleep**, which retires the candidate the process list suggested and
that `qrtr-lookup`'s unattended *IPA control service (49)* seemed to support.

☠️ `setprop ctl.start` did not bring them back either — the property mechanism
reported the request in both directions and performed neither. On this system the
reliable restore for an init service is a reboot, which the slot switch provides.

### Where that leaves the search

Everything nameable in userspace on both sides has now been tested:

| | result |
|---|---|
| our client (ModemManager) masked, modem online by one QMI command | **29–37 %** — the modem does it with no client at all |
| their IPA daemon (`ipacm`, `ipacm-diag`) killed | **6.4 %** — still cheap without it |
| their data manager (`netmgrd`) killed | **5.3 %** — lower still |
| a live PDP context on our side | 35.0 / 36.0 / 36.8 % — worth nothing |
| the AP's own sleep | not a variable: APSS is awake 100 % on **both** systems |

So the mechanism is looking less like a daemon and more like the **kernel↔modem
interface** — the downstream `rmnet_ipa`/`ipa` driver performs a handshake with the
modem that mainline's `ipa` driver may not, and the pmOS side does expose an
unexplored `modem` node under `/sys/devices/platform/soc@0/7900000.ipa/`. That is
the next thing to read, and it is on our side of the phone.

## ☠️★★★★ 2026-08-28 night — elimination has run out: no userspace daemon on either side explains it

The last vendor daemon: `netmgrd` killed and verified at 0, on top of `ipacm` and
`ipacm-diag` already down — **MPSS awake 5.3 %**, lower than the 8.0 % baseline.

So the oracle's modem is cheap with **every one of its data daemons dead**, and
ours is expensive with **no client having ever spoken to it**. Both APs are awake
100 % of the time. Both run the same modem firmware, on the same network, on the
same cell, on the same hardware.

**That is the end of what elimination can do.** Nine candidates have been tested
and every one is dead:

| candidate | verdict |
|---|---|
| our Linux-side levers (`mmcli --disable`, ModemManager stop, iio-sensor-proxy) | flat |
| our client at all — masked from boot, modem online by one QMI command | **29–37 %** |
| a live PDP context on our side | flat (35.0 / 36.0 / 36.8 %) |
| their IPA daemon (`ipacm`, `ipacm-diag`) | **6.4 %** without it |
| their data manager (`netmgrd`) | **5.3 %** without it |
| modem firmware build | identical on both (425464) |
| access technology | both `lte`, recorded |
| modem power state | a powered-down modem reads 0.0 %, not 6 % |
| the AP's own sleep | APSS awake 100 % on both |

☠️ **The next instrument has to observe rather than subtract.** Every remaining
question is about what the modem itself is doing during its awake time, and nothing
on the AP side can answer it — the modem's SMD edge is silent through the legs
where our duty is 35 %, so it is not telling us. That is the DIAG path: QCSuper is
in the workspace, and on pmOS every DIAG channel is UNBOUND while the oracle's
Android `diag` driver is bound and drained.

**Read the negative correctly**: it is not "there is nothing to find". Two systems
that differ five-fold on the same hardware differ *somewhere*, and every place a
subtraction could reach has now been checked. The remaining place is inside the
modem, which is exactly where the one instrument never used points.

## ★★★ 2026-08-29 — the DIAG path is open on mainline: r78 and one ioctl

Elimination had run out, so the next instrument had to observe the modem rather
than subtract from around it. On pmOS all seven DIAG channels sat `UNBOUND`,
and the reason was one kernel symbol: `CONFIG_RPMSG_CHAR=m` was set but
**`CONFIG_RPMSG_CTRL` was not**, and without it userspace cannot create an
endpoint on an rpmsg device at all.

**r78 is that config, and nothing else** — same `_commit`, in the shape of the r67
kprobes bump. Deployed by the hand-copy route with the net intact (`vmlinuz-r78`
default, r77 and r76 as labels), running as `#79-fp3`.

☠️ **Binding through sysfs does not work and is the wrong door.** `echo
remoteproc0:smd-edge.DIAG.-1.-1 > /sys/bus/rpmsg/drivers/rpmsg_chrdev/bind`
fails; the channel is opened through the *control* device with
`RPMSG_CREATE_EPT_IOCTL` (`0x4028B501`, `struct rpmsg_endpoint_info { char
name[32]; __u32 src; __u32 dst; }`). The modem edge is `remoteproc0`, whose
control node is `/dev/rpmsg_ctrl3` — ☠️ **the ctrl index does not follow the
remoteproc index**; read `/sys/class/rpmsg/rpmsg_ctrl*/device` to map them
(`rpmsg_ctrl0 → remoteproc:`, `1 → remoteproc2:`, `2 → remoteproc1:`,
`3 → remoteproc0:`).

```sh
python3 rpmsg_ept.py /dev/rpmsg_ctrl3 DIAG    # -> /dev/rpmsg0
```

That is the first time this device's modem DIAG interface has been reachable on
mainline.

**First reading: the modem sends nothing unprompted.** `/tmp/diag.bin` was 0 bytes
after the channel had been held open — DIAG is request/response, so the logging
masks have to be set before anything arrives. That is the next step.

☠️ **And the first duty measurement on the new kernel is void**: it ran in the
minutes after the reboot, `mmcli` still answered "couldn't find modem", and it
read 44.4 %. A window taken before the modem has registered is not a window about
the modem's idle behaviour. Re-run with `state: registered` confirmed first — the
same discipline the `modem-window.sh` capture was built to enforce, forgotten
within an hour of building it.

## ☠️ 2026-08-29 — the IPCRTR link is not the lever either, and the edge rings without a listener

The last AP-side consumer the modem has. A-B-A′ unbinding the modem's `IPCRTR`
rpmsg device from `qcom_smd_qrtr` —
[`captures/2026-08-29_ipcrtr-unbind-ab/`](captures/2026-08-29_ipcrtr-unbind-ab/):

| leg | driver bound | MPSS awake | **edge IRQ/s** | PRONTO |
|---|---|---|---|---|
| A | `qcom_smd_qrtr` | 51.9 % | 36.6 | 20.3 % |
| B | **unbound** | 47.0 % | **35.6** | 22.2 % |
| A′ | `qcom_smd_qrtr` | 51.1 % | 37.2 | 27.2 % |

A 5-point dip inside a day's spread of 29–52 %: not a lever.

★ **But the edge column is a finding.** With the qrtr driver detached from the
channel — nobody on the AP listening at all — **the modem still rings the SMD edge
at the same rate.** Together with the RAT legs (34.7 / 35.0 / 35.6 across LTE and
2G) that makes the ring independent of the radio technology, of the modem's own
awake duty, *and* of whether anything on this side is connected to it. It is not
traffic and not a response; it is something the modem does.

☠️ **And a confound in my own instrument, caught by its own numbers.** Every window
on this boot has read 47–52 % where the previous boot read 33–37 % — and since
01:46 two DIAG endpoints that I created have been sitting open. Which way that cuts
is not knowable from the runs already taken, because none of them has a leg without
them. Rebooted with no endpoints created, waited for `state: registered`, and
re-measured; until that lands, **every duty figure taken after 01:46 is quoted with
the caveat that an instrument of mine was attached to the thing being measured.**

## ☠️★★ 2026-08-29 — the duty is a boot-level property, not a stable number, and that re-grades half of tonight's negatives

The confound check: rebooted with **no DIAG endpoints created**, waited for
`state: registered`, four minutes of settle, two windows —
[`captures/2026-08-29_nodiag-baseline/`](captures/2026-08-29_nodiag-baseline/):

| window | MPSS awake | edge IRQ/s |
|---|---|---|
| first | **47.9 %** | 37.9 |
| second | **46.2 %** | 36.6 |

**My endpoints were not the cause.** But the number is still 46–48 % where the
previous boot sat at 33–37 %, so the level is a property of *the boot*, not of the
configuration under test. Every pmOS reading so far, in order:

| boot | windows |
|---|---|
| r77 (`#78-fp3`), afternoon | 29.1, 33.3, 34.2, 34.8, 35.0, 36.0, 36.8, 37.1 % |
| r78 (`#79-fp3`), night | 44.4, 46.2, 47.0, 47.9, 49.5, 49.7, 51.1, 51.9 % |

Two tight clusters, ~13 points apart, with the boot as the only thing that changed
between them. The oracle, across two boots and five windows, stayed at 5.3–8.0 %.

**What this re-grades.** A single leg compared against "the baseline" is worthless
here; only runs carrying their own control leg survive:

| result | still stands? |
|---|---|
| RAT: LTE 34.8 / 2G 6.5 / LTE 34.2 % | ✅ A-B-A′, A and A′ 0.6 points apart |
| bearer: 35.0 / 36.0 / 36.8 % | ✅ A-B-A′, flat |
| radio-low: leg B **0.0 %**, 186 of 186 | ✅ a floor, not a shift |
| IPCRTR unbind: 51.9 / 47.0 / 51.1 % | ✅ A-B-A′, and the dip is inside the boot's own spread |
| **DIAG endpoint open: 49.5 / 49.7 %** | ❌ **weak** — no control leg, and it is now clear the whole boot sat at 46–52 % |
| ModemManager masked: 29.1 / 37.1 % | ⚠️ on the low-cluster boot, so consistent with that boot's baseline — the acquittal holds, but as "indistinguishable from this boot's normal", not as a measured null |

☠️ **The rule this earns**: on this phone the modem's duty has a per-boot offset
big enough to swallow any effect smaller than about 15 points. A knob is only
tested by a run that carries its own A and A′ *inside the same boot* — which is
what `burst-master-knob.sh` does and what the loose single windows did not.

## ★★★★ 2026-08-29 — the duty is set at boot and does not decay, and the edge ring is a 35 Hz metronome

Forty-six 360 s windows across one boot, 48 s to 4.8 h of uptime, modem confirmed
`registered` on `lte` before the first —
[`captures/2026-08-29_duty-vs-uptime/`](captures/2026-08-29_duty-vs-uptime/):

| uptime band | n | MPSS awake, median | min–max | edge IRQ/s |
|---|---|---|---|---|
| 0–1 h | 10 | **49.7 %** | 44.2–52.9 | 35.2 |
| 1–3 h | 19 | **49.5 %** | 46.2–56.6 | 35.0 |
| 3–5 h | 17 | **50.0 %** | 46.0–54.9 | 35.2 |

Least-squares slope over the whole run: **+0.36 %/hour** — flat.

**So "post-boot decay" is dead and "per-boot level" stands.** The r77 boot's windows
were taken 3–7 h in and clustered at 29–37 %; this boot sat at 46–55 % from
48 seconds of uptime to nearly five hours. The level is fixed at boot and stays
there.

☠️ **The rule that follows is stricter than the one written last night.** It is not
"match the uptime" — it is that **a comparison is only valid inside one boot**, and
a reboot in the middle of an experiment invalidates it entirely. The A-B-A′ form
was already doing this by accident; now it is the reason.

★ **And the edge ring is a metronome.** `edge_irq_per_s` reads **34.1–36.2 across
all forty-six windows and 4.8 hours**, a spread of about 6 %. Put beside the other
things that do not move it — the RAT (34.7/35.0/35.6 across LTE and 2G), the modem's
own awake duty (which varies 46–56 % in this very run while the ring does not), and
unbinding `qcom_smd_qrtr` so that nothing on the AP is listening (36.6/35.6/37.2) —
the modem's SMD edge is a **fixed ~35 Hz heartbeat that is independent of
everything measured so far**.

That is worth stating plainly because of what it costs: 35 interrupts per second is
by itself enough to make s2idle residency impossible, whatever else is fixed. The
consumption front and the responsiveness front were shown to be independent
yesterday; this says the second one has a single, constant, so-far-immovable cause.

### What is now open, in order

1. **What differs between boots** to set the level at 35 % or 50 %? It is the one
   variable with a 15-point effect and no explanation. Cheap to sample: reboot
   twice more and take one window each.
2. **The DIAG data channel**, gated on the `DIAG_ID` exchange — recipe in
   [`leads/diag-bringup.md`](leads/diag-bringup.md).
3. The 35 Hz ring itself, which nothing on the AP side has moved.

## 2026-08-29 — the boot level follows the band the network hands out

Nine boots, one 6-minute window each, everything that might explain the level
recorded beside it (`tools/boot-level-sample.sh`):

| boot | cell | band | channel | signal | MPSS duty |
|---|---|---|---|---|---|
| 1 | 1470762 | eutran-1 (2100 MHz) | 500 | 81 % | **48.9 %** |
| 2 | 1470732 | eutran-3 (1800 MHz) | 1300 | 80 % | 36.8 % |
| 3–9 | 1470732 | eutran-3 (1800 MHz) | 1300 | 71–80 % | 26.5–31.6 %, median **29.1 %** |

The network put the phone on the same cell in eight boots out of nine, so the
high leg is n=1 and the table on its own is a suggestion, not a result: **a
correlation with one point on one side is a coincidence until the variable is
forced**. What it does buy is a lever to force — and the lever exists:
`mmcli -m 0 --set-current-bands=eutran-1` moved the modem onto cell 1470762 at
channel 500 within 25 seconds, the very cell the 48.9 % window was taken on.

So the question became answerable inside one boot, which is the only place the
previous entry allows it to be asked. `tools/band-ab.sh` runs A(eutran-3) →
B(eutran-1) → A′(eutran-3), records `--nas-get-rf-band-info` around every leg —
☠️ the witness watches the band, the variable the lever moves, not the modem's
power state — and writes the original band list back at the end so the run does
not leave the modem pinned.

☠️ Note the ring: `edge_per_s` reads **38.8–47.8** in these nine windows against
34.1–36.2 in the forty-six windows of the previous entry. The metronome is
constant *within* a boot and steps *between* boots, exactly like the duty. It is
a second quantity that gets its value at boot.

## 2026-08-29 — the band is a real lever, in both orders, and it is worth ~12 mA

The suggestion from the nine boots was forced, twice, inside single boots and in
**both orders** so that a monotone drift could not produce it
(`tools/band-ab.sh`, 360 s per leg, ~184 samples each):

| run | leg 1 | leg 2 | leg 3 |
|---|---|---|---|
| A-B-A′ | eutran-3 **39.7 %** | eutran-1 **48.4 %** | eutran-3 **33.7 %** |
| B-A-B′ | eutran-1 **52.7 %** | eutran-3 **36.4 %** | eutran-1 **50.0 %** |

| band | windows | median |
|---|---|---|
| eutran-1 (2100 MHz, channel 500, cell 1470762) | 48.4 / 52.7 / 50.0 | **50.0 %** |
| eutran-3 (1800 MHz, channel 1300, cell 1470732) | 39.7 / 33.7 / 36.4 | **36.4 %** |

**≈ 14 points of MPSS duty, about 12 mA.** The within-order drift is 6.0 points in
the first run and 2.7 in the second, so the effect is two to five times the noise
it has to beat, and it points the same way whichever band is measured first. This
also settles the previous entry's open question: what differs between boots to set
the level is, at least in part, **which band the network hands out**, and the
per-boot fixity was the network's choice being fixed, not the modem's state
decaying.

★ **It is not link budget.** The expensive band is the one with the *better*
reported signal — 81 % on eutran-1 against 71–80 % on eutran-3 — so "the modem
works harder because reception is worse" is the wrong way round here. Whatever
costs the 14 points is a property of the carrier or the cell, not of how hard the
receiver has to strain.

★ And the ring does not care: `edge_per_s` reads 35.5 / 35.7 / 35.3 and
35.6 / 35.0 / 35.0 across the six legs. The ~35 Hz metronome survives a band
change, as it survived a RAT change, a duty change and having nothing listening.

### What this is and is not

It is **12 mA of a 40 mA gap**, measured, and unlike 2G it is a configuration a
device could in principle carry. It is **not** a fix to ship as it stands: pinning
a phone to one LTE band trades coverage for power in a way no user asked for, and
the number was measured on one operator at one location. What it is, squarely, is
the first handle on the mechanism — the modem's idle cost here is set by what the
network gives it, and that is a lead worth following before it is a knob worth
turning.

☠️ **Two instrument bugs, both in the restore path**, both found by reading the log
rather than by the run failing. The band-list capture used a `sed` range that ran
past mmcli's wrapped list and swallowed the rest of the dump; and what mmcli
*prints* as the current bands (`gsm-umts, lte`) is a shorthand it will not accept
back, so writing it back could never work. The first run therefore left the modem
pinned. Restoring is now unconditional `--set-current-bands=any`. **A restore that
has only ever been observed on the path where it fails has not been tested.**

## ☠️☠️ 2026-08-29 — the "35 Hz modem metronome" is the RPM, and it was my own column

**Retracted:** every statement in the last two days that the *modem's* SMD edge
rings at a fixed ~35 Hz. It does not. Measured over 120 s on an idle phone, by
hardware IRQ:

| edge | GIC hwirq | rate |
|---|---|---|
| **RPM** (`rpm-proc`, SPI 168) | 200 | **13.29 /s** |
| ADSP (`lpass`, SPI 289) | 321 | 0.00 /s |
| WCNSS (`pronto`, SPI 142) | 174 | 0.39 /s |
| **MPSS** (the modem, SPI 25) | 57 | **0.07 /s** |

The modem's SMD edge fires **once every fourteen seconds**. The ring that has been
quoted all along is the **RPM's**, and of course it is independent of the RAT, of
the modem's awake duty and of whether anything is listening to the modem — it is a
different processor.

☠️ **And the instrument was not wrong; the reading was.** `burst-master.sh` logs
two columns: `edge_irq_per_s`, which sums *every* smd/smp2p/glink/ipcc/ipa
interrupt, and `modem_irq_per_s`, which it selects by hardware IRQ number
(`/smd-edge/ && $(NF-2) == 57`) — the modem alone, correctly. The tool computed the
right number and printed it beside the wrong one, and every conclusion quoted the
sum. **A summary column next to a specific one will be read as the specific one
unless its name forbids it.** `edge_irq_per_s` should have been `smd_irq_total_per_s`
from the start.

### What this changes, and it is not only a subtraction

The consumption story is untouched — it never rested on the ring. What changes is
the **responsiveness** story, and it changes for the better:

- The old claim was that 35 wakes/s from the modem made s2idle residency
  impossible and that nothing on the AP side could move it. That is now the wrong
  way round. The traffic is **ours**: the AP↔RPM channel carries every clock,
  regulator, bus and power-domain request this system makes, and at idle it is
  making **thirteen a second**.
- Which means it is **reducible in principle**, by finding out what is asking. That
  is an AP-side question with AP-side instruments, unlike everything the modem
  front has run into.

☠️ It also means the two fronts are **not** independent for the reason previously
given. They may still be independent, but the argument for it was built on a
counter belonging to the wrong processor.
