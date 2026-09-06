# ★ The oracle, read live: the stock stack is IMS-registered, and the AP never raises the IMS PDN

2026-09-06, slot a, Ubuntu Touch 4.9.218. Read over ofono's D-Bus **as
`phablet`, with no root at all** — which matters, because the capture this was
meant to be needed root and did not get it.

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

## The state

```
org.ofono.NetworkRegistration    Status: registered   Technology: lte   Name: One HU
org.ofono.IpMultimediaSystem     Registered: true     VoiceCapable: true   SmsCapable: true
```

Same card, same network, same modem, same firmware as the pmOS side. **The
stock stack is IMS-registered and voice-capable right now.** That turns
[#163](../2026-09-05_163-same-card-two-devices/)'s conclusion from an inference
into a live reading, and it bounds the `500` in
[`../2026-09-05_imsd-first-register/`](../2026-09-05_imsd-first-register/)
tightly: nothing about the card, the subscription, the network or the modem
prevents an IMS registration here.

## ★ And the thing that reframes the approach

`org.ofono.ConnectionManager` carries three contexts. The IMS one:

```
Name: IMS   AccessPointName: ims   Type: ims   Protocol: dual   Active: FALSE
```

**Active is false while IMS is registered.** So on the working stack the AP does
**not** raise the IMS PDN — the modem brings it up internally and the AP-side
context stays inactive throughout.

That is structurally different from what this project does on pmOS, where
`mmcli --simple-connect apn=ims` raises an **AP-visible** IMS bearer and `imsd`
registers over it as an ordinary host. The two are not the same registration
seen from two operating systems; they are two different designs, and only one of
them is the one this network is serving successfully.

☠️ It also explains a symptom that looked like our own bug: the P-CSCF needed an
explicit host route on pmOS because the AP-visible bearer's `/28` does not
contain it. On the stock stack that question never arises, because no AP-visible
bearer exists.

Note also `Protocol: dual` — the stock context asks for IPv4v6. Asked the same
way on pmOS the network still returns IPv4 only
([`../2026-09-06_carrier-config-volte/`](../2026-09-06_carrier-config-volte/)),
so that is not the difference, but it is what the working side requests.

## What this says about where to go

The userspace route (imsd) replaces the modem's IMS stack. The evidence now says
the **modem's own stack works on this network**, and that what it needs from the
AP is not a bearer — it raises its own — but whatever else the vendor RIL does.
That is [#172](../../leads/ims-missing-ap-half.md) exactly, and it is now backed
by a live measurement rather than by the reverse-engineering literature alone.

## ☠️ Where this stopped, and why

The intended measurement was the stock REGISTER on the wire, to diff header by
header against ours. It needs `tcpdump` (`/system/bin/tcpdump` exists, inside the
Android container) or `/dev/diag` (mode `crw-rw---- system root`), and both need
root. On UT `sudo` asks for a password, and the NOPASSWD drop-in installed today
exists only on the pmOS side. `phablet` is in the `sudo` group but that does not
help without the password.

So the remaining work on this slot is gated on one thing: **root on Ubuntu
Touch**. Everything above was obtained without it.
