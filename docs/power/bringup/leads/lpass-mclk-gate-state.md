# LPASS mclk-gate experiment — session state (2026-08-21)

> AI-generated working note (Claude Fable 5); temporary session-state file.
> Delete once the result is in RUNBOOK.md.

## What is proven (committed: aae124e and earlier, all pushed)
- LPASS never-sleeps root cause: `msm8916-wcd-digital` probe does an
  unconditional `clk_prepare_enable(mclk)`; on msm8953 mclk = q6afecc
  (`LPASS_CLK_ID_INTERNAL_DIGITAL_CODEC_CORE`) = an ADSP clock request.
  Bisection: codec loaded (card blocked) → LPASS frozen awake since ~27 s
  (exit>enter, cores 0x1). Codec blocked → LPASS enters XO shutdown ~75 s
  and stays (enter>exit, cores 0x0). q6/APR stack, wcd9335, NGD, smgr all
  exonerated. Live unbind does NOT release (firmware latch); ADSP SSR does.
- ☠️ Static shutdown count is ambiguous: read last-enter vs last-exit.
- vlow still 0 even with LPASS down → next blocker after this: LDO sleep-set
  gap (leads/rpm-sleep-set.md).

## The fix under test
`sound/soc/codecs/msm8916-wcd-digital.c`: mclk moved from probe/remove into
DAI startup (clk_prepare_enable, refcounted) / shutdown (clk_disable_unprepare).
Diff saved: scratchpad mclk-gate.patch; applied in BOTH
`/mnt/1TB/pmos/linux-fp3-work` (branch debug-int/7.1.3, uncommitted) and
`/mnt/1TB/pmos/fp3-sensors-wt` (branch wip/7.1.3/sensor, uncommitted, build tree).
Built with `FP3_KTREE=/mnt/1TB/pmos/fp3-sensors-wt fp3-kbuild.sh modules`
(clang/LLVM=1 — running kernel #62-fp3 is gcc: insmod OK, ftrace WARN expected,
do not report as defect; final package build is gcc).

## RESULT so far (2026-08-21 ~12:10)
- Patch DEPLOYED via .ko hot-swap; reboot with FULL stack: LPASS took 56
  shutdowns in 2 min (vs 2-forever before) → mclk fix PROVEN NECESSARY.
- ☠️ SECOND latch found: at ~38.8 s (ADSP ticks) something in session
  bring-up (PA UCM probe / first audio path use, between 24-52 s) latches
  LPASS awake AGAIN, one-way; no PCM open, mclk enable count 0, aw8898 DAPM
  ON (IN/SPK PA/OUT) but BE DAI off; stopping watchers/iio-sensor-proxy/
  snsregd/rmmod smgr does NOT release. Oracle (UT) plays audio and still
  sleeps → mainline misses a teardown. SEPARATE follow-up investigation.
- Audio regression check: speaker-test rc=0; selftest 24-speaker-amp FAILS
  but with the DOCUMENTED pre-existing aw8898-death signature (I2C dead,
  known invariant bug) — not plausibly caused by this internal-codec patch.
- Kernel commit DONE on wip/7.1.3/power: **4b09b2158dd8**
  "ASoC: msm8916-wcd-digital: hold mclk only while a stream runs".
  In linux-fp3-work the same change is UNCOMMITTED (checkout -- file, then
  cherry-pick 4b09b2158dd8); fp3-sensors-wt also has it UNCOMMITTED (revert
  with git checkout -- after, keep the built .ko).

## Continuation plan (do next, in order)
1. Artifact gate: `.output/sound/soc/codecs/snd-soc-msm8916-digital.ko`
   exists, `modinfo | grep vermagic` == `7.1.3-postmarketos-qcom-msm8953 SMP preempt mod_unload aarch64`,
   `strings` contains "failed to enable mclk".
2. Restore phone config BEFORE reboot test:
   - `rm /etc/modprobe.d/lpass-bisect.conf`
   - `systemctl enable fp3-voiced spkwatch ringwatch` (were disabled --now)
   - unmask user audio: `sudo -u fp3 XDG_RUNTIME_DIR=/run/user/10000 systemctl --user unmask pipewire.socket pipewire.service wireplumber.service`
   - `sudo -u greetd XDG_RUNTIME_DIR=/run/user/113 systemctl --user unmask pipewire.socket pipewire.service`
   - `rm /etc/pulse/client.conf.d/00-noautospawn.conf`
3. Deploy .ko: scp to phone, back up
   `/lib/modules/7.1.3-postmarketos-qcom-msm8953/kernel/sound/soc/codecs/snd-soc-msm8916-digital.ko`
   (it may be .ko not .ko.*; keep .bak), copy new one in, `depmod`, reboot.
4. Measure (PASS pre-declared): full `cat qcom_rpm_master_stats/LPASS` at
   ~2 min and ~5 min uptime: PASS = last-enter > last-exit persisting (or
   count growing) with FULL stack up; AND audio works: `speaker-test`/aplay
   short burst + `fp3-selftest --only speaker-amp` passes; play audio, then
   after stop LPASS returns to sleep.
5. Document in RUNBOOK (new section), commit+push fp3-pmaports.
6. Kernel commit: category = audio? power? → the change is in the codec but
   motivation is power; wip/7.1.3/power exists (2 LKML-ready patches per
   memory). DECIDE then: commit on the chosen wip branch + cherry-pick to
   integration/7.1.3 + debug-int/7.1.3, push all to fork (port 443), then
   later _commit bump. Trailer: Signed-off-by Lajosházi + Co-authored-by:
   Claude Fable 5 <noreply@anthropic.com> (local); upstream form gets
   Assisted-by: Claude:claude-fable-5.
7. Memory update: project_fp3_power_idle.md (root cause + fix + method traps:
   enter/exit ambiguity, mask-vs-disable, blacklist-vs-install, irq143 rebind).

## Phone state right now
- pmOS slot, charging OK. Blacklist file ACTIVE (no sound card, no smgr!),
  watchers disabled, fp3+greetd pipewire masked, autospawn=no. Audio dead
  until step 2+3 reboot. Modem/MM fine. rmtfs untouched.
- ☠️ never reboot with USBIN suspended (check `pmi632-charger/status` = Charging).

## Earlier today (already committed/pushed, no action)
- MM leg valid: ~10 % (e5473f5); MPSS duty-cycle probe: 37 % XO hold =
  network territory (2f670f2); LPASS milestone (aae124e).
