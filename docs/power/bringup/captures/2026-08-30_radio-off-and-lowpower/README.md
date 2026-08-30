# 2026-08-30 — the noise comes from the network, and low power loses the call

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who placed the call and reviewed the measurements.

Two measurements taken back to back, and between them they close the question of
*where the thing that ends every suspend comes from* and *whether powering the
modem down is available as a lever*.

## 1. ★★★★★ Radio off: the phone sleeps the whole window

A-B-A′ in one run, 1800 s alarm on every leg, only the radio state differing
(`mmcli --disable`, not a remoteproc restart):

| leg | radio | slept | ended by |
|---|---|---|---|
| A | on | **8 s** | modem edge |
| **B** | **off** | **1802 s of 1800** | **THE ALARM — the whole window** |
| A′ | on | **33 s** | modem edge |

**This is the first sleep in the project that filled its alarm rather than dying
on it**, and its own two controls, taken minutes either side, rule out time of
day and anything else drifting. ⇒ **What ends every suspend arrives from the
network.** Not the modem's own housekeeping, not our driver, not ModemManager.

It also explains the diurnal pattern that the (retracted) recovery hypothesis had
been covering: full 300 s and 240 s sleeps at 02:30 and 05:15, never more than
43 s through the morning. Network-side traffic is diurnal; a device's own
housekeeping is not.

## 2. ☠️ Low power across suspend loses the call — measured, not predicted

`leads/selective-smd-wakeup.md` said the low-power branch was *"expected to buy
residency and lose the call"*. Expectation is not measurement, and four
predictions written in that tone had already failed on this front the same day.

Run with `--test-low-power-suspend-resume` in place of the distro's
`--test-quick-suspend-resume`, phone asleep, a call placed by hand:

> **the network answered "the number you have dialled is not available"**

⇒ the modem **deregisters** in low power, so the network cannot page it at all.
The call never reaches the device — there is no `ringing-in` in the journal
because nothing arrived. **The lever is disqualified by the goal's own terms**
(parity *at the oracle's responsiveness*), and it is now closed on evidence.

## What the three levers now look like, all measured

| lever | residency | call |
|---|---|---|
| **terse** (the pmOS default) | ✗ 52–63 s — still owed a clean re-run | ✅ woke a sleeping phone and rang (`captures/2026-08-30_terse-call/`) |
| **low power** | not measured through | ☠️ **lost** |
| **radio off** | ✅✅ 1802 s | ☠️ none, by construction |

⇒ **Powering the modem down is not the route.** Since the noise arrives from the
network *and so does the call*, the only remaining lever is to **separate network
events from each other** — which is what `leads/selective-smd-wakeup.md`
proposes at the interrupt layer, and what eDRX would do at the network layer.
☠️ eDRX cannot be requested with the tools present: `libqmi` (checked at
`b7913df`) carries no PSM or eDRX control, only a NAS status enum.

Instruments: `tools/radio-off-sleep.sh`, `tools/lowpower-call2.sh`.

☠️ **A trap in the second instrument, found by the user mid-run.** Its first
version slept for the full alarm at the end of each round — but execution only
resumes once the phone is *awake*, so that wait spent the remainder of the round
awake: 302 s of a 15-minute window. A call placed by hand is most likely to land
exactly there, i.e. on a phone that is up. Fixed to go straight back down. The
same shape of error had already been found and fixed in `terse-call.sh` that
morning and was reintroduced by copying the structure.
