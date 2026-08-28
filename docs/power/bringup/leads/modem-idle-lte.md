# The modem core is awake 34.8 % of the time on LTE, and 6.1 % under the vendor stack

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed every measurement it rests on.

★ **This is the whole remaining idle gap.** With the modem core down this phone
idles at 57.5 mA, inside the oracle's own 55–64 mA band; with it up, 98–101 mA.
There is no second term behind it.

## The measurement

One instrument ([`../tools/modem-window.sh`](../tools/modem-window.sh)) on both
systems within half an hour of each other, same operator and cell —
[`../captures/2026-08-28_modem-window-both/`](../captures/2026-08-28_modem-window-both/):

| | pmOS (slot b, r78) | oracle (slot a, UT 4.9.218) |
|---|---|---|
| access technology | `lte` | `lte` |
| registration | `registered` | `registered` |
| EPS attach | `packet service state: attached` | `ConnectionManager Attached = true` |
| **data context** | **none** — `rmnet_ipa0` DOWN, 0 bytes, no bearers | **active** — `rmnet_data2`, 10.124.125.20, `internet.vodafone.net` |
| **MPSS awake** | **34.8 %** | **6.1 %** |
| operator / cell | (not read) | One HU, 216-70, CellId 1470762 |
| signal | ModemManager `78 %` | ofono `Strength = 12–15` |

The 6.1 % reproduces the 2026-08-24 figure of 6.3 % to a fifth of a point — and
that earlier capture recorded no radio state at all, which is why the instrument
now writes the modem's full state into the same file as the counters.

## What has been ruled out, each by a measurement

| candidate | how it died |
|---|---|
| any Linux-side lever | `mmcli --disable` 36/34/34 %, `ModemManager` stopped 38/36/37 %, `iio-sensor-proxy` stopped 36/39/36 %. All flat, and the modem's own SMD edge read zero through the daemon-less leg — **the modem wakes by itself** |
| different modem firmware | `modem_a`, `modem_b` and our rootfs copy all carry `QC_IMAGE_VERSION_STRING=MPSS.TA.3.1.C1-425464`. The `325768` was the **metabuild** number out of `verinfo/ver_info.txt`, and our own image embeds that string too |
| the oracle's modem was powered down | a powered-down modem reads **0.0 %** (`--set-power-state-low`, 186 of 186 samples). 6.3 % is not 0 % |
| the oracle was on a cheaper RAT | it was on `lte`, recorded in the capture |
| LTE is simply expensive on this modem | the same modem and firmware does LTE at 6.1 % under the vendor stack |
| user traffic | `rmnet_ipa0` DOWN, zero bytes over 60 s, no bearers |
| poor signal on our side | it points the wrong way — the oracle does not read stronger, and weak signal costs a modem *more* |
| 3G as a middle rung | the operator has switched UMTS off; `--set-allowed-modes=3g` searches for 40 s and gives up |

## What is left

**The cheaper system is the one doing more.** It holds an established PDP context;
we hold nothing. So the question is not what we keep alive but **what the vendor
stack sets up that we never do.** Its process list names the shape of it: `netmgrd`
and `ipacm` build the IPA data path, and the modem is told the AP's side exists. On
pmOS the IPA is probed (`7900000.ipa`, driver `ipa`) and no channel is ever brought
up — a modem whose data path was never completed has an obvious reason to stay out
of deep idle DRX, and that is exactly the shape of something that costs power while
sending the AP nothing.

☠️ **2G is an instrument, not a proposal.** Leg B of the RAT A-B-A′ put the duty at
6.5 % and the median at 54.0 mA with the phone still registered and call-capable —
which is how we know the number is reachable — but the networks are being switched
off and nothing here suggests shipping it.

## The next measurement

`mmcli -m 0 --simple-connect="apn=…"` and re-measure the duty. The connect already
works on pmOS: `rmnet_ipa0` comes up with a `qmapmux0.0` mux and the modem reads
`connected`. If the duty falls toward 6 %, the fix is userspace and it takes idle
from 98–101 mA to about 57.

☠️ And note what it will **not** fix: `edge_irq_per_s` is 34.7 / 35.0 / 35.6 across
LTE, 2G and LTE, so the modem's SMD-edge ring is independent of its awake duty. The
suspend-residency front does not come back with this one.
