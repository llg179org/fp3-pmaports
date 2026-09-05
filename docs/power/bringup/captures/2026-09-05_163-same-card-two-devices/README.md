# #163 — the same card in two devices: the FP3 is the variable

**Date:** 2026-09-05, 07:13–07:17 CEST · **Slot:** a (Ubuntu Touch, Halium, Android
10 base, kernel 4.9) · **Card:** the dev card, ICCID `…6542`, One HU (MCC 216 / MNC
070) · **Raw:** `ut-163.txt`, `163-journal.txt`, `ims-registration-dev-card.txt`.
MSISDNs redacted; the operator's IMS domain is kept.

## Why this measurement decides the thread

Every earlier capture compared **two cards in two devices**, which decides nothing
about either. This one moves the card that is *known* to get VoLTE on this network
into the FP3, so the subscription is held constant and only the device changes.

That the card gets VoLTE is established twice over, independently:

- in the daily stock-Android handset it held **4G through a whole call**, while
  ringing and while speaking, with only the per-SIM "4G hívás" switch on;
- on the FP3 it completes a real IMS registration against the operator's core -
  `state:0` REGISTERED, `radiotech:15`, empty `error_msg`, and a populated
  P-Associated-URI `sip:<msisdn>@ims.mnc070.mcc216.3gppnetwork.org|tel:<msisdn>`.

## The result

```
07:16:44  tech=lte
07:16:46  tech=edge                      <- fallback, 2 s BEFORE the call is signalled
07:16:48  tech=edge  states=incoming
07:16:58  tech=edge  states=active       <- answered
07:17:10  tech=edge  call ends           <- 12 s of speech
07:17:12  tech=lte
```

| device | the same dev card |
|---|---|
| daily handset, stock Android | **4G**, ringing and speech |
| **FP3, Ubuntu Touch** | **EDGE**, paging to teardown |

**The variable is the device, not the subscription.** This is the first result in
the thread that licenses a software conclusion, and it reverses the two closures
attempted earlier today in the opposite direction.

## What is now established, and what it costs to ignore

- The subscription **has** VoLTE. Proven by the Android call and, independently, by
  the P-Associated-URI the operator's IMS core returns to the FP3 itself.
- The FP3 **registers with that IMS core** and is then CS-paged anyway. The network
  chooses the terminating domain from what it knows about the UE, so it is
  answering "this device, no voice over IMS".
- Both cards register identically on the FP3 - same domain, same `radiotech:15`,
  same URI shape, no error - so the difference between them is not visible at the
  registration layer at all.

**Therefore the remaining question is device-side and sharp:** the registration
completes but the network does not treat this UE as IMS-voice-capable. The two
candidates are the media feature tags the UE offers in its SIP REGISTER (an
`+g.3gpp.icsi-ref="…mmtel"` / audio media tag that is absent or refused), and
operator gating on IMEI/TAC, which is a documented practice and a known wall for
custom ROMs and Linux phones.

## Corrections this closes

Two conclusions were published earlier today and are now settled against:

- *"The dev subscription has no VoLTE, so no software work on our side can help."*
  Retracted the same day when the Android's own VoLTE switch turned out to be off;
  now positively disproven.
- *"An IMS stack for pmOS is not the lever for the 2G dependency."* The reasoning
  was that the oracle has a full vendor IMS stack and still CSFBs. That observation
  stands, but its conclusion does not follow: the oracle's IMS **registers and is
  still refused voice**, which is a solvable, device-side problem rather than a
  property of the network.

## The strongest device-side candidate: the modem is on a generic carrier config

Having established that the device is the variable, the obvious place to look is
the **modem carrier configuration (MBN)**, because on Qualcomm that is largely what
enables VoLTE — the IMS stack registers under a generic config, but MMTEL voice is
gated by the carrier MBN.

From `../2026-08-29_pdc-configs/pmos-software.txt`, 25 configs are present in the
modem and the **active** one is:

```
Configuration 1:
    Description: ROW_Commercial      <- generic "Rest Of World", not a VoLTE config
    Status:      Active
```

while the same list contains, among others, `Global-VoLTE-Vodafone`,
`Germany-VoLTE-Vodafone`, `IE-VoLTE-Vodafone`, `Italy-VoLTE-Vodafone`,
`Netherlands-VoLTE-Vodafone` and `Non_VoLTE-Vodafone`.

Read on the device (as root, UT slot), the vendor MBN store confirms the shape:

```
/android/data/vendor/modem_config/mcfg_sw/generic/eu/
  bouygues dt ee elisa h3g kpn nos orange proximus sfr sky swisscom
  tdc tele2 telefoni telenor telia tim vodafone

  vodafone/volte/  ->  cz germany global ie italy netherla portugal
                       safrica spain turkey uk        <- NO hungary
  dt/commerci/     ->  austria croatia cz greece hungary nl pl slovakia
```

So there is **no Vodafone-Hungary VoLTE MBN**, but there is a
`vodafone/volte/global` one — and One HU is the former Vodafone Hungary
(MCC 216 / MNC 070).

**The hypothesis, stated as a hypothesis:** the modem runs the generic
`ROW_Commercial` config, under which IMS still registers (which is exactly what we
measure — registration succeeds, the operator returns a P-Associated-URI) but MMTEL
voice is not enabled, so the network has nothing to route a terminating call to and
CS-pages instead.

☠️ **Three things this does not yet establish, and each could sink it:**

1. **The `ROW_Commercial` Active reading is from a pmOS capture dated 2026-08-29,
   not from UT and not from today.** The active MBN lives in the modem, so it is
   in principle shared between the two OSes — but Android's `pdc` service
   re-selects a config at boot from the SIM's MCC/MNC, and UT may therefore differ.
   Nothing has been read on the UT side: there is no `qmicli` or `pdc` tool there
   and no QMI character device, because on Halium the modem is reached over binder.
2. **Whether `Global-VoLTE-Vodafone` matches this operator at all** is unknown -
   the rebrand from Vodafone HU to One HU may or may not be reflected in that
   config's carrier policy.
3. **Whether the MBN is the gate here at all.** Operator IMEI/TAC gating remains a
   live alternative and would produce the same symptom.

The check that settles (1) is a PDC config query, which the pmOS side can already
do — that is where the 2026-08-29 capture came from.
