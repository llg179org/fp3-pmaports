# Status — where the port stands right now

> ⚠️ **AI-generated.** This page was written by Claude working under the
> direction of Lajosházi, László Gergely, who reviewed every change and made or
> reviewed every measurement it rests on.

**This file is the live one.** It is rewritten as work happens, not at the end of
a session, and it is the first thing to read when picking the work back up. The
reasoning behind each open item is in [`TODO.md`](TODO.md) (by item) and
[`FP3-TODO.md`](FP3-TODO.md) (by branch); closed items move verbatim to
[`TODO-DONE.md`](TODO-DONE.md). When this page and `TODO.md` disagree, **this one
is newer and `TODO.md` is more complete** — fix whichever is wrong rather than
picking a winner.

☠️ Every line below is the kind that goes stale first. Each row says how to read
it off the device instead of trusting it.

Last updated: **2026-08-23 15:05**.

## The device

| what | value | how to check |
|---|---|---|
| kernel package | `linux-fp3-7.1.3-r72` **on the device**; the APKBUILD is already bumped to **r73** | `apk info -vv \| grep ^linux-fp3` |
| build stamp | `#73-fp3` | `uname -v` |
| pinned commit | `debug-int/7.1.3` `818d35f1` (r73, **not yet built/deployed**) | `grep _commit linux-fp3/APKBUILD` |
| boot config | 3 labels, md5 `863cdf20…`, `panic=10`, `timeout 3` | `md5sum /boot/extlinux/extlinux.conf` |
| last full battery | **31 ok / 0 failed / 3 skipped** (2026-08-23 13:43, on r71) | `tests/fp3-selftest` |

The three extlinux labels are `postmarketOS` (default), `postmarketOS-fallback`
(an older kernel, kept as the safety net) and `postmarketOS-xo` (adds
`clk_smd_rpm.xo_sleep_off=1` for the deep-sleep experiments).

## Branch tips

| branch | tip | note |
|---|---|---|
| `wip/7.1.3/audio` | `42b7e745` | + the three SSR fixes of 2026-08-23 |
| `integration/7.1.3` | `204f1cc3` | cherry-pick sum, debug-free |
| `debug-int/7.1.3` | `818d35f1` | **what the package builds** (r73) |
| `wip/7.1.3/power` | `d0e738c1` | smd wakeup teardown fix |

`fp3-pmaports` `origin/main` carries the docs and the APKBUILD; the kernel goes
to remote `fork` only, over port 443, and never to `origin`.

## ☠️ Resume here after a compact or a long gap

The state that is *not* in git, in one place. Everything else below is
recoverable from the repos.

1. `wip/7.1.3/audio` `42b7e745`, `integration/7.1.3` `204f1cc3`,
   `debug-int/7.1.3` `818d35f1` — **all three pushed to `fork`**, all three
   carry the same three commits. Nothing is stranded locally.
2. `linux-fp3/APKBUILD` is bumped to **r73** pinned at `818d35f1`, checksummed,
   and **the build was interrupted mid-run** (a 10-minute tool timeout, not a
   build error). Re-run it, then deploy:
   ```sh
   cd /mnt/1TB/pmos
   cp fp3-pmaports/linux-fp3/{APKBUILD,config-fp3.aarch64} \
      pmaports/device/testing/linux-fp3/
   ./pmb build --arch aarch64 --force --lax linux-fp3     # ~8 min, run detached
   ```
   Deploy exactly as [`deploy/README.md`](deploy/README.md) says — and the
   `extlinux.conf` re-arm afterwards is **not optional**: it was measured on
   2026-08-23 stripping the fallback label, the xo label and `panic=10`.
   Good md5 is `863cdf2001934d85c17d2ffad7c42fcb`.
3. The phone is on **r72 / `#73-fp3`**, which has the first two fixes and the
   irq leak. It is healthy and audio works; r73 is the one that closes the leak.
4. The reproduction script is `/tmp/ssr-repro.sh` on the device (source in the
   job tmp dir). ☠️ **Its `dmesg since MARK` section is broken** — its awk
   filter printed nothing on r72 while `dmesg` itself had 225 codec lines
   including a WARNING. Read `dmesg` directly; do not trust that section.

## The work queue, in order

Everything here is machine-doable unless the row says otherwise. Work down the
list; do not stop at the end of an item to report.

1. **Finish r73: build, deploy, and re-run the ADSP-restart reproduction.**
   The acceptance test is the one in "Resume here": one `echo stop`/`echo start`
   to the ADSP remoteproc *by name*, then `dmesg` must contain **no**
   `remove_proc_entry` warning, no `CODEC version detection fail!`, no
   `Failed to bringup WCD9335`, no `debugfs: '217:1a0:1:0' already exists`, and
   playback must still work. Then a full `tests/fp3-selftest` battery.
2. **The SSR write storm is still there and is now a `qcom-ngd-ctrl` question,
   not a codec one.** On r72 it ran 37.50 s → 38.98 s (69 lines of
   `Failed to write config eN` / `Failed to sync masks in 89`, all `-22`),
   *starting before* the codec is told anything, right after
   `HW wakeup attempt during SSR`. The controller accepts transfers while its
   state is `DOWN` instead of failing them fast. Bounded and harmless now that
   the teardown ends it; worth a look, and it is **`audio` category only if the
   fix lands in the codec** — a fix in `drivers/slimbus/` has no category yet.
3. **Read the RPM `Client Votes` mask immediately after a suspend window**, from
   the `postmarketOS-xo` label — the one boot where the APSS actually goes down
   during the window. Last open leg of `TODO.md` item ②.
4. **Price the WiFi lever in mA** (slope leg, `wlan0` down vs up). ☠️ PRONTO
   parks holding the XO when `wlan0` is down, so the naive reading flatters it.
5. **Housekeeping:** `linux-postmarketos-qcom-msm8953-7.1.3-r0` is installed,
   owns no `/boot/vmlinuz`, and makes every `apk` run end with `only one kernel
   release/flavor is supported`.
6. **Measure whether `base_dir` fixes the kernel ccache hit rate.** The source
   path carries the commit hash, so every bump is a new absolute path and
   direct-mode hits are expected to miss; `base_dir` is empty. The test is one
   file compiled from two directory names around a `ccache -z`, then the next
   real bump's wall-clock.

**Waiting on a human, skip over them:**

- the call-wake ↔ deep-sleep trade has to be *decided* (inhibitor while ringing,
  or conditional arming), not measured further
- the wake-arm unit's default, the WiFi suspend policy, and the fate of the three
  experiment knobs (`clk_smd_rpm.xo_sleep_off`, `qcom_smd_regulator.both_sets`,
  `icc_smd_rpm.sleep_init` — all default OFF)
- the USB-detached combined session (rail census, slot switch to the UT oracle)
- sending `smd-wake-v1` to the LKML

## Guardrails that have each cost a day

- **The category rule.** A kernel change lands on `wip/<base>/<category>` **and**
  `integration/<base>` **and** `debug-int/<base>`, then all of them are pushed to
  `fork`, and only then does `_commit` move.
- **Tarball check before the build:** `curl -sL -o /dev/null -w '%{http_code}'`
  on the pinned commit must be **200**, and the same command on a bogus hash must
  be **404** — a verifier not yet shown failing has proved nothing.
- **`apk add` first with `--simulate`,** read the output for `Purging`.
- **`apk add` rewrites `extlinux.conf`.** Re-arm it afterwards and check the md5;
  the backups live next to it in `/boot/extlinux/`.
- **One `pmbootstrap` command at a time.**
- **A reboot is witnessed by `uptime`, never by a return code.** Use
  `systemctl reboot`; a backgrounded `reboot` over ssh dies with the session.
- ☠️ **remoteproc indices move between boots.** Address by name or platform
  address (`grep -l 4080000 /sys/class/remoteproc/*/name`), never by index.
- ☠️ **Never run two destructive measurements at once**, and never trust a
  waiter built on `pgrep -f` — it matches its own command line and never exits.
- ☠️ **GitHub answers `429` to the tarball check when it is rate-limited**, and
  it answers it for the bogus hash too. Measured 2026-08-23. A `429/429` pair is
  **not** a pass and not a fail — it is the check refusing to answer. Retry
  until the bogus hash reads `404` again, and only then read the real one.
- ☠️ **`./pmb build` outlives a 10-minute tool timeout badly.** Run it detached
  and poll, rather than letting the harness kill the shell mid-compile.
