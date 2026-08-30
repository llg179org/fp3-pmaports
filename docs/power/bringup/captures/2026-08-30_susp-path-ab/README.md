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

☠️ **`# MM inhibitor:` came back empty in this run**, although the same query
listed a `delay`-mode `sleep` inhibitor from ModemManager hours earlier. The
inhibitor is state-dependent, not permanent, so any argument resting on "the
daemon always registers for sleep" does not hold.

**Secondary result:** in these four cycles the modem interrupted **one** suspend
of four, not all of them. The 2026-08-26 finding that the modem edge terminates
every suspend describes a *state* (most likely a live indication subscription —
compare the `mmcli --disable` leg, 8 s → 601 s), not a permanent property.

Instrument: `../../tools/susp-path-ab.sh` (on the phone at
`/usr/local/bin/susp-path-ab.sh`). ☠️ Its first version was wrong: `systemctl
suspend` does not block, so the "sleep" it timed was the command returning (1 s).
This version waits for `/sys/power/suspend_stats/success` to increment and
measures **wall clock**, since the monotonic clock stops across a suspend.
