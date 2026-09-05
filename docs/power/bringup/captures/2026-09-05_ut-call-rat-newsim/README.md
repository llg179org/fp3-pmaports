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
