<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# ★ `imsd` is working code now, on a different architecture than we assumed

**2026-09-05.** This overturns the load-bearing sentence in
[`ims-missing-ap-half.md`](ims-missing-ap-half.md) and the case-against on queue
item #172, both of which say the `imsd` document is *"documentation only, there
is NO code to port"*. That was true of
[`codeberg.org/flamingradian/imsd`](https://codeberg.org/flamingradian/imsd),
which is a reverse-engineering write-up. It is **not** true of the project that
now carries the name.

## What exists

[`forgejo.catcrafts.net/Catcrafts/imsd`](https://forgejo.catcrafts.net/Catcrafts/imsd)
— GPL-3.0, a userspace IMS/VoLTE daemon for mainline Linux phones. Per its README
and the project's own posts (as of 2026-08-18):

- SIP registration with **USIM AKA** authentication, call signalling, **AMR-WB
  RTP audio through PipeWire**, bridged to a stock dialer over D-Bus;
- inbound **and** outbound calls working on a **Fairphone 6 running
  postmarketOS**, across four carriers (KPN NL, Telekom DE, Phonero, Telia NO);
- emergency calling end-to-end tested 2026-08-18;
- requirements: ModemManager with working WWAN/MM integration, `qmicli` over
  QRTR, **kernel ESP/IPsec (`ip xfrm`)**, PipeWire, clang++/libc++ to build.

## ☠️ Why this is not the thing #172 describes, and why that matters

#172 is *"supply the AP half of the IMS handshake"* — help the **modem's own IMS
stack** finish its registration. Its case-against is #163: the Ubuntu Touch
oracle runs the full vendor Qualcomm IMS stack, **registers** against One HU's
core with a valid P-Associated-URI, and still takes every call on EDGE.

`imsd` does something architecturally different: it **replaces** the modem's IMS
stack rather than assisting it. The modem becomes a data pipe (the IMS APN
bearer) plus the UIM, and the SIP registration — including the media feature
tags that say *this contact can take voice* — is built in userspace.

That matters because it is exactly the gap #163 pointed at: the FP3 *is*
IMS-registered and the network still CS-pages it, which reads as **no
voice-capable registration exists**, so terminating access domain selection
(T-ADS) picks CS. A registration `imsd` builds is one we control the contents of.

**So #163 does not argue against `imsd`.** It argues against #172 as written, and
those are different things. Do not carry the objection across.

## Feasibility on the FP3, measured rather than assumed (2026-09-05, r81)

| requirement | our device | verdict |
|---|---|---|
| ModemManager + QMI over QRTR | working; PDC, NAS, IMS and UIM services all answer | ✅ |
| USIM AKA over a UIM logical channel | card reports exactly **one** application, `usim (2)` — **no ISIM** | ✅ AKA over USIM is what `imsd` uses |
| kernel ESP / IPsec (`ip xfrm`) | `CONFIG_XFRM_USER`, `CONFIG_INET_ESP`, `CONFIG_INET6_ESP`, `CONFIG_NET_KEY` **all "is not set"** in `config-fp3.aarch64`; `ip xfrm state` fails on the device | ❌ **and it is entirely ours to fix** |
| PipeWire + audio路 | PipeWire runs; the WCD9335 playback and mic paths are working and covered by selftests | ✅ for the plumbing; AMR-WB codec support unverified |
| build toolchain | Alpine has clang/libc++; the package would be new | untested |

`CONFIG_CRYPTO_AUTHENC=m` is already there, which ESP needs.

☠️ The kernel readings were taken twice — from the running kernel and from the
config file the package ships — and a known-set option (`CONFIG_CRYPTO_HMAC=y`)
came back positive from the same read, so "not set" is an answer and not a
truncated file.

## The one thing to do next, and it needs no test call

Turn the IPsec options on in `config-fp3.aarch64` and ship them. That is a
config change on the `debug` layer's own terms — additive, revertible, and
verifiable without the radio: `ip xfrm state` either works after the flash or it
does not. Everything else about `imsd` is blocked behind it, and nothing else
about it can be tested until it is done.

## What this does NOT establish

That `imsd` will work here. The FP6's modem is several generations newer, the
project makes no claim about msm8953/sdm632, and T-ADS may still choose CS for
reasons a userspace registration cannot reach. This lead establishes that the
**premise** under which we filed the work as not-worth-doing is false, and that
the first blocker is one line of our own kernel config.
