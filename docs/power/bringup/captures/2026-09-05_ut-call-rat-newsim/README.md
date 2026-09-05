# UT terminating calls on a second SIM: CSFB every time, with IMS registered

**Date:** 2026-09-05, 04:58–05:05 CEST
**Slot:** a (Ubuntu Touch, Halium, 4.9) — the oracle, with the full vendor Qualcomm IMS stack
**Card:** the operator swapped the dev FP3's SIM. New card: ICCID `<iccid-new-card>`,
IMSI `<imsi-new-card>`, MCC 216 / MNC 70, network name **One HU**.
**Instrument:** `ut-callwatch2.sh` (in this directory), 1 Hz, via `org.ofono` D-Bus.
**Raw:** `ut-callwatch2.txt` (timeline), `calls2-journal.txt` (journal).
Caller MSISDNs are redacted to `<caller-A>` / `<caller-B>`.

## Why this run exists

Run #1 (`../2026-09-05_ut-call-rat/`) showed the oracle taking a terminating call
on EDGE and concluded that the earlier claim *"the 2G dependency is ours, not the
network's"* was backwards. That run had one weakness: it never queried the modem's
actual IMS state — its `ims=` column counted something else — and the card was
never identified. This run changes exactly one thing, the card, and adds the real
instrument.

## What the instrument measures now

`org.ofono.IpMultimediaSystem.GetProperties` on `/ril_0`, sampled every second
alongside the RAT and the call state:

| column | source |
|---|---|
| `tech`, `reg` | `NetworkRegistration.Technology` / `.Status` |
| `imsreg` | `IpMultimediaSystem.Registered` |
| `imsvoice` | `IpMultimediaSystem.VoiceCapable` |
| `imsdev` | count of `imsradio*` netdevs — kept only for comparability with run #1 |
| `states` | `VoiceCallManager.GetCalls` call states |

**Gate (rule 5).** The rewritten sampler was first run for 8 s against a regime
already read directly out of D-Bus — idle, `registered`, `lte`, One HU — and
reproduced it, including the card identity. Only then was it used on a call.
That gate is what caught the `imsdev` problem below.

Idle state before any call, straight from D-Bus and reproduced by the sampler:

```
Registered=true  Registration=auto  VoiceCapable=true  SmsCapable=true
RadioSettings.TechnologyPreference = nr
NetworkRegistration = registered / lte / One HU
```

## The two calls

```
call A (caller A)                       call B (caller B)
04:58:48  tech=lte                      05:03:40  tech=lte
04:58:49  tech=edge         <- fallback 05:03:41  tech=edge        <- fallback
04:58:52  states=incoming             05:03:43  states=incoming
    --                                  05:04:08  states=active     <- ANSWERED
04:58:57  call gone                     05:04:29  call gone
04:58:58  tech=lte                      05:04:30  tech=lte
imsreg=true imsvoice=true throughout    imsreg=true imsvoice=true throughout
```

Journal, call end:

```
04:58:57  ofonod: Call 1 ended with cause 44 -> ofono reason 3
05:04:28  ofonod: Call 1 ended with cause 16 -> ofono reason 2
```

`cause` is the 3GPP TS 24.008 disconnect cause: **44 = "requested circuit/channel
not available"**, **16 = "normal call clearing"**. `ofono reason` is
`enum ofono_disconnect_reason` (0 UNKNOWN, 1 LOCAL_HANGUP, 2 REMOTE_HANGUP,
3 ERROR) — ⚠️ that enum ordering is quoted from knowledge of the ofono header,
not verified against a checkout in this session; the `cause` numbers are the
load-bearing ones and they are standard.

**What the operator observed, and it matches.** On call A the FP3 rang about
twice and then died, and **the caller never heard a ringback tone at all**. On
call B the caller heard the first ringback *after* the FP3 had already rung
twice. So on A the callee was alerted locally but no CS bearer was established
back toward the originating side — which is what cause 44 says. On B the same
sequence completed, with the caller's ringback lagging the callee's ringing by
about two rings, which is the CSFB setup latency made audible.

## What this establishes

1. **The fallback precedes the call.** On both calls the RAT drops to EDGE 2–3 s
   *before* ofono is told there is an incoming call. The 2G is not a side effect
   of call setup — 2G is what the call arrives on. That is CSFB by definition,
   and run #1 could not separate the ordering.
2. **A whole answered call ran on EDGE.** Call B was answered and held for 21 s,
   every sample `tech=edge`, and returned to LTE one second after teardown. No
   SRVCC, no mid-call promotion.
3. **This happened with IMS registered and voice-capable.** `imsreg=true`,
   `imsvoice=true` in every sample of both calls, on a stack that has the vendor
   IMS HAL (`vendor.qti.hardware.radio.ims@1.2::IImsRadio/imsradio0`, seen
   connecting in run #1's journal).
4. **The caller is not the variable.** The two calls came from two different
   originating numbers and produced identical callee behaviour.
5. **The card is not the variable either.** Run #1 used the previous card, this
   run a different one, on a network that offers IMS voice. Both CSFB.

## The consequence for the port

The plan that an IMS/VoLTE stack for pmOS would keep terminating calls off 2G is
**not supported by the oracle**. The oracle *has* a full vendor IMS stack, is IMS
registered and voice-capable, and still receives its calls over CS on GERAN.
Writing an IMS stack would therefore not, on this network and these
subscriptions, move a terminating call off 2G.

This does not say IMS is worthless — it says it is not the lever for the 2G
dependency, and the low-duty sleep work must not be justified by "IMS will
replace 2G paging later".

## What is still open

- Whether `IpMultimediaSystem.Registered=true` reflects a completed IMS *voice*
  (MMTEL) registration or only the modem's intent. ofono cannot distinguish
  these; QMI/diag can.
- Whether the terminating domain selection is the network's (T-ADS pointing at
  CS) or the device's. Same instrument gap.
- **Whether a factory Android on this same card behaves the same** — queue #160.
  That is now the single remaining discriminator: if stock Android also lands on
  GSM for a terminating call, the network settles it; if it holds LTE, the
  difference is above the modem and in the stack.

## Operator observation on the calling handset, same session

While placing these two calls the operator watched *Settings -> SIM status ->
Mobile network type* on the daily **factory Android** handset. Its **SIM2 shows
4G while idle and switches to GSM when a call is placed**. A note from
2026-09-03 records that the *other* SIM in that same handset keeps 4G through a
call.

Same handset, same Android, same modem, two cards, two behaviours. The variable
is therefore the **card / subscription VoLTE provisioning**, not the device and
not the software. Two consequences:

- Stock Android does not protect against CSFB either, when the card is not
  provisioned for VoLTE. So the FP3 landing on EDGE is not by itself evidence of
  a fault in this port.
- VoLTE *is* available on this network - the other card demonstrates it on the
  same handset. The question is decided at the subscription, not at the RAN.

This makes queue #160 the decisive and now well-controlled test: put the dev card
into that handset, where a different card is known to hold 4G. GSM there means the
dev subscription has no VoLTE and no amount of software work on pmOS or UT will
change it; 4G there means the stack is the difference after all and the conclusion
above must be narrowed.

**Caveat, stated because the two are easy to conflate.** What the operator saw is
a **mobile-originated** call on the calling handset; everything else in this
capture is **mobile-terminated** on the FP3. Both are CS domain selection, but
MO-CSFB and MT-CSFB are different procedures and may in principle differ. The
observation is recorded as what it is.

## Corrections this run forced

- **Run #1's `ims=` column is of unknown provenance.** Its sampler script was not
  kept, so the earlier claim that the column counted `imsradio*` netdevs cannot
  be verified and is withdrawn as a statement. What is measured here: zero
  `imsradio*` netdevs exist while the IMS HAL service is present and
  `IpMultimediaSystem.Registered` is true — so a netdev count is not an IMS state
  either way, which is the part of the earlier retraction that stands.
- **No `cause` was recorded for run #1's call.** Its journal capture ends at
  04:34:34, the same second the call tore down, so the line was cut. Cause 44 is
  therefore *not* known to be new — run #1 simply has no data there.

---

# Part 2 — outgoing calls, and the answer to #160

**Raw:** `ut-mo.txt`, `mo-journal.txt` (same instrument, 1 Hz). MSISDNs redacted.

## Outgoing from the FP3 on UT: CSFB as well

Two dial attempts, 05:15:54 and 05:16:19:

```
05:15:54  tech=lte   states=dialing     <- the dial starts on LTE
05:15:56  tech=edge  states=dialing     <- fallback, 2 s in
05:15:58  tech=edge  states=alerting
05:15:59  tech=edge  (call gone)
05:16:00  tech=lte

05:16:19  tech=lte   states=dialing
05:16:20  tech=edge  states=dialing
05:16:24  tech=edge  (call gone)
05:16:25  tech=lte
```

ofono routes the dial through the IMS HAL and the HAL accepts it:

```
ims:Dialing (ext) <msisdn>
imsradio0< [00000003] 2 dial
ims:qti_ims_call_result_response 0      <- accepted
                                        then: LTE -> EDGE
```

So the stack does not decline to try VoLTE - it tries, the request is accepted,
and the call still lands on GERAN. Mobile-originated behaves like
mobile-terminated, which closes the MO/MT caveat raised in Part 1.

☠️ **Both of these attempts were to the operator's own number** and were therefore
rejected by the network; they are *not* evidence about call reliability. They
remain valid as RAT evidence only because the fallback to EDGE **precedes** the
failure in both, by 2 s and 1 s respectively. An earlier draft of this page read
3 of 4 calls as failures and inferred an unreliable 2G leg - that inference is
**withdrawn**. The honest count is two valid calls: one completed (21 s), one
failed with cause 44.

## #160 is answered: the dev card has no VoLTE

The two phones had their cards swapped before this session: the daily
factory-Android handset's SIM2 went into the FP3 (it is the One HU card measured
in Part 1), and **the card that had been in the FP3 went into the daily Android
handset**. That is exactly the experiment queue #160 asked for, and it ran.

Operator's reading from that handset's *Settings -> SIM status -> Mobile network
type*, which updates live:

> GSM while ringing, GSM after answering, 4G after the call ended.

**The dev card, in a certified stock-Android handset, takes a terminating call on
GSM.** The 2026-09-03 note records that a *different* card in that same handset
holds 4G through a call, so the handset is demonstrably capable and the network
demonstrably offers VoLTE. The variable is the subscription.

### What this settles

- **No software work on our side can give this phone a 4G call on this card.**
  Not an IMS stack for pmOS, not a change to UT. The lever does not exist above
  the subscription.
- The `imsd` cost estimate and the "CSFB is a dependency" lead are both answered:
  the dependency is real, and it is not ours to remove.
- The low-duty sleep work must not be justified by "IMS will replace 2G paging
  later". On this card it will not.

### What it does not settle

- Whether a VoLTE-provisioned card would work on **pmOS** - the oracle shows the
  vendor stack manages it only where the subscription allows, and pmOS has no IMS
  at all. Reopening that needs a provisioned card in the FP3, not more analysis.
- ⚠️ One residual assumption: the operator read one SIM's status page on a
  dual-SIM handset. It is taken to be the ringing line's. If it was the other
  slot's, this section's conclusion does not follow - re-reading it with only the
  dev card inserted would remove the assumption.

---

# RETRACTION, same day — the Android's own VoLTE switch was off

The #160 conclusion above is **withdrawn**. It rested on a stock-Android handset
showing GSM for a terminating call on the dev card, read as evidence that the
subscription is not provisioned for VoLTE.

The operator then checked the handset itself: **"4G hívás" (VoLTE) is off by
default on that Android, per SIM slot, and it was off for the slot holding the dev
card** — the phone labels it "ajánlott" (recommended) but does not enable it.

A device-side switch in the off position fully explains a GSM call. Nothing about
the subscription follows from that measurement. The caveat this page already
carried - that a dual-SIM status page might have been read for the wrong slot -
was the right shape of doubt aimed at the wrong mechanism; the actual confounder
was one setting away and neither of us looked at it before concluding.

**What still stands, because it was measured on the FP3 and not inferred from the
Android:**

- Both terminating calls and both originating attempts on the UT oracle fell back
  to EDGE, with the fallback *preceding* the call in every case.
- `IpMultimediaSystem.Registered=true` and `VoiceCapable=true` throughout.
- ofono routes the dial through the IMS HAL and the HAL accepts it.

**What is now open again:** whether the dev subscription carries VoLTE at all, and
therefore whether an IMS stack could ever help. The re-test is the same experiment
with the switch on — and with mobile data enabled for that SIM, so a second
unknown is not introduced.

## Re-test (#162): the dev subscription DOES carry VoLTE

With the handset's per-SIM **"4G hívás" (VoLTE) switch turned on** - and with mobile
data and "data during calls" both left **off** for that slot - the dev card in the
stock Android **held 4G through the call**, read live from *Settings -> About phone
-> SIM status -> Mobile network type*, for calls from **both** of the calling
handset's SIMs.

Three things follow:

1. **The subscription is provisioned for VoLTE.** The claim that it is not, and the
   claim built on it that no software work on our side could ever give this phone a
   4G call, are **wrong**. Both were stated here earlier today; neither survives.
2. **The IMS PDN comes up without user data.** VoLTE registered with mobile data
   off and "data during calls" off, so the IMS APN is raised independently of the
   subscriber's data service - worth knowing, because the absence of a data plan
   had been offered as a possible confounder and is not one.
3. **The variable is above the subscription.** The card that CSFBs on our FP3 is
   the *other* one, so the direct comparison has not been made yet - see below.

### What is still missing: the FP3 has never been tested with a known-VoLTE card

Today's measurements do not form a comparison, because the card moved:

| card | daily Android (stock) | FP3 (UT oracle) |
|---|---|---|
| dev card | **4G** (measured, #162) | not tested |
| ex-SIM2 (now in the FP3) | not tested | **EDGE** (measured, Parts 1-2) |

Two different cards in two different devices decide nothing about either. The
decisive test is the diagonal that is missing: **put the dev card - now proven
VoLTE-capable on this network - back into the FP3 and call it.** If it still lands
on EDGE, the difference is the device or the stack and nothing else, and that is
the first result in this whole thread that would actually license a software
conclusion.

☠️ And the earlier "tariff" explanation for why two SIMs in the daily handset
behaved differently is now suspect for the same reason the #160 answer was: the
per-SIM VoLTE switch is off by default, so that observation may have been two
switch states rather than two tariffs. It should not be relied on until re-read.

If the FP3 does get VoLTE with this card, the next gate is device whitelisting -
operators commonly gate VoLTE on the IMEI/TAC, which is a known wall for custom
ROMs and Linux phones, and the FP3's status with this operator is unknown.

## The corporate SIM: a proper control, and it restores the tariff explanation

The daily Android holds two cards: the **corporate** SIM (which placed the calls)
and the **dev** card. On the corporate SIM both "4G hívás" **and** mobile data are
enabled - and its calls still ring out on **EDGE**.

| card | device | switches | RAT during the call |
|---|---|---|---|
| dev | daily Android | 4G calling on (data off) | **4G** |
| corporate | daily Android | 4G calling **and** data on | **EDGE** |

Same handset, same Android, same modem, both switches on, two subscriptions, two
outcomes. The device-side confounder that invalidated the #160 answer is removed
here, so this is the first clean statement of the point: **on this operator, VoLTE
is a property of the subscription and it differs between subscriptions.**

That also settles the note flagged as suspect earlier on this page - the older
"the two daily-handset SIMs differ by tariff" observation. It could have been two
switch states; with the switches read and on, it is not. The tariff explanation
stands.

⚠️ One asymmetry worth stating: the corporate observation is a **mobile-originated**
call and the dev-card observation was **mobile-terminated**. Both are CS domain
selection and the FP3 was measured to CSFB in both directions, so they are being
treated as comparable - but they are not the identical procedure.

### And this does not exonerate or convict the FP3

The card in the FP3 is neither of these two. It is the daily handset's former
SIM2, and **its VoLTE status has never been measured in a device that could use
it** - the UT oracle has no such switch to read and lands on EDGE regardless. So
the FP3's EDGE remains unattributed: it is compatible with a non-VoLTE
subscription, with a device/stack limitation, and with both.

The decisive test is unchanged: the **dev card**, now measured as VoLTE-capable on
this network, in the FP3.

## Part 3 — one call, both legs observed at once

**Raw:** `ut-mo2.txt`, `mo2-journal.txt`. The FP3 (UT, holding the `…3899` card)
called the daily Android (holding the dev card), and both ends were read.

```
FP3 / UT / card ...3899                  daily Android / dev card
06:29:50  tech=lte   states=dialing
06:29:52  tech=edge  states=dialing      <- CSFB, 2 s into the dial
06:29:55  tech=edge  states=alerting
06:30:08  tech=edge  states=active       <- answered      4G   (operator's reading)
06:30:17  tech=edge  call ends           <- 9 s of speech
06:30:18  tech=lte
imsreg=true imsvoice=true throughout
```

Journal: `ims:Dialing (ext) <msisdn>` → `imsradio0< [00000006] 2 dial` →
`ims:Dialing return 6`, and the call still went to GERAN.

**Why this one is worth more than the others.** The two legs are the *same call*,
so they share the moment, the operator and the radio conditions. At 06:30:08 this
network was carrying a call over IMS for one subscription while refusing it to
another. That eliminates "LTE voice was not available just then" as an
explanation, which no earlier capture could rule out.

⚠️ It does **not** separate device from subscription: the FP3 differs from the
Android in both the card and the stack. It removes the network from the list; the
remaining two are still tied together, and only #163 unties them.

### Also settled here: UT has no VoLTE switch that was left off

The Ubuntu Touch setting the operator found (2G/3G/4G/5G selected) is the **network
mode preference**, not a VoLTE toggle — it is ofono's
`RadioSettings.TechnologyPreference`, which reads `nr`, i.e. everything permitted,
the most permissive setting available. `org.ofono.IpMultimediaSystem` does expose
`SetProperty`, `Register` and `Unregister`, so IMS *can* be driven from software,
but `Registration` is already `auto` and `Registered` is already `true`. There is
no switch on this side that we forgot to turn on — which is what made the Android's
per-SIM switch such an easy confounder to miss.

### ☠️ The instrument was writing identifiers into its own captures

`ut-callwatch2.sh` printed the full ICCID and IMSI in every capture header, so each
capture it produced had to be scrubbed by hand — and this one was caught only
because `tests/no-identifiers.sh` had been written earlier the same day. The script
now prints the last four ICCID digits and the MCC/MNC, which is all a reader needs
to tell the cards apart, and nothing that identifies a subscriber. Fix the
instrument, not the output.

## Part 4 — the other direction, same asymmetry, both legs again

The same window carries a second call, this time **Android → FP3**, with the caller
(dev card) watched throughout:

```
FP3 / UT / card ...3899                  daily Android / dev card (caller)
06:35:35  tech=edge                      <- fallback, 2 s BEFORE the call is signalled
06:35:37  tech=edge  states=incoming                         4G  while ringing
06:35:57  tech=edge  states=active       <- answered         4G  while speaking
06:36:08  tech=edge  call ends           <- 11 s of speech
06:36:09  tech=lte
imsreg=true imsvoice=true throughout
```

With Part 3 the matrix is now complete in both directions, with both legs of each
call read at the same time:

| call | FP3 leg (card ...3899) | Android leg (dev card) |
|---|---|---|
| FP3 → Android (06:29) | EDGE, dialing to teardown | 4G |
| Android → FP3 (06:35) | EDGE, paging to teardown | 4G, ringing **and** speech |

Two calls, opposite directions, four legs, one network, minutes apart: the dev
subscription is carried over IMS every time and the `…3899` subscription over CS
every time. The caller is not the variable, the direction is not the variable, and
the moment is not the variable.

☠️ **A caller on VoLTE talking to a callee on CS is normal, not a contradiction.**
Each leg is negotiated independently and the IMS core interworks to the circuit
domain, so "the caller saw 4G the whole time" says nothing about what reached the
other phone. It is only informative here because both ends were instrumented.

And the fallback again precedes the call: 2 s before ofono is told there is an
incoming call, exactly as in Parts 1 and 2, so the CS paging - not the call setup -
is what pulls this subscription down to GERAN.

**Still unseparated:** card and stack. The FP3 has never held a card known to get
VoLTE. #163 is unchanged and is the only measurement that resolves it.
