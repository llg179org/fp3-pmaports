# CSFB measured end to end, with timestamps, on 2026-09-08

**12:34**, pmOS r88, ModemManager 1.25.95, dev card on One HU (MCC 216 / MNC 070,
operator id 21670). Instrument: `../../tools/fp3-callwatch.sh`, its first real
call.

☠️ **The raw log is NOT in this repository.** It lives at
`/mnt/1TB/pmos/fp3-raw-logs/2026-09-08_callwatch/`, md5 `0e0e0d60…`. Even
scrubbed of MSISDN, IMSI, IMEI and ICCID, a call log records *when its owner
telephoned*, and the radio stream beside it records the conditions they were in
while doing so — personal data about a person, not a measurement of a phone.
`.gitignore` now carries the rule, because this mistake was made by hand here
first. What follows is the finding; the log is the source.

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who placed the call.

## The measurement

An incoming call, answered, both directions audible — the operator's own report.
The log brackets it completely:

| time | event | access technology |
|---|---|---|
| 12:32:25 | logger start, phone idle | **`lte`** |
| **12:34:18** | `AccessTechnologies: <uint32 10>` | **LTE → GSM+GPRS** |
| 12:34:20 | `CallAdded`, ringing | `gsm, gprs` |
| 12:34:29 | `StateChanged (3, 4)` — answered, after **9 s** of ringing | `gsm, gprs` |
| 12:34:48 | `StateChanged (4, 7)` — ended, **19 s** of talk | `gsm, gprs` |
| **12:34:49** | `AccessTechnologies: <uint32 16384>` | **GSM+GPRS → LTE** |

`MMModemAccessTechnology` is a bitmask: **10 = 2|8 = GSM|GPRS**,
**16384 = 1<<14 = LTE**.

★ **The phone left LTE two seconds BEFORE the call object even appeared**, spent
the whole call on 2G, and returned one second after it ended — **≈31 s off LTE
for a 19 s conversation.** That is circuit-switched fallback, measured from the
handset with times rather than inferred.

This is the first timestamped device-side record of the behaviour the 2026-09-06
letter to One HU describes: the network moves this subscriber to GSM for voice
while it is registered on LTE and the data bearer is up.

## Why it matters right now

One HU are running a radio-side trace on this number 2026-09-08 → 09-10 and have
asked for the times at which trouble occurred (queue 185). **12:34:18 is exactly
such a time**, and it is the kind their own trace can be lined up against: at
that instant their network moved this subscriber from LTE to GSM for a voice
call. The open question in the letter — whether **MMTEL** rather than mere IMS
registration is authorised for this subscription — is what decides whether that
was correct.

## ☠️ Corrections made while reading this, both mine

1. **"I did not capture the transition" was wrong.** It was said after grepping
   only the `CALL` lines, which filtered out the two `MODEM` lines that hold the
   whole answer. Printing the *full* log settled it in one line. Grep narrower
   than the question is how a complete record reads as an incomplete one.
2. **The radio-quality stream was not running.** `--signal-setup=0` was restored
   after the instrument's gate and never set back, so `rsrp`/`rsrq`/`snr` — the
   column offered to One HU — collected **nothing** for the first call. Set to
   10 s afterwards; it is now producing (`rsrp -95, rsrq -9, snr 13.4`). **A gate
   that changes device state has to put back the state the measurement needs,
   not the state it found.**

☠️ **The 15-digit identifier scan fired on `snr: <14.800000000000001>`** — the
float, not an IMSI. The log is clean. But a scrubber that cries wolf teaches its
user to wave it through, which is the same failure as a tone that fires too
often; the pattern needs a word boundary it does not have.

☠️ **No subscriber identifier appears in this capture.** The letter quoted in
the session carries MSISDN, IMSI and IMEI; none of it is here.

☠️ **And the absence of identifiers was not a good enough reason to commit the
log.** It was committed on 2026-09-08 after passing the identifier scan, and the
operator was right to object: the scan asks "is there an IMSI in this", and the
question that matters is "whose behaviour does this record". A scan cannot
answer the second. Older tracked call artefacts from earlier sessions —
`2026-08-30_terse-call/`, `2026-09-05_call-wedges-the-touchscreen/`,
`2026-09-05_ut-call-rat-newsim/`, `night/runs/adsp-20260819/ofono-*.txt` — were
checked at the same time and carry **no** MSISDN, IMSI, IMEI or ICCID, but they
are already on `origin/main`, so removing them is a history rewrite and the
operator's call to make.
