# 2026-08-30 — the two-marker census, and why the window is STILL not the sleep

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

**Command:** `run-wake-qmi.sh start 600 2`, 12:38:10. Both rounds slept **601 s**
of a 600 s alarm and were ended by `pm_wakeup_irq=72` — the RTC.

The pre-registered prediction (`leads/selective-smd-wakeup.md`) was that an
RTC-ended round must contain **zero** QMI messages, because the modem edge is
wake-armed and any SMD interrupt during s2idle ends the suspend before the
handler runs. Each round instead shows ~20 messages.

## ☠️ That does not falsify the prediction, because the window is still wrong

Read what the messages *are*:

```
5  src_port=40  RSP  msg=3    NAS: Register Indications
2  src_port=52  RSP  msg=37   DSD: System Status Change
2  src_port=45  RSP  msg=1    WDS: Set Event Report
2  src_port=44  RSP  msg=32   UIM: Read Transparent
1  src_port=40  RSP  msg=77   NAS: Get System Info
...
```

**Identical counts in both rounds**, and identical to the counts in the
single-marker capture before them. That is the signature this project already
named: *network traffic varies, a fixed handshake does not*. It is
ModemManager's terse sequence again — and the port resolution now names each
line rather than offering a list, so there is no ambiguity about it.

**Why it is still inside the window.** The marker is written and then
`systemctl suspend` is called. That call is not the suspend: it goes to logind,
which announces the sleep, which runs ModemManager's terse path, which sends
those messages and waits for the replies — and only then does the kernel freeze.
So `SUSPENDING` means *"I am about to ask"*, not *"the system is down"*, and the
whole handshake falls between the markers.

**Third time in one day that a boundary was not where it was assumed to be**:
first the resume edge, then the suspend-request edge, now the difference between
requesting a suspend and entering one. The class is the same each time, and the
tell was available each time — a per-round count that does not vary.

## What the capture does establish

- Both rounds filled the window and were **RTC-ended**, which is consistent with
  the prediction rather than against it.
- After removing the handshake, what is left is **at most a handful of
  indications** — round 1 shows one `NAS: Signal Info`, round 2 two on port 10 —
  and possibly none belong to the sleep either.
- The decode is now unambiguous: every line resolves to exactly one service,
  through the port map taken from this run's own `qrtr-lookup` (32 ports).

## The fix, not yet run

The marker has to be written where the kernel is actually about to suspend, not
where userspace asks for it: a hook in `/usr/lib/systemd/system-sleep/`, which
runs after every inhibitor and delay handler, ModemManager's included. Until
that runs, **the question "does the modem send anything unprompted while
asleep?" remains unanswered** — for the third time, and it should be stated that
way rather than answered from this file.
