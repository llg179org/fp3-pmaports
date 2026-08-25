# Status — where the port stands right now

> ⚠️ **AI-generated.** This page was written by Claude working under the
> direction of Lajosházi, László Gergely, who reviewed every change and made or
> reviewed every measurement it rests on.

**This file is the live one.** It is rewritten as work happens, not at the end of
a session, and it is the first thing to read when picking the work back up. The
reasoning behind each open item is in [`TODO.md`](TODO.md) — the by-item view, with the
by-branch view folded in at its end since 2026-08-24; closed items move verbatim
to [`TODO-DONE.md`](TODO-DONE.md). When this page and `TODO.md` disagree, **this one
is newer and `TODO.md` is more complete** — fix whichever is wrong rather than
picking a winner.

☠️ Every line below is the kind that goes stale first. Each row says how to read
it off the device instead of trusting it.

Last updated: **2026-08-25 — ★★★★★ THE GOAL (pmOS down to the UT level or
below) took its first real step, and the two biggest wakers on the phone turned
out to be OURS. (1) `apcs_hold_cluster()`, our own PLL-relock guard, took a
GLOBAL `cpu_latency_qos`: 45.8 pm_qos updates/s and 128 IPIs/s on a 96 %-idle
phone — two thirds of all IPI traffic — with both clusters barred from power
collapse for every hold. Fixed to a cluster-local cpuidle hold (`68dcadbd`,
shipped as r76 `#77-fp3`); measured after: pm_qos 458 → 0 per 10 s, zero PLL
failures. (2) A diagnostic harness left running since August: `spkwatch` alone
had burned 2.6 % of a core permanently. Disabled with ringwatch, fp3-powerlog,
avahi and cups. AGGREGATE, one idle-ab hour, same protocol as the matched pair:
median **148–157 → 98.3 mA (−35 %)**, floor unchanged (54 → 52.9) — exactly the
shape wakeup fixes predict. Burstiness (median ÷ floor) **2.75× → 1.86×**
against the oracle's 1.97×, so pmOS now bursts LESS than UT. **The wakeup half
of the gap is closed; what remains is ~38 mA of pure continuous draw** (52.9 vs
15.3 mA floor), which no tracepoint can see. **THE CENSUS AGAINST THE ORACLE
WAS THEN RUN, and it answered all three questions and unseated its own
premise.** The modem does not move the oracle's floor (30.8 / 31.1 / 31.1 /
31.1 mA over four legs, modems on / both `Powered=0` / back / untouched — and
there are TWO modems, `ril_0` and `ril_1`). The debug UART is not the
difference: the oracle runs the same clock at the same 3 686 400 Hz with
`console=` and `earlycon=` on its cmdline, and 43 enabled clocks against our
37. The rail diff was published as a lead — `s3` and `s4` enabled on ours with the
panel dark — and ☠️☠️ **the matching capture killed it the same evening**:
`regulator_summary` is a **tree**, and the indented rows are **child
regulators**, not only consumers. Both of `s3`'s direct consumers read 0; it is
up because its child `l3` is, held by the USB PHY, and `s4` because its
children `l5` (eMMC I/O) and `l7` (USB PHY PLL) are. Leaf for leaf the rail
sets **match**. So the census excluded everything it was meant to find, and
**~38 mA of continuous draw remains with no candidate** — while the oracle's
own floor read **31.1 mA** today against 15.3 yesterday, so the 3.5× framing
itself is now the first thing to settle. ☠️☠️ **The premise: the oracle has NEVER been measured
with its screen actually off.** It never blanks on its own (no inhibitor held,
inactivity action unset), `Unity.Screen.setScreenPowerMode("off")` returns
`true` with the panel still powered, and the `fb0/blank` write is half a blank
— the LCDB bias rails stay at 5500 mV and the compositor undoes it. ☠️ RETRACTED the same
evening: `tools/press-power-key.py` did not blank the screen, it **switched the
phone off** (found on the offline-charging screen; a held hardware button was
needed). The lost RNDIS/WiFi was a powered-down phone, not a suspend, and the
suspend reading is withdrawn — the LCDB and `show_blank_event` evidence stands
on its own. So every UT idle
figure so far, the 15.3 mA floor included, describes a state the phone is not
in when its screen is off; today's oracle floor read **31.1 mA**. ☠️ And 74 ssh
logins in 70 minutes — my own waiter loops — cost **18.3 mA** on the coulomb
integral and produced a trend that read exactly like a modem effect: do not
poll during a leg. ☠️ WITHDRAWN from the entry
before this one: the `msm_mdss 79/s with the display off` lead was sampled with
the display ON; with the CRTC proven off the display subsystem raises no
interrupts at all. ☠️ `boot-deploy` rewrites extlinux.conf on every kernel
install and drops the multi-label net and `panic=10` — restored by hand.
Details: findings-log 2026-08-25 entries.**

## The device

| what | value | how to check |
|---|---|---|
| kernel package | `linux-fp3-7.1.3-r76` | `apk info -vv \| grep ^linux-fp3` |
| build stamp | `#77-fp3` | `uname -v` |
| pinned commit | `debug-int/7.1.3` `5aafd59e` | `grep _commit linux-fp3/APKBUILD` |
| boot config | **3 labels**, all with `panic=10`: default `postmarketOS` → **frozen** `/vmlinuz-r76` + `/sdm632-fairphone-fp3.dtb-r76`; `postmarketOS-r73` fallback; `postmarketOS-headless` (same r76 snapshot + `systemd.unit=multi-user.target`, for GUI-less legs). ☠️ The default was pointing at the LIVE `/vmlinuz` symlink until 2026-08-25 evening, which is the r74 no-boot trap — the next package install replaces the kernel under the label that boots by default, on a phone with no console. `preflight.sh` refuses to arm a night on that, correctly; the snapshot was verified by sha256 against the running kernel before the config was switched. ☠️ `boot-deploy` rewrites this file on every kernel install and drops all of it — restore by hand afterwards | `cat /boot/extlinux/extlinux.conf` |
| last full battery | **29 ok / 2 failed / 3 skipped** (2026-08-23 17:11, r73). ☠️ Read that number with care: the failures were `98-camera-af-rail` and `99-suspend`, and neither is a check defect — **the camera wedged and the watchdog reset the phone mid-run** (queue item 4). ☠️ It also predates the runner fixes of 2026-08-23, so its `ok` count includes checks scored green after the reset | `tests/fp3-selftest` |
| last camera-block run | **8 ok / 0 failed** on a fresh boot (2026-08-23 late, r73), and the same block wedged the phone earlier the same evening — the fault is intermittent, ~1 run in 2 | `tests/fp3-selftest --only camera,suspend` |

☠️ The paragraph that stood here describing "three extlinux labels" was stale
twice over; the boot-config row in the table above is the accurate one (5 labels,
default `postmarketOS-prev`). Read `/boot/extlinux/extlinux.conf` off the device
rather than trusting any prose copy of it.

## Branch tips

| branch | tip | note |
|---|---|---|
| `wip/7.1.3/audio` | `42b7e745` | + the three SSR fixes of 2026-08-23 |
| `integration/7.1.3` | `ecce72c3` | + icc suspend-scoped sleep-set drop knob (2026-08-24 eve) |
| `debug-int/7.1.3` | `0c3dcfba` | tip advanced by the icc knob; ☠️ **the package still pins `8d7ecf9` (r73)** — the knob is default-off with no runtime effect, so it was **not** shipped/bumped |
| `wip/7.1.3/power` | `3d883ecd` | + `icc_smd_rpm.sleep_bw_off` suspend-hook experiment knob (2026-08-24 eve) |

☠️ **The device runs r73 (`8d7ecf9`), which the `linux-fp3` package still pins.**
The three branches above advanced by one commit (the default-off icc suspend-hook
knob, `icc_smd_rpm.sleep_bw_off`), pushed to `fork`, but `_commit` was
deliberately **not** bumped: the knob has no runtime effect unless armed on a boot
label, and it does not by itself reach `vlow` (which, as of the same night's
oracle raw-read, **nothing** can — the mode never occurs on this platform).
Bump `_commit` only when there is a reason to ship.

★★ 2026-08-24: the all-20-rails `regulator-state-mem` commit (r74,
`84241a07`) **did not boot** and is now **reverted** on all three branches
(`wip/power` `53e51066`, `integration` `140ff98e`, `debug-int` `8d7ecf9`), pushed
to `fork`. `linux-fp3` re-pinned to `pkgrel=75`,
`_commit=8d7ecf9153cde4c1a80f0f1d4f53562524a30598` (reverted debug-int, content
≡ the running r73 kernel). Why revert: a one-rail bisection probe proved the
mechanism is sound (state-mem on only `pm8953_s3` boots, casts the vote —
`sleep smpa/3 swen=1 @ t=0.276084` — and suspends), so the all-20 no-boot is the
`regulator_register()` all-or-nothing behaviour tripping on one specific rail;
**and** `on-in-suspend` saves no power anyway (rail stays on, only the vote
exists). `vlow` is unchanged (still 0) — the deep-sleep win is gated behind the
AP-XO regression, not the LDO votes. Full detail:
[`power/bringup/findings-log.md`](power/bringup/findings-log.md) 2026-08-24
one-rail entry.

`fp3-pmaports` `origin/main` carries the docs and the APKBUILD; the kernel goes
to remote `fork` only, over port 443, and never to `origin`.

## ☠️ Resume here after a compact or a long gap

## ✅ RESOLVED — r74 no-boot cause found + reverted (2026-08-24); device on r73

The device is up again on the r73 kernel/DTB and answers on SSH. r74 stays on
`/boot` untouched for diagnosis; the boot default was moved off it. Kept below
because only the boot is recovered — the *cause* is not fixed.

**r74 does not boot.** Deployed, rebooted 22:45:10, never re-enumerated on USB or
WiFi. The host log shows the `cdc_ncm` disconnect and **no re-enumeration** — and
that absence is the informative part: `panic=10` is on every entry and the debug
layer starts the watchdog at probe, so a *later* hang would produce a reboot
**cycle**. There was none, so the kernel stops **before the watchdog probes**.

**Prime suspect: the change itself, `regulator-state-mem` on all 20 rails.**
Read out of the source after the failure:

- `suspend_set_initial_state()` runs inside `regulator_register()`
  (`core.c:1497`), one of the earliest things on this SoC for the RPM rails; the
  change makes it send 20 extra `qcom_rpm_smd_write()` calls into the RPM
  **sleep** set right there.
- `qcom_rpm_smd_write()` (`soc/qcom/smd-rpm.c:139`) waits on the ack with
  `RPM_REQUEST_TIMEOUT = 5 * HZ`, returning `-ETIMEDOUT` or the RPM `ack_status`.
- ☠️ **`regulator_register()` treats that as fatal** (`if (ret < 0) return ret`),
  and `rpm_reg_probe()` returns out of its child loop — so **one rejected or
  timed-out sleep vote unregisters every rail on the board**. No regulators →
  no storage, USB or display: the silent early stop observed. 20 rails × 5 s is
  also up to 100 s of blocked probe.
- ☠️ A NULL `smd_vreg_rpm` was checked and **ruled out** (assigned before the
  loop, `qcom_smd-regulator.c:1530`).

**Hypothesis, not measurement.** The next attempt must not be "all 20 rails
again with a tweak": start from **one** rail and read the boot before the second.

**How it was recovered (the route that worked):** stock ABL fastboot →
`set_active a` → UT boots (adb as `phablet`, sudo `<pw>`) → mount pmOS's
embedded `/boot` off `system_b` (`losetup -o 1048576 <loop> /dev/mmcblk0p31`;
mount RW) → edit `extlinux.conf` default to `postmarketOS-prev` (r73) → sync,
umount, `losetup -d` → `sudo reboot bootloader` → `set_active b` → `reboot`.
pmOS came up on r73 in ~15 s; `02-boot-fallback` passes and the running tree has
**zero** `regulator-state-mem` nodes (proof it is r73). Full step-by-step in
`docs/TODO.md` (the ✅ RECOVERED block).

☠️ **Button-mapping correction, measured by the user.** **Volume-UP + power
reaches EDL** (`05c6:900e`); **volume-DOWN + power starts fastboot**. The lk2nd
menu is **not usable blind** — the screen stays black — so recovery goes through
fastboot + the UT-slot route above, never by picking an on-screen menu entry.
The earlier note (down→EDL, up→lk2nd menu) was inverted and is retracted.

☠️ **The guardrail was followed in letter and missed in substance, and that is
the lesson to keep.** "Put anything risky on the non-default label" was obeyed
by putting the *tracing arguments* on a separate label — but the tracing
arguments were never the risky part. The **device tree** was, and it is on
`/boot/sdm632-fairphone-fp3.dtb`, which **both** r74 labels point at. Isolating
a change means isolating the file that changed, not the flag that came with it.
A `-sleepset` label whose only difference is `trace_event=` is not an isolated
arm; it is the same arm twice.

☠️ Second thing this cost: `apk add` ran `boot-deploy`, which **rewrote
`extlinux.conf` from scratch** — dropping the fallback label, `panic=10` and the
menu timeout, exactly as `docs/deploy/README.md` warns. The rewrite afterwards
put all four labels back and `02-boot-fallback` confirmed them (4 of 4 entries
carry `panic=`), so the net that now has to be used was verified *after* the
install and before the reboot. The pre-install file is saved on the device as
`/boot/extlinux/extlinux.conf.pre-r74`.

**Where the change lives, so nothing is lost while the phone is down:**
`wip/7.1.3/power` `e59893af`, `integration/7.1.3` `4cf51780`,
`debug-int/7.1.3` `84241a07`, all pushed to `fork`. Package
`linux-fp3-7.1.3-r74` is built at
`/mnt/1TB/pmos/work/packages/edge/aarch64/linux-fp3-7.1.3-r74.apk`.
☠️ **Do not roll `_commit` back in the APKBUILD before the cause is known** —
the commit is not proven wrong yet, only the boot is proven broken.


The state that is *not* in git, in one place. Everything else is recoverable
from the repos.

1. ★ **There IS a half-finished step as of 2026-08-23 22:20: r74 is built or
   building, and is NOT deployed.** The RPM sleep-set DT commit is on
   `wip/7.1.3/power` `e59893af`, `integration/7.1.3` `4cf51780` and
   `debug-int/7.1.3` `84241a07`, all pushed to `fork`, tarball checked
   (200 real / 404 bogus). `linux-fp3` is at `pkgrel=74` with that `_commit`,
   checksummed, and the build log is `/mnt/1TB/pmos/build-r74-sleepset.log`.
   The remaining steps, in order:

   1. `apk add` the built package. ☠️ `--simulate` first and **read the output
      for `Purging`** — apk-tools 3 re-resolves the whole `world` on a single
      local install and has broken this device that way before.
   2. Re-arm extlinux and check the md5 of the deployed kernel/dtb. The net was
      verified intact just before the bump (`02-boot-fallback`: fallback entry
      present, menu armed, all three entries carry `panic=`, watchdog active).
   3. Add a **non-default** label carrying
      `trace_event=qcom_smd_rpm:qcom_rpm_smd_write trace_buf_size=8M`
      (the `postmarketOS-xo` label is the precedent for an experiment label),
      flip `default` to it, reboot, and run
      `docs/power/bringup/tools/sleepset-witness.sh` **early** — the ring
      overwrites the boot window within minutes. Then flip `default` back.
      ☠️ **Never add `tp_printk`.** The cmdline carries
      `console=ttyMSM0,115200`; a boot's worth of tracepoints at 115200 baud
      runs past the 20 s watchdog and boot-loops the phone.
   4. Only once the votes are witnessed does reading `vlow` mean anything.

   `wip/7.1.3/audio` is unchanged at `42b7e745`; nothing there is stranded.
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

☠️ **Before starting anything power-related, read the modem-lead plan in
[`TODO.md`](TODO.md) ("Deep sleep — CLOSED" section) and the queue item above.** A finished
investigation that lives only in a `leads/*` working note is invisible from this
page, and on 2026-08-23 that produced a re-run of a closed bisect and a
conclusion that had to be retracted. If you close something, move the result to
the runbook in the same commit.

## ★ The primary goal, stated 2026-08-24 evening

**Bring pmOS's consumption down to the Ubuntu Touch level, or below.** Set by
Lajosházi, László Gergely; it replaces "reach a deep-sleep mode" as the thing
this track is for, and it is what "done" now means.

Why the restatement matters: the oracle does not get its number by sleeping.
Measured the same evening on the same protocol (panel **off**, radio up, WiFi
associated, on battery, via the newly validated `bms/cc_soc` coulomb counter),
**UT idles at 32.2 mA** where pmOS idles at 54 mA on its floor but **148 mA on the median** — measured 2026-08-25 by one instrument on both sides — and our best *asleep*
figure, the radio-low leg of the same day, is 40.8 mA. The oracle sitting awake
beats our phone asleep. So the gap to close is **idle depth**, not suspend, and
the target is a level rather than a mode.

**The matched pair (2026-08-25, `tools/idle-ab.sh` on both, panel proven dark,
compositor running on both):**

| | floor (p10) | median | integrated | voltage slope |
|---|---|---|---|---|
| UT | 15.3 mA | 30.1 mA | **32.2 mA** | 43.0 mV/h |
| pmOS r73 | 54.3 mA | **148.0 mA** | — | 133.7 mV/h |

**The shape is the finding.** pmOS's floor is close to its long-documented
58-63 mA, but its median is three times its own floor where UT's is barely
twice. So the gap is not a load that burns continuously — it is **wakeups**.
First evidence: with the panel dark, `IPI1` 1927/s, `arch_timer` 1037/s,
`msm_mdss` **79/s with the display off**, at 82-100 % CPU idle.

☠️ Earlier readings of the oracle (22, then 29.7 mA) came from shorter windows
and a different script; 32.2 is the one taken by the same instrument as the pmOS
row, and only same-instrument rows belong in this table.

## The work queue, in order

Everything here is machine-doable unless the row says otherwise. Work down the
list; do not stop at the end of an item to report.

**Re-ordered 2026-08-24 night: the deep-sleep/`vlow` item CLOSED; the modem
lead takes slot 1.** Items 2 and 3
are directly under it (evidence retention, and the WiFi lever the same
measurement has to account for); the camera wedge, which led this list yesterday,
is now item 4.

1. ★★★ **TOP — the MODEM LEAD.** The `vlow`/`vmin` deep-sleep item that stood
   here is **CLOSED 2026-08-24 night**: the raw message-RAM read
   (`power/bringup/tools/rpmstats_raw.py`) shows the RPM never enters `vlow`
   on the working UT oracle either (count 0 across a 10-min window with
   APSS +34 603 collapses and thousands of co-proc XO shutdowns) — the mode
   does not occur on this platform under any OS, the target was a phantom,
   the `smd-rpm.c` handshake plan is cancelled. Full account: findings-log
   2026-08-24 "(continued)"; the item's 300-line history: git log of this file
   + TODO-DONE.

   What remains of "deep sleep" is absolute draw, and its one proven lever is
   the modem: **modem processor off is worth ~36 mA** (79.1 → 43.3 mA asleep),
   mechanism unnamed, and every service-cut leg was contaminated by `rmtfs -P`
   (= modem shutdown). The ordered plan is in TODO "Deep sleep — CLOSED"
   section: (1) ✅ MPSS XO-duty across s2idle — DONE 2026-08-24: radio up =
   suspends abort early + MPSS chops the crystal; radio low = full-term
   suspends + MPSS XO off the whole window
   (`captures/2026-08-24_modem-xo-duty.txt`); (2) ✅ **(a) radio-low night slope leg
   DONE 2026-08-24 evening: 40.8 mA asleep** (phase-A −18.68 mV/h, r²=0.987,
   6/6 full-term suspends) against a 79–83 mA baseline and the 43.3 mA
   modem-off leg — **radio-low buys the whole ~36 mA without powering the
   modem processor off**; (b) the remoteproc modem-off leg is now optional;
   (3) **next: does a power-save mode that keeps the phone REGISTERED
   (PSM/eDRX/paging cycle) reproduce any part of it** — radio-low itself is
   airplane mode by another name, so it is a mechanism, not a fix. The fix
   direction is modem configuration, likely not an AP-side kernel patch.

2. ✅ **DONE 2026-08-23 night — rootfs freed 94%→81% and `10-health`
   recalibrated.** The bulk was the apk *download* cache: `/var/cache/apk`
   held 313 MB of old cached kernel `.apk` builds (r65–r74, ~30 MB each),
   redundant with the installed/unpacked kernel. Cleared with a plain
   `rm -f /var/cache/apk/*.apk` — **not** `apk`, so `world` was never
   re-resolved (the docs/deploy caution is specifically about `apk` mutating
   world; deleting cached downloads does not). Rootfs went 2.1 G→1.8 G used,
   128 MB→441 MB free, so journald is back above its 15% keep-free guard and
   the boot-before-last survives resets again.
   `tests/checks/10-health-test.sh` now has two tiers: FAIL at ≥98% (the old
   upgrade-hazard line) and a new **WARN at ≥85%**, where journald's default
   `SystemKeepFree` (15% of the fs, ~360 MB here) starts dropping older boots —
   so the instrument no longer prints a bare green `PASS: rootfs 93% used`
   while evidence is being deleted. The WARN line names the safe reclaim command.
   ☠️ **This refills on every kernel bump** (each `pmbootstrap` build re-caches
   the new `.apk`), so it is not a one-time fix — the WARN is the standing
   reminder to clear the cache when it fires.

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
     client in existence — [`TODO.md`](TODO.md) 33f-4, and it cuts
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
   appear in neither that table nor `TODO.md`'s by-branch sections. Written
   up in [`TODO.md`](TODO.md); the table is incomplete, not
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

   ★ **Partly settled during the r74 bump of 2026-08-23, and it turned up a
   second, larger defect.** `base_dir = /home/pmos` and `hash_dir = false` are
   confirmed present in **both** `ccache.conf` files, so that fix is in place.
   ☠️☠️ **But the recorded "raised to 25G" was false and had never taken
   effect.** Measured mid-build: `ccache -s` reads `Cache size (GB): 5.0 / 5.0
   (99.94%)` with **5062** cleanups, and both config files read literally
   `max_size = 5G`. The cache has been evicting continuously the whole time,
   which is exactly the condition the `base_dir` work was meant to stop
   mattering. Raised to 25G for real (`sudo`, read back from both files;
   ☠️ an unprivileged `sed -i` fails on this root-owned tree with a *temp-file*
   permission error that is easy to skim past as noise). 398 G free on the
   volume, so the size is not a constraint.
   ☠️ **The lesson is about this document, not about ccache: a note saying a
   thing was fixed is not evidence that it was.** Read the config back.
   Hit rate at the time of measurement, for the next comparison: 60.30 %
   (622 829 / 1 032 922 cacheable calls).

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
