# Running a night unattended

> ⚠️ **AI-generated.** Maintained by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

The measurements that answer "where does the idle current go" take four to eight
hours each and every one of them needs a full pack first. Until 2026-08-19 each
was hand-launched with a host-side poller babysitting it, which capped a night at
whatever one leg could fill and put a human at every handover. This directory is
what makes a night run itself.

**It is four pieces and one rule.** The rule is that no piece may leave the phone
worse than it found it: the charger comes back on every exit path, the record
survives the filesystem it is written on, and a phone that dies at 02:00 is found
alive at 08:00.

| piece | side | what it does |
|---|---|---|
| [`preflight.sh`](preflight.sh) | device | the gate. Fourteen checks; a failure means do not arm |
| [`guardian.sh`](guardian.sh) | device | the net. Watches the eMMC, the pack and the RPM counters, and acts |
| [`queue.sh`](queue.sh) | device | the runner. Works through a job file, charging between jobs |
| [`night-supervisor.sh`](night-supervisor.sh) | **host** | pulls the record off the phone every poll and notices silence |

## Why there is a gate at all

Every check in `preflight.sh` exists because its absence cost something:

- **`root-rw`** — `emergency_ro` is invisible to a reader. Only a write finds it.
- **`boot-default` / `boot-fallback`** — a boot change repeats on every boot and
  this device has no console. The fallback label is the entire recovery story, so
  the check is that the files it names exist, not that the stanza is present.
- **`charger`** — ☠️ `USBIN_SUSPEND_BIT` lives in the PMIC and survives a warm
  reboot. A leg that died without restoring it hands over a phone that silently
  will not charge, and the next night starts from a pack that only falls.
- **`no-stale-units`** — phase A measures suspends. Another script waking the
  phone once a minute measures the instrument instead.
- **`rpm-stats`** — ☠️ `rpm_master_stats` is a module and nothing autoloads it.
  Without it the whole APSS column reads `?`, which looks exactly like "the
  processor never collapsed".
- **`counters-live`** — the check that makes a convenient zero believable: read
  the masters twice and require that at least two moved. This is what turned
  "LPASS shut down twice since boot" from a suspicious number into a finding.
- **`mem-sleep`** — ☠️ there is no `deep` here. A plan that waits for it waits
  forever.
- **`dpms`** — ☠️ `backlight = 0` is not `dpms off`, and the difference was
  +24.5 mA on every floor measured before it was noticed.
- **`mmc-clean`** — if the card has already errored this boot, reboot first.

☠️ **A gate has to exclude the thing that is asking.** The first armed night
aborted in twenty seconds: `no-stale-units` listed `night-queue`, and the queue
runs the gate as its own first step, so the check failed on itself. The gate was
right to fail loudly and right to abort — that is what it is for — but a
condition the caller always satisfies is not a check, it is a stop.

## Why there is a net

On 2026-08-18 the eMMC stopped answering (`-110`), root went `emergency_ro`, and
from that moment the journal held nothing but its own failure to write. A reboot
cleared it completely. It has not recurred across the four long runs since,
including two overnight-length ones — but **"it has not recurred" is not a
mechanism**, and the way to run anyway is not hope, it is a net.

`guardian.sh` is [`../tools/emmc-watch.sh`](../tools/emmc-watch.sh) plus an
action:

1. ☠️ **Its log lives on tmpfs.** `/run` survives a read-only root, which is the
   entire reason it is not a journal grep.
2. **It writes every cycle.** That write *is* the detector.
3. **On two consecutive failures it acts**: dumps the evidence, restores the
   charger and reboots — so the morning finds a live phone with a timestamped
   record instead of a dead one with none. Two failures, not one, because a
   single failed write during a busy moment is not a card off the bus.
4. ☠️ **The charger is restored before the reboot, always.** Rebooting with USBIN
   suspended produces a phone that will not charge, which is a worse morning than
   the one being rescued.
5. **It watches the pack**, well below any leg's own floor, so a leg that loses
   control of its descent does not end on a flat battery.

## Arming a night

```sh
# 1. host: check the gate first, and read it
ssh fp3@192.168.100.17 'echo 147147 | sudo -S /root/night/preflight.sh 2>/dev/null'

# 2. device: the net, before anything else
sudo systemd-run --unit=night-guardian --collect /root/night/guardian.sh 30

# 3. device: the night itself
sudo systemd-run --unit=night-queue --collect /root/night/queue.sh /root/night/jobs.txt lpass

# 4. host: the supervisor, which pulls the record every poll
docs/power/bringup/night/night-supervisor.sh lpass-20260819 300 12
```

☠️ **Everything on the device runs under `systemd-run`, never in the foreground
over ssh.** An ssh timeout once killed a probe mid-script and left the modem and
the ADSP unbound with nothing running to rebind them.

☠️ **The queue refuses to start without the guardian.** That is deliberate: the
reason long unattended runs were barred is that the one failure this device has
shown destroys its own record.

## The job file

```
@preflight 95            # the gate; a failure aborts the whole queue
@note anything worth a line in the log
@timeout 21600           # wall-clock cap per job from here on
@charge 99 180           # wait for the pack, up to 180 minutes
/root/night/lpass-holders.sh 240 30
@charge 99 240
/root/slope-leg.sh lpass-cut-20260820
```

Output goes to `/run/night/`: `queue.log` for the timeline, one numbered file per
job, `guardian.log` for the net, `evidence-*.txt` if the net ever fires. All of
it is tmpfs — the supervisor pulls it to `runs/<tag>/` on the host every poll,
because the guardian's answer to a dead card is a reboot and a reboot is exactly
what tmpfs does not survive.

## What runs first, and why

[`lpass-holders.sh`](lpass-holders.sh) — step 1 of the deep-sleep chain, and the
reason the harness was built now. `qcom_stats/vlow` has read **Count: 0** in every
capture this investigation has ever taken, and the named mechanism for that gate
is in [`../leads/lpass-never-sleeps.md`](../leads/lpass-never-sleeps.md): the
audio DSP has shut down **twice since boot, 0.12 s in total**, against 4344
shutdowns on the vendor stack on the same hardware.

The script removes the ADSP's clients in six stages — sensor userspace, SMGR
drivers, audio userspace, the q6 stack, then the DSP itself — and after each one
re-reads all five masters over a full dwell.

☠️ **Every stage re-verifies the counter is live**, because a zero from a stuck
file and a zero from a DSP that never sleeps look identical. And ☠️ **nothing
here becomes a patch until the counter moves**: the XO branch was mechanically
plausible, moved its own counter from 0 to 1952, and changed the discharge slope
by nothing.
