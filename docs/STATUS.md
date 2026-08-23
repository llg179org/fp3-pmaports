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

Last updated: **2026-08-23 16:00**.

## The device

| what | value | how to check |
|---|---|---|
| kernel package | `linux-fp3-7.1.3-r73` | `apk info -vv \| grep ^linux-fp3` |
| build stamp | `#74-fp3` | `uname -v` |
| pinned commit | `debug-int/7.1.3` `818d35f1` | `grep _commit linux-fp3/APKBUILD` |
| boot config | 3 labels, md5 `863cdf20…`, `panic=10`, `timeout 3` | `md5sum /boot/extlinux/extlinux.conf` |
| last full battery | **30 ok / 1 failed / 3 skipped** (2026-08-23 15:47, r73). ☠️ The one failure is `99-suspend`, and it is the harness: it passes standalone on that same boot, twice - before and after the battery - and fails only when it runs directly after `98-camera-af-rail`, by one second (`woke at 98179, alarm was 98180`) | `tests/fp3-selftest` |

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

The state that is *not* in git, in one place. Everything else is recoverable
from the repos.

1. `wip/7.1.3/audio` `42b7e745`, `integration/7.1.3` `204f1cc3`,
   `debug-int/7.1.3` `818d35f1` — **all pushed to `fork`**, all carrying the
   same three commits. Nothing is stranded locally, and r73 is built, deployed
   and proven, so there is no half-finished step to pick up.
2. The reproduction is `docs/audio/ssr-repro.sh` in this repo: one ADSP restart
   addressed **by name**, health measured before and at +20 s / +90 s, then a
   verdict table of named symptoms. Copy it to the device and run it under
   `systemd-run --collect` so the ssh session cannot contaminate it.
   ☠️ **An earlier version of it filtered `dmesg` by timestamp with awk and
   printed nothing at all** while `dmesg` held 225 codec lines including a
   `WARNING`. That silence read as a pass. The script now counts named patterns
   over the whole buffer and prints sanity rows that must be **non-zero**; if
   those are zero the instrument is blind, not the kernel clean.

## The work queue, in order

Everything here is machine-doable unless the row says otherwise. Work down the
list; do not stop at the end of an item to report.

1. **The SSR write storm is a `qcom-ngd-ctrl` question, not a codec one.**
   Measured on r73: 78 lines of `Failed to write config eN` / `Failed to sync
   masks in 89`, spanning 36.46 s → 38.10 s, every one of them `-22` or `-12`,
   and they start *before* the codec is told anything — immediately after
   `HW wakeup attempt during SSR`. The controller accepts transfers while its
   own state is `DOWN` instead of failing them fast. Bounded and harmless now
   that the teardown ends it, so this is noise-removal, not a defect.
   ☠️ A fix in `drivers/slimbus/` has **no category** in this port's branch
   model — decide where it lands before committing it.
2. **Provoke the non-recovering SSR path** — needs a kernel-side hook now, so
   this is the one item here that is not a quick measurement. ☠️ Two dead ends
   are already recorded in [`TODO.md`](TODO.md), do not re-walk them: the
   `avs/audio` PDR route does not exist on msm8953 (`PDM: no support for the
   platform`), and holding audio traffic across a whole restart cycle moved the
   bring-up count by exactly one, not two. The reachable second source is
   `qcom_slim_ngd_notify_slaves()` on a runtime-PM resume taken while the
   controller state is `DOWN`, and that window closes as soon as the controller
   unregisters. Widening it deliberately is the next move.
3. **Read the RPM `Client Votes` mask immediately after a suspend window**, from
   the `postmarketOS-xo` label — the one boot where the APSS actually goes down
   during the window. Last open leg of `TODO.md` item ②.
4. **Price the WiFi lever in mA** (slope leg, `wlan0` down vs up). ☠️ PRONTO
   parks holding the XO when `wlan0` is down, so the naive reading flatters it.
5. **`99-suspend` fails inside the battery and passes outside it.** Measured
   2026-08-23 three times on r73: standalone before the battery **ok (15 s)**,
   inside the battery **FAIL (12 s, one second short)**, standalone after the
   battery **ok (15 s)**. `65-bluetooth` unblocks the controller a few checks
   earlier and `98-camera-af-rail` restarts wireplumber immediately before it.
   Either the check needs to settle the wake sources it inherits, or its alarm
   margin is one second too tight. Fix the check, not the kernel.
6. **Housekeeping:** `linux-postmarketos-qcom-msm8953-7.1.3-r0` is installed,
   owns no `/boot/vmlinuz`, and makes every `apk` run end with `only one kernel
   release/flavor is supported`.
7. **Measure whether `base_dir` fixes the kernel ccache hit rate.** The source
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
