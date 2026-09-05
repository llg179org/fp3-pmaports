> ☠️ **OPEN, and the ground has moved. 2026-09-05, measured:** the dev subscription
> **does** carry VoLTE - the card holds 4G through a call in a stock Android with only
> the handset's per-SIM "4G hívás" switch on. So the network is not the limit, and the
> earlier closure ("no software work on our side can help") is withdrawn in full.
> ☠️ But nothing here is decided yet either: the FP3 has never been tested with this
> card. The one that CSFBs on the FP3 is a different card, so the two measurements are
> not a comparison. Decisive next test: put the dev card back in the FP3 and call it.
> See `../captures/2026-09-05_ut-call-rat-newsim/` ("Re-test (#162)").
>
> Superseded notes below, kept for the record:
>
> ~~NOT CLOSED - the 2026-09-05 closure is RETRACTED.~~ It rested on a stock
> Android showing GSM for the dev card; that handset's "4G hívás" switch is off by
> default per SIM slot and was off for that slot, which explains the GSM on its own.
> Re-test pending (queue #160). The paragraph below is kept for the record but does
> not hold:
>
> ~~**CLOSED 2026-09-05.**~~ The dev card was put into a certified stock-Android
> handset and took a terminating call on **GSM** (4G only after teardown), while a
> different card in that same handset holds 4G through a call. The subscription is
> the variable, so no software work on our side - IMS stack included - can give this
> phone a 4G call on this card. See `../captures/2026-09-05_ut-call-rat-newsim/`
> Part 2. Reopening requires a VoLTE-provisioned card in the FP3, not more analysis.

> **2026-09-05, second SIM, direct IMS instrument:** the oracle is IMS
> registered and voice-capable (`IpMultimediaSystem.Registered=true`,
> `VoiceCapable=true`) and *still* takes terminating calls on EDGE - the RAT
> drops 2-3 s before the call is even signalled, and a 21 s answered call ran
> entirely on 2G. An IMS stack is therefore not the lever for the 2G
> dependency. See `../captures/2026-09-05_ut-call-rat-newsim/`.

<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# ☠️ The cheap configuration rests on a network service: CSFB

> ☠️ **2026-09-05 — and it is not our stack's fault.** The UT oracle, with a full
> vendor IMS stack and `ims=1` throughout, was measured taking an incoming call
> on **EDGE** and returning to LTE a second after it ended. So the CS dependency
> this page describes is **not** removable by implementing IMS on pmOS: the
> system that has IMS depends on CS just the same. The variable is most likely
> the subscription — the daily handset's two SIMs differ by tariff, one keeping
> 4G through a call and one not, and the dev phone carries a third card never
> characterised alone.
> [`../captures/2026-09-05_ut-call-rat/README.md`](../captures/2026-09-05_ut-call-rat/README.md)

**CS** = *Circuit Switched*, the classic 2G/3G voice path. **CSFB** = *Circuit
Switched FallBack*: the UE camps on LTE, but when a CS call arrives the network
moves it to 2G/3G for the duration of the call.

## The measurement

`fp3-ringlog` reads the band **after** a call, and on 2026-09-02 it recorded
`gsm-900-extended` on three consecutive calls while the phone was camped on LTE
(`mmcli … access tech: lte`). The modem's `--nas-get-system-info` reports
`Domain: 'cs-ps'`: the LTE registration **includes the CS domain**, i.e. the SGs
association between the network (vodafone HU, 21670) and the MSC is live.

So the calls do not arrive "somehow" — **they arrive by CSFB, measured.**

## ☠️ What this says about the report

The price of the `≤50 mA` configuration is that IMS is switched off and the call
comes in over CS. That is **not a property of the phone but of the network**: if
the operator switches off 2G (3G is already gone in Hungary), then on this
configuration an incoming call is not slower, it is **absent**.

The report used to say "the call path works with IMS off" — true, but it was
missing the **condition**. The correct form:

> The call path works with IMS off, **as long as the network's CS domain is
> reachable** (measured: SGs is live, the call falls back to gsm-900). This
> configuration therefore leans on a network service whose retirement has been
> announced across the sector — it is not on our device and not on our schedule.

## What this says about the PLAN

The `imsd` path — building the AP-side IMS daemon, which would give VoLTE — was
filed as "a separate project, a separate decision, not the tail of this thread".
That grading is **too low**: it is not a curiosity, it is the **contingency
plan**. If 2G goes, the choice is not "IMS on or off" but "VoLTE or nothing", and
then the question is not how to switch off the 8.4 s PDN loop but **why** the
modem tears the bearer down — which is exactly the item currently blocked by the
silent DIAG stream.

## What we are NOT claiming

We have no measurement of when this network will switch off 2G, and operator
announcements do not belong in this repository. What we know: **it works today**,
and our configuration depends on it.
