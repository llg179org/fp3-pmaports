# The logind drop-in does load — and that removes the last explanation

> ⚠️ AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.

**2026-08-31.** `tools/logind-policy-witness.sh`, run on the phone.

## Reading

```
BEFORE:   IdleAction = s "ignore"    IdleActionUSec = t 1800000000
AFTER:    IdleAction = s "suspend"   IdleActionUSec = t 60000000
RESTORED: IdleAction = s "ignore"    IdleActionUSec = t 1800000000
```

A `/run/systemd/logind.conf.d` drop-in **takes effect on a plain
`systemctl reload systemd-logind`** — no restart needed, and the value comes back
when it is removed.

For the record, at the same three moments:

```
systemctl show systemd-logind -p IdleAction --value   ->   ''   (all three)
```

☠️ **`IdleAction` is a property of the logind D-Bus interface, not of the
systemd unit.** The `systemctl show` form returns an empty string regardless of
the setting, silently. That empty string is what made a gate refuse to arm the
step-0 night run on 2026-08-30, costing 35 minutes. Validated against a
known positive on the host first, where `busctl` answered `s "ignore"` /
`t 1800000000` while `systemctl show` answered nothing.

## What it does to R1b

R1b measured **zero** suspends in 1800 s with `IdleAction=suspend` and a 60 s
threshold. `logind.conf(5)` names three conditions. All three are now measured,
and **all three held**:

| condition | witness | verdict |
|---|---|---|
| all sessions whose class can idle report idle | `loginctl show-session c1` → `IdleHint=yes`, since 14:52, hours before the window | ✅ held |
| no idle inhibitor lock | `systemd-inhibit --list` at both ends: seven entries, all `delay` for `sleep` plus two `block` for `handle-power-key`; **no `idle`** | ✅ held |
| the delay expired | 60 s inside an 1800 s window | ✅ held |
| **the policy was loaded** | this capture | ✅ held |

⇒ **The zero is unexplained.** Every pre-registered reading has now been
eliminated by measurement, which is a better place to be than a plausible story,
but it is not an answer.

## ☠️ What this capture does NOT say

`IdleHint` read **`b false`** at the manager level during this run, with
`IdleSinceHint = t 0`. **That cannot be read back onto the R1b window.** This
probe ran over ssh, and an ssh session on this phone is `Class=user`, so it counts
toward the manager's idle hint and makes it false by existing. The same
contamination invalidated a reading the day before.

The manager idle hint during an *unobserved* window is the one witness still
missing, and it can only come from the phone sampling itself — see the R1b-3 step
in the frame. Any interactive read of it answers a different question.
