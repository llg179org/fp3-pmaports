# 4G voice (VoLTE) on the Fairphone 3 — bring-up

> ⚠️ **AI-generated.** This page — and the code, device tree and tooling it
> describes — was written by Claude (Opus 5) working under the direction of
> Lajosházi, László Gergely, who reviewed every change and made or reviewed
> every measurement it rests on.

**State as of 2026-09-05: voice does not run over LTE.** Calls arrive and leave
over CS fallback. What *does* work is every link of the chain up to a named,
server-side failure — see [The chain](#the-chain).

This page is the status and the procedure. The method and the traps live in the
skills (`/fp3-porting-debug`, `/fp3-kernel-test`); the dated evidence lives in
`../power/bringup/captures/` and `../power/bringup/leads/`.

## Why this matters, and it is not a preference

Hungary has already retired 3G, and 2G retirement is announced across the
sector. The phone currently rings because the network's **CS domain is still
reachable** — measured: the LTE registration includes the CS domain
(`Domain: 'cs-ps'`), the SGs association to the MSC is live, and calls fall back
to `gsm-900`. So the working call path leans on a service whose withdrawal is
not on our schedule. See [`../power/bringup/leads/csfb-is-a-dependency.md`](../power/bringup/leads/csfb-is-a-dependency.md).

When 2G goes, the choice is not "IMS on or off" but **VoLTE or no calls**.

## The chain

Each row is measured, not assumed. Links to the capture that established it.

| # | link | state | evidence |
|---|---|---|---|
| 1 | the network provisions IMS for this SIM | ✅ | two P-CSCF addresses + the IM CN Subsystem Signalling Flag out of the PDN's PCO, length-validated TLV walk, 21/21 and 18/18 closing, zero in the negative control — [`volte-is-provisioned.md`](../power/bringup/leads/volte-is-provisioned.md) |
| 2 | the network offers **this UE** IMS voice | ✅ | `qmicli --nas-get-system-info` → `IMS voice support: 'yes'` for MCC 216 / MNC 70 — [`2026-09-05_166-volte-config-activate/`](../power/bringup/captures/2026-09-05_166-volte-config-activate/) |
| 3 | the modem prefers PS for voice | ✅ | `qmicli --voice-get-config` → `Current Voice Domain Preference: 'ps-preferred'` |
| 4 | the subscription really has VoLTE | ✅ | the same card in a stock-Android handset holds **4G through a whole call** — [`2026-09-05_163-same-card-two-devices/`](../power/bringup/captures/2026-09-05_163-same-card-two-devices/) |
| 5 | the kernel can build an IPsec SA | ✅ | r82: a real ESP SA with `hmac(sha1)`/`cbc(aes)` added, counted, deleted — [`2026-09-05_kernel-ipsec-r82/`](../power/bringup/captures/2026-09-05_kernel-ipsec-r82/) |
| 6 | a userspace IMS daemon runs here | ✅ | `imsd` cross-built, packaged, installed — [`2026-09-05_imsd-packaged/`](../power/bringup/captures/2026-09-05_imsd-packaged/) |
| 7 | the USIM answers AKA on this modem | ✅ | the daemon reads the SIM over QMI/UIM and completes AKA |
| 8 | SIP reaches the operator's core | ✅ | 401 challenge received, protected TCP connect established |
| 9 | **the REGISTER completes** | ❌ | **`500 Server Internal Error`** with a `Warning: 399` operator diagnostic — [`2026-09-05_imsd-first-register/`](../power/bringup/captures/2026-09-05_imsd-first-register/) |
| 10 | a call runs over IMS | — | not reached |

★ Our REGISTER **does** advertise `+g.3gpp.icsi-ref=…mmtel` — the MMTEL voice
feature tag whose absence was one of the two candidates in row 4's capture for
why the network treats this UE as not voice-capable. So a registration that
completes would complete as a voice-capable contact.

## What is established, and what is not

**Established**, each by a measurement with a control:

- The **network side is not the obstacle** (rows 1–4).
- The **device is the variable** — the same card gets VoLTE in another handset
  and CS fallback here.
- The **failure is not the P-CSCF**: the PCO returns two, and pointing the
  daemon at each in turn gives byte-for-byte the same 500.
- **IPv4 is not the obstacle.** This network's IMS PDN is IPv4-only and both
  P-CSCF addresses are IPv4; `imsd` threads the address family through as data
  (`Is6(local) ? AF_INET6 : AF_INET` at every socket). Only its `LOCAL`
  auto-detection is IPv6-only, and `LOCAL` is settable.

**Not established** — say so rather than filling the gap:

- **Why the core answers 500.** The `Warning: 399` string is an operator-internal
  code we cannot decode. No candidate is supported by evidence rather than
  plausibility. ☠️ One candidate was published here as "strongest" and demoted
  within the hour: the IMSI-derived temporary IMPU is *correct* behaviour for a
  USIM-only card, which `imsd` handles deliberately (`main.cpp`, "the temporary
  IMPU is barred for anything but REGISTER").
- Whether terminating calls would arrive over IMS even after a successful
  registration. `imsd`'s own README lists *"T-ADS may route incoming calls to CS
  domain regardless of IMS registration"* as a known limitation.

## The two paths, and why this one

| path | what it is | verdict |
|---|---|---|
| **drive the modem's own IMS stack** | supply the AP half of the handshake the firmware waits for | ☠️ measured against: the Ubuntu Touch oracle runs the **full vendor stack**, registers with a valid P-Associated-URI, and **still takes every call on EDGE** |
| **replace it in userspace (`imsd`)** | SIP + USIM AKA + AMR-WB over PipeWire, the modem as a data pipe | the path being taken — its registration is one we control the contents of, including the MMTEL tag |

The second is not the first with a different name: `imsd` bypasses the modem's
IMS stack rather than assisting it, so the oracle's failure does not carry over.
Reasoning: [`imsd-is-code-now.md`](../power/bringup/leads/imsd-is-code-now.md).

## Reproducing today's state

Everything below is machine work; none of it needs a test call.

```sh
# 1. the kernel must have IPsec (r82 or later)
sudo ip xfrm state && echo ok        # EPERM as a normal user is expected, not a failure

# 2. build and install the daemon
cd /mnt/1TB/pmos && ./pmb checksum imsd && ./pmb build --arch aarch64 imsd
#    then copy the apk over and `apk add --allow-untrusted`

# 3. the modem's own IMS stack must stay out of the way
sudo /usr/local/bin/fp3-ims-reconcile.py off     # already held off by its timer

# 4. raise the ims PDN, IPv4
sudo mmcli -m any --create-bearer='apn=ims,ip-type=ipv4'
sudo mmcli -b <path> --connect
sudo ip addr replace <addr>/<prefix> dev qmapmux0.0

# 5. ☠️ THE HOST ROUTE. Without it the REGISTER leaves over wlan0.
sudo ip route replace <pcscf>/32 via <bearer-gateway> dev qmapmux0.0

# 6. configuration, mode 0600, values NOT in this repository
#    /etc/imsd.env:  PCSCF=  LOCAL=  DEV=  DUMP_SIP=1  DUMP_DIR=/tmp/imsd-sip

# 7. one run
sudo env $(cat /etc/imsd.env | tr '\n' ' ') /usr/bin/imsd
```

The `PCSCF` value is recovered offline, with no new capture:

```sh
python3 docs/power/bringup/tools/pcscf-scan.py \
        docs/power/bringup/captures/2026-09-02_diag-ota-pmos/raw/diag.bin
```

## ☠️ Traps this area has already sprung

- **The REGISTER goes out over Wi-Fi unless you add a host route.** The IMS
  netdev carries only its on-link `/28`; the P-CSCF is outside it. On an IPv6 PDN
  this never arises, which is why upstream's `ims-pdn-up.sh` does not do it.
  Symptom: `no 401 to unprotected REGISTER` — total silence, not an error.
- **`ims-pdn-up.sh` is IPv6-only** (`bearer.ipv6-config.address`,
  `ip -6 addr replace`) and stops at *"bearer up but no interface/address"* here.
  The **daemon** needs no patch; the bring-up does.
- **`DumpRaw` only runs on success paths**, so `DUMP_SIP=1` writes nothing when
  registration fails. A one-line local patch fixes that
  ([`0001-dump-the-failing-protected-REGISTER.patch`](../power/bringup/captures/2026-09-05_imsd-first-register/0001-dump-the-failing-protected-REGISTER.patch)).
- **pmOS's nftables INPUT chain is policy-drop and drops inbound on `qmapmux*`.**
  Upstream states this killed every network-initiated request after ESP decap, so
  **terminating delivery failed and MT calls fell back to CS**. Open tcp/udp
  45061–45062 on `qmapmux*`.
- **The modem's own IMS PDN service races an AP-side one** and flaps the bearer.
  `fp3-ims-reconcile` already holds the modem's IMS switches off — for power
  reasons — and that requirement coincides exactly with this one.
- ☠️ **SIP dumps carry the IMSI, the IMPI and the IMEI** (the last as
  `+sip.instance="<urn:gsma:imei:…>"`, hyphenated). They stay on the device.
  `tests/no-identifiers.sh` now catches both forms; it did not before
  2026-09-05.
- ☠️ **Do not loop registration attempts.** `imsd`'s README warns of the
  network's fresh-SA throttle. Today's work ran once per change, four times
  total.

## What would move this next

**Diff our REGISTER against the stock stack's, header by header.** `imsd`'s
`DumpRaw` was built for exactly that comparison, and this project has the
oracle: on Ubuntu Touch the vendor stack registers successfully against this same
core with this same card. That turns "500 for unknown reasons" into a named
difference.

☠️ It needs a UT-side SIP or DIAG capture — the same wall queue items #54 and
#64 stand at. It is the right instrument rather than another guess, and the
guesses are exhausted: the P-CSCF has been eliminated, IPv4 has been eliminated,
and the IMPU candidate was demoted by reading the code.
