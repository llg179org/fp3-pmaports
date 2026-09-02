<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# With IMS off the phone rings, answers, talks and receives SMS — the reachability gate on a live network

2026-09-02 06:20, pmOS on the FP3, **every IMS service switch `False`** (read
back), modem `registered` / `attached` / `vodafone HU`, access technology `lte`.
An incoming call was placed by the owner from a second handset.

| moment | source |
|---|---|
| caller heard first ringback | ~5 s after dialling (owner's own account) |
| **06:20:24.034** — modem: `call state changed: unknown -> ringing-in (incoming-new)` | journal |
| **06:20:24.537** — ringtone actually starts (`Feedback 'phone-incoming-call' triggered`) | journal |
| 06:20:28.171 — caller hung up; `ringing-in -> terminated` | journal |

**Device-side latency, modem event to audible ring: 503 ms.** The ~5 s the caller
experienced is network signalling and CSFB setup, and the phone rang at
essentially the same moment the caller heard ringback — no added delay on our
side.

So the fear that switching IMS off would cost reachability does not materialise
on this network: this device has never registered IMS, calls run CSFB, and the CS
paging path is untouched by the IMS service switches.

## The answered call, 5 minutes later

| moment | |
|---|---|
| **06:25:22.777** | modem: `ringing-in (incoming-new)` |
| **06:25:23.106** | ringtone starts — **329 ms** device-side |
| **06:25:27.465** | `ringing-in -> active (accepted)` — the call is picked up |
| 06:26:24.417 | `active -> terminated` — **57 seconds of live call** |

Audio was good in **both directions** (owner's own account, on both handsets).
So with every IMS service switch `False` the device rings, answers, and carries
speech.

## SMS arrives too, and that is a switchover rather than a given

An incoming SMS landed **~5 s** after being sent. SMS had been riding IMS
(`SMS True` before the intervention); with IMS off it has to fall back to the CS
path over SGs, and it does. The journal's `failed deleting SMS message ... No SMS
found` at 06:24:00 is a post-read cleanup race in ModemManager, not a delivery
failure — the message was received.

## ☠️ What this does NOT yet establish

- **The corona test.** This ran with the AP awake, on the cable. The one that
  matters for the goal is: AP asleep, on battery, from a cold boot of the
  *shipped* configuration — because a hand-built state and a booted state have
  already been shown to differ on this device (ModemManager did not re-enumerate
  the modem after a firmware restart).
- **The outgoing direction.** Outgoing call and outgoing SMS are untested.
- **Reboot survival.** The IMS write is modem-persistent, so a rebooted phone
  must still ring. Untested.

## Raw

`raw/journal-call-2026-09-02_0620.txt` — the journal window. ☠️ The calling
number is redacted to `+36XXXXXXXXX`: it is the owner's own second line, and this
repository is public.

---

# ☠️☠️ 2026-09-02 06:31 — THE REBOOT UNDID IT. The write is NOT persistent.

The reboot test was meant to confirm that a rebooted phone still rings. It
answered a different and more important question first. Read **after the boot,
before any write in that session** (twice, same answer):

```
voice True · VoWiFi False · video telephony True · SMS True · UT True · USSD False
```

That is the **original vector**, exactly as recorded before the intervention.
Every switch that was `False` at shutdown is back where it started.

## What this retracts

**"The IMS write is modem-persistent / NV-backed" is wrong**, and so is
everything built on it:

- The write survived a **modem firmware restart** (`remoteproc0` stop/start) —
  that part was measured and stands. It does **not** survive a system reboot.
  The two are not the same test, and this repo concluded the stronger claim from
  the weaker evidence.
- ★ **The shared-NV warning on the oracle slot is void.** The oracle's modem was
  not permanently reconfigured; the setting is gone. The dated warning in
  [`../2026-09-01_both-slots/`](../2026-09-01_both-slots/) should be read as
  "temporarily changed and since reverted by a reboot", not as a standing
  hazard.

The likely mechanism, not yet measured: on a firmware restart ModemManager did
not re-enumerate the modem at all (measured — `mmcli -L` said "No modems were
found" for an hour), so nothing re-initialised the IMS settings. On a full boot
ModemManager starts fresh against a fresh modem and the original configuration
is what comes back. Whether MM writes it or the modem restores it from NV is a
separate question, and the journal at boot names no writer.

## What this changes about shipping

The boot-time assertion service moves from **insurance to requirement**: without
it every reboot silently restores the expensive configuration, and the phone goes
back to ~48 % modem duty with nobody noticing. That is exactly the failure mode
this project has been bitten by before — a setting that looks applied because
someone applied it once.

☠️ And a smaller lesson, paid for immediately: the tools were installed under
`/tmp`, which is tmpfs here, so the reboot deleted every one of them — including
the tool needed to read the state being tested. The repo's own `modem-night.sh`
carries the note "☠️ /var/log/fp3, NOT /tmp. /tmp is tmpfs here". They now live
in `/usr/local/bin`.
