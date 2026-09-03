# The modem transmits in 13 % of samples while there is no data at all

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed the measurement it rests on.

Measured 2026-09-01 evening, pmOS, expensive state, eutran-1 cell 1470762.
Raw: [`raw/tx-sample-120s.txt`](raw/tx-sample-120s.txt).

## Why

By this evening the duty gap had lost five explanations — RAT list, phantom-RAT
scanning, multi-second bursts, QMI-reply latency plus rmtfs, and AP wake-up
latency. Then a desk computation on our own cheap-state capture reframed the
whole hunt: the cheap state is not our stack running cheaper, it is
**numerically identical to the oracle** — 3.14/s at 16 ms per wake, against the
oracle's 3.14/s at 22 ms. And the expensive state is not a stretched version of
it: 2.57/s at 197 ms. The **rate went down 18 % while the length went up 12×**.

That is a discrete mode change in the modem's radio-protocol state, not an
analog slowdown — which points at RRC: expensive = `RRC_CONNECTED` with
connected-mode DRX, cheap = `RRC_IDLE` camped. It fits every property observed:
bistable within one boot, indifferent to mode-preference writes, indifferent to
cpuidle, needing almost no QMI traffic, with ~200 ms on-durations and not one
quiet second.

## The reads

First, is there a data path holding a connection up?

```
rmnet_ipa0       DOWN     rx=0 tx=0
default via 192.168.x.x dev wlan0
```

**No.** The modem interface is down and has passed zero packets since boot; the
route is over Wi-Fi. So no user traffic is holding anything.

Then, is the UE transmitting? `--nas-get-tx-rx-info=lte`, 60 samples over 120 s:

**TX in traffic: 8 / 60 samples — 13 %.**

In `RRC_IDLE` a camped UE transmits essentially never: only a random-access burst
for a tracking-area update or a paging response, which would not land in 13 % of
snapshots. Periodic uplink at this rate with **zero user data** is what a
connected-mode UE does — CQI, SRS, measurement reports.

## What this is and is not

It is a strong, cheap positive for the RRC hypothesis, and it cost two commands.

☠️ It is **n=1 and uncontrolled**. There is no paired measurement of the same
quantity in the cheap state, because the cheap state cannot yet be produced on
demand — and that comparison is the whole experiment. Until it exists, this is a
lead, not a finding.

☠️ And there is a tension to keep on the page: a modem core power cycle and a
full reboot both landed back in the expensive state, 34.7 % six minutes after
boot. A merely *stuck* RRC connection should not survive either. Whatever holds
this, it re-establishes immediately.

## Next

The paired read: TX-in-traffic and wake rate/length together, in the cheap state.
Either by learning to produce the cheap state, or on the oracle at the next slot
switch — where the same two commands answer whether a system with a *live* bearer
still sits RRC-idle.
