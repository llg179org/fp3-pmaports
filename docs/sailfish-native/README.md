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

## ★ Morning report, 2026-08-20 — both questions answered, and the answer is go

Everything below this section is the evidence. This is the summary and the
recommendation.

| question | answer | measured |
|---|---|---|
| **Can ofono drive this modem over QRTR?** | **Yes** — modem created, SIM read, **registered on the network**, thirteen ofono interfaces including `ConnectionManager` and `MessageManager` | on the device, 00:11–00:20 |
| **What is missing for it?** | **Three `rmnet_data` netdevs.** ofono wants ≥3; mainline's `ipa2_lite` creates none. `CONFIG_RMNET=m`, so three `ip link add`s fix it | on the device |
| **Does Qt's eglfs start on this panel?** | **Yes** — KMS planes enumerated, CRTC 1080×2160, ran the full probe | on the device, 00:25 |
| **Is the kernel config a blocker?** | **No** — 29 `mer-kernel-check` errors, all netfilter/PPP/IPsec/quota, nothing structural | `mer_verify_kernel_config` |
| **How much of the stack is packaged?** | Most of it: Mesa, Qt (with eglfs-KMS **and** the Wayland compositor), `mce`, `dsme`, `sensorfw`, `mlite`, `libngf`, `nemo-*`, `connman`, `maliit` — all in Alpine edge | APKINDEX |
| **What has to be built?** | **~10 small packages** + lipstick + a homescreen. All open, all in `sailfishos`/`nemomobile-ux` | lipstick's own spec |

### Go / no-go: **go**, as a staged effort, and not as a replacement for pmOS

**Why go.** Nothing in the way is research. The two things that could have ended
it — "ofono cannot reach a QRTR modem" and "Qt cannot drive this panel without a
rebuilt Qt" — were both tested tonight and both came back positive, on the real
hardware. The remaining work is packaging: about ten small open components, then
lipstick, then `glacier-home`.

**Why staged.** The order matters and each stage is independently useful:

1. **Fix the rmnet gap** — worth doing regardless of Sailfish, and if it goes into
   `ipa2_lite` it fixes ofono for every msm8953 mainline device.
2. **Package the ten** into pmaports/Alpine. Each one is a small tarball with a
   qmake or CMake build; they are useful to anyone running Nemo/Glacier.
3. **Then** lipstick and glacier-home, which is where it becomes a UI project
   rather than a packaging one.

**What would make it a no-go, and did not:** a closed telephony stack, a closed
graphics path, a kernel that needs porting, or a homescreen with no open
alternative. None of those hold.

☠️ **What this is not.** It is not an estimate of effort in hours, because the
part after step 3 — making a phone people can use — is not measured by anything
tested tonight. And it is not a claim that Sailfish would be *better* here: pmOS
boots, and every subsystem this project has fixed is fixed on pmOS. This is a
statement that the native path is **open**, not that it is preferable.

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

## ★★★ Question 1, answered on the device: ofono works over QRTR, with one missing piece

Measured 2026-08-20 00:11–00:20 on `linux-fp3` 7.1.3, ofono 2.19 from Alpine
community. Raw, with the SIM identifiers redacted:
[`2026-08-20_ofono-qrtr.txt`](2026-08-20_ofono-qrtr.txt).

**First run — ofono found the modem by itself.** The hand-written `modem.conf`
turned out to be unnecessary: `plugins/udevng.c` has a `qrtrsoc` path that
enumerates the QRTR bus and matched immediately.

```
udevng.c:add_device()    modem:/embedded/qrtr/3  device:/sys/.../7900000.ipa/net/rmnet_ipa0
udevng.c:create_modem()  driver=qrtrsoc
udevng.c:setup_qrtrsoc() Not enough rmnet_data interfaces found      <- the whole blocker
udevng.c:destroy_modem()
```

Reading `setup_qrtrsoc()` rather than guessing: it wants one `rmnet_ipa*` device —
we have `rmnet_ipa0` — and **at least three** interfaces named `rmnet_dataN`, from
which it derives `mux_id = N + 1`. A downstream SoC kernel's IPA driver creates
those; mainline's `ipa2_lite` does not.

**They can be created by hand.** `CONFIG_RMNET=m` is in this kernel:

```sh
modprobe rmnet
ip link add link rmnet_ipa0 name rmnet_data0 type rmnet mux_id 1   # and data1/2, mux 2/3
```

☠️ **The first attempt at that failed, and the failure was the instrument.** The
device's `ip` is **busybox**, which does not implement `type rmnet mux_id`: it
sends the netlink message without `IFLA_RMNET_MUX_ID`, the kernel's
`rmnet_rtnl_validate()` answers `-EINVAL` ("MUX ID not specified"), and `ip`
prints a bare `RTNETLINK answers: Invalid argument` — which reads exactly like the
kernel refusing the operation. `apk add iproute2` and it worked first time. The
script now refuses to run under busybox rather than producing that false negative.

**Second run — the whole telephony stack came up.**

| | |
|---|---|
| modem | `/qrtrsoc_0`, `SystemPath /embedded/qrtr/3`, `Type hardware`, `Capabilities: lte` |
| SIM | `Present: true`, ICCID and IMSI read, MCC **216** / MNC **70** |
| network | **`Status: registered`**, `Mode: auto`, LAC and CellId present |
| interfaces exposed | `NetworkRegistration`, `ConnectionManager`, `MessageManager`, `LongTermEvolution`, `RadioSettings`, `CallForwarding`, `CallBarring`, `CallSettings`, `SupplementaryServices`, `NetworkMonitor`, `MessageWaiting`, `SmartMessaging`, `PushNotification` |

`drivers/qmimodem/sim.c` is visibly reading SIM elementary files (0x6F49, 0x6F46,
0x4F20) and `qmimodem/lte.c` sets the default attach profile. This is not "ofono
starts"; it is ofono **operating** the modem over QRTR.

**So the telephony answer for a native Sailfish port is: yes, with one small
kernel-side gap** — the three `rmnet_data` interfaces. Two ways to close it, and
neither is research:

1. **Userspace**: create them at boot (a udev rule or a systemd unit doing the
   three `ip link add`s). Zero kernel work; that is what this experiment did.
2. **Kernel**: have `ipa2_lite` create its own `rmnet_data` children the way the
   downstream IPA driver does. Cleaner, and it would make ofono work out of the
   box on every msm8953 mainline device.

☠️ **Restore verified, not assumed.** The links were deleted, `rmnet` unloaded,
and ModemManager started again: `state: registered`, `packet service state:
attached`, interface list back to `ipa_lan0 lo rmnet_ipa0 usb0 wlan0`.

### What was not measured

- **SMS.** `org.ofono.MessageManager` is present, but sending one needs a
  destination number, and the SIM's own `SubscriberNumbers` array is empty — so
  the phone does not know its own number. That is a fact only the user has.
- **A data context.** `org.ofono.ConnectionManager` is present and the LTE attach
  profile was written; activating a context needs an APN and would take the data
  path away from ModemManager for longer than a probe. Next session.
- **A call.** Deliberately not attempted at night.

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

Every one of them was checked to exist and to be openly licensed, and four of the
names guessed from the pkgconfig tokens were wrong — ☠️ worth stating, because a
plausible package name is not a package:

| pkgconfig token | the repository that actually provides it | licence |
|---|---|---|
| `contentaction5` | `sailfishos/libcontentaction` | LGPL-2.1 |
| `mce-qt5` | `sailfishos/libmce-qt` | (open, unlabelled) |
| `dsme_dbus_if`, **`thermalmanager_dbus_if`** | `sailfishos/libdsme` — **one package, not two** | |
| `usb_moded` | `sailfishos/usb-moded` | |
| `usb-moded-qt5` | `sailfishos/libusb-moded-qt` | BSD-3 |
| `libresourceqt5` | `sailfishos/libresourceqt` | LGPL-2.1 |
| `ngf-qt5` | `sailfishos/libngf-qt` (+ `sailfishos/ngfd`) | LGPL-2.1 |
| `systemsettings` | `sailfishos/nemo-qml-plugin-systemsettings` | BSD-3 |
| `sailfishusermanager` | `sailfishos/user-managerd` | BSD-3 |
| runtime | `sailfishos/sailjail`, `sailfishos/pulseaudio-modules-nemo` | |

### ★ And there is a fully open path that avoids Jolla's closed homescreen

Jolla's Silica and the `jolla-*` homescreen are **closed**, and no amount of
building solves that. But the NemoMobile project maintains both halves in the
open and both are alive:

| | | last push | licence |
|---|---|---|---|
| [`nemomobile-ux/lipstick`](https://github.com/nemomobile-ux/lipstick) | the compositor | 2026-07-01 | LGPL-2.1 |
| [`nemomobile-ux/glacier-home`](https://github.com/nemomobile-ux/glacier-home) | **the homescreen** | 2026-07-18 | open |
| [`sailfishos/lipstick`](https://github.com/sailfishos/lipstick) | Jolla's own | 2026-08-18 | LGPL-2.1 |

☠️ **The NemoMobile fork is not a shortcut on dependencies.** It is the same
version (0.36.29) with the same `BuildRequires` minus two, so the ten-package list
above stands either way. What it buys is the *homescreen*, which is the part that
is otherwise unobtainable.

**So the honest size of it is: about ten small packages, then lipstick, then
`glacier-home`** — and none of it needs a Qt rebuild, a kernel port, or anything
from Jolla.

## ★★★ Question 2, answered on the device: Qt eglfs comes up on this panel

Package listings can say the plugin exists; they cannot say it initialises on this
display stack. Measured 2026-08-20 00:25, raw:
[`2026-08-20_eglfs-probe.txt`](2026-08-20_eglfs-probe.txt).

`apk add qt5-qtbase-x11 qt5-qtdeclarative qt5-qtwayland`, then with greetd stopped
so the DRM device is free:

```sh
QT_QPA_PLATFORM=eglfs QT_QPA_EGLFS_INTEGRATION=eglfs_kms QT_QPA_EGLFS_KMS_CONFIG=/etc/eglfs-config.json QT_LOGGING_RULES="qt.qpa.*=true" qmlscene-qt5 probe.qml
```

**It ran for the full 20 s and drove the panel.** The `qt.qpa.eglfs.kms` log walks
the real display: planes enumerated (Overlay / Primary / Cursor), atomic
properties read, and the CRTC at **1080 × 2160** — this phone's panel, not a
fallback mode. The config file is the PinePhone's two-line one with this device's
card:

```json
{ "device": "/dev/dri/card0", "hwcursor": false }
```

☠️ **The card number is not portable.** The PinePhone adaptation names `card1`;
here the display controller (`msm_dpu`) is `card0`, and a wrong number produces
"Could not open DRM device", which reads like a missing driver rather than a
wrong path. The probe derives it from the driver rather than copying it.

**So both of Lipstick's platform prerequisites are met on the real hardware:** the
compositor library ships in `qt5-qtwayland`, and the eglfs KMS platform starts on
this panel with Mesa 26.1.6 underneath.

☠️ **Session restore, verified rather than assumed:** greetd came back and the
panel is `dpms: On`. Note it returns to the **greeter**, not the autologin
session — `[initial_session]` fires at boot only, so a hand-restarted greetd
leaves `phoc` running with no `phosh`. A reboot restores the autologin session.

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
- 00:11 ofono installed, first run: modem found by `udevng`, stopped on
  `Not enough rmnet_data interfaces found`.
- 00:17 three `rmnet_data*` created (after `apk add iproute2` — busybox `ip`
  cannot set `mux_id`); ofono brought the modem online, read the SIM and
  registered.
- 00:25 Qt installed, eglfs probe ran on `/dev/dri/card0`; session restored.
- ☠️ eMMC clean all night: no `-110`, root stayed `rw`, checked before each
  phase.
- Alpine's real package inventory read from the APKINDEX files, after the search
  page produced a false negative.
- Lipstick's BuildRequires split against that inventory.
