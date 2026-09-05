<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# Does the operator refuse IMS voice to *this device*? — the IMEI/TAC gate

**Status:** open, **not measurable from anything we currently hold**, but there is
one decisive measurement and we have the tooling for it.

## Why the question is live

[#163](../captures/2026-09-05_163-same-card-two-devices/) established that the same
card gets VoLTE in a stock Android handset and CS on the FP3, so the difference is
device-side. Two device-side mechanisms remain, and the modem carrier config is only
one of them. The other is operator device policy.

Two independent sources say this is a real mechanism rather than a worry:

- [`volte-is-provisioned.md`](volte-is-provisioned.md) already flagged it on
  2026-09-02: the network provisions IMS for this SIM (P-CSCF addresses and the IM
  CN Subsystem Signalling Flag, measured), *"but it does not mean the operator would
  admit this device: carriers frequently tie IMS registration to device policy
  (IMEI lists, certified models)"*.
- Fairphone's own support statement, quoted on their community forum: the FP3 *"is
  technically capable of using VoLTE and VoWiFi technologies but we are still
  waiting to complete the partnerships with the various phone carriers"*, and a
  contributor there describes operator VoLTE capability as something *"added by
  Vodafone and other network carriers to Fairphone's software"* — i.e. delivered as
  operator-specific configuration into the phone, which is exactly the MBN
  mechanism [#165](../captures/2026-09-05_163-same-card-two-devices/) found
  unloaded here.

Our device: **TAC `35781109`**, `Fairphone FP3`.

## The measurement that decides it

The EPS **`ATTACH ACCEPT`** (EMM 0x42) and **`TRACKING AREA UPDATE ACCEPT`**
(EMM 0x49) carry the *EPS network feature support* IE, whose **IMS voice over PS
session indicator** is the network telling *this UE, in this tracking area*,
whether it may use IMS for voice. That bit is the answer:

- **not supported** → the network is refusing IMS voice to this UE. Whether that is
  the subscription or the device policy is a further question, but it is not our
  stack's fault and no local change can help.
- **supported**, and the phone still CSFBs → the refusal is not at that layer and
  the fault is below ofono, on our side.

## Why it cannot be read from what we have

The existing captures do not contain an attach.
`tools/diag-ota-decode.py` over `captures/2026-09-02_diag-ota-pmos/raw/diag.bin`
gives 612 log entries: 391 RRC (`0xB0C0`), 220 ESM (`0xB0E1/E2/E3`), and exactly
**one** EMM entry (`0xB0ED`). The device was already registered for the whole
window, so no Accept was ever sent.

## What it needs

A new diag capture **spanning an attach** — airplane mode off, or a modem restart,
with QCSuper running (`/mnt/1TB/Fp3-Sailfish/QCSuper`, already used for the
2026-09-02 captures). On **pmOS**, where the diag port is reachable; the UT/Halium
side has not been shown to expose it.

☠️ Then decode the Accept and walk to IE `0x64`, reading bit 0 of its first octet —
and **do not trust a byte-scan for `0x64`**: `volte-is-provisioned.md` records that
this repo has already published one wrong conclusion from a scanner that searched
too widely and only looked right. Walk the IEs by their own lengths and make them
close on the message boundary, as `tools/pcscf-scan.py` does.
