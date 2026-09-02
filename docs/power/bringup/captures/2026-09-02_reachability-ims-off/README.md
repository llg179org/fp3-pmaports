<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# With IMS off, the phone rings — first half of the reachability gate

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

## ☠️ What this does NOT yet establish

- **Answering.** The caller hung up after 4.1 s of ringing. No call was picked
  up, so **audio in either direction is untested** — "it rings" and "you can talk"
  are different claims.
- **The corona test.** This ran with the AP awake, on the cable. The one that
  matters for the goal is: AP asleep, on battery, from a cold boot of the
  *shipped* configuration — because a hand-built state and a booted state have
  already been shown to differ on this device (ModemManager did not re-enumerate
  the modem after a firmware restart).
- **SMS.** IMS was carrying SMS (`SMS True` before the intervention); with IMS
  off it must fall back to SGs. That is a switchover, not a given, and it is
  untested in both directions.
- **Reboot survival.** The IMS write is modem-persistent, so a rebooted phone
  must still ring. Untested.

## Raw

`raw/journal-call-2026-09-02_0620.txt` — the journal window. ☠️ The calling
number is redacted to `+36XXXXXXXXX`: it is the owner's own second line, and this
repository is public.
