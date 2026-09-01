# ★★★★★ NAMED: the modem sets up an IMS PDN and hangs it up again, every 8.4 seconds, forever

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed the measurement it rests on.

2026-09-02 00:00–00:03, pmOS, expensive state, `tools/diag-log-capture.py`,
120 s of the modem's own over-the-air log. **38 299 bytes, 612 log records.**

## The loop

Decoded from the LTE NAS ESM log (0xB0E2 in / 0xB0E3 out), one complete cycle,
verbatim message identities from 3GPP TS 24.301 §9.8:

| t | direction | ESM message |
|---:|---|---|
| +0.00 s | UE → net | **PDN CONNECTIVITY REQUEST — APN `ims`** (0xD0) |
| +0.60 s | net → UE | ACTIVATE DEFAULT EPS BEARER CONTEXT REQUEST (0xC1) |
| +0.61 s | UE → net | ACTIVATE DEFAULT EPS BEARER CONTEXT ACCEPT (0xC2) |
| +0.64 s | UE → net | **PDN DISCONNECT REQUEST** (0xD2) |
| +0.73 s | net → UE | DEACTIVATE EPS BEARER CONTEXT REQUEST (0xCD) |
| +0.73 s | UE → net | DEACTIVATE EPS BEARER CONTEXT ACCEPT (0xCE) |

**22 complete cycles in 120 s**, spaced 8.3–8.7 s (mean 8.4). The APN string is
in the request as an ASCII IE — `28 04 03 69 6d 73` = Access Point Name, len 4,
`03 "ims"` — alongside a Protocol Configuration Options block asking for DNS.

The network is not refusing anything. It grants the PDN every single time. **The
UE throws it away 30 ms after accepting it**, and asks again eight seconds later.

Log-code census over the window:

```
0xB0C0  391  LTE RRC OTA Message
0xB0E3   88  LTE NAS ESM plain OTA, outgoing
0xB0E1   88  LTE NAS ESM security-protected OTA, outgoing
0xB0E2   44  LTE NAS ESM plain OTA, incoming
0xB0ED    1  LTE NAS EMM plain OTA, outgoing
```

391 RRC messages in 120 s is what 22 connection setups and releases cost.

## Why this is the 30-point duty gap

Every cycle needs an RRC connection. At one cycle per 8.4 s the UE never gets to
stay in RRC_IDLE, so it lives in **RRC_CONNECTED with connected-mode DRX** — and
that is exactly the micro-structure every window has measured on this stack:

| | wake rate | ms per wake | reading |
|---|---:|---:|---|
| oracle, and our own cheap state | 3.14–3.15/s | 16–22 ms | **1/320 ms = the LTE paging DRX cycle.** A UE camped in RRC_IDLE, waking for its paging occasion |
| pmOS expensive state | 2.38–2.57/s | 142–197 ms | connected-mode DRX on-duration plus PDCCH monitoring plus connected-mode measurement |

So the 2.47/s wakes were never the thing to explain — they are the connection's
housekeeping. The thing to explain was **why the connection never releases**, and
this log answers it: something re-establishes it every 8.4 s.

It also explains, at once, four things that had no explanation:

* **why the AP is not in the wakeups** — 14 QMI messages against ~770 wakes: this
  is pure NAS signalling between the modem and the network, and the applications
  processor is not a party to it;
* **why the UE transmits with `rmnet_ipa0` down and rx=tx=0** — the traffic is
  signalling, not user plane;
* **why nothing decays** — the first 2.5 h of the 2026-09-01 overnight watch are
  flat to 1.2 pp, and a *successful* setup-then-teardown loop has no backoff to
  decay;
* **why every AP-side lever failed** — daemon, Wi-Fi, cable, band, RAT list,
  cpuidle, bearer, reboot, SMSM: none of them is upstream of a modem-internal
  client asking for a PDN.

## ☠️ What is NOT established

**Why the UE disconnects.** The obvious reading is that the modem brings the IMS
PDN up on behalf of an IMS client that pmOS does not run, finds no one holding
it, and releases it — then a timer retries. That is a *story*; the log shows the
disconnect, not its reason.

**That stopping the loop fixes the duty.** Predicted, not measured. The
confirming experiment is an intervention, and it is pre-registered here before it
runs:

> Stop the IMS PDN loop — by disabling IMS on the modem, or by having something
> claim and hold the PDN. **Duty collapses toward ~5–6 % and the wake rate rises
> to ~3.14/s** ⇒ named and confirmed. Duty unchanged ⇒ the loop is a passenger
> and this page is wrong about causation, however good the correlation looks.

**The oracle side.** Nobody has yet read the same log on the Ubuntu Touch slot.
The differential — does the vendor stack hold the IMS PDN, or never ask for it? —
is what turns "our modem does this" into "our stack causes it".

## How it was measured, and the door that had been missed

[`../leads/diag-bringup.md`] had been stuck for days on the DIAG **command**
path: the modem answers control messages and has never once answered a command.
The power question never needed a command. It needed the modem's **log stream**,
and logs are turned on by a control message —

```
DIAG_CTRL_MSG_LOG_MASK = 9        (diagchar.h, vendor tree on disk)
```

— on the channel that already worked. The peripheral's own feature mask (0x3EF7)
sets bit 11, MASK_CENTRALIZATION, which is precisely "send me my masks as control
packets". The wall was real; the door was ten feet to the left.

☠️ **DIAG is not a neutral observer**: `struct diag_ctrl_msg_diagmode` carries a
`sleep_vote`, so a duty measured with logging enabled is not the same measurement
as one without. This capture makes no duty claim — the duty numbers it reasons
about were all taken with logging off.

## Raw

`raw/diag.bin` (38 464 B, the log stream), `raw/cntl.bin` (9 502 B, the control
handshake). Reproduce with `tools/diag-log-capture.py 120`.
