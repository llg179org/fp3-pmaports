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
