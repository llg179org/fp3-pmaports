# The kernel can build an IPsec SA now — #176 closed

2026-09-05, `linux-fp3-7.1.3-r82`, `uname -v #83-fp3`, source commit
`3f843d0534e3` (unchanged from r81 — **only the config changed**). Raw output in
`raw.txt`.

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

## What changed

Three lines in `config-fp3.aarch64`:

```
CONFIG_XFRM_USER=y
CONFIG_INET_ESP=m
CONFIG_INET6_ESP=m
```

`olddefconfig` pulled `CONFIG_XFRM=y` and `CONFIG_XFRM_ALGO=y` in with them.
Every crypto dependency ESP needs was already present (`AUTHENC=m`, `HMAC=y`,
`SHA1=y`, `AES=y`, `CBC=m`, `MD5=m`, `ECHAINIV=y`).

Verified in the **shipped package** rather than in the intention: the config
inside `linux-fp3-7.1.3-r82.apk` carries all four, and the package contains
`net/ipv4/esp4.ko` and `net/ipv6/esp6.ko`.

## ★ The result, and why the first reading looked like a failure

As the unprivileged user the command still fails — but **with a different
error**, and the difference is the whole finding:

| | `ip xfrm state` says |
|---|---|
| r81 | `Cannot open netlink socket: Protocol not supported` |
| r82, as `fp3` | `RTNETLINK answers: Operation not permitted` |
| r82, as root | *(nothing — rc=0)* |

The socket now **opens**; the kernel refuses the operation because `ip xfrm`
needs `CAP_NET_ADMIN`. That is the expected behaviour for a non-root caller and
not a defect. ☠️ Reading the first line as "still broken" would have been the
easy mistake here: the command failed both times.

## The real test: an SA that actually exists

Not "the interface is present" but "the kernel accepts an ESP association with
the algorithm classes IMS uses":

```
ip xfrm state add src 10.0.0.1 dst 10.0.0.2 proto esp spi 0x1000 \
    mode transport auth "hmac(sha1)" 0x…  enc "cbc(aes)" 0x…
  -> SAs present after add: 1
  -> after deleteall:       0
```

and the modules loaded themselves on demand:

```
authenc  12288  1
esp4     28672  1
```

**So `imsd`'s hard kernel requirement is met.** The addresses above are dummies;
nothing was configured for the real IMS core.

## No regressions

`fp3-selftest` on r82: identity (`#83-fp3`, `linux-fp3-7.1.3-r82`,
`3f843d0534e3`), boot-fallback (3 labels, 3 distinct kernels, `panic=` on all,
watchdog active), dtb (**booted DTB matches the installed package**, charger,
audio and camera layers all present), modules, and ims-config (every IMS switch
off, the reconciler's timer running) — all green. `touch` correctly reports that
the panel has barely been used rather than banking a PASS on an unexercised
check.

The boot net is r82 default, **r81** and r79 behind it, checked green *before*
the reboot.

## What this does NOT establish

Only that the kernel side is no longer the blocker. Nothing here says `imsd`
builds, runs, registers, or that One HU's IMS core accepts an SA from this UE.
Those are #177.

## Commands

```sh
sudo ip xfrm state                 # rc=0 now; as a normal user it is EPERM, not EPROTONOSUPPORT
fp3-selftest --only identity
```
