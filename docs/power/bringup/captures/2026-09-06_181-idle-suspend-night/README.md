# #181 — armed: the phone is set to suspend on its own, for the first-call-after-idle sample

**2026-09-06 evening**, pmOS `linux-fp3-7.1.3-r88` (`6113869dcc3d`). Steps 1–3 of
the task are done here; steps 4 (the untouched night) and 5 (the operator's one
morning call) are the measurement itself and are not in this page yet.

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

## 1. The before-state — the way back

Full output in `before.txt`. The load-bearing parts:

| | |
|---|---|
| `IdleAction` in `/etc/systemd/logind.conf` | **not set** |
| `/etc/systemd/logind.conf.d/` | **did not exist** |
| `/sys/power/suspend_stats/success` | **0** — the phone had never suspended |
| sleep inhibitors | 4 × `delay` (ModemManager, NetworkManager, rtkit, UPower, gsd-power) and **no `block`** on sleep; the two `block` entries are `handle-power-key`, not sleep |

So nothing was preventing sleep — nothing was *asking* for it. That confirms the
task's own diagnosis rather than re-deriving it.

## ★ The obstacle that was NOT there, and would have cost the morning link

Three `fp3-*` timers fire overnight — `usbnet-watchdog` every 30 s,
`touch-sample` every 2 min, `ims-reconcile` every 5 min — and a 30-second timer
would make a long idle impossible. The reflex is to stop them. **Measured
instead:**

```
fp3-usbnet-watchdog          WakeSystem=no
fp3-touch-sample             WakeSystem=no
fp3-ims-reconcile            WakeSystem=no
systemd-tmpfiles-clean       WakeSystem=no
```

☠️ A systemd timer only wakes a suspended system with `WakeSystem=true`; without
it the elapse is simply deferred until the system is next awake. **None of them
wakes it**, so none had to be stopped — and `fp3-usbnet-watchdog` is what brings
the USB link back, so stopping it on a hunch would have risked the morning
connection for nothing.

## 2. What was changed — one file

`/etc/systemd/logind.conf.d/99-fp3-idle-suspend.conf`:

```ini
[Login]
IdleAction=suspend
IdleActionSec=5min
```

Read back from logind itself, not from the file:

```
IdleAction     s "suspend"
IdleActionUSec t 300000000
```

**The way back is deleting that one file and `systemctl restart systemd-logind`.**

## ★ Why "DO NOT SSH IN" is a mechanism, not a superstition

The task forbids logging in before the call. Measured here, with an ssh session
open:

```
session 1 : Class=manager  Remote=no   IdleHint=no
session c1: Class=user     Remote=no   IdleHint=yes    (the phosh seat, idle)
session c2: Class=user     Remote=yes  IdleHint=no     <- the ssh login
manager IdleHint = false
```

`IdleAction` fires on the **manager's** idle hint, and one non-idle session holds
it false. So an ssh login does not merely disturb the measurement — it makes the
phone **incapable of suspending at all** for as long as it is connected. The
rule was written as a warning about waking the phone; the actual mechanism is
worse than that, and it is now on record.

## 3. The lock, proven rather than assumed

`~/.fp3-measure.lock` set until 08:00, and the very next login was refused:

```
REFUSED by fp3-measure: 181-idle-suspend-night|DO NOT LOG IN: an ssh session
sets IdleHint=no and logind then never suspends the phone - a login voids the
night|2026-09-06T22:59:54+02:00|1788760800
```

A lock that has not been shown refusing something has proved nothing; this one
has.

## What is left, and what may not be claimed

- ☠️ **Step 3 is HALF done, and the half that is missing is the one that
  proves it.** Left alone for 7 minutes past the 5-minute timer, the phone
  stopped answering ssh:

  ```
  ssh: connect to host 172.16.42.1 port 22: Connection timed out
  fp3-ssh: giving up after 3 attempts
  ```

  That is consistent with suspend and it is **one** of the task's two criteria.
  The other — `suspend_stats/success` climbing — cannot be read without logging
  in, and logging in is what the night must not have. So it stays unread until
  morning.

  ☠️ **An alternative explanation is not excluded: a dead USB gadget link looks
  exactly the same from here.** That failure is common enough on this device to
  have its own watchdog (`fp3-usbnet-watchdog`). If that is what happened, the
  night measures nothing and it will not be visible until morning. Checking
  would destroy the thing being measured, so the right move is to leave it — but
  "the phone suspended" may NOT be claimed on this evidence.
- Steps 4 and 5 belong to the operator: leave it untouched, then place **one**
  incoming call in the morning and report whether it rang and how long it took.
- ☠️ This consumes the night that #158 also wants. #181 was chosen because the
  operator ordered it after the touch work, and that work closed with #179.
