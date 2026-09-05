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

## The README's own limitations, and what they change

Read 2026-09-05. Two of them bear directly on this device, and one reverses an
expectation stated earlier the same day.

☠️ **"T-ADS may route incoming calls to CS domain regardless of IMS
registration."** The project names our exact failure mode as a known open issue.
So `imsd` is **not** a promise that an incoming call will arrive on LTE — the
network still decides the terminating domain, and a userspace registration may
not move it.

What it does reach directly is the **originating** side: a call the phone places
goes out over IMS. **So the first test to run is an OUTGOING call, not an
incoming one.** An earlier note in this session said the opposite — that one
incoming call would settle it — and that was wrong: an incoming call landing on
EDGE would be consistent with `imsd` working perfectly.

★ **"P-CSCF discovery from PDN Protocol Configuration Options not yet
implemented"** — and `PCSCF` is the one setting the daemon *requires*, failing
registration with a clear error without it. This repository already has the
answer: [`volte-is-provisioned.md`](volte-is-provisioned.md) extracted **two
P-CSCF addresses** from the PCO of `ACTIVATE DEFAULT EPS BEARER CONTEXT REQUEST`
with a length-validated TLV walk, 21/21 and 18/18 closed, against a clean
negative control. The single hand-configured value the daemon needs is a number
we measured weeks ago for another reason.

## The rest of its configuration, against what we have

| `imsd` needs | our state |
|---|---|
| `PCSCF` (required) | **measured**, two addresses from the PCO |
| `DEV` — the IMS PDN network device | the modem raises an IMS PDN by itself every 8.4 s; holding one up with `mmcli --simple-connect apn=ims` was already exercised |
| `LOCAL` — UE address, auto-detected from a global IPv6 | ☠️ **MEASURED 2026-09-05: there is none.** The `ims` APN bearer comes up IPv4-only (`10.12.230.131/29` on `qmapmux0.0`), with zero IPv6 lines in the capture, even though `ipv4v6` was requested. Coherent with the P-CSCF addresses being IPv4. So `LOCAL` must be given explicitly — **and reading the source the same day answered the follow-on question favourably: `imsd` is IPv4-capable.** Every socket is opened with `Is6(local) ? AF_INET6 : AF_INET`, `MakeAddr` branches per family, and the IPsec module picks its prefix length the same way; the *only* IPv6 hardcode is `DetectLocal()`, the auto-detection itself. [`captures/2026-09-05_ims-pdn-address/`](../captures/2026-09-05_ims-pdn-address/) |
| kernel ESP + `ip xfrm` | ❌ the blocker — see above |
| `qmicli` over QRTR for USIM AKA on a UIM logical channel | QMI works; the card is a plain USIM, which is what it uses |
| PipeWire, AMR-WB RTP | PipeWire runs; AMR-WB support unverified |
| build: clang++/libc++, and it advertises `--target=aarch64-alpine-linux-musl` | Alpine aarch64 is exactly our target, and **`libc++`, `libc++-dev` and `libc++-static` 22.1.8 are packaged for Alpine edge aarch64** (checked 2026-09-05). ☠️ Unverified: whether the *libc++ std module sources* the Makefile route asks for are in `libc++-dev` |

Tested by the project on **postmarketOS, Linux 7.1.2** — we are on 7.1.3, the
same series.

☠️ Still not a claim that it will work here: the Fairphone 6's modem is several
generations newer than msm8953/sdm632, and nothing in the project speaks to ours.

## ★ What the upstream packaging says, read from a clone (2026-09-05)

`git clone https://forgejo.catcrafts.net/Catcrafts/imsd.git` at `1987275`
(2026-09-02). There is a `packaging/` directory with an `APKBUILD`, a systemd
unit, a D-Bus policy and a bring-up script — and reading them answers three of
our open questions and hands us one cause for our headline symptom.

### ☠️ 1. pmOS's own firewall makes terminating calls fall back to CS

Verbatim from `packaging/ims-pdn-up.sh`:

> *"pmOS's default nftables INPUT chain is policy-drop and explicitly drops all
> inbound on `qmapmux*`, which silently killed every network-initiated request
> (reg-event NOTIFY, MT INVITE) after ESP decap — the P-CSCF's TCP SYNs to the
> protected server port never reached the listener, so terminating delivery
> failed and **MT calls fell back to CS**."*

That is our symptom, named, with a cause and a fix: insert accept rules for
tcp/udp 45061–45062 on `qmapmux*`. It does **not** explain the Ubuntu Touch
result (#163 CSFBs on a Halium stack with no such firewall), so it is not *the*
answer — but it is a concrete mechanism by which a working IMS registration
still yields a CS-paged call, and it would have bitten us silently.

### ☠️ 2. The modem's own IMS-PDN service races an AP-side one

The APKBUILD carries `provides="81voltd=$pkgver-r$pkgrel"` with the reason:

> *"81voltd serves the modem's own ims-PDN requests, which races imsd for the PDN
> and flaps it with a new prefix every ~2.5 min — the two IMS stacks cannot share
> one PDN."*

Ours flaps faster — 22 up/down cycles in 120 s, ~8.4 s apart
([`../captures/2026-09-02_diag-ota-pmos/`](../captures/2026-09-02_diag-ota-pmos/)) —
but it is the same class of conflict, and it says plainly that **the modem's IMS
stack has to be kept out of the way**. `fp3-ims-reconcile` already does exactly
that, for power reasons. The two requirements coincide.

### 3. AMR-WB is a packaging question, and it is answered

`depends="modemmanager opencore-amr vo-amrwbenc pipewire-tools"` — the media leg
`dlopen`s the AMR-WB codecs. **`opencore-amr`, `vo-amrwbenc` and
`pipewire-tools` all exist for Alpine edge aarch64.** That unknown is closed.

### ☠️ 4. The bring-up script IS IPv6-only, even though the daemon is not

`ims-pdn-up.sh` defaults `IMS_IP_TYPE=ipv6`, reads `bearer.ipv6-config.address`,
and configures the netdev with `ip -6 addr replace`. On our IPv4-only IMS PDN it
would stop at *"bearer up but no interface/address in mmcli output"*.

This **refines** the earlier finding rather than contradicting it: the *daemon*
threads the address family through as data, and the *bring-up script* does not.
Adapting it to read `bearer.ipv4-config.*` is small and local.

### Packaging notes for #177

- **There is no release tag yet.** `packaging/APKBUILD` fetches
  `archive/v0.3.0.tar.gz`, which returns **404** — and so does a bogus version,
  so the check discriminates. The package has to be built from a git checkout.
- **`makedepends` names are upstream's, not Alpine's.** Alpine edge aarch64 has
  versioned toolchains — `clang20`, `clang21`, `clang22` and `libc++` 22.1.8 —
  with no unversioned `clang`. The list needs translating.
