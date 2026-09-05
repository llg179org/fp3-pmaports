# ★ The FP3 reached One HU's IMS core over the IMS PDN, and got as far as the protected REGISTER

2026-09-05, pmOS `linux-fp3-7.1.3-r82`, `imsd-0.3.0_git1987275-r0`. Part of #177.
**Not a success: registration failed.** But it failed at the last step of the
sequence, and everything before it worked.

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely. All addresses and the IMSI are masked here and were
> scrubbed on the device; the SIP dumps never left it.

## How far it got

Read off `implementations/main.cpp`, where the message that appeared marks a
point *after* every step below:

| step | evidence |
|---|---|
| daemon starts, owns its D-Bus name | `object registered at /net/catcrafts/IMS1` |
| **the USIM is readable through QMI/UIM** | `SIM slot=1 IMSI=<redacted> domain=ims.mnc070.mcc216.3gppnetwork.org` |
| unprotected REGISTER sent, **401 challenge received** | attempt 2 passed the point that threw `no 401` in attempt 1 |
| ★ **USIM AKA succeeded** | the code throws `USIM AKA failed` before this point and did not |
| ★ **IPsec SAs installed** (`ip xfrm`) | the code runs `BuildSetupCommands` before this point — *this is the r82 kernel work being used for real* |
| ★ **protected TCP connect to the P-CSCF** | the code throws `protected TCP connect failed` before this point and did not |
| protected REGISTER sent | — |
| ❌ **the core answered `500`** | `REGISTER failed 500` |

**A 500 is a SIP response from the operator.** So there is two-way SIP between
this phone and One HU's IMS core, over the IMS PDN, from mainline Linux.

Two unknowns that were open this morning are closed, both positively: **USIM AKA
works on an msm8953-generation modem**, and **the kernel IPsec added in r82 is
sufficient for the SA pair imsd installs**.

## ☠️ The first attempt failed for a reason worth keeping

Attempt 1 ended `no 401 to unprotected REGISTER` — nothing came back at all. The
cause was routing:

```
ip route get <P-CSCF>   ->   via <addr> dev wlan0
```

The REGISTER went out over **Wi-Fi**, to a private 10/8 address on the home LAN,
where nothing answers. The IMS netdev had only its on-link `/28`, and the P-CSCF
sits outside it.

`ims-pdn-up.sh` never had to solve this: on an IPv6 PDN the P-CSCF is reached
through the same `/64` the bearer hands out. With an IPv4 `/28` and an
off-subnet P-CSCF, an explicit host route via the bearer's gateway is required —
`ip route replace <pcscf>/32 via <gw> dev qmapmux0.0`. Adding it changed the
failure from *silence* to *a server response*, which is the whole difference.

## What is not yet known: why 500

`DumpRaw` is called only on the **success** paths
(`imsd-register-200.raw`, `imsd-subscribe-200.raw`, `imsd-invite-in.raw`), so the
failing response is discarded and only its status code survives. `DUMP_SIP=1`
was set and wrote nothing for that reason, not because dumping is broken.

The next step is a one-line local change — dump the response before throwing —
then read the reason phrase and headers. A 500 is a *server* error, so the
candidates are something in our protected REGISTER the core cannot process (an
IPv4 `Contact` where it expects v6 is the obvious suspect on an operator whose
own deployment we have only seen over v4), rather than a rejection like 403.

☠️ **Not attempted more than twice.** The README warns about the network's
fresh-SA throttle, so this was run once per change and not looped.

## Configuration used

`/etc/imsd.env` on the device, mode 0600: `PCSCF` (recovered offline by running
`tools/pcscf-scan.py` over `captures/2026-09-02_diag-ota-pmos/raw/diag.bin`),
`LOCAL` (the bearer's IPv4 address — set explicitly, which bypasses the daemon's
IPv6-only auto-detection entirely, so **the daemon needed no patch**), `DEV`,
`DUMP_SIP`, `DUMP_DIR`. The values are not reproduced here.

`ims-pdn-up.sh` was **bypassed**, not adapted, for this first pass — the scripts
that replaced it are beside this page.

## The 500, read (attempt 3, with a local patch that dumps it)

`DumpRaw` only ran on success paths, so a one-line patch was added to our package
(`0001-dump-the-failing-protected-REGISTER.patch`) to dump both the protected
REGISTER we send and the failing response. What came back:

```
SIP/2.0 500 Server Internal Error
Via: SIP/2.0/TCP <addr>:45062;branch=…;rport=45061
Call-ID: …@<addr>
From: <sip:<impu>@ims.mnc070.mcc216.3gppnetwork.org>;tag=…
To:   <sip:<impu>@ims.mnc070.mcc216.3gppnetwork.org>;tag=…
CSeq: 2 REGISTER
Warning: 399 <operator diagnostic string>.ims.mnc070.mcc216.3gppnetwork.org "Server Internal Error"
Content-Length: 0
```

★ It carries a **`Warning: 399`** header with an operator-internal diagnostic
code. That is a server-side failure inside their core, not a rejection of us —
a refusal would be 403 or 404.

## ★ And what we sent contains the thing #163 said might be missing

The protected REGISTER is structurally complete: `Authorization: Digest …
algorithm=AKAv1-MD5`, `Require`/`Proxy-Require: sec-agree`, a `Security-Client`
and a `Security-Verify` carrying the negotiated SPIs and the P-CSCF's protected
ports, `P-Access-Network-Info: 3GPP-E-UTRAN-FDD` with the cell id, `Supported:
sec-agree, path`. And in the Contact:

```
Contact: <sip:<impu>@<addr>:45062>;+sip.instance="<urn:gsma:imei:…>";
         +g.3gpp.icsi-ref="urn%3Aurn-7%3A3gpp-service.ims.icsi.mmtel";expires=600000
```

**`+g.3gpp.icsi-ref=…mmtel` is the MMTEL voice feature tag** — the first of the
two candidates
[`../2026-09-05_163-same-card-two-devices/`](../2026-09-05_163-same-card-two-devices/)
named for why the network treats this UE as not IMS-voice-capable. `imsd` offers
it. So if a registration completes, it completes as a voice-capable contact.

## Candidates for the 500, as candidates

Not established — the Warning code is operator-internal and we cannot decode it:

- ☠️ **The IMPU is derived from the IMSI.** This card is a **USIM with no ISIM**,
  so there is no provisioned IMPU and the temporary public identity
  `sip:<IMSI>@ims.mnc…` is used. If the HSS has no such temporary IMPU, an
  S-CSCF lookup can fail internally — which fits a 500 better than a 403.
- The requested `Expires: 600000` is large; some cores object.
- Something in the header set their P-CSCF cannot process.

## ☠️ A masking gap this found, in our own guard

The Contact carries the IMEI as `+sip.instance="<urn:gsma:imei:35…-…-…>"`. The
repository guard's IMEI pattern was `\b35[0-9]{13}\b`, which **cannot match the
hyphenated form** — the hyphens break both the word boundary and the digit run.
It reported clean on a file containing it. `tests/no-identifiers.sh` now carries
a second pattern anchored on the word `imei`, with a self-test case using
synthetic digits.
