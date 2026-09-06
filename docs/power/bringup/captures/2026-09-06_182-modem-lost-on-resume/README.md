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

## What would settle it, and what it costs

- **A suspend of 15–20 minutes, undisturbed, then one call.** That is the only
  untested cell of the table above, and it is the failing one. It costs twenty
  quiet minutes, not a cable.
- Then, if the long suspend reproduces the loss, the question narrows to whether
  the qrtr QMI port is simply **late** on resume — the script already times that
  — or absent because the modem's QRTR services need re-announcing.

☠️ **#181 stays blocked behind this.** Its morning sample would be a guaranteed
"did not ring", and would read as a reachability result.
