# The IMS PDN on this network is IPv4-only, and `imsd` auto-detects from IPv6

2026-09-05, pmOS r81, One HU (MCC 216 / MNC 70). Raised the `ims` APN with
`mmcli --create-bearer 'apn=ims,ip-type=ipv4v6'`, read it, tore it down. Raw
output in `raw.txt`, the probe in `ims-pdn-addr.sh`.

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

## The measurement

```
interface: qmapmux0.0
ip type:   ipv4v6                 <- what was REQUESTED
IPv4 configuration
  method:  static
  address: 10.12.230.131
  prefix:  29
```

**No IPv6 configuration at all** — `grep -ci ipv6` over the whole capture returns
**0**, and `ip -6 addr show dev qmapmux0.0` printed nothing. A dual-stack bearer
was asked for and the network configured v4 only.

The bearer was disconnected and deleted; the modem returned to `registered`,
`attached`. Exactly one bearer object existed throughout, so the ssh wrapper's
retry did not duplicate this state-mutating script.

## Why it matters for the `imsd` candidate

`imsd`'s `LOCAL` — the UE address it registers from — is documented as
**auto-detected from a global IPv6**. There is no global IPv6 here, so that
detection cannot work on this network, and `LOCAL` would have to be given
explicitly as the IPv4 address.

That is coherent with what this repository already measured rather than a
surprise: the two P-CSCF addresses extracted from the PDN's Protocol
Configuration Options in [`../../leads/volte-is-provisioned.md`](../../leads/volte-is-provisioned.md)
are **IPv4** (`10.149.x.x`, `10.150.x.x`). One HU's IMS core is addressed over
IPv4.

☠️ **So the open question is no longer "does the PDN get a v6 address" — it is
whether `imsd` works over IPv4 at all.** It was developed and tested against four
carriers on a Fairphone 6, and many operator IMS deployments are IPv6-only; a
daemon written against those may assume v6 in its SIP transport, its IPsec SA
setup, or both. Nothing here says it does or does not. It is now the top
feasibility risk for that path, ahead of anything about the modem generation.

## Commands

```sh
sudo sh ims-pdn-addr.sh      # raise the ims APN, read the address, tear it down
```
