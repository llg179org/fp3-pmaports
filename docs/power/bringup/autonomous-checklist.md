# Autonomous run checklist

> ⚠️ **AI-generated.** Maintained by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

What has to be true before, during and after an unattended measurement session
on this phone. It is a **method** page: it states the command, never its current
answer. The current state of the investigation is in
[`../../STATUS.md`](../../STATUS.md); what is still open is in
[`../../TODO.md`](../../TODO.md).

Every line here exists because it was once got wrong and cost a run.

## 0. Before anything — is the phone reachable and is it ours?

```sh
ssh fp3 'uname -a; uptime; cat /proc/cmdline | tr " " "\n" | grep -i slot'
```

* The link is `fp3` (USB, 172.16.42.1) **and** `192.168.100.17` (wlan). ☠️ A run
  that takes the wlan radio down must not be driven over the wlan address —
  `burst-wlan-ab.sh` refuses, nothing else does.
* Read the kernel revision **off the device**, never off a doc page. That
  paragraph in `TODO.md` has gone stale five times.

## 1. Brick safety — the gates that must not be skipped

* **No flashing during an unattended block** unless the run is explicitly a
  kernel test with the `fp3-kernel-test` gates satisfied. A measurement session
  changes no boot artefact.
* ☠️ **Never restart the modem remoteproc** (`/sys/class/remoteproc/*/state`).
  It costs audio until the next reboot, and a mixer write afterwards oopses the
  kernel. To take the modem *off the air* use `mmcli --disable`, which stops the
  RF and leaves the MSS firmware running — and know that this is a different cut.
* If the phone does not come back: the recovery route is `fp3-kernel-test`'s
  `references/recovery.md`. ☠️ `fastboot boot` does nothing on this bootloader.

## 2. Charge state — the one that silently ruins a measurement

On pmOS the input is cut and restored through the **charger** node:

```sh
echo Unknown  > /sys/class/power_supply/pmi632-charger/status   # cut
echo Charging > /sys/class/power_supply/pmi632-charger/status   # restore
```

☠️ `input_suspend` is the **Ubuntu Touch** path (`pmi632-battery/input_suspend`);
it does not exist on mainline. The bit it drives lives in the PMIC and survives a
warm reboot — restore before any reboot, on both systems.

* Before a run: `status` must be `Charging`/`Full`, and the pack must be where
  the instrument needs it. Most instruments have a capacity floor;
  `discharge-run.sh` deliberately has none, because the pack is what it measures.
* After every run, on every exit path: **restore the input unconditionally and
  idempotently.** A trap that only fires on success is not a trap.
* `capacity` is not charge, `current_now` is not energy, and an event count is
  not a level. ☠️ **Packets are not power.**

## 3. Measurement hygiene

* **Run instruments under `systemd-run --unit=… --collect`, never in the
  foreground over ssh.** An ssh timeout once killed a probe mid-script and left
  the modem and the ADSP unbound with nothing to rebind them.
* ☠️ **Never reinstall an instrument on the device while a run that invokes it is
  in flight.** The A-B-A′ wrappers exec `/usr/local/bin/<tool>` once per leg, so
  replacing the file between legs silently makes the legs incomparable — and the
  capture carries no record that it happened. Stage the new version locally, and
  install it after the unit has exited.
* **Do not poll the phone while a leg is running.** 74 ssh logins in 70 minutes
  measured **18.3 mA** — the observer was a fifth of the thing observed. Poll at
  400–700 s, or not at all, and read the capture when the unit exits.
* **Every comparison carries a control leg (A-B-A′).** The A↔A′ spread is the
  noise floor; an effect smaller than it is not an effect. `burst-knob-ab.sh`
  exists so the fourth near-identical A-B-A′ is not written by hand.
* **Report the floor (p10) and the median, never a mean** — the distribution is
  bursty and a mean hides both ends. Say which statistic cleared its own spread
  and which did not.
* **Prove the panel is dark on every sample**, not once at the start. Writing
  `blank`/`dpms` alone fails under DRM master; the session has to be locked so
  the compositor blanks it. `idle-ab.sh` owns that, the panel witness and the
  charge cut — wrap it, do not reimplement it.
* **Measure what you actually wrote.** A per-sample cost benchmarked with a
  globbed `cat` said "under 1 ms" for a loop that took over 2 s and dropped a
  seventh of the samples. Count the samples the run returned against the samples
  it was due.
* **A mark that is written but not honoured is worse than no mark** — the file
  then *looks* filtered. `burst-attrib.sh` appends its `# window_from=` cutoff at
  the **end**, so every reader of it needs two passes.

## 3b. Before measuring, grep the captures

`captures/` is indexed by date and by the question that prompted each run, not by
what the file happens to contain. ☠️ On 2026-08-27 the plan of record was to spend
a **slot switch** re-taking an oracle measurement that had been committed three
days earlier for a different investigation — two snapshots that answered the
question better than the sampling run being planned. One `grep -rl` over
`captures/` cost seconds.

```sh
grep -rln '<the field or counter you are about to sample>' docs/power/bringup/captures/
```

Ask it of the *field*, not of the topic. The capture that answers you was taken by
someone chasing something else.

## 4. Attribution discipline

* Rank a trace and you describe the background; split it by the thing you are
  explaining and you test it. The top workqueue entry was flat across a 9×
  current swing.
* Two instruments that share a layer are one instrument. Reach for a witness with
  a different mechanism — the pack voltage sag settled "is the burst real?" after
  a day of tracepoints could not.
* A shortlist produced by a broken parser is retracted, not patched in prose.

## 5. During the block

* Keep a running log in the capture directory (`analysis.md` beside every
  capture) as the run finishes, not at the end of the session.
* After a compaction, resume from `STATUS.md` + `TODO.md` without asking.
* Commit as work completes. Author `Lajosházi, László Gergely` with
  `Signed-off-by:`, trailer `Co-authored-by: Claude Opus 5`.

## 6. Closing a block

* Restore everything the run cut: charge input, both radios, `debug_mask`,
  any tracing (`tracing_on`, `set_event`), any stopped service.
* Verify with one read, not from memory:

```sh
ssh fp3 'cat /sys/class/power_supply/pmi632-battery/status; nmcli radio wifi; \
  mmcli -m 0 | grep -m1 state:; cat /sys/kernel/debug/tracing/tracing_on'
```

* Write the finding into [`findings-log.md`](findings-log.md) with its date, the
  number **and its spread**, and what it rules out — including the stories it
  kills.
* Where the note goes: *would this be wrong next month?* → `docs/`. *Would this
  still be true on a different phone?* → the skill. A dated log → `archive/`.
