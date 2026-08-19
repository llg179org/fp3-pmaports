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
