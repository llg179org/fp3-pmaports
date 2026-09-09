# 2026-09-08 — call matrix: which IMS configuration, which call, which error

**Purpose.** One HU are running a radio-side trace on this number 2026-09-08 →
09-10 and asked for the times trouble occurred. This capture is the operator-side
half of that: every call placed during the window, under a *named* IMS
configuration, with what the phone logged. It is the table the operator and the
carrier can put side by side.

☠️ **Not a power measurement.** An earlier line of work on this device measured
the modem's duty cycle; that is deliberately out of scope here and no duty number
belongs in this file.

## The three configurations

| id | what is enabled | rationale |
|---|---|---|
| **A — baseline** | neither. `fp3-ims-reconcile.timer` holds the modem's IMS switches off | the shipped state of this port |
| **B — modem IMS** | the modem's own IMS stack (`voice/vowifi/video/sms/ut` = True) | the firmware's own implementation |
| **C — imsd** | the FP6-derived userspace daemon (`imsd.service`, GPL-3.0, Catcrafts) | demonstrably delivers VoLTE on an FP6 across four carriers |

☠️ **B and C are never enabled together.** They contend for the same `ims` APN,
and a fault seen with both up could not be attributed to either.

## The calls

Times are the phone's local clock (CEST), which is NTP-synced. "off LTE" is the
interval between `AccessTechnologies` leaving 16384 (LTE) and returning to it.
MT = the phone was called, MO = the phone dialled.

| # | time | dir | config | outcome | band while on the call | off LTE |
|---|---|---|---|---|---|---|
| 1 | 12:34:18 | MT | A | answered, audio both ways | gsm/gsm-900-extended | 31 s |
| 2 | 18:34:20 | MT | A | answered, audio both ways | gsm/gsm-900-extended | 30 s |
| 3 | 18:39:45 | MO | A | answered, audio both ways | — | 27 s |
| 4 | 19:14:27 | MT | A | rang 10 s, rejected | gsm/gsm-900-extended | 13 s |
| 5 | 19:23:34 | MT | **B** | rang 13 s, rejected | gsm/gsm-900-extended | 15 s |
| 6 | 19:24:46 | MO | **B** | rang 13 s, hung up | — | 16 s |
| 7 | 20:03:38 | MT | A | rang 8 s, rejected | gsm/gsm-900-extended | 11 s |
| 8 | 20:05:22 | MT | **B** | rang 9 s, rejected | gsm/gsm-900-extended | 12 s |
| 9 | 20:05:56 | MO | **B** | rang 10 s, hung up | — | 14 s |

**Every call in this table left LTE.** Not one was carried over IMS.

## The two timing signatures, unchanged by configuration B

- **MT:** the access technology drops to GSM **1–2 s BEFORE** ModemManager creates
  the call object. The network pages on the CS domain; the handset is told to fall
  back before it knows a call exists.
- **MO:** the call object is created **on LTE** and the drop follows **1 s LATER**.
  So the handset demonstrably starts the call on LTE and is moved off it.
- Return to LTE is **+1 s after the call ends** in all six.

★ **Configuration B changed neither signature.** With the modem's own IMS stack
fully enabled and read back (`voice/VoWiFi/video/SMS/UT` all True, band
`eutran-1`, cell 1470762), calls 5, 6, 8 and 9 are indistinguishable from the
configuration-A calls.

## Configuration B: the modem's IMS never registers

Sampled every 15 s by [`tools/ims-modem-leg.sh`](../../tools/ims-modem-leg.sh),
which reads QMI IMSA through [`tools/ims-state.py`](../../tools/ims-state.py).
Two windows, 420 s and 100 s (the second stopped once calls 8 and 9 were in it):

| | IMS off (shipped) | IMS on |
|---|---|---|
| `registered` | 0 NOT_REGISTERED | **0 NOT_REGISTERED**, every sample |
| `error code` | 0 | **0**, every sample |
| `UE-to-TAS` | 0 | **2** |

★ The `UE-to-TAS` 0→2 swing is what proves the instrument is reading the modem
and not a constant — it is the known-differing regime the gate requires.

★ **And the samples cover the calls themselves.** At t=60 s (`tech=gsm, gprs`,
call 8) and t=90 s (`tech=gsm, gprs`, call 9) the reading is unchanged:
NOT_REGISTERED, error code 0. So with its own IMS enabled the modem is not
registered at the moment the call arrives, and reports no error for it.

☠️ **"Not registered, no error" is not "made no attempt."** IMSA reports a state,
not a conversation. The channel that would show the attempt is DIAG log families
0x14/0x15 — and `ims-why-teardown.sh` returned **`diag 0 bytes` for a 600 s
window** on this date: the log mask was accepted by the transport and no stream
followed. Its own output says not to read that as "the modem is quiet". Whether
the modem sends a SIP REGISTER of its own is therefore **still unmeasured**.

## Configuration C: imsd reaches the network and is refused 500

Run at **2026-09-08 20:12:57 CEST** and again at **2026-09-09 06:29:54 CEST**,
both inside One HU's trace window, by
[`tools/imsd-leg.sh`](../../tools/imsd-leg.sh) — one attempt, no loop:

```
imsd: SIM slot=1 IMSI=<redacted> domain=ims.mnc070.mcc216.3gppnetwork.org
imsd: FRESH registration
imsd: bring-up FAILED: REGISTER failed 500
```

Everything before the 500 worked: the IPv4 `ims` PDN came up (`qmapmux0.0`, /30),
the host route to the P-CSCF was installed over it, USIM AKA completed and the
protected REGISTER went out. **This reproduces the 2026-09-06 result** whose
`Warning: 399 5144.2233.S.260.5.94.255.255.5938.0.0` is the question put to the
carrier — now with a fresh timestamp inside their measurement window.

★ **The SIP dump of this occurrence exists** — `imsd-register-protected-sent.raw`
(1438 B) and `imsd-register-fail.raw` (455 B), written 20:12 by the patch the
installed `imsd-0.3.0_git1987275-r1` does carry. Raw files are kept **outside git**
(they hold the IMSI, MSISDN and addresses): `/mnt/1TB/pmos/fp3-raw-logs/2026-09-08_imsd-sip/`.

The response, in full apart from nothing:

```
SIP/2.0 500 Server Internal Error
CSeq: 2 REGISTER
Warning: 399 5144.2233.S.260.5.3.255.255.5938.0.0.ims.mnc070.mcc216.3gppnetwork.org "Server Internal Error"
Content-Length: 0
```

★★ **Three occurrences now, and the third settles what the second only hinted at.**

| when | the diagnostic |
|---|---|
| 2026-09-06 22:03:58 | `5144.2233.S.260.`**`5.94`**`.255.255.5938.0.0` |
| 2026-09-08 20:12:58 | `5144.2233.S.260.`**`5.3`**`.255.255.5938.0.0` |
| 2026-09-09 06:29:54 | `5144.2233.S.260.`**`5.75`**`.255.255.5938.0.0` |

**94 → 3 → 75.** One sub-field takes a different value on every attempt and every
other character is identical, all three `500 Server Internal Error` on `CSeq: 2
REGISTER`, all three from the same cell `2167014B4016712A`.

★ **So that field is a per-attempt identifier, not a state code — and knowing this
prevents a wasted question.** With two samples the natural move is to ask the
carrier what the *differing* field means; with three it is clear that the varying
part is noise and the question belongs to the **invariant**:
`5144.2233.S.260. … .255.255.5938.0.0`. The full host suffix
`.ims.mnc070.mcc216.3gppnetwork.org` was truncated in the 2026-09-06 letter and is
recorded here in full.

The bearer's IPv4 address differs per bring-up (`10.18.255.185` → `10.26.191.57`),
which is expected and is why `LOCAL` is rewritten on every run.

Header names in our protected REGISTER (values withheld): `Allow, Authorization,
CSeq, Call-ID, Contact, Content-Length, Expires, From, Max-Forwards,
P-Access-Network-Info, Proxy-Require, Require, Security-Client, Security-Verify,
Supported, To, User-Agent, Via`. The `Contact` carries the MMTEL ICSI tag.

☠️ **Two false "it is empty" readings preceded this, both mine, both the same
mistake.** `find / -xdev` does not cross a mount point and `/tmp` is a tmpfs, so
it skipped the very directory; and `ls -la /tmp/imsd-sip/` was run *without sudo*
against a 0700 root-owned directory with stderr discarded. Each produced no output,
and each time the absence of output was read as a fact about the world. Same class
as the `grep` without `-a` earlier the same evening.

☠️ **`systemctl start imsd.service` is the wrong door and was tried anyway.** Its
`ExecStartPre=ims-pdn-up.sh` asks for `ip-type=ipv6` and this network answers
`Ipv4OnlyAllowed: ip-version-mismatch` — seven identical retries at 20:08 before
it was stopped. That is **not** a carrier fault and **not** a change: the
2026-09-05 work already established that this IMS APN is IPv4-only and bypassed
`ims-pdn-up.sh` deliberately. The unit stays disabled.

☠️ **A guard that passed while measuring nothing.** The first `imsd-leg.sh` run at
20:11 found the *leftover ipv6* ims bearer, could not connect it, and `mmcli` then
returned `--` for interface, address and gateway. `[ -n "$IFACE" ]` accepts `--`,
so every later step ran against it and the host route landed on **wlan0**. The
script now rejects `--` explicitly (`bad()`, gated on `""`/`--`/a real ifname) and
deletes any ims bearer that is not ipv4 instead of reusing it. Nothing reached the
network on that run, so the fresh-SA throttle was not touched.

## Instruments

| what | how |
|---|---|
| call events, access technology, signal | `fp3-callwatch.service` → `gdbus monitor` on ModemManager |
| the band a call actually ran on | `fp3-ringlog.service` → `/var/log/fp3/ringlog.tsv` |
| the modem's own SIP + IMS state | `ims-why-teardown.sh` → DIAG log families **0x14** (IMS), **0x15** (QIPCALL), **0x0B** (LTE NAS/ESM) |
| the userspace SIP exchange | `imsd.service` journal |

☠️ **The ModemManager journal cannot answer the IMS question at any log level.**
Its QMI debug dump carries `service = nas / voice / wds / dsd / wms` and not one
`ims` message — MM binds no IMS client. See `findings-log.md`, 2026-09-08 evening.

## Historical baseline

`fp3-ringlog` has logged **every incoming call since 2026-09-03**: as of call 5,
**37 of 37 arrived on `gsm/gsm-900-extended`, none on LTE.**

## What this says to the carrier

★ **Two IMS implementations, two different failures. They are not one fault.**

| | configuration B — modem firmware | configuration C — `imsd` |
|---|---|---|
| gets an IMS PDN | not observable from here | **yes**, IPv4 `ims`, /30 |
| sends a SIP REGISTER | **unmeasured** (DIAG channel silent) | **yes**, protected, after USIM AKA |
| network's answer | none seen; modem reports no error | **500**, with `Warning: 399 …` (2026-09-06) |
| result | stays NOT_REGISTERED indefinitely | exits, no registration |

And in **every** configuration, including with the modem's own IMS fully enabled,
all nine calls fell back to GSM — MT ones 1–2 s **before** the call object exists,
which is the network paging on the CS domain.

## Still open

- whether the modem's own IMS ever sends a REGISTER (needs the DIAG wall solved,
  or the UT oracle diff that #54/#64 stand at)
- why the carrier's core answers 500 — only One HU can say; the two Warning
  diagnostics now give them a varying field to look at
