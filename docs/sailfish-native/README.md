# Native Sailfish on the Fairphone 3 — is it reachable?

> ⚠️ **AI-generated.** Maintained by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed every change and made or reviewed every
> measurement it rests on.

**This is not a port.** It is the evidence for one decision: whether a *native*
Sailfish — Lipstick on the mainline kernel and Mesa, no hybris, no Android
container — is worth starting on this device. The existing Sailfish work here is
the hybris track and is a different thing entirely; it lives in the skill archive.

Two questions decide it, and neither is answered by reading:

1. **Can the telephony stack Sailfish uses talk to this modem?** Sailfish uses
   **ofono**, and mainline msm8953 reaches the modem over **QRTR**. postmarketOS
   uses ModemManager over the same transport, so ModemManager is a working oracle
   sitting on the same phone: whatever ofono cannot do, the difference is
   measurable rather than theoretical.
2. **What is the minimal open Lipstick stack, and how much of it is prebuilt?**
   The PinePhone adaptation is the reference — it is the one native, Mesa-based
   Sailfish adaptation with a public package set.

Everything below is measured or read from a named file. Where a number came from
a run, the run is in this directory and dated.

## Question 2, first answer: the kernel config is not the obstacle

`mer_verify_kernel_config` (the Sailfish adaptation checker, from the
`mer-kernel-check` tree in the local HADK checkout, `ef81c46`) run against the
port's own `linux-fp3/config-fp3.aarch64`:

```sh
perl hadk22/hybris/mer-kernel-check/mer_verify_kernel_config \
     fp3-pmaports/linux-fp3/config-fp3.aarch64
```

Full output: [`2026-08-19_mer-kernel-check.txt`](2026-08-19_mer-kernel-check.txt).
**29 errors, 58 warnings** — and the shape of them is the result:

| errors | area |
|---|---|
| 13 | netfilter / iptables, all of it what **connman** wants |
| 7 | PPP and L2TP — cellular data and tethering |
| 5 | IPsec (`INET_AH`, `INET_ESP`, `INET6_*`, `IPCOMP`) |
| 2 | quota (`QUOTA_NETLINK_INTERFACE`, `QFMT_V2`) |
| 1 | `NLS_UTF8` |
| 1 | `DUMMY` must be **n**, and is `m` |

**Nothing structural is missing.** Every systemd requirement, every namespace,
`CGROUPS`, `AUTOFS`, `FHANDLE`, `SIGNALFD`, `TIMERFD`, `TMPFS_POSIX_ACL`, `VT` -
all pass, which is why they are absent from the list. Eight of the 29 are already
built as modules and only need `=y`:

```
IP_NF_TARGET_REJECT  IP6_NF_TARGET_REJECT  IP_NF_MANGLE  NETFILTER_XT_MATCH_CONNTRACK
IP_NF_NAT            IP_NF_FILTER          DUMMY(→n)     NETFILTER_XT_MATCH_MULTIPORT
```

☠️ **What this does and does not say.** It says the config has no architectural
gap — the work is a `defconfig` edit and a rebuild, not a kernel port. It does
**not** say Sailfish boots: the checker only reads a config file, it never ran on
the device, and it knows nothing about graphics, about the modem, or about
whether the userspace exists. Treat it as one gate passed out of several.

☠️ It also carries an assumption worth stating: this checker was written for
**hybris** adaptations, so some entries (the quota pair, parts of the netfilter
set) are requirements of Jolla's own middleware rather than of the kernel/Sailfish
boundary. A native port may not need all 29. None of them is expensive either way.

## Run log

### 2026-08-19 21:xx — started, host-side only

☠️ The device was busy with a power-measurement slope leg until roughly 23:35 and
was deliberately not touched: an SSH login wakes it, and the leg's phase A is a
series of 900 s suspends. Host-side work only until it finished.

- `mer_verify_kernel_config` run and written up above.
