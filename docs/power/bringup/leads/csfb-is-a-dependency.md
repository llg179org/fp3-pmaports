<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# ☠️ The cheap configuration rests on a network service: CSFB

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
