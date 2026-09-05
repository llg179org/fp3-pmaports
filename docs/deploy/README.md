# Building and deploying

> ⚠️ **AI-generated.** This page — and the code, device tree and tooling it
> describes — was written by Claude (Opus 5) working under the direction of
> Lajosházi, László Gergely, who reviewed every change and made or reviewed
> every measurement it rests on. Kernel commits carry `Co-authored-by: Claude`;
> anything prepared for the LKML carries `Assisted-by:` instead and never a
> `Signed-off-by` from the assistant, since only a human can certify the DCO.

How a change gets from an edit to a booted phone, and how the last working
kernel stays bootable while the new one is tried.

## Building

Assumes the checkouts and the `pmb` wrapper from
[Setting the checkouts up](../rolling-a-new-base.md#setting-the-checkouts-up-once-per-machine). After a
change to the APKBUILD or the config, mirror it into pmaports and build:

```sh
cp fp3-pmaports/linux-fp3/{APKBUILD,config-fp3.aarch64} \
   pmaports/device/testing/linux-fp3/

./pmb checksum linux-fp3            # only needed if you changed _commit
./pmb build --arch aarch64 --force --lax linux-fp3
```

☠️ **If you skip that `cp`, everything still says DONE and nothing is built.**
`pmbootstrap` builds `pmaports/device/testing/linux-fp3/`, not the copy in this
repository — `pmbootstrap config aports` names the tree it uses. Bump `_commit`
and `pkgrel` only in the mirror and both `checksum` and `build` exit **0**, the
build prints *"Package 'linux-fp3' is up to date"*, and no package appears.
Measured 2026-09-01. Two ways to catch it, and prefer the second:

* a `checksum` that finishes in ~2 s did not fetch the tarball; a real one takes
  ~40 s;
* **look for the artefact, not for DONE:**
  `ls work/packages/edge/aarch64/linux-fp3-<pkgver>-r<pkgrel>.apk`

☠️ **Know what the flash carries before you flash it.** `pkgrel` is not the
distance: a package can be built and never deployed, so the phone may be several
pins behind. Ask git, using the `_commit` the *running* kernel was built from:

```sh
git -C linux-fp3 log --oneline <running _commit>..<new _commit>
```

On 2026-09-01 the phone ran r78 while the tree was at r80, and that innocent-
looking two-step carried **four** commits including an unrelated fuel-gauge
change. A measurement taken after a flash has to name every commit the flash
brought, or it is a two-variable experiment wearing one variable's label.

`--force` and `--lax` are **`build` flags, not global ones** — `./pmb --lax build`
is rejected with `unrecognized arguments`. Without `--force`, a rebuild at the
same `pkgver` is skipped with *"Package is up to date"* even though `_commit`
changed; without `--lax` the buildroots are zapped first, which throws the
ccache away and turns a four-minute rebuild into thirty.

The source tarball is ~250 MB straight from GitHub, so the first fetch takes a
minute or two. A warm ccache rebuild is around four minutes; a new `_commit`
means a new source directory and therefore a cold ccache, which is 20–35.

☠️ **The cache is full, and that is what a slow rebuild actually costs.** Ask
ccache itself rather than guessing:

```sh
sudo chroot <work>/chroot_native /bin/sh -c 'HOME=/home/pmos ccache -s'
```

Measured 2026-08-23: 1 122 523 calls, **59.8 % hits** — and `Cache size (GB):
5.0 / 5.0 (99.98%)` with **4988 cleanups**. The cache had been running against
its own ceiling for a long time, evicting objects to make room for the next
ones, so a "warm" rebuild kept finding half its work already thrown away. Two
settings in `<work>/chroot_native/mnt/pmbootstrap/ccache/ccache.conf` are
worth having:

```
max_size = 25G
hash_dir = false
```

`hash_dir = false` matters because each `_commit` unpacks into a differently
named source directory; with the directory hashed into the key, a new commit
misses on every object even where the file content is identical. (It also
means paths baked into debug info follow the first compilation rather than
the current directory — fine here, worth knowing.)

☠️ **Edit the cache the build actually uses, which is not the one named after
the target.** An aarch64 kernel is cross-compiled *in the native chroot*, so
its ccache is `work/cache_ccache_x86_64` — `chroot_native/mnt/pmbootstrap/
ccache` is a bind mount of it, and `stat -c %i` on both proves it. Meanwhile
`work/cache_ccache_aarch64` has been carrying a careful `hash_dir = false` +
`base_dir = /home/pmos` since 2026-08-01 and taking no part in any kernel
build: 572 MB, untouched, in the directory whose name matches the target.
Confirm the mapping before tuning anything:

```sh
stat -c '%i %n' <work>/chroot_native/mnt/pmbootstrap/ccache \
                <work>/cache_ccache_x86_64 <work>/cache_ccache_aarch64
```

☠️ **These live inside the chroot, so a `--force` without `--lax` zaps them.**

☠️ **And do not measure the cache with an unprivileged `find`.** The tree is
owned by the build uid, so `find <ccache> -newermt '-5 minutes'` returns `0`
whether or not anything is being written — it cannot descend and says so
nowhere. The same query under `sudo` returned **1438**. Run 2026-08-23, that
zero was briefly written up here as proof that `abuild.conf`'s commented-out
`USE_CCACHE=1` had disabled ccache entirely. It had not: pmbootstrap puts
`/usr/lib/ccache/bin` at the front of `PATH` itself, so the wrapper is in
place regardless of what `abuild.conf` says, and `ccache -s` shows six hundred
thousand hits to prove it. **Two instruments, one of them blind, and the blind
one was the one that agreed with the hypothesis.**

⚠️ **Push `debug-int/<base>` before you bump `_commit`.** The package fetches
the tarball from GitHub, so a commit that only exists locally gives a 404 during
`./pmb checksum`. If you skip the checksum step, the build fails one step
later with the far less helpful

```
ERROR: linux-fp3-<sha>.tar.gz is missing in checksums
```

which points at the checksums rather than at the missing push.

## Deploying

The built package lands in the work directory the wrapper pins
(`work/packages/edge/aarch64/`, or `~/.local/var/pmbootstrap/packages/...` with
a default pmbootstrap). An apk is a gzipped tar, so unpack it and take the
pieces you need:

```sh
APK=work/packages/edge/aarch64/linux-fp3-7.1.3-r0.apk
mkdir -p /tmp/apk && tar xzf "$APK" -C /tmp/apk

tar tzf "$APK" | grep q6voice-dai        # check the module is actually in there
```

**Device tree only** — extlinux loads the fdt separately, so no kernel flash and
no module rebuild is needed. Roughly a two-minute round trip:

```sh
scp /tmp/apk/boot/dtbs/qcom/sdm632-fairphone-fp3.dtb fp3@$FP3_DEV_IP:/tmp/
ssh fp3@$FP3_DEV_IP 'sudo cp /tmp/sdm632-fairphone-fp3.dtb /boot/ && sudo sync && sudo reboot'
```

**A driver change** — copy the module in beside the others and refresh the
dependency list:

```sh
KREL=$(ssh fp3@$FP3_DEV_IP uname -r)
scp /tmp/apk/lib/modules/$KREL/kernel/sound/soc/qcom/qdsp6/q6voice-dai.ko \
    fp3@$FP3_DEV_IP:/tmp/
ssh fp3@$FP3_DEV_IP "sudo cp /tmp/q6voice-dai.ko \
    /lib/modules/$KREL/kernel/sound/soc/qcom/qdsp6/ && sudo depmod -a && sudo reboot"
```

**A full kernel change (a new base)** — deploy by hand. The pmOS
`mkinitfs`/`boot-deploy` tooling does **not** work here, for two independent
reasons, so do not rely on the apk's install trigger to put the kernel in
`/boot`:

* `mkinitfs` refuses to run with more than one kernel *flavor* present
  (`only one kernel release/flavor is supported`), and a device that has been
  through a rename or a parallel-package phase easily has two or three stamps
  under `/usr/share/kernel/`; and
* `boot-deploy` regenerates the extlinux config. ☠️☠️ **This line used to say it
  "fails against the FP3's hand-maintained lk2nd + `extlinux.conf`
  (`boot-deploy failed`, exit 1)", and that is measurably wrong** — corrected
  2026-08-26 against a 2026-08-23 measurement recorded in
  [`../TODO-DONE.md`](../TODO-DONE.md). On that install `apk add` ran
  `boot-deploy` and it **rewrote `extlinux.conf` from scratch**, dropping the
  fallback label, `panic=10` and the menu timeout. It does not politely fail; it
  succeeds at doing the wrong thing.

  **So `apk add` in step 2 destroys the boot fallback net, silently.** The
  config must be rebuilt by hand **after the install and BEFORE the reboot** —
  that ordering is the whole safety margin, and it is why the r74 no-boot had
  three working alternatives to fall back to. Verify with
  `fp3-selftest --only boot-fallback` before rebooting; keep the pre-install file
  (`cp extlinux.conf extlinux.conf.pre-<rev>`).

  ☠️ This mattered in the worst way a doc error can: the wrong version was in the
  file a person reads *while deploying*, telling them a destructive step was a
  harmless one.

Because every boot-critical driver is built **in** (`MMC_BLOCK`, `SDHCI_MSM`,
`EXT4`, `F2FS` = `y`), the one initramfs boots any of these kernels, so a
fallback is just a second set of boot files and a second extlinux entry. Full
procedure, from the host (`$D` = device, e.g. `fp3@172.16.42.1`):

```sh
APK=work/packages/edge/aarch64/linux-fp3-7.1.3-r0.apk
scp "$APK" $D:/tmp/linux-fp3.apk

ssh $D 'sudo sh -c '"'"'
  cd /boot

  # 1. keep the current kernel as the version-free fallback
  cp -n vmlinuz vmlinuz-fallback
  cp -n sdm632-fairphone-fp3.dtb sdm632-fairphone-fp3.dtb-fallback

  # 2. register the package (for apk info + the /usr/share/kernel/fp3 stamp that
  #    01-identity checks); its mkinitfs trigger will error - that is expected.
  #
  # ☠️ RUN THIS FIRST AND READ IT: apk-tools 3 re-resolves the whole `world` on a
  # single local install and will execute deletions left over from an earlier
  # half-finished upgrade. One such run removed the session shell and left a
  # phone that hung after the password prompt. Look for `Purging` and for
  # anything being removed that you did not ask about.
  #   apk add --simulate --allow-untrusted /tmp/linux-fp3.apk
  #
  # ☠️ And this step REWRITES /boot/extlinux/extlinux.conf via boot-deploy (see
  # above). Rebuild it by hand before rebooting.
  apk add --allow-untrusted /tmp/linux-fp3.apk

  # 3. leave exactly one flavor: drop the old package and any stale flavor stamp
  apk del linux-fp3-709 2>/dev/null
  rm -rf /usr/share/kernel/fp3-713 /usr/share/kernel/fp3-709   # whatever is stale

  # 4. copy the kernel, DTB and modules in by hand (bypassing boot-deploy)
  mkdir -p /tmp/x && tar xzf /tmp/linux-fp3.apk -C /tmp/x
  KV=$(cat /tmp/x/usr/share/kernel/fp3/kernel.release)
  cp /tmp/x/boot/vmlinuz /boot/vmlinuz
  cp /tmp/x/boot/dtbs/qcom/sdm632-fairphone-fp3.dtb /boot/sdm632-fairphone-fp3.dtb
  cp -a /tmp/x/lib/modules/$KV /lib/modules/ && depmod $KV
  sync
'"'"''
```

Then write `extlinux.conf` by hand — two version-free entries, the new kernel as
default and the preserved one as fallback (keep the `append` line's UUIDs
exactly as they were):

```
timeout 3
default postmarketOS
menu title FP3 boot (linux-fp3 / fallback)

label postmarketOS
	kernel /vmlinuz
	fdt /sdm632-fairphone-fp3.dtb
	initrd /initramfs
	append quiet splash ... pmos_boot_uuid=<...> pmos_root_uuid=<...> pmos_rootfsopts=defaults

label postmarketOS-fallback
	kernel /vmlinuz-fallback
	fdt /sdm632-fairphone-fp3.dtb-fallback
	initrd /initramfs
	append quiet splash ... pmos_boot_uuid=<...> pmos_root_uuid=<...> pmos_rootfsopts=defaults
```

Reboot and confirm the identity: `uname -v` shows `#<pkgrel+1>-fp3` and
`tests/fp3-selftest --only identity` is green (build stamp, installed package,
source commit). To test a base before trusting it, deploy it as the *fallback*
first, or flip `default` and reboot — a power-cycle then recovers on its own
only if the entry you booted is not the default, so revert `default` as soon as
SSH returns.

⚠️ Take the DTB from the **built package**, not from your source tree — a stale
locally-built DTB is an easy way to spend an hour debugging a device tree that
was never deployed. The symptom is silent: the driver loads, the node it needs
simply is not there.

⚠️ The slot_b rootfs is 2.4 GB and normally sits around 90% full. At 100% the
graphical session does not come up at all, which looks like a kernel
regression and is not one — check `df -h /` before blaming the build.

### ☠️ If the phone does not boot at all

Both remote channels — ssh over USB and ssh over WiFi — need userspace running,
so a change that hangs the kernel takes away every way in. The recovery below is
what was measured on 2026-08-16, after `fw_devlink=off` was added to the `append`
line and the device stopped enumerating on USB entirely.

**The one thing that works is a button press.** Hold **power** for ~15 s to force
the phone off, then hold **volume up** while powering on to reach the lk2nd boot
menu and pick `postmarketOS-fallback`. That is why the fallback label has to be
armed *before* the experiment, and why its `append` line must never be edited in
the same session as the default one — it is the only entry a hang cannot reach.
`fp3-selftest --only boot-fallback` is the check that says whether the net is up.

Everything else was tried and does not work on this bootloader. Recording it so
the next hang does not spend the same three hours:

* **`fastboot boot` is dead here, for every image.** It fails with
  `FAILED (remote: 'unknown reason')` — and it fails that way for `lk2nd.img`
  itself, the image that boots perfectly when flashed to the same slot. So the
  message says nothing about the image you built; do not read it as a hint and
  do not iterate on the image to chase it.
* **A boot image flashed to `boot_b` is rejected before boot is attempted.**
  `fastboot flash boot_b <img>` reports OKAY, the phone reboots straight back
  into fastboot, and `getvar slot-retry-count:b` still reads **6** — the counter
  is untouched, so the bootloader never tried. That points at image validation,
  not at the kernel.
* **The appended DTB is only found on an *uncompressed* kernel.** With the pmOS
  gzip `vmlinuz` plus an appended dtb the error is `dtb not found`; with the raw
  `Image` plus the same dtb it changes to `unknown reason`. The FP3 entry the
  bootloader matches is `qcom,msm-id = <0x15d 0>` with
  `qcom,board-id = <0x08 0x03>`, which is what lk2nd carries; the mainline
  `sdm632-fairphone-fp3.dtb` has `<0x08 0x10000>` instead. A dtb carrying both
  pairs gets past the lookup. ⚠️ None of this makes the image boot — see the
  first bullet — it only moves the error message.
* ☠️ **Never flash `boot_a`.** That slot holds the Ubuntu Touch kernel, which is
  the Halium oracle every register-level comparison is measured against.

**The fastboot USB link freezes if you interrupt a command** (a `timeout` that
fires mid-transfer is enough): every later command then hangs. The cure is a
`USBDEVFS_RESET` on the device node, after which it works immediately —

```sh
B=$(lsusb | sed -n 's/^Bus \([0-9]*\) Device \([0-9]*\): ID 18d1:d00d.*/\1\/\2/p')
sudo usbreset "/dev/bus/usb/$B"      # 8-line ioctl(USBDEVFS_RESET) wrapper
fastboot devices                     # answers again
```

So give fastboot commands a generous timeout and let them finish. Flashing
lk2nd back to `boot_b` restores the normal boot chain:

```sh
fastboot flash boot_b lk2nd.img
```

### ☠️ The kernel installed but the initramfs did not

`apk add linux-fp3` can succeed at unpacking and still leave `/boot`
inconsistent, because its postmarketos-mkinitfs trigger runs separately and can
fail on its own:

```
only one kernel release/flavor is supported, found:
  ["/usr/share/kernel/fp3/kernel.release"
   "/usr/share/kernel/postmarketos-qcom-msm8953/kernel.release"]
ERROR: lib/apk/exec/postmarketos-mkinitfs-2.11.1-r0.trigger: exited with error 1
```

Measured 2026-08-16 installing r57: `vmlinuz` was current, while `initramfs`
and the whole boot deployment were **five hours old**. Rebooting there would
have started the new kernel against an initramfs built from the previous
release's modules. Nothing said "your boot is now inconsistent" — the only
signs were the trigger's exit status, buried in apk's output, and two stale
mtimes in `/boot`. So after any kernel install, look:

```sh
ls -la --time-style=+%m-%d_%H:%M /boot/vmlinuz /boot/initramfs /boot/*.dtb
```

The second flavor is `linux-postmarketos-qcom-msm8953`, which
`device-fairphone-fp3` **depends on**, so `apk del` refuses to remove it and it
returns whenever the device package is reinstalled. The repair is to hide it
for the length of one mkinitfs run:

```sh
mkdir -p /root/kernel-stash
mv /usr/share/kernel/postmarketos-qcom-msm8953 /root/kernel-stash/
mkinitfs                       # prints "Installing: /boot/initramfs" etc.
mv /root/kernel-stash/postmarketos-qcom-msm8953 /usr/share/kernel/
```

☠️ Renaming it in place to a dotted name does **not** work — mkinitfs's glob
finds the dotted directory too and repeats the same error with the new name in
it. It has to leave `/usr/share/kernel` entirely.

☠️ And boot-deploy rewrites `extlinux.conf` from scratch: it drops the
hand-added `postmarketOS-fallback` label and resets `timeout` to 1. Copy the
file aside before running mkinitfs and re-append the label afterwards, or the
next bad kernel has nothing to fall back to.

## Things that look like build or kernel bugs and are not

Every one of these cost real time at least once.

**Never pad an abbreviated commit hash.** `_commit` takes the full 40
characters; extending the 12 from `git log --oneline` by guessing gives a
GitHub 404 at `./pmb checksum` that reads like the push failed. Take it from
`git rev-parse <branch>` or, better, from `git ls-remote fork <branch>`, which
also proves the push landed.

**"Package is up to date" can mean a stale package outranks your bump.** `--lax`
compares against the highest version in the local work repo, and a leftover
`--src` build carries a `_pYYYYMMDDHHMMSS` suffix that sorts **above** a plain
`pkgrel` bump — with `linux-fp3-7.1.3_p20260729013201-r12` sitting in the repo,
`7.1.3-r21` was skipped as up to date, twice, with no hint why. Deleting the
`.apk` is only half the fix: `APKINDEX.tar.gz` still advertises it. Move the
stale apk aside, then

```sh
./pmb index
```

and build again. What matters is not the `pkgrel` number but that the highest
version *in the index* is below yours — which is what to check when a build
refuses to run:

```sh
sudo tar xzOf work/packages/edge/aarch64/APKINDEX.tar.gz APKINDEX |
    awk '/^P:linux-fp3$/{p=1} p&&/^V:/{print; p=0}' | sort -V | tail -3
```

**Do not run `./pmb checksum` (or a second build) while a build is running.**
They share `/home/pmos/build` in the chroot, so the running build loses its
source tree mid-compile and dies with

```
<command-line>: fatal error: ./include/linux/compiler-version.h: No such file or directory
```

which points at the kernel source rather than at the concurrent command.

**A `--src` build silently drops tracked files the tree's own `.gitignore`
names.** `pmbootstrap build --src <tree>` rsyncs the tree with
`--exclude-from=<tree>/.gitignore`, and rsync does not understand git's `!`
negation lines: the kernel ignores `*.bc` and then un-ignores
`kernel/time/timeconst.bc`, so git keeps the file and rsync leaves it out. The
build dies far from the cause with

```
make[2]: *** No rule to make target 'kernel/time/timeconst.bc',
        needed by 'include/generated/timeconst.h'.  Stop.
```

The copy persists between runs, so the repair is to put the file into it and
build again, not to rebuild the copy:

```sh
sudo cp <tree>/kernel/time/timeconst.bc \
    work/chroot_native/tmp/pmbootstrap-local-source-copy/kernel/time/
```

The whole class is `git ls-files -i -c --exclude-standard` in the source tree —
anything it lists is tracked *and* ignored, and therefore missing from the copy.

**Also clean the tree before a `--src` build.** Object files from a host `make`
are copied in too, and the chroot's compiler then links against objects built by
a different one. `git clean -xdf` (keep `.config` aside) before handing a tree
to `--src`.

**Pass `--arch aarch64` or you get a package for the host.** Without it the
build succeeds, `BUILD_RC=0`, and the apk lands in
`work/packages/edge/x86_64/` — where the deploy step will not look for it. Half
an hour, and the only symptom is that the file "is not there".

**`--lax` reuses a buildroot that may not have the toolchain a package needs.**
For `linux-fp3` this is free speed; for a Rust package it can fail at configure
time with

```
meson.build:1:0: ERROR: Unknown compiler(s): [['rustc']]
```

because the reused `buildroot_aarch64` was never given `rustc`. Dropping `--lax`
zaps and repopulates it, which fixes it at the cost of the ccache. Rule of
thumb: `--lax` for repeat builds of a package that already built in this
buildroot, plain `--force` the first time.

**`apk add` finishing with `1 error` is usually the network, not the package.**
With no route to the repositories the phone reports

```
WARNING: updating and opening https://...: DNS: transient error (try again later)
1 error; 2035.3 MiB in 1208 packages
```

and still installs the local apk correctly — `apk list -I | grep linux-fp3`
confirms it. It matters because a deploy script with `set -e` aborts here, which
silently skips whatever came after (in one case the whole extlinux fix-up, so
the fallback entry, `panic=10` and the menu timeout were all missing on the next
boot).

**`apk add` regenerates `extlinux.conf` and overwrites `/boot/*.dtb`,** so the
fallback label, `panic=10` and the menu timeout have to be written *after* the
install, never before. Check the file, do not assume:

```sh
ssh $D cat /boot/extlinux/extlinux.conf
fp3-selftest --only boot-fallback     # the same question, as a check
```

☠️ **Reading that file is not the same as checking it**, and the difference cost
a physical recovery on 2026-08-16: the net had been gone for an unknown number
of installs, the file was opened — to *edit* it — and the missing `timeout`,
`default` and `panic=10` went unread, because nothing was looking for them. A
kernel command line experiment then hung the boot with no way back in. That is
why the question is now a check (`tests/checks/02-boot-fallback-test.sh`): it
also asks whether the fallback's kernel and dtb actually exist, and whether the
watchdog — the only thing that recovers a *hang* rather than a panic — is
running.

**Watch the device's free space.** Each kernel apk is ~30 MB and they accumulate
in `/home/fp3` and `/var/cache/apk`; on a 2.4 GB rootfs a day of iteration
reaches 99% full, and the phone raises a low-disk notification long before
anything fails visibly. Clean up between rounds:

```sh
ssh $D 'sudo sh -c "rm -f /home/fp3/*.apk; rm -rf /var/cache/apk/*; \
    journalctl --vacuum-size=20M"'
```

⚠️ `journalctl --vacuum-size` is not free: it drops the kernel log of earlier
boots, and a later comparison across boots then shows a *perfect* correlation
that is really just missing data. If you are about to compare boots, check that
each one still has a plausible number of lines
(`journalctl -b -N -k | wc -l`).

## ☠️ Rust packages were building under emulation, and one word was why

Measured 2026-08-03 building `snapshot` for aarch64 on this machine:

| | compile phase |
|---|---|
| before | **~35 min** |
| after | **6 min 27 s** |

Same package, same source, same `pkgrel` — the only difference was one line in
`cross/crossdirect/cargo.sh`. pmbootstrap says *"Building package (cross
compiling: crossdirect)"* either way, so the log line is not evidence that any
cross compiling happened; what gives it away is buried further down:

```
WARNING: crossdirect: 'cargo auditable build --manifest-path … --release'
         command not supported, running in QEMU (slow!)
```

crossdirect's `cargo` wrapper recognises `build`, `test` and `run` — as the
**first** word. pmaports patches the GNOME Rust applications to build with
[`cargo auditable`](https://github.com/rust-secure-code/cargo-auditable) so the
binary carries its dependency list, which makes the first word `auditable`. The
wrapper does not know it, removes itself from `PATH` and hands the whole build
to an emulated `cargo`, so every crate in the tree is compiled by an aarch64
`rustc` under `qemu-aarch64-static`. `sccache` does not help either: it is
wired up correctly by pmbootstrap, but the wrapper that would reach it is the
one being bypassed, which is why `work/cache_sccache` stays empty.

The fix is [`crossdirect-cargo-auditable.patch`](crossdirect-cargo-auditable.patch)
— look past a wrapper subcommand to the one that decides, and carry the wrapper
along. Apply it to the pmaports checkout and rebuild `crossdirect` (14 seconds,
native):

```sh
git -C pmaports apply fp3-pmaports/docs/deploy/crossdirect-cargo-auditable.patch
cd pmos && ./pmb build crossdirect
```

☠️ **It cannot be sent upstream.** postmarketOS does not accept AI-assisted
contributions, so this lives here and has to be reapplied after a
`pmbootstrap pull`. Check whether it is still needed by grepping the build log
for `command not supported` — that warning is the whole diagnosis.

☠️ **Two plausible explanations were wrong before this one**, and both would
have been reported as fact if the log had not been read. It is not a missing
`sccache` (pmbootstrap sets `RUSTC_WRAPPER` and mounts `work/cache_sccache`),
and it is not meson resolving `cargo` to an absolute path and missing the
wrapper — the log says `Program cargo found: YES
(/native/usr/lib/crossdirect/aarch64/cargo)`, so it found it. The wrapper was
reached and declined the job.

---

## ☠️ The rear-camera dtb switch and the `_commit` bump are ONE change

Measured 2026-09-04, preparing queue #151. Since `7f18166c7b7c` the board dts is
split into a base dts plus two per-module overlays, composed in
`arch/arm64/boot/dts/qcom/Makefile`:

```
sdm632-fairphone-fp3-rear-camera-ak7374-dtbs   := sdm632-fairphone-fp3.dtb sdm632-fairphone-fp3-rear-camera-ak7374.dtbo
sdm632-fairphone-fp3-rear-camera-lc898217-dtbs := sdm632-fairphone-fp3.dtb sdm632-fairphone-fp3-rear-camera-lc898217.dtbo
```

so the **plain `sdm632-fairphone-fp3.dtb` has no rear camera** from that commit
on, and the device has to be pointed at a composite:

```
device/testing/device-fairphone-fp3/deviceinfo
  deviceinfo_dtb="qcom/sdm632-fairphone-fp3"                      # today
  deviceinfo_dtb="qcom/sdm632-fairphone-fp3-rear-camera-ak7374"   # after the bump
```

Two things that decide how this is done, both measured rather than assumed:

- **The `linux-fp3` APKBUILD needs no change.** All three names are in `dtb-y`
  and the package installs with `make dtbs_install
  INSTALL_DTBS_PATH="$pkgdir/boot/dtbs"`, so the composites ship automatically.
  Half of #151's premise ("linux-fp3 dtb install") is already satisfied.
- ☠️ **The `deviceinfo_dtb` edit must not land ahead of the `_commit` bump.**
  The pinned `_commit` at the time of writing (`b8023520cddb`, `pkgrel=80`)
  **predates** the split — the tip `7f18166c7b7c` is five commits ahead of it —
  so the pinned kernel does not build any composite. Renaming `deviceinfo_dtb`
  first therefore points the device at a dtb that does not exist in the package,
  and breaks the *next* build: one step earlier than the silent camera loss the
  task exists to prevent, and louder, but still a broken boot. Make both edits
  in one change, or neither.

Order for the window that has the phone, and it is not negotiable — the net goes
in before the wire is cut:

1. `fp3-selftest --only boot-fallback` on the **current** kernel, green.
2. `_commit` → the `debug-int/<base>` tip and `pkgrel`+1, in **both** APKBUILD
   copies (`pmaports/device/testing/linux-fp3` is the one that builds; the
   `fp3-pmaports/linux-fp3` mirror builds nothing — as of 2026-09-04 the two are
   byte-identical, so the trap is not currently armed), `deviceinfo_dtb` → the
   ak7374 composite, `pmbootstrap checksum`, build.
3. Flash, then `fp3-selftest` camera + focus checks.

The tarball gate before any bump — and it needs its negative control, or it
passes unconditionally:

```sh
SHA=$(git -C <fork checkout> rev-parse debug-int/<base>)
curl -sL -o /dev/null -w '%{http_code}\n' "https://github.com/llg179org/linux/archive/$SHA.tar.gz"        # 200
curl -sL -o /dev/null -w '%{http_code}\n' "https://github.com/llg179org/linux/archive/deadbeef…beef.tar.gz" # 404
```

Run 2026-09-04 on `7f18166c7b7cf04fb3e672d47393b2f51ee7b1a0`: **200**, control
**404**, and `git ls-remote fork refs/heads/debug-int/7.1.3` returns that same
sha — so the bump is unblocked whenever the device is back.

☠️ And a live demonstration of why the sha comes from `rev-parse`: the first run
of that check here used a 12-character hash extended to 40 by hand. It returned
**404**, which said nothing about anything — a padded hash is a hash of nothing.

## ☠️ `fp3-commit` describes the INSTALLED package; `uname -v` describes the BOOTED image

Measured 2026-09-05, on a phone that had been treated all week as "running r80".
It was not. Three instruments were asked the same question and gave three
answers, and each was telling the truth about a different thing:

| instrument | answer | what it actually describes |
|---|---|---|
| `uname -v` | `#80-fp3` | the **booted boot.img** — `KBUILD_BUILD_VERSION` is `pkgrel + 1`, so `#80` is pkgrel **79** |
| `/usr/share/kernel/fp3/fp3-commit` | `5aafd59e553a` | the **installed apk in the rootfs**, i.e. r78's source |
| `apk` (via `fp3-selftest --only identity`) | `linux-fp3-7.1.3-r78` | the same installed apk |

So the rootfs held r78 while the boot partition held a kernel built from r79.
The two are flashed by separate steps, so nothing keeps them together — and on
**this device's slot_b, between 2026-08-29 and 2026-09-05, r79 and r80 were
never flashed at all**. That is one install on one phone, read off its own
`extlinux.conf` (`default` pointed at `/vmlinuz-r79`) and its own apk database;
it says nothing about any other install, and it is not a claim that the deploy
procedure generally loses releases. Every conclusion drawn in that window
which assumed an r79 or r80 feature was present was drawn on a kernel that did
not have it; the SMSM processor-awake pair (`3b6498ac`, `b8023520`) is the
concrete example, which is why the #50 A/B was correctly still blocked.

Two things follow, and only the second one is new:

- **Read `fp3-commit`, not `uname -v`, to answer "what source is this?"** — that
  is what the marker was added for. But it answers for the *rootfs*, so it is
  silent about a boot partition flashed separately.
- **Run `fp3-selftest --only identity` after every flash, before believing
  anything else.** It compares all three against the pinned `_commit` in one go
  and prints the disagreement:

  ```
  FAIL: build stamp:   expected '#82-fp3', running '#80-fp3 …'
  FAIL: package:       expected 'linux-fp3-7.1.3-r81', installed 'linux-fp3-7.1.3-r78'
  FAIL: source commit: expected 3f843d05…, built from 5aafd59e…
  ```

  The check already existed and already worked. It had simply not been run, and
  a check that is not run is worth exactly as much as one that does not exist.

☠️ **The `#N` off-by-one is a trap in its own right.** In *this* APKBUILD —
`linux-fp3`, which passes `KBUILD_BUILD_VERSION="$((pkgrel + 1))-$_flavor"`, and
has done so since at least r78 (checked against the mirror history) — the
`uname -v` number is the package release **plus one**, so reading `#80` as "r80"
is wrong by construction. Other kernel packages set that variable differently or
not at all; the rule to carry away is "check what the APKBUILD passes", not the
constant 1.

## ☠️ Piping `pmb build` into `tail` reports the pipe's exit status, not the build's

Measured 2026-09-05, in the same session. `./pmb build --arch aarch64 linux-fp3
device-fairphone-fp3 2>&1 | tail -60` finished and the harness recorded **exit
code 0**. It had not succeeded: `linux-fp3` built, and `device-fairphone-fp3`
failed with `ERROR: Use 'abuild checksum' to generate/update the checksum(s)`
— the `deviceinfo` edit needed its own `pmbootstrap checksum`. The zero came
from `tail`.

It was caught only because the next step went looking for the `.apk` and it was
not there. Had the deploy not needed that package, the run would have been
recorded as a clean two-package build.

```sh
./pmb build --arch aarch64 <pkgs> > build.log 2>&1; echo "exit=$?"   # right
./pmb build --arch aarch64 <pkgs> | tail -60                         # reports tail
```

☠️ **And `pmbootstrap checksum` is per package.** Bumping `_commit` in
`linux-fp3` and editing `deviceinfo` in `device-fairphone-fp3` is two source
changes in two packages, so it is two `checksum` calls. Running one and
assuming it covered the change is what produced the failure above.
