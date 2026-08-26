# The instruments

> ⚠️ **AI-generated.** Maintained by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

Everything that measured a number in [`../../README.md`](../../README.md). They
are kept together because most of the mistakes in this investigation were
instrument mistakes, not reasoning mistakes, and the fix always ended up written
into the script that made it.

☠️ **Run every one of these under `systemd-run --unit=… --collect`, never in the
foreground over ssh.** An ssh timeout once killed a probe mid-script and left the
modem and the ADSP unbound with nothing running to rebind them. The unattended
wrapper for all of it is [`../night/`](../night/README.md).

## Measuring a current

| tool | the question it answers |
|---|---|
| [`slope-leg.sh`](slope-leg.sh) | **the workhorse.** A discharge-slope leg with an arbitrary cut applied: descend, settle, six sleeps, then six awake controls. ☠️ Compare phase-A slopes between legs directly; the derived mA is for scale only |
| [`slope-fit.py`](slope-fit.py) | reduce a slope run to a current: `I_sleep = I_awake × (slope_A / slope_B)` |
| [`suspend-slope.sh`](suspend-slope.sh), [`suspend-leg.sh`](suspend-leg.sh) | the earlier, single-purpose versions `slope-leg.sh` generalises |
| [`idle-leg.sh`](idle-leg.sh) | one leg of an awake idle measurement |
| [`await-charge.sh`](await-charge.sh) | wait for a full pack, then `exec` the next measurement — so one transient unit covers the whole chain |

## Decomposing the awake floor

| tool | the question it answers |
|---|---|
| [`idle-ladder.sh`](idle-ladder.sh) | one-boot cumulative subtraction, S0–S5 plus a restore control. ☠️ A cumulative ladder attributes any episode inside a stage to that stage's cut — use it to generate candidates, not to price them |
| [`idle-ladder-fit.py`](idle-ladder-fit.py) | the floor (p10) with a bootstrap SE, the median with its own, and every marginal marked when it is inside the noise |
| [`freq-probe.sh`](freq-probe.sh) | the controlled three-phase version: baseline, cut, restored, in one boot. This is what refuted the ladder's "the modem costs 84 mA" |
| [`de-compare.sh`](de-compare.sh), [`de-compare-fit.py`](de-compare-fit.py), [`de-switch.sh`](de-switch.sh) | one desktop environment against another, and the greetd switch that arranges it |

## Comparing the two systems

The goal stated 2026-08-24 is a comparison — pmOS down to the oracle's level or
below — so the numbers on the two sides have to come from one instrument on one
protocol, or they are two measurements rather than a comparison.

| tool | the question it answers |
|---|---|
| [`idle-ab.sh`](idle-ab.sh) | **the instrument the goal is scored on.** The same awake-idle measurement on pmOS and on Ubuntu Touch: panel off, on battery with the cable still in, radio up. Reports the floor (p10) and the median, never a mean, and integrates `bms/cc_soc` where the gauge exists |
| [`panel-witness.sh`](panel-witness.sh) | every candidate answer to "is the panel actually off", printed side by side, so the disagreement between them is visible instead of one being picked and called proof |

☠️ **Each single panel witness has already lied once**, which is why
`panel-witness.sh` prints all of them: the oracle sat fully powered at backlight
brightness 37–38; `setScreenPowerMode("off")` returned `true` over a lit panel;
`/sys/class/drm/*/dpms` is owned by the compositor and a good run was declared
invalid on it. The one that does not lie is the panel bias rail — and ☠️ **read
its `state`/`enable`, never its `microvolts`**: measured 2026-08-26, across a
`blank=4` that demonstrably powered the panel down, `lcdb_ldo`/`lcdb_ncp` went
`enabled → disabled` while `microvolts` did not move off 5500000, because that
file reports the rail's *configured* voltage. Reading the voltage is very
probably the origin of the claim that `fb0/blank` is only a half blank.

☠️ And until 2026-08-26 `idle-ab.sh` proved the panel dark **once, at the door**,
then measured for an hour without looking again — on the exact question it exists
to settle. It now carries the panel state in every sample and refuses to report a
floor from a window the panel relit inside.

## Getting to the other system

| tool | the question it answers |
|---|---|
| [`gptattr.py`](gptattr.py) | read, and flip, the Qualcomm A/B boot-control attribute bits in the GPT — the whole slot-switch mechanism on this eMMC device |

☠️ **`qbootctl -s <slot>` cannot switch slots on this phone.** It aborts in a UFS
`bLun` step (`Unable to open '/dev/bsg/ufs-bsg0'`) that has no meaning on eMMC,
and the `-i` flag its own help text advertises for exactly that case is **not
implemented** in the packaged build — getopt answers `unrecognized option: i`.
Reading works, so `qbootctl` remains a useful independent check on what
`gptattr.py` wrote. Measured 2026-08-26 on `qbootctl-0.2.2-r1`, the newest in
Alpine edge.

The attribute layout is Qualcomm's, not the generic AOSP one: priority 48–49,
active 50, tries 51–53, successful 54, unbootable 55. ☠️ `gptattr.py dump` does
not take that on faith — it XORs the `_a` against the `_b` attribute of every
slotted pair and prints which fields differ, so a wrong layout shows up before
anything is written. On this device exactly one bit differs, bit 50, and
`active` is therefore what the bootloader reads; `gptattr.py active <slot>` flips
that bit and nothing else, rather than rewriting priority, tries and successful
the way a full `set_active` would. ☠️ It also surfaced that **`modem_a` is marked
`unbootable=1 prio=0 tries=0`** — state we did not create, left untouched
deliberately.

## Asking the RPM what it did

| tool | the question it answers |
|---|---|
| [`rail-census.sh`](rail-census.sh), [`rail-census-parse.py`](rail-census-parse.py) | which rails vote active and never vote sleep, traced across a real suspend and decoded against the FP3 rail map |
| [`vlow-probe.sh`](vlow-probe.sh), [`leg3.sh`](leg3.sh), [`leg3-control.sh`](leg3-control.sh) | the sleep-set XO vote: does zeroing it let the RPM reach `vlow`, and is it worth any current |
| [`oracle-capture.sh`](oracle-capture.sh) | the same records from the Ubuntu Touch oracle on `slot_a` — the ground truth for every "is this normal?" question |

☠️ `rpm_master_stats` is a module and nothing autoloads it; without a `modprobe`
the whole APSS column reads `?`, which looks exactly like "the processor never
collapsed". And ☠️ `qcom_stats`' `Client Votes` field is an instantaneous,
fluctuating sample — a before/after pair of it proves nothing.

## Watching for something rare

| tool | the question it answers |
|---|---|
| [`emmc-watch.sh`](emmc-watch.sh) | did the card fall off the bus, and what was the RPM doing when it did. ☠️ Logs to tmpfs, because the filesystem it watches is the one that dies. Superseded for unattended use by [`../night/guardian.sh`](../night/guardian.sh), which also acts |
| [`episode-watch.sh`](episode-watch.sh) | the unexplained 44-minute episode of 2026-08-18. ☠️ Must never run during a suspend leg — a sampler once a minute is a wakeup once a minute |
| [`pll-sweep.sh`](pll-sweep.sh), [`pll-vs-voltage.sh`](pll-vs-voltage.sh), [`pll-ramp-fit.py`](pll-ramp-fit.py) | the `apcs-cpu0-pll` failures: how often, and whether they depend on pack voltage. They do not — 7.3 per 10 000 transitions, flat from 4.32 V to 3.93 V |
