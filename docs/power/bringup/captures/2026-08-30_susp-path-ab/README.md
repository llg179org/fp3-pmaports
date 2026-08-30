# 2026-08-30 — does the suspend PATH change the residency?

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed the measurement it rests on.

**The hypothesis this kills:** every residency number measured so far slept with
`rtcwake -m mem`, which writes `/sys/power/state` directly and **bypasses
logind**, so ModemManager never receives `PrepareForSleep` and never runs its own
suspend preparation. If the daemon's preparation is what quiets the modem, then
"ModemManager ends every suspend" was an artefact of the instrument.

**Result: the two paths are equivalent.** A-B-A-B, same 240 s alarm, same boot:

| leg | path | slept, wall clock | wake IRQ |
|---|---|---|---|
| A | `rtcwake -m mem` | **82 s** of 240 | 139 = modem |
| B | `systemctl suspend` (logind) | 242 s | 72 = RTC alarm |
| A′ | `rtcwake -m mem` | **241 s** of 240 | 72 = RTC alarm |
| B′ | logind | 242 s | 72 = RTC alarm |

The second `rtcwake` leg slept the full alarm, so the path is not the variable —
the first leg's short sleep is one early interruption, not a property of writing
`/sys/power/state`. ⇒ **the residency front's numbers stand as measured**, and no
re-measurement is owed.

☠️ **The Linux IRQ number is an allocation and it moved on this boot.** The modem
edge is **139** here (`GIC-0 57 Edge smd-edge`); **141 is `wcn36xx_tx`, the WLAN
transmit interrupt.** Every earlier page that names "IRQ 141, the modem's SMD
edge" was correct *on the boot it was written*. Read the identity off
`/proc/interrupts` by the `smd-edge` row and hwirq 57, never off the number.

☠️ **The `# MM inhibitor:` line came back empty, and that was MY BUG, not the
system's state.** The heredoc that wrote the script onto the phone ate the awk
program's quotes, leaving `awk /ModemManager/{print , }` — a truncated program
that prints nothing. ModemManager holds its `delay`-mode `sleep` inhibitor the
whole time (`'sleep', 'ModemManager', 'ModemManager needs to reset devices',
'delay'`). ⇒ **the A/B contrast is real and better evidenced than first written**:
the journal shows the daemon being told about both logind legs and nothing about
the two `rtcwake` ones —

```
05:15:10  [sleep-monitor-systemd] system is about to suspend
05:15:10  [sleep-monitor-systemd] ready to sleep; dropping inhibitor
05:19:12  [sleep-monitor-systemd] system is resuming
```

— and the residency came out the same either way. The general form: **a field
that reports "absent" is a claim about the instrument first.** Verify the query
returns something on a case you know is positive before reading a blank as data.

★★★★ **What that check turned up instead — nobody asks the modem to sleep, and it
is a distro default.** pmOS ships

```
/usr/lib/systemd/system/ModemManager.service.d/quick-suspend-resume.conf
  ExecStart=/usr/sbin/ModemManager --test-quick-suspend-resume
  owner: postmarketos-base-ui-modemmanager-systemd
```

so **every measurement on this device so far ran in quick mode**, where the daemon
does nothing to the modem across a suspend and just drops its inhibitor. The other
branch, `--test-low-power-suspend-resume`, actually puts the modem in low power.
Same shape as the camera's `GSK_RENDERER=cairo`: a distro quirk quietly settling a
performance question. ☠️ It probably works against the goal — a sleeping radio
does not deliver a call, and the target is parity *at UT's responsiveness* — so it
has to be measured on both sides: residency **and** call wake-up.

**Secondary result:** in these four cycles the modem interrupted **one** suspend
of four, not all of them. The 2026-08-26 finding that the modem edge terminates
every suspend describes a *state* (most likely a live indication subscription —
compare the `mmcli --disable` leg, 8 s → 601 s), not a permanent property.

Instrument: `../../tools/susp-path-ab.sh` (on the phone at
`/usr/local/bin/susp-path-ab.sh`). ☠️ Its first version was wrong: `systemctl
suspend` does not block, so the "sleep" it timed was the command returning (1 s).
This version waits for `/sys/power/suspend_stats/success` to increment and
measures **wall clock**, since the monotonic clock stops across a suspend.
