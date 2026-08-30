# 2026-08-30 — does a call still reach a TERSE, sleeping phone? (yes)

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who placed the call and reviewed the measurement.

**The question the whole power goal hangs on.** The target is parity with the
oracle *at the oracle's responsiveness*. ModemManager's quick suspend mode puts
the modem in `TERSE` — 3GPP unsolicited registration events and unsolicited
events disabled. Its source says calls and texts survive that; what survives on
this QMI modem is a measurement.

## Result: the call woke the sleeping, terse phone and rang

One chain, one second wide:

```
07:17:04  [sleep-monitor-systemd] system is about to suspend
07:17:04  terse state 3GPP (1/3): disable unsolicited registration events done
07:17:04  terse state 3GPP (2/3): disable unsolicited events done
07:17:04  setting terse state (2/2): all done
07:17:04 -> 07:17:19  = 15s asleep        (kernel PM: suspend entry/exit)
07:17:19  [modem0/call0] call state changed: unknown -> ringing-in (incoming-new)
07:17:19  gnome-calls: New incoming call ... Setting ring state to 'ringing'
```

Terse was demonstrably applied (four journal lines), the phone was demonstrably
asleep (the kernel's own entry/exit pair, and the host's USB log independently:
`07:17:06 disconnect → 07:17:20 new`), and the call arrived in the same second
the suspend ended.

⇒ **`TERSE` does not cost the call path.** The distribution's default is right on
this axis, and `--test-low-power-suspend-resume` — which disables the modem and
puts it in low power — stays disqualified: it would buy residency with the thing
the goal is defined by.

## ☠️ But terse buys no residency either, and a wrong number was published first

Six legs, alternating `rtcwake` and logind with a ModemManager restart before
each so terse could not carry over, produced this — and the first write-up of it
was wrong:

| leg | path | terse | **reported** | **actually asleep** |
|---|---|---|---|---|
| r1 | rtcwake | 0 lines | 52 s | 52 s |
| l1 | logind | 4 lines | ~~306 s~~ | **61 s** |
| r2 | rtcwake | 0 lines | 62 s | 62 s |
| l2 | logind | 4 lines | ~~306 s~~ | **61 s** |
| r3 | rtcwake | 0 lines | 63 s | 63 s |
| l3 | logind | 4 lines | ~~306 s~~ | **63 s** |

The logind legs never slept 306 s. `systemctl suspend` does not block, so the
script sat in a loop for `alarm + 5` seconds and printed that as the sleep. Its
own output gave it away: `wake_irq=139` — the modem edge — on legs where no RTC
alarm had been armed at all. The true durations come from the kernel's
`PM: suspend entry (s2idle)` / `PM: suspend exit` pairs, which are journalled
with wall timestamps and which no script bug can forge.

⇒ **terse changes nothing about residency here**: 52–63 s with it and without it.
It is harmless and useless, and the modem-duty front stays open.

## Two measures that are now the standard ones

1. **`journalctl -k | grep 'PM: suspend'`** — the authoritative sleep duration,
   on any suspend path, regardless of what woke the phone.
2. **The host's own `dmesg`** — the phone's USB gadget drops on suspend and
   re-enumerates on resume, one second from the kernel's own marks. It is a
   completely independent witness that **touches nothing on the phone**: no ssh,
   no poll, no wake. Every `disconnect`/`new high-speed` pair on the host is a
   sleep window, free of charge:
   ```sh
   UP=$(cut -d. -f1 /proc/uptime)
   sudo dmesg | grep -oE '^\[ *[0-9]+\.[0-9]+\] usb 1-5: (USB disconnect|new high-speed)' \
     | while read -r l; do s=$(echo "$l" | grep -oE '[0-9]+\.' | head -1 | tr -d .)
         echo "$(date -d "@$(( $(date +%s) - UP + s ))" '+%H:%M:%S')  $l"; done
   ```
   ☠️ It also caught a measurement being run on an awake phone: the first
   call-test leg suspended once, was woken after 76 s, and never went back to
   sleep — so the "window" the call was supposed to land in was awake for almost
   all of it. Three instrument generations were written before this witness,
   which was on the host all along, was used.

Instrument: `../../tools/terse-call.sh`, `../../tools/terse-ab.sh`. Phone number
redacted from the capture.
