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
know what to do next, that is [`RUNBOOK.md`](RUNBOOK.md).

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

Full working in [`RUNBOOK.md`](RUNBOOK.md).

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
