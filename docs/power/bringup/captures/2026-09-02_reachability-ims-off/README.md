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

---

# 2026-09-02 08:41–08:54 — four more calls, and the number that has to go beside them

Four incoming calls with the phone asleep on battery, IMS=off, 3–5 minutes apart
so it went back to sleep between them. All four rang.

| call | modem `ringing-in` | ringtone | device-side |
|---|---|---|---:|
| 1 | 08:41:34.238 | 08:41:34.758 | 520 ms |
| 2 | 08:47:07.139 | 08:47:07.479 | 339 ms |
| 3 | 08:51:02.252 | 08:51:02.607 | 355 ms |
| 4 | 08:54:37.618 | 08:54:37.944 | 326 ms |

**385 ms mean, 92 ms spread**, and the 329 ms measured at 06:25 falls inside it.

## ☠️ FOUR OUT OF FOUR IS COMPATIBLE WITH LOSING EVERY SECOND CALL

There are two claims here and only one of them is closed.

**Closed: the call path works with IMS off.** Four calls rang, one was answered
and carried 57 s of speech both ways, an SMS arrived over SGs. That is a
functional proof, and functional proofs do not need large N.

**Not closed, and not close: that the delivery *rate* is unharmed.** From four
successes out of four, the one-sided 95 % lower bound on the delivery probability
is

    p ≥ 0.05^(1/4) = 0.473

so this evidence is equally consistent with a phone that misses **half** its
calls. For the record, what the same rule demands:

| to claim | consecutive successes needed |
|---|---:|
| p ≥ 0.86 | 20 |
| p ≥ 0.95 | 59 |
| p ≥ 0.99 | 299 |

And the four samples do not even reach into the dangerous corner: they were 13
minutes apart in total, on one boot, after **minutes** of idleness. A paging miss
after **hours** of idle and deep sleep — the case a user would actually hit
overnight — is unsampled.

☠️ This is the same error as quoting 40.1 mA from one leg of one boot, moved to
the success-rate side, and it is the more expensive half: a few mA of runtime is
an inconvenience, a missed call is a silent, user-facing failure and the reason a
phone is a phone. It is also the exact shape of the speaker-amp saga, where a
battery of checks reported 27 ok / 0 failed against a silent speaker.

**So no report may say "reachability is fine" on this evidence.** It may say the
call path works, and it must print 0.473 next to the 4/4.

☠️ **And "the ~6 s the caller waits is the network" is an attribution, not a
measurement.** It is plausible (alerting plus CSFB redirection), but nothing here
measured it. Either label it a hypothesis or measure the same call on the oracle
slot, which does not use CSFB.

## The machine-only way to actually close it

A second human is not required. Scheduled calls from a SIP/VoIP account —
N=30, spread across a night with **hours** between them — sample the corner that
matters and need only a cron and a few forints of balance. That is what the open
item asks for.

## ☠️ The instrument outlived by its own measurement, again

The recorder for this window was started with `RuntimeMaxSec=1800` and stopped at
08:57, so calls placed after 09:00 were never recorded and are simply lost. The
same failure class had already appeared in this investigation once — the fuel
gauge's 76 s window against a 60 s sleep. **The lifetime of the instrument has to
be checked against the length of the measurement**, and since it has now happened
twice in one day it belongs in the measurement wrapper, not in anybody's
attention.

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
