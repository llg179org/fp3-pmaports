<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# ★ The network DOES provision IMS for this SIM — the evidence was already in a capture

The [CSFB dependency](csfb-is-a-dependency.md) raised the point that if 2G goes
away, the `imsd` path is the fallback. But a fallback the **network does not
provision** is not a fallback. The question could be answered **with no new
measurement**.

## What the loop gives away by itself

Every cycle of the IMS-PDN loop is opened by the network with an `ACTIVATE
DEFAULT EPS BEARER CONTEXT REQUEST` (ESM **0xC1**, downlink), and it is **in
that message** that the **Protocol Configuration Options** field returns the
**P-CSCF addresses** — the SIP proxy the UE would register against. The presence
of the address *is* the VoLTE provisioning.

`tools/pcscf-scan.py`, over the 2026-09-02 loop capture, with a
**length-validated TLV walk**:

| capture | log entries | ESM 0xC1 | closed PCO walk | P-CSCF | what came with it |
|---|---:|---:|---:|---|---|
| `diag.bin` | 612 | **21** | **21 / 21** | `10.149.x.x` ×21, `10.150.x.x` ×21 | DNS `80.244.x.x` ×21, **IMS signalling flag** ×21 |
| `diag-ims-held.bin` | 497 | **18** | **18 / 18** | the same two, ×18 | the same |
| `diag-ims-off.bin` *(control)* | 179 | **0** | — | **none** | — |

Four things make this a measurement rather than a pattern match:

1. **The walk starts at the PCO header and steps by each container's own length
   field**, and the lengths have to **close on the IE boundary**. 21/21 and 18/18
   closed. A misaligned match would arrive at a length that does not close, and
   the script then reports the error rather than a finding.
2. **The neighbouring containers make sense**: the same walk yields the DNS
   server (`80.244.x.x`, a public address) and the **IM CN Subsystem
   Signalling Flag** — the latter is not an address but the network stating that
   this PDN is for IMS signalling. An address could be a stale provisioning
   leftover; that flag is the answer itself.
3. **The negative control**: where the modem asked for no bearer, there are zero
   REQUESTs and zero addresses.
4. **The counts match exactly**: two P-CSCF addresses, each appearing precisely
   as many times as there are REQUESTs. No orphan number.

☠️ **CORRECTED 2026-09-02 evening — the first version named the wrong message and
only gave the right answer because it searched too widely.** `0xC2` (ACCEPT) is
the UE's uplink acknowledgement and **carries no PCO**; the strict walk reports
"0 / 22" on it. The published pairing — *"`10.149.x.x` ×22, `10.150.x.x`
×21, against 22 accepts"* — was **a coincidence of two independent numbers**: the
old scanner byte-scanned *every* ESM message, and the 22 was the count of
accepts, not of addresses. The orphan 21, which went unexplained at the time, was
precisely the signal that something was wrong. The conclusion survived the fix,
but **not on the tool's merit**.

## What it means, and what it does not

**It means:** the network provisions IMS for this subscription, so the `imsd`
fallback **has somewhere to register**. The network side is not the obstacle.

☠️ **It does not mean** the operator would admit **this device**: carriers
frequently tie IMS registration to device policy (IMEI lists, certified models).
The `imsd` path therefore stands on **two gates** — technical (building the
daemon) and policy (being let in) — and this finding touches only the first, from
the network's side.

The cheapest witness for the second gate is the owner's **daily factory-Android
FP3 on this same network**: if it stays on LTE during a call, policy is permissive
for this model; if it also drops to 2G, it is not.
