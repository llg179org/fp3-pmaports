# `imsd` builds for the FP3 — packaged, cross-compiled, first attempt

2026-09-05. Part of #177; **not** the end of it — nothing has registered yet.

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

## What exists now

`imsd-0.3.0_git1987275-r0.apk`, 260 183 bytes, built by
`pmbootstrap build --arch aarch64 imsd` from `pmaports/temp/imsd/`. Exit 0 on
the first attempt. Contents:

```
usr/bin/imsd                     ELF 64-bit LSB pie executable, ARM aarch64
usr/bin/imsd-dialerd             ELF 64-bit LSB pie executable, ARM aarch64
usr/libexec/imsd-media           ELF 64-bit LSB pie executable, ARM aarch64
usr/libexec/ims-pdn-up.sh
usr/lib/systemd/system/imsd.service
usr/share/dbus-1/system.d/net.catcrafts.IMS1.conf
etc/xdg/autostart/imsd-dialerd.desktop
```

Upstream's `packaging/APKBUILD` needed **two** changes, both forced, and the
local copy is kept beside this page as `APKBUILD.fp3`:

- ☠️ **There is no release tag.** Upstream's `source=` fetches
  `archive/v0.3.0.tar.gz`, which 404s; so does a bogus version and so does an
  archive by sha, so the endpoint is not serving archives at all. The source is
  a local `git archive` of the clone, pinned by `_commit`.
- `options="!check"` for this first pass; the unit tests want the same toolchain
  and should be run once the thing works.

☠️ **`makedepends` did NOT need changing.** An earlier reading of a cached
`APKINDEX` came back empty for `clang`, `lld`, `glib-dev` and `pkgconf` — packages
that certainly exist — so it was recorded as inconclusive rather than as absence,
and upstream's names were kept. `apk` then resolved every one of them:

```
(buildroot_aarch64) install libc++-dev llvm-libunwind-dev llvm-runtimes pkgconf glib-dev clang lld
```

The blunt read was wrong, and treating it as an answer would have sent an hour
into renaming things that were already right.

## What is still needed before it can register

1. **`ims-pdn-up.sh` is IPv6-only** and our IMS PDN is IPv4-only — it reads
   `bearer.ipv6-config.address` and runs `ip -6 addr replace`, and would stop at
   *"bearer up but no interface/address"*. A local adaptation to `ipv4-config`.
2. **`PCSCF` must be set by hand** (upstream does not implement PCO discovery).
   The two addresses are recoverable offline: `tools/pcscf-scan.py` over
   `captures/2026-09-02_diag-ota-pmos/raw/`. They are written redacted in the
   docs and should stay that way; the value belongs in `/etc/imsd.env` on the
   device, not in this repository.
3. **`LOCAL` must be set explicitly** — the auto-detection is the one IPv6
   hardcode in the daemon.
4. **The nftables accept rule** for 45061–45062 on `qmapmux*`, which
   `ims-pdn-up.sh` inserts — and which upstream says is what makes terminating
   calls fall back to CS when missing.
5. **The modem's own IMS stack must stay out of the way.** `fp3-ims-reconcile`
   already holds every IMS switch off, for power reasons; upstream reaches the
   same requirement from the other side by excluding `81voltd`.

## Commands

```sh
cd /mnt/1TB/pmos && ./pmb checksum imsd && ./pmb build --arch aarch64 imsd
```
