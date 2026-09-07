# #182 — the modem does not survive resume, and the fault could not be reproduced from here

**2026-09-06 late evening**, pmOS `linux-fp3-7.1.3-r88` (`6113869dcc3d`).

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, whose call is the measurement that found this.

## The fault, as it happened

```
23:04:02  [sleep-monitor-systemd] ready to sleep; dropping inhibitor
23:23:38  [sleep-monitor-systemd] system is resuming        <- an INCOMING CALL woke it
23:23:42  [device qcom-soc] creating modem with plugin 'qcom-soc' and '2' ports
23:23:42  [base-manager] couldn't create modem for device 'qcom-soc':
          Unsupported device: at least a QMI port is required
```

19 min 36 s of real suspend, `suspend_stats/success = 1`, woken by the call —
and then **no modem**. `mmcli -L` reported none while the firmware was fine
(three remoteprocs `running`, `qmicli -d qrtr://0 --dms-get-model` answering
normally). The phone had no cellular service until ModemManager was restarted,
after which it returned immediately. The operator saw the backlight come on after
~3 rings, no answer button, and **no ring** — there was nothing to ring it.

## What was tried, and what it rules out

Controlled `rtcwake` suspend/resume cycles, each timing how long after resume the
QMI transport first answers:

| run | state | asked | actually suspended | QMI back | modem |
|---|---|---:|---:|---:|---|
| 1 | session's dirty state, MM restarted 23:24 | 30 s | 32 s | **+0 s** | survived |
| 2 | **clean boot**, MM up since 23:32:20 | 600 s | ~100 s | **+0 s** | survived |
| 3 | clean boot | 900 s | **24 s** | **+0 s** | survived |

★ **The reboot was the operator's idea and it earned its place**: without it,
run 1 could be dismissed as an artefact of a ModemManager this session had
restarted by hand. Runs 2 and 3 are on the installed configuration as it comes
up.

So: **short suspends do not reproduce the fault.** Two of the three differences
from the failing case are now the candidates —

- **duration**: 24–100 s here against 19 min 36 s when it failed;
- **wake source**: an RTC alarm here against an incoming call there.

## ★★ The control that narrows it to ONE variable

Run 3 asked for 900 s and resumed after **24 s**. That was first written up here
as "the ssh session keeps waking it" — **wrong, and withdrawn**. The journal
names the waker exactly:

```
23:36:43  [modem0/call0] call state changed: unknown -> ringing-in (incoming-new)
23:36:43  gnome-calls: New incoming call
23:36:49  [modem0/call0] call state changed: ringing-in -> terminated
```

The operator rang the phone during the run. So run 3 is not a failed long
suspend — it is a **second call-wake test**, and this one **worked end to end**:
the modem survived, the call arrived, and the phone rang.

| suspend | woken by | modem after | rang? |
|---|---|---|---|
| **19 min 36 s** | incoming call | **lost** | **no** |
| **24 s** | incoming call | survived | **yes** |

Same wake path, same configuration, same clean-boot ModemManager. **The only
remaining variable is the duration of the suspend.** The wake-source candidate
is eliminated.

## ☠️ Why it could not be pushed further tonight

Every attempt to hold the phone down longer failed: 900 s was requested and it
resumed after **24 s**, with **no `wakeup_source` showing a `wakeup_count`** to
name what woke it.

~~The leading explanation is the instrument itself: the ssh session over the USB
gadget keeps waking it.~~ **Withdrawn — see the control above.** The waker was
the operator's call, named in the journal. `wakeup_sources` did not attribute it,
which is worth remembering: **that file did not name a waker that the modem's own
log named plainly.**

What remains true is that no run here stayed down long enough. Reaching a
20-minute suspend needs ~20 minutes of nobody touching the phone, and it is
worth noting that the successful long suspend happened with nothing connected —
whether that matters is now **untested**, not suspected.

## ★★★ REPRODUCED, and the mechanism is a race — 2026-09-07 00:06

The untested cell was filled by the operator, who chose to call at ~10 minutes
rather than wait for morning:

```
00:06:08  [sleep-monitor-systemd] ready to sleep; dropping inhibitor
00:16:31  [sleep-monitor-systemd] system is resuming     <- 10 min 23 s, woken by the call
00:16:35  [device qcom-soc] creating modem with plugin 'qcom-soc' and '2' ports
00:16:35  [base-manager] couldn't create modem for device 'qcom-soc':
          Unsupported device: at least a QMI port is required
```

`suspend_stats/success` went 2 → 3, `mmcli -L` reported **no modems**, and the
operator saw exactly the earlier symptom: the backlight flashed, the screen
stayed black, **the phone did not ring**.

| suspend | woken by | modem after | rang? |
|---|---|---|---|
| 24 s | incoming call | survived | **yes** |
| **10 min 23 s** | incoming call | **lost** | **no** |
| 19 min 36 s | incoming call | **lost** | **no** |

★ **The QMI port is LATE, not absent.** ModemManager probed **4 seconds** after
resume and found none — and `qmicli -d qrtr://0 --dms-get-model` answered
normally when asked **~30 seconds** later, from the same shell, with nothing
restarted in between. So the transport comes back on its own and MM has already
given up by then: it concludes *unsupported* and never re-probes.

That settles fix candidate (1) from the task: the port is not missing, MM is
early. Candidate (3) — **MM should retry rather than conclude unsupported** — is
therefore the real fix, and candidate (2), restarting MM after resume, is a
workaround whose cost is exactly the first-call latency #181 exists to measure.

☠️ **What is still not known: how late is late.** The gap was measured only as
"failed at +4 s, worked at +30 s". Bracketing it is what tells anyone writing the
retry how long to wait, and it is one more suspend/resume with a poll loop from
+0 s.

## Why the threshold matters, and where it is

24 s survives and 10 min 23 s does not, so the boundary sits between them. The
operator's choice to call at ~10 minutes instead of in the morning is what
produced that bracket: a morning call would have been ~8 hours, far past the
failing point, and would have added nothing to a result already known at 19 min.

## What would settle it, and what it costs

- **A suspend of 15–20 minutes, undisturbed, then one call.** That is the only
  untested cell of the table above, and it is the failing one. It costs twenty
  quiet minutes, not a cable.
- Then, if the long suspend reproduces the loss, the question narrows to whether
  the qrtr QMI port is simply **late** on resume — the script already times that
  — or absent because the modem's QRTR services need re-announcing.

☠️ **#181 stays blocked behind this.** Its morning sample would be a guaranteed
"did not ring", and would read as a reachability result.

## ☠️☠️ WITHDRAWN: "the only remaining variable is the duration"

Three unattended `rtcwake` cycles ran overnight to bracket how late the QMI port
is (`rtcwake-three-cycles.log`). They answered a different question, and they
overturn the section above.

```
cycle 1  resumed after  110 s   QMI at +0 s   modem survived
cycle 2  resumed after    4 s   QMI at +0 s   modem survived
cycle 3  resumed after  665 s   QMI at +0 s   modem survived
```

**Cycle 3 slept for 11 minutes and the modem survived** — longer than the
10 min 23 s suspend that lost it two hours earlier. So duration alone does not
cause it, and the claim that it was "the only remaining variable" is wrong.

With every run on the table, the design is a clean 2×2 and **both factors are
needed**:

| suspend | woken by | modem after |
|---|---|---|
| 24 s | **incoming call** | survived |
| 665 s | RTC alarm | survived |
| 623 s (10 min 23 s) | **incoming call** | **LOST** |
| 1176 s (19 min 36 s) | **incoming call** | **LOST** |

A short suspend woken by a call is fine. A long suspend woken by an RTC alarm is
fine. **Only a long suspend ended by an incoming call loses the modem.**

☠️ That also retires the earlier reasoning that eliminated the wake source: it
was eliminated on the strength of the 24 s call-wake alone, which is now visible
as the *short* arm of the design, not a control for the long one. **One cell of a
2×2 cannot rule out an interaction.**

### What this points at, and what would test it

An RTC wake is a local alarm; a call wake comes **through the modem**, which
raises it over QRTR/glink after the modem itself has been in a low-power state
for minutes. The candidate is therefore that a *long* modem sleep plus a
*modem-originated* wake leaves the QRTR services needing re-announcement, and
ModemManager probes into that window.

☠️ Untested. The instrument would be a QRTR service dump taken at +0 s on resume
in both arms — the same script, one arm woken by RTC and one by a call — which
needs the operator for the call arm.

### The number this run was supposed to produce is still missing

Every cycle reported `QMI transport answered at +0 s`, because in every cycle the
modem had survived and the transport never went away. **How late the port is in
the failing case is still unmeasured**, and it cannot be measured in the
surviving arm.

### ☠️ And a loose end that is still not explained

Cycles 1 and 2 asked for 720 s and slept 110 s and **4 s**. Cycle 3, asking the
same, got 665 s. Something wakes this phone unpredictably during an rtcwake
suspend and it has not been identified; `wakeup_sources` named nothing earlier.
It does not affect the 2×2 — the surviving long arm is cycle 3's real 665 s —
but any future run that needs a guaranteed sleep duration cannot assume it gets
one.

## ☠️☠️ WITHDRAWN: "the QMI port is LATE". It was never away.

The failing arm was run again on 2026-09-07 with a sampler started **before** the
suspend and left running, so it resumes with the system and samples from **+0 s**
without a resume hook.

```
06:44:00  ready to sleep
07:09:08  system is resuming            <- 25 min 08 s, ended by the operator's call
07:09:12  couldn't create modem for device 'qcom-soc':
          Unsupported device: at least a QMI port is required
```

`suspend_stats/success` 6 → 7, `mmcli -L`: **no modems**, and the operator
confirmed: **it did not ring.** The failing arm reproduced exactly.

And the sampler, `qmi-poller-failing-arm.log`:

```
06:44:05  QMI ok        <- last sample before the freeze
07:09:08  QMI ok        <- FIRST sample after resume, +0 s
07:09:09  QMI ok
07:09:10  QMI ok
07:09:11  QMI ok
07:09:12  QMI ok        <- the second MM declared there was no QMI port
...        QMI ok        (not one "NO ANSWER" in the whole file)
```

★ **The QMI transport answered on the very first sample after resume and every
second thereafter — including the second in which ModemManager said there was no
QMI port.** So the port was never late and never absent. **The diagnosis "MM
probes at +4 s and the port arrives later" is wrong and is withdrawn**, together
with the fix it implied: a retry would have found the port present on its first
attempt too, and changed nothing.

### What the evidence says instead

ModemManager's own view of the device is what is broken, not the transport:

```
07:09:12  [device qcom-soc] creating modem with plugin 'qcom-soc' and '2' ports
07:09:12  couldn't create modem: at least a QMI port is required
```

Two ports, and neither is the QMI one — while a working ModemManager lists
`qrtr0 (qmi), rmnet_ipa0 (net)` with `rpmsg_ctrl3` ignored. So the **`qrtr0` port
object is missing from MM's rebuilt device**, and `qrtr0` is not a device node:
it exists only as MM's representation of a node on the QRTR bus, learned through
libqrtr's bus notifications. **MM's QRTR bus watch does not survive suspend, and
nothing re-adds the node.**

That relocates the fix from "retry the probe" to "re-establish the QRTR bus
connection, or re-add its nodes, after resume" — a different change in a
different place, and it would not have been found by making MM retry.

☠️ **The sampler is not a passive observer** — it polls the transport once a
second, so it could in principle have kept something alive. That caveat cuts the
other way here: it means the transport may have been *helped*, and MM still could
not see it, which only strengthens the conclusion that MM's failure is internal.

### The 2×2 stands, and now has a mechanism

| suspend | woken by | modem |
|---|---|---|
| 24 s | incoming call | survived |
| 665 s | RTC alarm | survived |
| 623 s / 1176 s / **1508 s** | incoming call | **LOST** |

Why a *long* suspend and a *call* wake together, when the transport is fine
either way, is still unexplained.

## ★★★ CAUSE FOUND, and it is ours: our debug drop-in disabled the distro's fix

Searching for other people's work **before** writing any code — the rule this
session put into `/msm8953-mainline-pr` — found it in minutes.

ModemManager's own `NEWS` describes a daemon mode in which, on resume, **no
device re-probing from scratch is launched**; the daemon syncs the existing
modem's state instead. In `src/main.c`:

| mode | on resume | |
|---|---|---|
| default | `resuming_cb` → `mm_base_manager_start (manager, FALSE)` | *"re-scanning (resuming)"* — the full rebuild that loses `qrtr0` |
| `--test-quick-suspend-resume` | `resuming_quick_cb` → `mm_base_manager_sync (manager)` | *"syncing modem state"* — nothing is rebuilt, so nothing is lost |

The precondition its NEWS names — *"useful when the WWAN module stays awake
while the host is suspended"* — is **measurably true here**: the modem is what
wakes the AP with an incoming call.

★ **And pmOS already ships it**, `/usr/lib/systemd/system/ModemManager.service.d/quick-suspend-resume.conf`,
dated 2026-08-05:

```ini
# Force the new quick suspend/resume mode until it's the default upstream,
# see: https://gitlab.freedesktop.org/mobile-broadband/ModemManager/-/issues/1039
ExecStart=
ExecStart=/usr/sbin/ModemManager --test-quick-suspend-resume
```

☠️ **Our own debug drop-in removed it.** `/etc/systemd/system/ModemManager.service.d/zz-fp3-debug.conf`,
dated 2026-09-02, clears `ExecStart` and sets only `--log-level=DEBUG`. `/etc`
beats `/usr/lib` and `zz-` sorts last, so it wins. The effective command line,
read from systemd rather than inferred:

```
argv[]=/usr/sbin/ModemManager --log-level=DEBUG
```

So the fault this task chased is very probably **self-inflicted by our own
configuration**, and the distro had already worked around it a month earlier.

### What was changed

`zz-fp3-debug.conf` now carries **both** flags — the debug logging `#75` depends
on, and the workaround — with the reason written into the file so the next person
to edit it cannot repeat this:

```
/usr/sbin/ModemManager --test-quick-suspend-resume --log-level=DEBUG
```

☠️ **Not yet proven to fix it.** The failing arm — a long suspend ended by an
incoming call — has not been re-run with the flag restored. Until it has, this is
a very strong hypothesis with a mechanism, not a result.

### ☠️ The lesson, and it is not about ModemManager

A drop-in that sets one option **replaced an entire command line**. `ExecStart=`
in a `[Service]` section does not add — it clears, and every later drop-in that
sets it silently discards what earlier ones set. **After adding a drop-in, read
back the effective value** (`systemctl show <unit> -p ExecStart`) rather than
assuming the option you added is the only change you made. Four days of a
"platform bug" hung on that.

★ It also vindicates the rule added to the skill this same session: the
search that would have found this was never run, because the work started from
our own measurement and went straight to the source. **Both halves of the rule
fired here** — the distro's fix predates ours by a month, and the search took
minutes.
