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
   deep-sleep work is the **modem-lead** (RUNBOOK), not any RPM mode counter.

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
