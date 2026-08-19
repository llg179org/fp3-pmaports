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

## Question 1, first answer: the plugin exists, and it is not auto-detected

**ofono has a QRTR driver upstream.** `plugins/qrtrqmi.c` is in
`git.kernel.org/pub/scm/network/ofono/ofono.git`, copyright 2024 Cruise LLC, and
`Makefile.am` builds it unconditionally inside the `if QMIMODEM` block - which is
on by default. Alpine ships **ofono 2.19** in `community/aarch64`, configured with
a plain `./configure --enable-external-ell --enable-test`, so it does **not**
disable QMI. The plugin is therefore in the packaged binary we can install.

That removes the version of this question that would have ended the enquiry: it
is not "does ofono speak QRTR at all".

☠️ **But `qrtrqmi` is a modem *driver*, not an auto-detecting plugin.** Read the
source rather than assuming udev finds it: it registers via
`OFONO_MODEM_DRIVER_BUILTIN(qrtrqmi, ...)` and takes its whole configuration from
modem properties, documented in the file itself:

| property | what it wants |
|---|---|
| `NetworkInterface` | *"`rmnet_ipa` on SoC systems, or `wwan0` for upstream linux systems"* |
| `NetworkInterfaceIndex` | the index of that interface |
| `PremuxInterface<n>` / `<n>MuxId` | the pre-multiplexed netdev and its mux id (e.g. `rmnet0`, mux 1) |
| `NumPremuxInterfaces` | how many of them |

So on this device the modem has to be **declared by hand** in `/etc/ofono/modem.conf`
with `Driver=qrtrqmi` and the interface names this phone actually has. There is no
udev rule that will do it for an integrated SoC modem, and an ofono that starts
and reports no modems is the expected outcome of skipping this - not a failure.

**Which makes the first device measurement a cheap one:** what rmnet interfaces
exist on FP3 pmOS today, and what does ModemManager - the working oracle on the
same phone, on the same transport - bind to? `ipa2_lite` is in the module list, so
the netdevs should be there.

## Question 2, second answer: the open graphics set is small, and it is Mesa + eglfs

From the PinePhone adaptation, which is the reference native (non-hybris) port:
[`sailfish-on-dontbeevil/droid-config-pinephone`](https://github.com/sailfish-on-dontbeevil/droid-config-pinephone),
`patterns/patterns-sailfish-device-adaptation-pinephone.inc`. The entire graphics
requirement is eight packages:

```
mesa-dri-drivers  mesa-libEGL  mesa-libGLESv2  mesa-libgbm  wayland-egl
qt5-plugin-platform-eglfs  qt5-qtwayland-wayland_egl  qtscenegraph-adaptation
```

plus one config file, `/etc/eglfs-config.json`, whose entire content is:

```json
{ "device": "/dev/dri/card1", "hwcursor": false }
```

**Lipstick runs on Qt's `eglfs` platform over KMS/GBM, with Mesa underneath.** No
libhybris, no droidmedia, no Android container in that path - and the pattern
proves it by what it comments *out*: `hybris-libsensorfw-qt5` and
`gstreamer1.0-droid` are both disabled on this port.

☠️ **One hybris-named package survives on the native port**: `mce-plugin-libhybris`,
for the notification LED. The name is misleading; it does not imply an Android
layer.

The rest of the pattern is ordinary middleware — `pulseaudio`, `gstreamer1.0-*`,
`bluez5-tools`, `usb-moded`, `connman` plugins, `gpsd`/`geoclue`, `alsa-ucm-conf`,
`sensorfw` config — and the device-specific packages follow the familiar HADK
shape even on a native port: `droid-config-<device>`,
`droid-hal-version-<device>`, `kernel-adaptation-<device>`. **The "droid-" names
are kept for the packaging scaffolding, not because Android is involved.**

☠️ **The PinePhone's modem is not comparable to ours and its ofono fork is not the
one we want.** It carries `eg25-manager` and `atinout` because the EG25-G is an
external USB modem; the org's `ofono` fork is described as *"Ofono fork with QMI
modem support for the PinePhone"*, i.e. USB QMI. The FP3's modem is integrated and
reached over QRTR, so the relevant code is upstream `qrtrqmi`, not that fork.

## Question 2, third answer: most of the middleware is already an `apk add` away

Read from the **authoritative** Alpine indexes (`APKINDEX.tar.gz` for edge
main/community/testing, aarch64, fetched 2026-08-19), not from the package search
page — ☠️ a first pass at this scraped the HTML and reported "NOT FOUND" for
things that are plainly there, which is a failed query masquerading as a negative.

Already packaged in Alpine edge, **straight from `github.com/sailfishos/*`**:

| package | version | upstream |
|---|---|---|
| `mce` | 1.117.1 | sailfishos/mce |
| `dsme` | 0.84.9 | sailfishos/dsme |
| `sensorfw` | 0.15.2 | sailfishos/sensorfw |
| `mlite` | 0.5.5 | sailfishos/mlite |
| `libngf` | 0.28 | sailfishos/libngf |
| `nemo-keepalive` | 1.8.13 | sailfishos/nemo-keepalive |
| `nemo-qml-plugin-{devicelock,connectivity,dbus,models,time,alarms,configuration}` | | sailfishos/* |
| `libsailfishkeyprovider`, `sailfish-access-control` | | sailfishos/* |

Plus everything the graphics set needs: `mesa-egl`/`gles`/`gbm`/`dri-gallium`
26.1.6, `wayland-libs-egl`, `qt5-qtbase`/`qtdeclarative`/`qtwayland`/`qtsensors`
5.15.18, `connman` 2.0, `maliit-keyboard`, `pulseaudio` 17.

**Absent, and this is the actual work:** `lipstick` itself is not packaged
anywhere — not in Alpine, not in pmaports (checked both; `device-wd-glacier` is a
phone, not the UI). Neither is `ngfd`, nor a home UI.

### ★ Both Qt prerequisites are already packaged — no Qt rebuild

Verified by downloading the packages and listing them, not by reading a package
description. ☠️ The names are misleading in both directions and this is exactly
where an assumption would have produced a wrong estimate.

`qt5-qtbase-x11` 5.15.18 — despite the name, this is where `libQt5Gui` and **all**
the platform plugins live:

```
usr/lib/qt5/plugins/platforms/libqeglfs.so
usr/lib/qt5/plugins/egldeviceintegrations/libqeglfs-kms-integration.so      <- KMS/GBM
usr/lib/qt5/plugins/egldeviceintegrations/libqeglfs-kms-egldevice-integration.so
```

`qt5-qtwayland` 5.15.18 — ships the **compositor**, not only the client:

```
usr/lib/libQt5WaylandCompositor.so.5
usr/lib/qt5/plugins/wayland-graphics-integration-server/libqt-wayland-compositor-wayland-egl.so
usr/lib/qt5/plugins/wayland-graphics-integration-server/libqt-wayland-compositor-linux-dmabuf-unstable-v1.so
```

**That is the whole platform foundation Lipstick needs, already built for
aarch64.** The PinePhone adaptation's eight-package graphics list maps onto Alpine
packages one for one, and the eglfs KMS integration — the piece that would have
meant rebuilding Qt if it were missing — is there.

### What building Lipstick would take

From `sailfishos/lipstick`'s own spec (`lipstick-qt5.spec`, version 0.36.29), the
`BuildRequires` split against what Alpine already has:

**Present:** Qt5 Core/DBus/Quick/Sql/Test/Sensors, `mlite5`, `mce`, `keepalive`,
`wayland-server`, `wayland-protocols`, `glib-2.0`, `nemodevicelock`,
`nemoconnectivity`.

**Missing — roughly ten packages, all open, all in the `sailfishos` org:**

```
contentaction5   mce-qt5      thermalmanager   usb_moded + usb-moded-qt5
libresourceqt5   ngf-qt5      systemsettings   sailfishusermanager (user-managerd)
```

plus the runtime `Requires`: `pulseaudio-modules-nemo-mainvolume` and
`sailjail-daemon`. `dsme_dbus_if` most likely comes from the `dsme-dev`
subpackage that is already there.

**So the honest size of it is: ten to twelve small packages, then lipstick, then a
home UI** — and the home UI is where it stops being mechanical. Jolla's Silica and
`jolla-*` homescreen are **closed**; the open alternative is Glacier
(nemomobile), which is not packaged in Alpine or pmaports either.

## What is still unmeasured

- Everything on the device. Both answers above are from source and packaging.
- Whether `qt5-plugin-platform-eglfs` and `qtwayland` exist as **pmOS/Alpine**
  packages (the PinePhone set is RPM, from Jolla's own OBS).
- Whether Lipstick itself builds. Lipstick is open
  (`github.com/sailfishos/lipstick`); the **Silica UI and the homescreen are
  not**, which is the part no amount of building solves.

## Run log

### 2026-08-19 21:xx — started, host-side only

☠️ The device was busy with a power-measurement slope leg until roughly 23:35 and
was deliberately not touched: an SSH login wakes it, and the leg's phase A is a
series of 900 s suspends. Host-side work only until it finished.

- `mer_verify_kernel_config` run and written up above.
- ofono `qrtrqmi` confirmed present upstream and built by default; Alpine ships
  ofono 2.19. The driver's own configuration requirements read out of its source.
- The PinePhone adaptation pattern and `eglfs-config.json` read from GitHub.
- Alpine's real package inventory read from the APKINDEX files, after the search
  page produced a false negative.
- Lipstick's BuildRequires split against that inventory.
