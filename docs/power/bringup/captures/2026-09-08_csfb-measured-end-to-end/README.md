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

## Second call, 18:34 — two for two, and the signature is reproducible

| | call 1 (12:34) | call 2 (18:34) |
|---|---|---|
| LTE → GSM+GPRS | 12:34:**18** | 18:34:**20** |
| call object appears | 12:34:20 (**+2 s**) | 18:34:22 (**+2 s**) |
| answered | after 9 s of ringing | after 11 s |
| ended | 19 s of talk | 16 s |
| GSM+GPRS → LTE | 12:34:49 (**+1 s**) | 18:34:50 (**+1 s**) |
| **off LTE** | **31 s** | **30 s** |

Both calls audible in both directions, both answered. The two intervals that
depend on the network rather than on the operator are **identical**: the drop
leads the call object by exactly 2 s, and the return follows the end by exactly
1 s.

### ★ An independent confirmation the bitmask cannot give

The `Modem.Signal` stream was running for this call and it **stops for the
duration of it**:

```
18:34:12  rsrp -94  rsrq -12  snr 21.0     <- last LTE sample before
    ...   (40 s with no LTE measurement at all)
18:34:52  rsrp -84  rsrq  -9  snr 21.4     <- first after
```

There is nothing to measure because the modem is not on LTE. That is the same
conclusion as `AccessTechnologies: 10`, reached through a different interface,
and neither depends on the other.

☠️ **One thing not to over-read**: `rsrp` improves from about −94 to about −86
across the call and stays there. That may be a cell reselection on return to
LTE, or the operator having moved. One instance, two possible causes, no
instrument that separates them here.

## The times for One HU

Their trace window is 09-08 → 09-10 and they asked for the moments trouble
occurred. These are the two so far, in their local time (CEST):

- **2026-09-08 12:34:18** — subscriber moved LTE → GSM for an incoming voice call
- **2026-09-08 18:34:20** — the same, 31 s and 30 s off LTE respectively

Neither call *failed*: both rang, both were answered, audio was fine in both
directions. **The fault being reported is not a broken call — it is that a
handset registered on LTE with a live data bearer is moved to GSM for voice at
all.** That distinction matters in the report: asking them why CSFB was chosen
is a different question from reporting a service outage, and the letter already
frames it that way.

## ★★ Third call, 18:39 — OUTGOING, and the asymmetry is the finding

The first two were incoming (MT). This one was placed **from** the phone (MO),
and it falls back too — but at a different moment.

```
18:39:44  CallAdded, State 0 -> 1 (dialing)      tech = LTE
18:39:45  AccessTechnologies: <uint32 10>        LTE -> GSM+GPRS, 1 s AFTER dialling
18:39:48  State 1 -> 2 (ringing at the far end)
18:40:03  State 2 -> 4 (answered, after 15 s)
18:40:11  State 4 -> 7 (ended, 8 s of talk)
18:40:12  AccessTechnologies: <uint32 16384>     back to LTE
```

| | call 1 (MT) | call 2 (MT) | **call 3 (MO)** |
|---|---|---|---|
| drop relative to the call object | **−2 s** (before) | **−2 s** (before) | **+1 s (after)** |
| ringing | 9 s | 11 s | 15 s |
| talk | 19 s | 16 s | 8 s |
| return after the end | +1 s | +1 s | +1 s |
| **off LTE** | 31 s | 30 s | **27 s** |

★ **The sign of that first interval is the result.** Incoming: the device is
already on GSM two seconds *before* a call object exists — the network paged it
on the CS domain and the fallback happened first. Outgoing: the call is created
**while still on LTE**, and the drop follows one second later — the handset
began the origination on LTE and was moved.

Both are CSFB. But the MO case shows the device *trying* on LTE, which is the
half a subscriber-side argument needs: it is not the handset declining to use
IMS.

☠️ What this cannot say is **who** decided. From the handset, "the modem chose
CSFB because it knows MMTEL is not authorised" and "the network redirected an
LTE origination" produce the same one-second gap. Separating them needs the
network side — which is exactly what One HU are measuring.

### A third independent confirmation, from a third interface

The `Modem.Signal` interface switches which radio it reports:

```
18:39:42   'Lte'                    only
18:39:49   'Lte' + 'Gsm'            the transition, both present
18:39:51   'Gsm'  rssi -69
18:40:02   'Gsm'  rssi -67
18:40:12   'Gsm'  rssi -70
18:40:22   'Lte' + 'Gsm'            back
```

So the fallback is attested three ways: the `AccessTechnologies` bitmask, the
disappearance of LTE measurements (call 2), and the `Signal` interface changing
which radio it describes (call 3).

## ☠️ CORRECTION: those three are not independent, and this page said they were

The sentence above originally read *"none depending on the others"*. **That is
wrong.** All three come from **ModemManager**, out of the same QMI reports from
the same modem. They are separate code paths inside one daemon, not separate
measurements of the radio. If the modem misreported its access technology, all
three would agree and all three would be wrong together.

The operator then reported a fourth: **the pmOS status icon changed from 4G to
2.5G during the call**, which matches exactly — `2.5G` is GPRS, and the measured
`AccessTechnologies: 10` is `GSM | GPRS`. It is worth recording, but it is a
**fourth rendering of the same source**, not a fourth measurement: phosh draws
that icon from ModemManager too.

★ What it *does* add is that the fallback is **visible to the subscriber without
any instrument**. That matters for the report: One HU are asking a customer what
they observed, and "the icon dropped from 4G to 2.5G for the duration of every
call" is an observation anyone can make and check, independent of this repository
and its tooling.

Two things would be genuinely independent, and only one is available:

- reading the modem directly over QMI or AT, bypassing ModemManager entirely —
  not done here, and the honest status of the claim until it is;
- **the network side** — which is precisely what One HU are measuring now.

☠️ The GSM rssi (−67 … −70) reads stronger than the LTE rssi (−87). Different
bands and different measurement definitions; nothing follows from the comparison
and it is recorded only so a later reader does not draw something from it.

## The times for One HU — three now

- **2026-09-08 12:34:18** — incoming, moved LTE → GSM, 31 s off LTE
- **2026-09-08 18:34:20** — incoming, 30 s off LTE
- **2026-09-08 18:39:45** — **outgoing**, dialled on LTE and moved 1 s later, 27 s off LTE

All three rang, all three were answered, audio was good in both directions on
all three. **Nothing failed.** The question put to them is why a handset
registered on LTE, with a live data bearer, is moved to GSM for voice — and the
outgoing call sharpens it, because there the handset demonstrably started on LTE.

## ★★★ The direct QMI read — genuinely independent, and it changes the question

Asked for by the operator after the correction above. `qmicli` speaks to the
modem over QRTR **beside** ModemManager rather than through it, so this is the
first evidence here that does not come from MM. Raw:
`qmi-direct-system-info.txt`.

☠️ **Done in proxy mode (`-p`) on purpose.** ModemManager owns the QMI channel;
taking it would have killed the running callwatch measurement in the middle of
One HU's window. The first attempt used the wrong node (`qrtr://1`) and failed
with `QMI protocol error (3): 'Internal'` — MM was checked immediately
afterwards and was untouched. `qrtr://0` is the modem.

### The gate: it agrees where the answer is already known

```
Registration state: 'registered'      Radio interfaces: [0]: 'lte'
CS: 'attached'                        PS: 'attached'
```

`lte` and `registered`, matching ModemManager. The instrument reproduces a
regime whose answer is on record, which is what licenses the rest.

★ And it already adds something MM's summary does not show: **`CS: 'attached'`**.
The device is attached to the circuit-switched domain *while camped on LTE* —
that is the standing precondition for CSFB, present before any call.

### ★★ And then the field that reframes the whole investigation

```
Domain:                    'cs-ps'
Voice support:             'yes'
IMS voice support:         'yes'
Cell access:               'all-calls'
Registration restriction:  'unrestricted'
```

**`IMS voice support: 'yes'`** is the network's own indication — the *IMS Voice
over PS Session Supported* bit the network returns in the LTE attach/TAU accept.
**The network is telling this device, on this cell, that voice over IMS is
available to it.**

The 2026-09-06 letter *asserted* this ("a hálózat kifejezetten jelzi, hogy az
IMS-en keresztüli hanghívást támogatja"). It is now **measured, with the field
name**, from the modem, independently of ModemManager.

### What that makes the chain

1. The network says IMS voice is supported — **measured 2026-09-08, above.**
2. The device's IMS registration is refused with `500 Server Internal Error` and
   the operator's internal diagnostic — **measured 2026-09-06.**
3. With no IMS registration there is nowhere to route voice but the CS domain,
   so every call falls back — **measured 2026-09-08, three times.**

★ **Every link is now measured, and only one is broken.** The single blocking
point is the `500`. That is why question (a) of the letter — what does
`399 5144.2233.S.260.5.94.255.255.5938.0.0` mean — is the one that matters:
everything on either side of it works.

☠️ **What `IMS voice support: yes` does NOT establish.** It is a *radio/network
capability* indication for the cell and the attach, not a statement about the
subscription. MMTEL provisioning lives in the HSS and this bit does not report
it. So it does not answer question (b); it sharpens it, by removing the
possibility that the network is simply not offering VoLTE here.

☠️ **Location data was stripped before this was committed.** Cell ID, tracking
area code, location area code, MCC and MNC identify where the phone was standing.
The kept file carries `<redacted>` in their place, and a residual scan for any
remaining 6-digit-or-longer number comes back empty. The unredacted output was
never written to the repository.

## ★★★ Why there is no 4G call: the modem's own IMS is switched OFF

The operator asked whether the current stack can do 4G voice at all. The modem
answers, and the answer is not the one the investigation had assumed.

### The modem has an IMS stack of its own

It advertises four IMS-capable QMI services (`qrtr-lookup`):

| service | |
|---|---|
| 9 | Voice service |
| **18** | **IMS settings service** |
| 33 | IMS application service |
| 77 | IMS QMI Priv service |

So voice over IMS does **not** require an AP-side SIP stack on this hardware.
The modem can register and place IMS calls itself; the AP's job would be to
enable it and dial through the Voice service.

### And every IMS service in it is disabled

`--ims-get-ims-services-enabled-setting`, after `--ims-bind`:

```
          Voice service enabled: no
Video Telephony service enabled: no
     Voice WiFi service enabled: no
      UE to TAS service enabled: no
            SMS service enabled: no
           USSD service enabled: no
```

and consequently `--imsa-get-ims-registration-status`:

```
    Status: 'not-registered'
Technology: 'wwan'
```

★ **That is the answer.** Nothing is broken and nothing is refusing us: the
modem's Voice-over-IMS is simply **switched off**, so it never registers, so
voice has nowhere to go but the CS domain, so every call is CSFB. The stock
software turns these on at boot; ModemManager has no notion of them —
`mmcli -m 0` mentions IMS nowhere.

☠️ These queries return `QMI protocol error (70): 'InvalidOperation'` until the
client is **bound** (`--ims-bind` / `--imsa-bind`). An unbound query looks
exactly like a service that does not work, and the first attempt read that way.

### ★★ What it does to the imsd plan

`#177` builds an **AP-side** SIP/IPsec stack (`imsd`) to do what this modem
already does in firmware, and that stack is the one being answered with
`500 Server Internal Error`. The stock software — which uses the **modem's**
IMS — registers successfully, by the operator's own account in the letter.

So the highest-value lead is no longer "make our SIP registration acceptable"
but **"turn on the IMS stack that already works"**.

☠️ **Stated as a lead and not a fix, for three reasons:**

1. **libqmi 1.39 has no setter.** `--ims-get-ims-services-enabled-setting`
   exists; there is no `--ims-set-…` in this build. Writing it needs a newer
   libqmi, a raw QMI message, or ModemManager support that does not exist.
2. **Enabling the flag may not be sufficient.** The modem's IMS also needs its
   configuration — P-CSCF, the IMS APN, the vendor's provisioning — normally
   supplied by the stack that also sets the flag.
3. **It does not answer question (b).** Whether MMTEL is provisioned for the
   subscription is still an HSS question, and still One HU's to answer. If it is
   not, a registered modem IMS will still not carry voice.

### What is measured, in one place

| | |
|---|---|
| network offers IMS voice | **yes** (`IMS voice support: 'yes'`) |
| modem has an IMS stack | **yes** (services 18, 33, 77) |
| modem's IMS voice enabled | **NO** |
| modem's IMS registered | **no** — `not-registered` |
| ModemManager IMS support | **none** |
| libqmi setter for it | **none in 1.39** |
| result | CSFB on every call, three for three |
