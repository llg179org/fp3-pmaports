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

Last updated: **2026-08-24 04:10**.

## The device

| what | value | how to check |
|---|---|---|
| kernel package | `linux-fp3-7.1.3-r73` | `apk info -vv \| grep ^linux-fp3` |
| build stamp | `#74-fp3` | `uname -v` |
| pinned commit | `debug-int/7.1.3` `818d35f1` | `grep _commit linux-fp3/APKBUILD` |
| boot config | 3 labels, md5 `863cdf20…`, `panic=10`, `timeout 3` | `md5sum /boot/extlinux/extlinux.conf` |
| last full battery | **29 ok / 2 failed / 3 skipped** (2026-08-23 17:11, r73). ☠️ Read that number with care: the failures were `98-camera-af-rail` and `99-suspend`, and neither is a check defect — **the camera wedged and the watchdog reset the phone mid-run** (queue item 4). ☠️ It also predates the runner fixes of 2026-08-23, so its `ok` count includes checks scored green after the reset | `tests/fp3-selftest` |
| last camera-block run | **8 ok / 0 failed** on a fresh boot (2026-08-23 late, r73), and the same block wedged the phone earlier the same evening — the fault is intermittent, ~1 run in 2 | `tests/fp3-selftest --only camera,suspend` |

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

3. **The test runner changed today, in three ways that affect how any past
   result should be read.** `tests/fp3-selftest` now (a) scores a check with no
   `PASS:`/`FAIL:` line as **FAIL — no verdict** instead of `ok`, (b) compares
   `/proc/sys/kernel/random/boot_id` across the run and **fails** the run if the
   phone rebooted under it, and (c) **fails** rather than passes when the device
   is unreachable at the end and the reboot cannot be confirmed. ☠️ Before (a),
   a battery that reset mid-run printed `ok:` for nine checks on a dead phone —
   so **any "N ok" from a run older than 2026-08-23 that reset is not
   trustworthy**. All three were shown firing and shown not firing before being
   believed.
4. **A hunt may be running on the device.**
   `docs/power/bringup/tools/camera-wedge-hunt.sh` reboots the phone once per
   pass, so a device found rebooting is expected rather than alarming. It writes
   `summary.txt`, `pass-N.log` and a `kmsg.log` spanning all passes into its
   output directory; kill it by the PID from `ps -eo pid,args`, ☠️ **never with
   `pkill -f`**, whose pattern matches the killer's own command line.

☠️ **Before starting anything power-related, read
[`power/bringup/RUNBOOK.md`](power/bringup/RUNBOOK.md) top section.** A finished
investigation that lives only in a `leads/*` working note is invisible from this
page, and on 2026-08-23 that produced a re-run of a closed bisect and a
conclusion that had to be retracted. If you close something, move the result to
the runbook in the same commit.

## The work queue, in order

Everything here is machine-doable unless the row says otherwise. Work down the
list; do not stop at the end of an item to report.

**Re-ordered 2026-08-23: full deep sleep is the top priority.** Items 2 and 3
are directly under it (evidence retention, and the WiFi lever the same
measurement has to account for); the camera wedge, which led this list yesterday,
is now item 4.

1. ★★★ **TOP PRIORITY — full deep sleep (`vlow`/`vmin`). The AP-side gate IS
   identifiable from source, and it was identified on 2026-08-23: the
   sleep-set regulator votes are never cast because no device tree describes a
   suspend state.**

   The standing fact is unchanged: `vlow` and `vmin` `Count` have **never** left
   0 in any capture we hold, and that survives the AP-side sleep-set family,
   `xo_sleep_off`, `both_sets`, `sleep_init`, and a powered-off ADSP. System
   suspend itself works (12 successes in the last votes run); what has never
   happened is the RPM entering an aggregate low-power set.

   ☠️☠️ Everything this queue once said about LPASS being pinned is
   **retracted** — a flat `Shutdown count` reads the same whether the ADSP is
   held awake or asleep and staying down, and it was the latter. `enter > exit`
   with `cores 0x0` is asleep; on a clean r73 boot LPASS reads `ASLEEP
   cores=0x0` from ~34 s onward. Full retraction in
   [`leads/rpm-sleep-set.md`](power/bringup/leads/rpm-sleep-set.md).

   ### Can `vlow`'s preconditions be read out of the source?

   **The RPM's own entry rule: no, and that is settled rather than assumed.**
   - mainline `drivers/soc/qcom/qcom_stats.c` names "vmin"/"vlow" exactly once,
     in a comment at line 273. The code reads the mode name out of the RPM's own
     memory (`type = readl(d[i].base)`) and makes a debugfs file per record. It
     is a **reader**, and can hold no preconditions.
   - the vendor 4.9 tree
     (`/mnt/1TB/Fp3-Sailfish/hadk22/kernel/fairphone/sdm632`) carries the
     downstream counterpart `drivers/soc/qcom/rpm_stats.c`, whose binding doc
     says it outright: *"RPM maintains a counter of the number of times the SoC
     entered a deeper sleep mode involving lowering or powering down the
     backbone rails - Cx and Mx and the oscillator clock, XO."* Also a reader.
   - a word-boundary grep for `vlow|vmin` across the whole vendor tree returns
     **no RPM hit at all** — every match is `VMIN` in `termbits.h` / `termios.h`
     / `tty.h`, or a `vmin` regulator property in a dtsi. ☠️ Those look like hits
     in an unanchored grep; they are not.

   So the RPM's threshold lives in closed firmware. **But the thing that feeds
   it — what the AP votes — is entirely readable, and it is where the answer
   turned out to be.**

   ### ★★★ The chain, read end to end (2026-08-23)

   Exactly four subsystems ever write `QCOM_SMD_RPM_SLEEP_STATE` in mainline:
   `clk/qcom/clk-smd-rpm.c`, `pmdomain/qcom/rpmpd.c`,
   `interconnect/qcom/icc-rpm.c`, and `regulator/qcom_smd-regulator.c`. Three of
   them vote sleep; the measured hole was always the LDOs (14 active / 0 sleep).
   That hole now has a cause:

   1. `qcom_smd-regulator.c` **does** have a sleep-vote path —
      `rpm_reg_write_sleep()`, wired to `.set_suspend_enable` /
      `.set_suspend_disable` / `.set_suspend_voltage` on every rpm-regulator ops
      struct. ☠️ That is **our own commit** `0be43747a1d2` *"regulator: qcom_smd:
      cast sleep-set votes for suspend states"*, so the driver side was already
      done and the lead was mis-stated as a missing driver path.
   2. Those ops are reached from `__suspend_set_state()` in
      `regulator/core.c:1078`, which needs a non-NULL `struct regulator_state`.
   3. That state comes from DT and only from DT:
      `of_regulator.c` looks for a `regulator-state-mem` (or `-standby`,
      `-disk`) child node, fills `constraints->state_mem`, and — line 327 —
      sets `constraints->initial_state = PM_SUSPEND_MEM`.
   4. `regulator_register()` (`core.c:1497`) then calls
      `suspend_set_initial_state()` **at probe**, casting the RPM sleep-set vote
      once, for good. That is exactly the shape downstream gets from
      `qcom,set = <3>`, reached through a purely upstream mechanism.
   5. ☠️ **No device tree in the tree has that node.** `grep -rl
      regulator-state-mem arch/arm64/boot/dts/qcom/` returns **nothing** — not
      the FP3's `sdm632-fairphone-fp3.dts`, not any of the ~616 qcom arm64 DTs.
      So `suspend_set_initial_state()` has never run for a single rail, and the
      ops we added have never once been called.

   The FP3 node is `qcom,rpm-pm8953-regulators` at
   `arch/arm64/boot/dts/qcom/sdm632-fairphone-fp3.dts:741`, ~20 rails, none of
   them carrying a suspend state.

   ☠️ **Trap, read straight out of `regulator_get_suspend_state_check()`
   (`core.c:583`):** a `regulator-state-mem` node is ignored unless it contains
   `regulator-on-in-suspend` **or** `regulator-off-in-suspend`. A suspend
   voltage on its own produces a `No configuration` warning and no vote. Adding
   voltages without the boolean would look like the experiment ran when it did
   not.

   ☠️ **Second trap, and the reason step 4 is the one that matters:** the phone
   suspends via **s2idle** — `/sys/power/mem_sleep` reads `[s2idle]` with no
   `deep` offered. `pm_suspend_target_state` is then `PM_SUSPEND_TO_IDLE`, and
   `regulator_get_suspend_state()` (`core.c:565`) returns **NULL** for it
   (`default:` case; `of_regulator.c` explicitly `continue`s past
   `PM_SUSPEND_TO_IDLE` too). So the *runtime* `regulator_suspend()` path is
   dead on this device no matter what the DT says. The probe-time
   `initial_state` path is not — it is the only one that can work here.

   ### The other AP-side candidate, also new today

   Of the 45 `soc@0` children, exactly **two** have runtime PM disabled: the USB
   controller `7000000.usb` and its HS PHY `79000.phy` are `power/control = on`;
   the other 43 are `auto`. `runtime_suspended_time` for both is **0** after
   1605 s of uptime — they have never once runtime-suspended. Read out of
   `drivers/usb/dwc3/core.c`: `dwc3_core_probe()` calls `pm_runtime_forbid(dev)`
   unconditionally (line 2321) and the **success path never calls
   `pm_runtime_allow()`** — only the error path and `dwc3_core_remove()` do. So
   `control=on` is dwc3's own default and would hold with no cable attached at
   all. Whether a permanently active USB controller keeps the RPM out of `vlow`
   is **not established** — it is a candidate, ranked below the regulator one.

   ### The two cable questions, answered from measurement

   - *Can a plugged-in, non-charging cable be a limit?* **Not for system
     suspend.** Measured with the cable in and `status = Not charging`:
     `active_since = 0` for every wakeup source, and `prevent_suspend_time = 0`
     for all three USB/charger sources (`tcpm-source-psy…typec@1500`,
     `pmi632-charger`, `pmi632-battery`). Nothing holds the system awake — which
     differs from the UT oracle, where `7000000.ssusb` *was* held. It **can** be
     a limit one layer down: with `control` forced to `auto`, the controller
     still stayed `active`, because the gadget is `configured` — an enumerated
     cable holds it up once runtime PM is allowed at all.
   - *Should the cable be unplugged for the overnight run?* ☠️ **Unplugging
     alone changes nothing** — `control=on` pins the controller active with or
     without a cable, so detaching it without also writing `auto` tests nothing
     and costs the USB link. The pair is the experiment: `echo auto >
     /sys/devices/platform/soc@0/7000000.usb/power/control` **and** the same for
     `79000.phy`, **then** unplug. And note this is now the *second*-ranked
     candidate: the regulator DT change above does not need the cable out at all.

   ★ The run no longer needs the cable to stay reachable: the WiFi path is live
   and verified today (`fp3@192.168.100.17`, key auth, `WIFI_OK`), so the phone
   can be logged into with USB detached. ☠️ WiFi is itself a power lever
   (item 3), so a WiFi-attached measurement is not the 79.1 mA baseline — state
   which link was up in every capture.

   ### Next, in order

   1. **Add `regulator-state-mem` to the FP3 rails** and measure `vlow`. This is
      a `power`-category DT change (`wip/7.1.3/power` + `integration/7.1.3` +
      `debug-int/7.1.3`). Start with the rails downstream marks sleep-capable
      rather than all ~20 at once, and include the mandatory
      `regulator-on-in-suspend` / `regulator-off-in-suspend` boolean.
      ☠️ Before believing a null result, prove the votes were actually cast: the
      `qcom_rpm_smd_write` tracepoint must show sleep-context writes with
      `type=ldoa/smpa`, and the vote mask must move. A DT property that parsed
      into nothing looks identical to a lever that did not work.
   2. If `vlow` still reads 0 with sleep votes demonstrably cast, that **kills**
      the regulator candidate — say so as loudly as a positive result — and the
      USB one is next: over WiFi with USB detached, `control=auto` on both
      nodes, confirm `runtime_status` actually reaches `suspended` and
      `runtime_suspended_time` leaves 0. Until that is seen the lever has been
      described, not pulled.
   3. Either way the regulator work is **upstreamable** — a DT addition plus an
      already-written driver commit, both in `submit/7.1.3/power` territory.

   ☠️ Read [`power/bringup/RUNBOOK.md`](power/bringup/RUNBOOK.md) before opening
   any LPASS question: it was closed on 2026-08-21 and the closure was invisible
   from here, which is what cost a day's re-run.

2. ☠️ **The rootfs is 93% full and it is eating this investigation's
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

3. **Price the WiFi lever in mA** (slope leg, `wlan0` down vs up). ☠️ PRONTO
   parks holding the XO when `wlan0` is down, so the naive reading flatters it.

4. ☠️☠️ **The camera wedges the phone and the watchdog resets it — and the
   fault is INTERMITTENT, about one camera-touching run in two.** This is not
   `99-suspend` failing, and it is not a `cpuidle` bug: the phone reaches
   `watchdog0: pretimeout event` because the camera cannot be torn down.
   Signature, every time:

   ```
   qcom-camss 1b00020.camss: VFE halt timeout
   qcom-iommu-ctx 1e34000/1e35000.iommu-ctx: timeout waiting for TLB SYNC   (x60-125, every 5 s)
   [sometimes] rcu: INFO: rcu_preempt detected stalls on CPUs/tasks
   watchdog0: pretimeout event
   ```

   ☠️ **Do not bisect this one run per arm.** A whole day was spent doing that
   on 2026-08-23 and it "cleared" four different arms; at a ~50% failure rate
   every one of those clearances was a coin flip, and all of them are retracted.
   Any arm-by-arm comparison needs several runs per arm and a stated rate.
   What is established, because it was observed rather than inferred:
   - `44-camera-af-windows` taking ~502 s rather than ~5 s is a **symptom** of an
     already-damaged camera, not a cause;
   - a `cci ... timeout` + `imx363 -110` fires at boot, ~13 s in, with no camera
     client in existence — [`FP3-TODO.md`](FP3-TODO.md) 33f-4, and it cuts
     against the client-collides-with-teardown story in 33f-2 and 33f-3;
   - the rate itself, ~3 wedges in 6 independent runs.
   ★★ **The hunt ran 8 passes and reproduced nothing — which is itself a
   result, and it corrects the rate I quoted.** Eight consecutive camera blocks,
   each from its own fresh reboot with the tap attached: **0 wedges, 0 fault
   lines**, boot id unchanged every time. Together with step G and both passes of
   step H that is **11 clean camera runs from fresh boots**. If the fault were a
   uniform coin flip, 0 of 11 would happen about 1 time in 2000. So ~50% is the
   rate *across all camera runs*, **not** the rate under these conditions, and
   the "about one run in two" phrasing above should be read that way.
   ☠️ **But do not turn that into "a fresh boot is safe" — that is exactly the
   inference this investigation keeps getting wrong.** What separates the arms is
   not established. The one *measured* difference is how long the phone had been
   up when the camera was first touched: the three wedges began at **290 s,
   1444 s and 2198 s** of uptime, every clean hunt pass at **~43 s**. That is a
   candidate, not a cause, and the 290 s case makes any threshold uncomfortably
   low. Other differences have not been excluded.
   **Next:** the hunt now takes a third argument, a settle time, so the same
   passes can be run after the phone has been up for a while — varying the one
   thing that actually differs.
   ☠️ **Second sighting of a smaller defect:** `98-camera-af-rail` finished with
   **no verdict at all** in 2 of the ~11 runs (hunt pass 8, step H pass 1). Before
   today's runner fix that scored as `ok`, so it has probably been happening for
   a long time unseen. Its detached mechanism is the suspect.
   **Instrument:** `docs/power/bringup/tools/camera-wedge-hunt.sh` — repeat the
   camera block from a fresh reboot, with `kmsg-tap.sh` streaming the kernel log
   to the **host**, and stop at the first fault, so the onset is finally captured.
   It has to go to the host because the phone's rootfs is 93% full and journald
   vacuums the boot before last (queue item 2): a reset destroys its own evidence.
   Full day-by-day account, including the three instrument errors it exposed:
   [`power/bringup/leads/camera-wedge-2026-08-23.md`](power/bringup/leads/camera-wedge-2026-08-23.md).

5. **The SSR write storm is a `qcom-ngd-ctrl` question, not a codec one.**
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

6. **Provoke the non-recovering SSR path** — needs a kernel-side hook now, so
   this is the one item here that is not a quick measurement. ☠️ Two dead ends
   are already recorded in [`TODO.md`](TODO.md), do not re-walk them: the
   `avs/audio` PDR route does not exist on msm8953 (`PDM: no support for the
   platform`), and holding audio traffic across a whole restart cycle moved the
   bring-up count by exactly one, not two. The reachable second source is
   `qcom_slim_ngd_notify_slaves()` on a runtime-PM resume taken while the
   controller state is `DOWN`, and that window closes as soon as the controller
   unregisters. Widening it deliberately is the next move.

7. ☠️ **Housekeeping item withdrawn — its premise is false.**
   `linux-postmarketos-qcom-msm8953` is **not installed**: `apk info` lists only
   `linux-fp3`. What does exist is a second module tree,
   `/lib/modules/7.0.9-postmarketos-qcom-msm8953`, and that one belongs to the
   **`postmarketOS-fallback` boot label** — the brick-safety net. Do not delete
   it. If `only one kernel release/flavor is supported` still appears on an
   `apk` run, it comes from the two module trees and needs a fix that keeps the
   fallback intact, not a package removal.
   ☠️ `apk del` on a package that is not installed reports a bare `1 error` and
   nothing else; `-v` is what makes it say why.

8. ★ **`base_dir` measured, and it was set on the wrong cache. Applied; the
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

- **`pkill -f` / `pgrep -f` match your own command line — and this bit again on
  2026-08-23.** A cleanup `pkill -f 'kmsg-tap.sh'` was written at the front of
  the same command that then started the tap and ran the battery; the pattern
  matched that command line, so the job killed itself before doing anything
  (exit 144) and the measurement had to be repeated. This guardrail was already
  written down. Kill by **explicit PID** from `ps -eo pid,args`, or give the
  pattern something the killer's own line does not contain.
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
