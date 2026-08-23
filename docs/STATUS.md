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

Last updated: **2026-08-24 02:45**.

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
   ☠️ **The "no category" worry is retracted — it was wrong, and measured so.**
   `drivers/slimbus/qcom-ngd-ctrl.c` is *already* carried by two categories at
   once, on purpose: `wip/7.1.3/audio` has the QDSP6SS framer-bit commit and its
   revert (made to get the codec working), and `wip/7.1.3/power` has `implement
   disable_stream so the ADSP releases the channel` (same file, chased because
   LPASS would not sleep). The category follows **why** the change is made, not
   which directory it touches. This storm is SSR bring-up on the codec path, so
   it lands on **`wip/7.1.3/audio`** + `integration/7.1.3` + `debug-int/7.1.3`.
   ☠️ Found while checking that: **the branch table in `~/.claude/CLAUDE.md`
   lists five upstream-bound categories and there are seven.** `power` (8
   commits) and `i2c` (the QUP runtime-PM pinctrl fix) both carry real work and
   appear in neither that table nor `FP3-TODO.md`'s per-branch sections. Written
   up in [`FP3-TODO.md`](FP3-TODO.md); the table is incomplete, not
   authoritative — re-derive with `git for-each-ref`.
   The fix itself is still unwritten; the placement question is what is closed.
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
3b. ☠️ **The rootfs is 93% full and it is eating this investigation's
   evidence.** `/var/log/journal` is persistent (22.4 MB) but only the current
   and previous boot survive: 153 MB free on a 2.4 G rootfs puts journald
   permanently against its free-space guard, so **every reset destroys the boot
   before last** — which is why the two earlier RCU-stall boots can no longer be
   checked. `10-health` reports `rootfs 93% used` as a **PASS**, so our own
   instrument is watching this happen and calling it fine. Two separable moves:
   raise `10-health`'s threshold question (a check that passes at 93% on a
   device that loses evidence at 93% is miscalibrated), and free space —
   ☠️ **not with `apk`**, which re-resolves `world` and has broken this device
   before. Until then, capture full boot logs to the host at the moment of a
   reset rather than expecting to read them later.

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
   ★★ **Two instances confirmed now.** A second full battery, run alone, reset
   the device again — uptime 1667 s before, 356 s after — and its dead boot ends
   the same way: `rcu: INFO: rcu_preempt detected stalls` at monotonic 2398.8 s
   (`t=5252 jiffies, g=213625, q=2286 ncpus=8`), then `watchdog0: pretimeout
   event` at 2417.8 s, with nothing logged in between. Capture:
   `captures/2026-08-23_rcu-stall-second-instance.txt`. So it reproduces on the
   full battery and not on the two checks alone — **2 of 2 full runs, 0 of 3
   isolated runs**.
   ☠️ **Localisation, and a wrong reading of mine corrected:** the interleaved
   `ssh: Connection refused` lines start next to `60-wifi`, which looked like an
   early reset. It is not — those are the detached check's own polling. The
   monotonic timestamps put the stall ~750 s into the run, i.e. inside
   `98-camera-af-rail`'s detached phase, matching the first instance.
   ☠️ **Tried, and it does not reproduce in isolation.** `--only
   camera-af-rail,suspend`, three consecutive runs: **2 ok / 0 failed each time,
   no reset** (uptime monotonic 1299 → 1331 → 1362 → 1398 s). So the hang is
   **load-dependent** — it needs the rest of the battery ahead of it, not just
   these two checks. ★★★ **Step B reproduced the reset, and the kernel named the subsystem this
   time — the "cpuidle hang" framing is now too narrow.** Dropping the *first
   half* of the pre-camera checks (01-identity … 25-sensor) and keeping the
   camera block **still reset the device** (uptime 2198 → 27). So checks 01–25
   are not part of the load, and with step A that brackets it to the camera
   block. The dead boot contains **no RCU stall at all**
   (`grep -c 'rcu_preempt detected stalls'` = 0) — it is a *different* failure
   mode reaching the same watchdog, and until something links them the two must
   not be called one bug. The chain, monotonic, the run having started at 2198 s:

   ```
   [2260.16] i2c-qcom-cci 1b0c000.cci: master 0 queue 0 timeout
   [2260.16] imx363 0-001a: Error reading reg 0x0016: -110
   [2319.92] qcom-camss 1b00020.camss: VFE halt timeout
   [2324.94] qcom-iommu-ctx 1e34000.iommu-ctx: timeout waiting for TLB SYNC
             ... 60 TLB SYNC timeouts + 5 VFE halt timeouts over 518 s ...
   [2859.02] watchdog0: pretimeout event
   ```

   The first fault is **62 s into the run** — inside `42-camera-flash` /
   `43-camera-manual-focus`, **not** in the detached tail where the earlier
   localisation put it. The phone then spends ~10 minutes unable to tear the
   camera down. Capture:
   `docs/power/bringup/captures/2026-08-23_camss-iommu-wedge-watchdog.txt`.
   ★ **This is nearly the known item [`FP3-TODO.md`](FP3-TODO.md) 33f-2**, which
   already records the same `master 0 queue 0 timeout` + `-110` from touching the
   camera while another client tears it down. Two differences: 33f-2's `-110` is
   on the ak7375 **lens**, this one is on the imx363 **sensor**; and 33f-2's
   consequence is bounded (AF disabled for the boot, streaming continues) while
   this one wedges the IOMMU and resets the phone. Same first link, worse ending
   — so the next move is against **concurrent CCI access during camera
   teardown**, not against cpuidle.
   ☠️☠️ **A defect in our own instrument, found in the same log: a dead phone
   reports green.** After the reset the runner printed `ok:` for **nine** checks
   (`50-charger` through `71-clock`), each with empty output, each immediately
   after `ssh: connect to host 172.16.42.1 port 22: No route to host`. A check
   whose transport fails is being scored as a pass. Every "N ok" from a run that
   reset is therefore worthless after the reset point — including, by the same
   rule, any future bisect step. Step A is unaffected: it did not reset.
   ★ **FIXED and both directions shown, 2026-08-23.** `tests/fp3-selftest` now
   keeps ssh's exit status (the `|| true` was throwing it away) and requires a
   verdict: a check whose output has no `PASS:` and no `FAIL:` line is scored
   **FAIL — no verdict**, with the reason distinguishing an unreachable device
   (ssh rc 255) from a check that exited non-zero from one that simply printed
   nothing. A no-verdict check no longer marks its category covered either.
   Shown failing: a temporary check that emits nothing scored
   `FAIL: 97-noverdict (1s) - no verdict: the check produced no PASS: or FAIL:
   line`, where the old code would have printed `ok:`. Shown passing:
   `ok: 71-clock (1s)` on the same build.
   ★★★ **Step C, and three corrections it forced.** Ran `--only camera,suspend`.
   ☠️ **First I read it as "no reset" and that was wrong.** uptime went 951 →
   1242, rising, so I called it monotonic — but the run lasted ~2000 s, so an
   un-reset device would have read ~2950. **uptime-after > uptime-before is not
   evidence of no reset; it must be compared against the run's elapsed wall
   time.** Added to the guardrails below.
   ☠️ **Second, the run is confounded, by my own earlier mistake.** That boot's
   first fault is at 541 s and step C only started at 951 s: the camera was
   already wedged, left that way by a previous attempt at the same run which I
   killed by leaving it in the foreground past a 10-minute cap. So step C says
   nothing about its own contribution. What it does support is that a
   camera-block-only run started the wedge unaided (the killed attempt did, ~4
   min in), and that the wedge survives into a later run and ends in a reset
   19 minutes on. **Before trusting a run, check the kernel log's first fault is
   later than the run's start.**
   ★★ **Third, the two failure modes are linked after all — and CCI is not
   required.** That single boot carries **both**: 125 `TLB SYNC` timeouts, 9
   `VFE halt timeout`, **and** an `rcu_preempt detected stalls` (CPU 5, 1 GP
   behind) 1131 s after the storm began, then `watchdog0: pretimeout`. So the
   step-B insistence that these are two unrelated bugs is withdrawn; a CPU
   spinning in a 5 s IOMMU timeout loop stalling RCU is a plausible mechanism,
   but that is a hypothesis, not a measurement. The same boot has **zero** CCI
   timeouts and zero `-110`, so step B's CCI timeout is **not necessary** to
   reach the wedge. The common core across every reset so far is **VFE halt +
   TLB SYNC storm**.
   ☠️ **Retraction of my own step-B sentence:** I wrote that the two earlier
   resets "contain no camss or IOMMU line at all". That came from excerpt files
   I had written myself, not from the boots, and the boots are gone. Unknown, not
   false — but it was never measured.
   Capture: `docs/power/bringup/captures/2026-08-23_camss-wedge-step-c-confounded.txt`.
   ★ The no-verdict guard added an hour earlier caught a **real** case here, not
   a synthetic one: `FAIL: 45-camera-af-windows-pipewire (74s) - no verdict: the
   device was unreachable`, where the old runner printed `ok:`.
   Next: a clean camera-only run **from a fresh boot** (the only way to
   un-confound it), then bisect by running the battery with growing prefixes
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
7. ★ **`base_dir` measured, and it was set on the wrong cache. Applied; the
   real verification is the next kernel bump.**
   Measured 2026-08-23 in the native chroot with a synthetic harness (same
   source, two absolute paths, `-g` and a differing `-I`), control shown hitting
   first so the harness is not blind:

   | configuration | hits |
   |---|---|
   | control, same path twice | **1 / 2** — harness works |
   | `hash_dir=true`, no `base_dir` | 0 / 2 |
   | `hash_dir=true`, `base_dir` set | 0 / 2 |
   | `hash_dir=false`, no `base_dir` | **0 / 2** |
   | `hash_dir=false`, `base_dir` set | **1 / 2** |

   So the changed absolute path really is what costs the hit, and `base_dir`
   recovers it — **but only together with `hash_dir=false`**, which the kernel
   cache already had. ☠️ **And `base_dir` was already present — on
   `cache_ccache_aarch64`, which the kernel build does not use.** The kernel
   compiles with x86_64-hosted cross tools, so its cache is
   `cache_ccache_x86_64`, and that one had `max_size`/`hash_dir` and no
   `base_dir`. Added `base_dir = /home/pmos` there (`builddir` is
   `$srcdir/linux-$_commit`, so `/home/pmos/build/src/linux-<hash>` changes
   every bump); the previous file is kept as `ccache.conf.bak-20260824`.
   ☠️ **Not yet verified on a real build** — a synthetic two-file harness is not
   a kernel. The measurement that settles it is `ccache -z` before the next
   `_commit` bump and `ccache -s` plus wall-clock after it. Until then this is
   "the mechanism is confirmed and the config now matches it", not "the hit rate
   improved".

**Waiting on a human, skip over them:**

- the call-wake ↔ deep-sleep trade has to be *decided* (inhibitor while ringing,
  or conditional arming), not measured further
- the wake-arm unit's default, the WiFi suspend policy, and the fate of the three
  experiment knobs (`clk_smd_rpm.xo_sleep_off`, `qcom_smd_regulator.both_sets`,
  `icc_smd_rpm.sleep_init` — all default OFF)
- the USB-detached combined session (rail census, slot switch to the UT oracle)
- sending `smd-wake-v1` to the LKML

## Guardrails that have each cost a day

- **A reboot's witness is `uptime` compared against elapsed time, not `uptime`
  alone.** Measured 2026-08-23: a run started at uptime 951 and ended at 1242, so
  the number rose and I called it "no reset" — but the run itself took ~2000 s,
  so an un-reset device would have read ~2950. Record the host-side start and
  end and require `uptime_after >= uptime_before + elapsed`.
- **A killed run can poison the next one.** Same day: a battery left in the
  foreground past a 10-minute cap was killed mid-camera-test and left the camss
  wedged; the next run inherited it and its result was uninterpretable. Before
  trusting a run, check that the kernel log's **first fault is later than the
  run's start**. Long runs go in the background, never the foreground.
- **An excerpt you wrote is not evidence about the boot it came from.** A claim
  that two earlier boots "contained no camss line" rested on capture files that
  were my own selections; the boots had since been vacuumed and it could not be
  rechecked. Grep the source, or write it down as unknown.
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
