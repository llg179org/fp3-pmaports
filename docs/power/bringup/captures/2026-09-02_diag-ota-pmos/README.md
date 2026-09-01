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

---

# ★★★★★ INTERVENTION: switching IMS off stops the loop dead

2026-09-02 00:00–00:30, same boot, same cell, three arms.

| arm | what was changed | ESM messages / window | verdict |
|---|---|---:|---|
| baseline | nothing | **220 / 120 s** (22 full cycles) | the loop |
| 1 | AP holds a bearer on APN `ims` (`mmcli --simple-connect`) | **18 cycles / 90 s** | **no change** |
| 3 | every IMS service switch set False | **0 / 120 s** | **loop gone** |

With IMS off: RRC OTA 391 → 179, whole log 38 299 → 9 620 bytes, and **not one
ESM message of any kind**. The device stayed `registered` throughout.

The lever is `Qmi.ClientIms.set_ims_services_enabled_setting`, reached with the
bind-in-one-process pattern ([`../tools/ims-toggle.py`](../tools/ims-toggle.py)).
Read *before* the write: **voice, video telephony, SMS and UT all True** — IMS was
switched on, which is why the client kept asking.

☠️ **The setter names and the getter names do not correspond.**
`set_ims_service_enabled(False)` on its own came back with only **UT** flipped and
voice, video and SMS still True. Every switch has to be set explicitly *and read
back*. A write that is not read back is a hope, not a change.

## Why arm 1 failed, and what it is evidence for

An AP bearer on the same APN does not satisfy the requester — which rules out
"an unclaimed context looking for an owner", and points at the shape of the
protocol instead of the shape of the APN.

The design this modem expects is a two-party one. The kernel knows nothing about
IMS — `grep` for IMS across the vendor 4.9 tree's `drivers/` and `include/`
returns **nothing**; it is entirely a userspace QMI client's job. And `qrtr-lookup`
shows the role assignment: the **modem is the server** on all three IMS services
(settings 18, application 33, QMI Priv 77), with **no client on our side** and no
IMS process running. On Android and on the Ubuntu Touch oracle that client is
`imsdatadaemon`, which drives PDN setup and teardown through the **IMSDCM** (IMS
Data Connection Manager) service — the same service libqmi exposes here as
`Qmi.Service.IMSDCM` with `PdpActivateRequest` / `PdpDeactivateRequest`.

So the behaviour is **designed, but for a system that runs the other half**. The
carrier config (`ROW_Commercial`) has IMS enabled; the modem plays its half,
finds no counterpart, releases, and retries 8.4 s later. It is not waste by
design — it is a half-configured stack.

## ☠️ Two claims that are NOT established, and one that was refuted

**Refuted, and kept here so nobody resurrects it.** The outside review's
explanation was *P-CSCF starvation*: the granted PDN carries DNS but no P-CSCF, so
the IMS client has nothing to register against. Decoded container by container,
the network's PCO returns:

```
0x8021 len=16  IPCP
0x000D len= 4  DNS IPv4                        80.244.99.36
0x0005 len= 1  MS support NRBC                 02
0x0002 len= 0  IM CN Subsystem Signaling Flag  (present)
0x000C len= 4  P-CSCF IPv4                     10.149.10.129
0x000C len= 4  P-CSCF IPv4                     10.150.10.129
```

**Two P-CSCF addresses and the IM CN flag** — exactly what the UE's own outgoing
PCO asks for. The PDN is fully provisioned and the UE hangs up anyway. The review
accepted the refutation and named its own error: a mechanism built on a partial
decode instead of a container-level dump.

**Still unknown: why it tears down.** Its own `PDN DISCONNECT REQUEST` is a bare
`02 fc d2 06` — protocol discriminator, PTI, message type, linked EPS bearer
identity 6, **and no ESM cause IE at all**. 30 ms is too fast for anything
network-dependent, so it is a local precondition check failing between "bearer
up" and "first SIP message". Which check is not yet read. The instrument for it
is the same door one step further: enable the IMS/QIPCALL log equipment ranges
and let the state machine narrate itself.

**Still unmeasured: the milliamps.** The chain loop → RRC_CONNECTED → duty is
measured. duty → current still rests on the fitted slope with its known ≥15 mA
structural residual, so "the mechanism is the whole duty gap" must not quietly
become "the power problem is solved".

## The channel decode: with IMS off, the UE never opens a connection at all

The three captures were re-read with [`../../tools/diag-ota-decode.py`](../../tools/diag-ota-decode.py),
which pulls the `pdu_num` (logical channel) out of every `0xB0C0` record instead
of only counting them. 120 s each, same cell (PCI 109, EARFCN 6200) throughout:

| `pdu_num` | channel | IMS on | AP holds bearer | **IMS off** |
|---:|---|---:|---:|---:|
| 4 | PCCH — paging | 152 | 122 | **176** |
| 6 | DL_DCCH | 72 | 56 | **0** |
| 8 | UL_DCCH | 154 | 123 | **0** |
| 5 / 7 | DL/UL_CCCH — connection setup | 1 / 1 | 0 / 0 | **0 / 0** |
| 2 | BCCH_DL_SCH — SIB | 0 | 4 | 0 |
| — | ESM (`0xB0E1/E2/E3`) | 88/44/88 | 74/36/74 | **0** |

**This is what closes the channel enum.** `pdu_num` is a firmware-version
dependent field and this repo does not take such enums on faith — but the
behaviour names them: the two codes that vanish completely when IMS is switched
off are exactly the two that carried the ESM loop, and the one that survives is
the one a camped idle UE must keep hearing. No external table was needed.

Three things follow, and one of them is a warning:

1. **With IMS off the UE holds no RRC connection whatsoever.** Not "fewer
   connections" — zero dedicated-channel messages and zero CCCH setups in 120 s.
   The IMS loop was the *only* thing keeping the connection up.
2. **Paging goes up, not down** (152 → 176). Consistent with a UE that now hears
   every paging occasion instead of missing those it spent connected. It is also
   the reassuring direction for reachability: the phone is listening more.
3. ☠️ **So the ladder can now falsify itself cleanly.** If the band-pinned
   `ims-ab.sh` still measures a high duty in the IMS-off leg, the cause cannot be
   radio work — an idle camped UE with no connection has none to do — and the
   remaining suspects are the DIAG residue and whatever else keeps the modem
   awake. That is a much sharper question than "why is the duty high".

☠️ ~1 % of records (4–8 per file) parse with an absurd PCI/EARFCN and header
version 1 rather than 22 — a second log format in the same stream. They are
reported, not silently dropped, and they change none of the counts above.
