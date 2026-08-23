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

Last updated: **2026-08-24 00:30**.

## The device

| what | value | how to check |
|---|---|---|
| kernel package | `linux-fp3-7.1.3-r73` | `apk info -vv \| grep ^linux-fp3` |
| build stamp | `#74-fp3` | `uname -v` |
| pinned commit | `debug-int/7.1.3` `818d35f1` | `grep _commit linux-fp3/APKBUILD` |
| boot config | 3 labels, md5 `863cdf20…`, `panic=10`, `timeout 3` | `md5sum /boot/extlinux/extlinux.conf` |
| last full battery | **29 ok / 2 failed / 3 skipped** (2026-08-23 17:11, r73). ☠️ Both failures are `98-camera-af-rail` and `99-suspend`, and neither is a check defect: **the device hung in `cpuidle_enter_state` and the watchdog reset it mid-run** — see queue item 5 | `tests/fp3-selftest` |

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

☠️ **Before starting anything power-related, read
[`power/bringup/RUNBOOK.md`](power/bringup/RUNBOOK.md) top section.** A finished
investigation that lives only in a `leads/*` working note is invisible from this
page, and on 2026-08-23 that produced a re-run of a closed bisect and a
conclusion that had to be retracted. If you close something, move the result to
the runbook in the same commit.

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
3. **The `vlow` gate is still unidentified, and the ADSP is not it.**
   ☠️☠️ Everything this queue said today about LPASS being pinned is
   **retracted** — a flat `Shutdown count` reads the same whether the ADSP is
   held awake or asleep and staying down, and it was the latter. `enter > exit`
   with `cores 0x0` is asleep; re-measured on a clean r73 boot, LPASS reads
   `ASLEEP cores=0x0` from ~34 s onward. That is the goal state the NGD
   `disable_stream` fix produced in r63, still working. Full retraction and the
   three mistakes behind it in `leads/rpm-sleep-set.md`.
   What is actually open is what it was before: `vlow`/`vmin` `Count` have never
   left 0, and that survives the AP-side sleep-set family, `xo_sleep_off`,
   `both_sets`, `sleep_init`, and a powered-off ADSP. The one control still
   unrun is the oracle with USB detached — **which is a human item**, so the
   machine-side move is to stop attacking `vlow` blind and take the mA
   measurements below instead.
   ☠️ Read `docs/power/bringup/RUNBOOK.md` before opening any LPASS question:
   it was closed on 2026-08-21 and the closure was invisible from here, which is
   what cost a day's re-run.
4. **Price the WiFi lever in mA** (slope leg, `wlan0` down vs up). ☠️ PRONTO
   parks holding the XO when `wlan0` is down, so the naive reading flatters it.
5. ☠️☠️ **The phone HANGS and the watchdog resets it — `99-suspend` was never
   the problem.** This item used to read "fix the check, not the kernel". That is
   **retracted**: measured 2026-08-23 on r73, the battery's detached tail
   (`98-camera-af-rail`, `99-suspend`) does not fail, it **dies with the
   device**. The boot before the current one ends with

   ```
   rcu: INFO: rcu_preempt detected stalls on CPUs/tasks:
   ...  pc : cpuidle_enter_state+0xb8/0x740
        cpuidle_enter / do_idle / cpu_startup_entry / secondary_start_kernel
   watchdog0: pretimeout event
   ```

   — the RCU grace-period kthread's CPU stuck inside `cpuidle_enter_state`, and
   then the debug layer's watchdog resetting the phone. `journalctl
   --list-boots` shows the reboot landing mid-run. **The safety net worked;** the
   check's "no verdict was written" and the `run-detached.sh: no such file` that
   follows are both just `/tmp` being tmpfs on a machine that rebooted.
   Capture: `docs/power/bringup/captures/2026-08-23_rcu-stall-cpuidle-watchdog.txt`.
   ☠️ **Also retracted:** this page previously explained the same 606 s hang away
   as "a boot that had had an ADSP restart, did not reproduce on a clean boot".
   It has now reproduced on a boot with no manual ADSP restart.
   ☠️ **One instance is confirmed, not two.** The earlier run rebooted at the
   same point but its boot is no longer retained (`--list-boots` holds only −1
   and 0), so it is a matching timing signature and nothing more.
   ☠️ **Tried, and it does not reproduce in isolation.** `--only
   camera-af-rail,suspend`, three consecutive runs: **2 ok / 0 failed each time,
   no reset** (uptime monotonic 1299 → 1331 → 1362 → 1398 s). So the hang is
   **load-dependent** — it needs the rest of the battery ahead of it, not just
   these two checks. Next: bisect by running the battery with growing prefixes
   (`--skip` the tail, then progressively fewer), each time checking `uptime`
   for a reset, until the smallest prefix that still hangs is known. Budget it
   as a long unattended run; each iteration costs a reboot when it hits.
   ☠️ **Harness trap, mine:** never run two batteries overlapping — killing the
   first fires its cleanup trap, which deletes `/tmp/fp3-selftest` out from under
   the second and produces exactly this "vanished helper" signature for
   an unrelated reason.
6. ☠️ **Housekeeping item withdrawn — its premise is false.**
   `linux-postmarketos-qcom-msm8953` is **not installed**: `apk info` lists only
   `linux-fp3`. What does exist is a second module tree,
   `/lib/modules/7.0.9-postmarketos-qcom-msm8953`, and that one belongs to the
   **`postmarketOS-fallback` boot label** — the brick-safety net. Do not delete
   it. If `only one kernel release/flavor is supported` still appears on an
   `apk` run, it comes from the two module trees and needs a fix that keeps the
   fallback intact, not a package removal.
   ☠️ `apk del` on a package that is not installed reports a bare `1 error` and
   nothing else; `-v` is what makes it say why.
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
- ☠️ **A blank row is not a zero.** A debugfs sampler that runs as the user
  prints *empty* lines for `/sys/kernel/debug/qcom_rpm_master_stats` — root-only
  — and they read as "nothing to see" next to lines that do print. Gate every
  sampler on being able to read each of its sources, and show each gate aborting
  before believing any row.
- ☠️ **`./pmb build` outlives a 10-minute tool timeout badly.** Run it detached
  and poll, rather than letting the harness kill the shell mid-compile.
