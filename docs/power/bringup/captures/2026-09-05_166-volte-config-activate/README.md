# The VoLTE switch is in the modem, it is off, and pmOS can read it

2026-09-05, pmOS on slot_b, `linux-fp3-7.1.3-r81` (`3f843d0534e3`), qmicli
1.39.0, SIM on One HU (MCC 216 / MNC 70), camped LTE, registered home.

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed the change and the measurements.
> No subscriber identifiers are reproduced here; the raw captures were scrubbed
> on the way off the device and `tests/no-identifiers.sh` is clean.

## What was measured, in one table

Every row is a `qmicli -d qrtr://0` query against the live modem. Raw output in
`ims-before.txt` and `imsa-ims-through-proxy.txt`; the scripts are beside them.

| question | verb | answer |
|---|---|---|
| does the network offer this UE IMS voice over PS? | `--nas-get-system-info` | **`IMS voice support: 'yes'`** (LTE block, MCC 216 MNC 70) |
| does the modem prefer PS for voice? | `--voice-get-config` | **`Current Voice Domain Preference: 'ps-preferred'`** |
| is the modem's IMS registered? | `--imsa-get-ims-registration-status` | **`Status: 'not-registered'`** |
| are the modem's IMS services enabled? | `--ims-get-ims-services-enabled-setting` | **every one `no`** — voice, video, VoWiFi, UE-to-TAS, SMS, USSD |
| which carrier config is active? | `--pdc-list-configs=software` | `ROW_Commercial`, generic, unchanged |

So the chain reads: the network says yes, the modem wants PS, **and every IMS
service inside the modem is switched off**, so nothing ever registers.

## ☠️ Two instruments that were there all along

**1. `IMS voice support`.** Queue item #169 — *"capture an LTE attach and read
the IMS-voice-over-PS bit the network sends this UE"* — has been blocked for
weeks behind a DIAG capture that never worked. That bit is the *IMS voice over
PS session indicator* in the EPS network feature support IE, and the modem
reports it as a decoded field of `--nas-get-system-info`. No DIAG, no pcap, one
command.

The same command was already being run on this phone: `leads/csfb-is-a-dependency.md`
quotes its `Domain: 'cs-ps'` line. The answer to #169 was four lines further
down the same output and nobody read it.

**2. `-p`.** Without qmi-proxy, `--imsa-*` and `--ims-*` return
`QMI protocol error (70): 'InvalidOperation'`, and with an explicit `--client-cid`
they return `Unknown client N for service imsa`. Both look like a modem that has
no IMS. They mean the client identity does not survive between two qmicli
processes. With `-p` every one of those queries answers, first try. The failing
and succeeding runs are both kept here (`imsa-without-proxy-fails.txt` against
`imsa-ims-through-proxy.txt`) because the difference is one character.

## How far to trust `IMS voice support: 'yes'`

Stated with its basis, not with confidence:

* **Stable** — identical across three consecutive reads.
* **Not a constant** — the adjacent boolean `eMBMS coverage info support` decodes
  as `'no'` from the same message, and GSM/WCDMA report `'none'` where LTE
  reports `'available'`. The decoder discriminates rather than returning yes.
* **Right structure** — MCC 216, MNC 70, TAC and Cell ID in the same block match
  the operator the phone is actually on, so the fields are being read at the
  right offsets.
* **Corroborated independently** — on Ubuntu Touch this same SIM completed a real
  SIP REGISTER with One HU's core and the network returned a P-Associated-URI.
  A different instrument, a different OS, the same conclusion: this subscriber is
  entitled to IMS voice.
* ☠️ **Not established** — that this field tracks the network's *per-UE grant*
  rather than a UE-side capability. Settling that needs a network known to
  withhold VoLTE, which is not available here. The corroboration above is what
  the claim rests on, and it is evidence about the subscriber, not proof about
  the field.

## What this does to the MBN hypothesis (#166)

It undercuts it. #166 proposed loading a Hungarian carrier config on the theory
that the generic `ROW_Commercial` withholds VoLTE. But the two things such a
config would be expected to fix — the network's IMS-voice grant and the voice
domain preference — **both already read correctly**. The measurement says the
carrier config is not what is stopping VoLTE here.

The modem holds 25 software configs and none is Hungarian; the nearest is
`Global-VoLTE-Vodafone` (One HU is the former Vodafone Hungary). Activating it
remains cheap and reversible — the restore is unchanged, activate
`software,5C:F9:CA:DA:5C:35:85:17:BA:3B:B8:88:D0:34:2B:79:BD:5F:AD:ED` — but it
is now a *second* hypothesis, not the leading one, and it was **not** done on
this pass: changing a config to fix a symptom the measurements attribute
elsewhere is how a coincidence gets recorded as a cause.

## The actual blocker, and it is a small one

`Set IMS Services Enabled Setting` **exists** — QMI service IMS, message
`0x008f`, defined in libqmi's own `data/qmi-service-ims.json` since 1.38, with
`0x10 = IMS Voice Over LTE Enable` as a boolean, plus TLVs for the video, VoWiFi,
SMS, USSD and UT services and a call-mode preference.

What is missing is only the **CLI option**. `qmicli` exposes
`--ims-get-ims-services-enabled-setting` and no setter — checked in 1.39.0 on the
phone and in the 1.39.1 checkout at `/mnt/1TB/pmos/libqmi`. The library API is
generated from that JSON at build time, so the call exists in the built library
and nothing reaches it.

So the unblock for #166 is not a carrier config and not DIAG: it is a patched
`qmicli` (or any small client) that sends IMS `0x008f` with `0x10 = 1`. That is
also the shape of a genuinely upstreamable libqmi patch.

☠️ **What it will not do by itself.** Enabling the services tells the modem's IMS
stack it may register. Whether it then registers without an AP-side IMS client is
the open question — on Ubuntu Touch the vendor stack drives that handshake, and
mainline has nothing equivalent. Expect this to move `not-registered` or to
prove that it cannot; either outcome is worth more than the current blank.

## Commands

```sh
qmicli -p -d qrtr://0 --nas-get-system-info | grep -A3 'Voice support'
sh ims-state.sh          # the whole snapshot
sh imsa-proxy.sh         # the bind-then-query pattern that actually works
```
