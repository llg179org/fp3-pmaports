# ★★★ The compositor, not the modem: phoc cannot restore DSI-1 on resume

**2026-09-07**, pmOS `linux-fp3-7.1.3-r88`, `#89-fp3`. Found while trying to run
`#142`'s arm A; it is not a `#142` finding and not a kernel finding.

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, whose report — *"megnyomtam a bekapcsoló gombot, de
> nem ébredt fel"* — is what exposed it.

## The symptom the operator has been reporting for two days

> *"felvillant a háttér, de fekete a képernyő"* · *"nem fekete lenne a kijelző,
> hanem világos szürke — semmi nem látható rajta"* · *"megnyomtam a bekapcsoló
> gombot, de nem ébredt fel"*

All three were read as part of `#182` — the phone had no modem, so of course it
did not ring. **`#182` was fixed and verified at 08:24 this morning, the phone
rang, and the screen still did not come back.** They were two faults sharing one
appearance.

## The measurement

Every `PM: suspend exit` in the journal, against the nearest phoc failure line:

| resume | nearest phoc failure | screen wanted? |
|---|---:|---|
| 2026-09-06 23:23:38 | **+0 s** | yes (call) |
| 2026-09-06 23:31:09 | **+0 s** | yes |
| 2026-09-06 23:35:32 | +77 s | yes |
| 2026-09-06 23:36:43 | +6 s | yes |
| 2026-09-07 00:16:31 | **+0 s** | yes (call) |
| 2026-09-07 00:27:01 | −630 s | **no — rtcwake, unattended** |
| 2026-09-07 00:27:10 | −639 s | **no — rtcwake, unattended** |
| 2026-09-07 00:38:20 | −1309 s | **no — rtcwake, unattended** |
| 2026-09-07 07:09:08 | **+0 s** | yes (call) |
| 2026-09-07 08:24:45 | **+0 s** | yes (call) |
| 2026-09-07 08:45:36 | **+0 s** | yes (ssh woke it) |

★ **Six of the six resumes that were followed by an attempt to light the screen
produced a phoc DRM failure in the same second. The three that nobody asked for a
screen produced none.** 1561 failure lines in this journal.

The lines themselves:

```
08:24:45  phoc: [types/output/swapchain.c:109] Swapchain for output 'DSI-1' failed test
08:24:45  phoc: Failed to commit power mode change to 1 for 0xffff919e9db0
```

`power mode 1` is DPMS on. At suspend the mirror image appears — *"Failed to
commit power mode change to **0**"* at 23:04:02, the moment of that suspend.

## The state it leaves behind, which is exactly what the operator sees

| | |
|---|---|
| `dpms` | `On` |
| `status` | `connected` |
| backlight | `160`, `bl_power=0` (unblanked) |
| `ScreenSaver.GetActive` | `(true,)` — **and it stays true through `SetActive false`** |

**The panel is powered and lit; the compositor is stuck in the blanked state and
neither direction of the ScreenSaver call moves it.** A lit screen with nothing
on it.

☠️ **And the power button is dead for a second, independent reason**: `phosh`
holds a **`handle-power-key` block** inhibitor (`systemd-inhibit --list`). It
took the key and then wedged, so nothing handles the press. That is why waking it
by hand fails while an ssh login resumes it perfectly.

## What did NOT fix it, and what did

- `ScreenSaver.SetActive false` — no effect in either direction.
- `systemctl restart greetd` — a **new** phoc starts and immediately fails with
  `connector DSI-1: Atomic commit failed: Resource busy`, every ~15 s. The old
  phoc was already gone and only the new one held `/dev/dri/card0`, so "busy" is
  not a stale holder.
- **A clean reboot fixed it.** Afterwards `SetActive true` → `dpms=Off`,
  `SetActive false` → `dpms=On`, one phoc failure line for the whole boot.

## ☠️ My own contribution to the wreck, recorded so it is not repeated

`142-run-A.sh` ran `systemctl restart systemd-logind` to apply a drop-in removal.
Every `libseat` error in this capture —

```
08:46:06  phoc: [libseat] Could not take device: You are not in control of this session
08:46:06  phoc: Failed to open device: '/dev/input/event4': Invalid argument
```

— is dated **after** that restart and is its consequence: restarting logind takes
the seat away from the running compositor. **It did not cause the fault** (the
first `swapchain failed` of this journal is 00:16:31, at a resume, long before),
but it made the session unrecoverable without a reboot, and a session that could
have been repaired more cheaply was not.

Removing a `logind.conf.d` drop-in does not need a logind restart at all when the
next boot is coming anyway; when it does, `systemctl kill -s HUP systemd-logind`
re-reads the configuration without dropping the seat.

## What this is worth

- It is a **userspace/compositor** bug, not a kernel or panel one: DRM reports
  the connector on and connected while phoc's atomic commit fails.
- It has been mistaken for `#182` for two days, which is the real cost: the
  screen symptom was double-counted as evidence for a modem fault.
- ☠️ It is **not diagnosed**, only localised. What fails inside the swapchain
  test on resume is unknown, and no `phoc`/`wlroots` version has been checked
  against upstream reports yet. That search is the next step, and by the rule
  this repository adopted on 2026-09-07 it comes **before** any code.
