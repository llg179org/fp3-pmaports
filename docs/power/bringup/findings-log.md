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
