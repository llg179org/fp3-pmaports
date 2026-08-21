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

## Branch propagation DONE (2026-08-21 afternoon)
- wip/7.1.3/power: **4b09b2158dd8** (pushed to fork).
- integration/7.1.3: cherry-pick **63b826b741f3** (pushed).
- debug-int/7.1.3: applied via `git am` on the real tip → **1a18f3137887**
  (pushed; tarball check: real hash 200, bogus 404).
- ☠️ `/mnt/1TB/pmos/linux-fp3-work` is a STALE clone (8+ commits behind fork's
  debug-int) — the live debug-int checkout is the MAIN clone
  `/mnt/1TB/pmos/linux-fp3` itself. Work clone reset back to its old tip.
- ☠️ `git fetch` in/into that work clone was killed mid-run three times
  (object negotiation on the slow disk); workaround that worked:
  `git format-patch --stdout` + `git am`.
- fp3-sensors-wt codec diff reverted (built .ko kept).
- REMAINING (deliberately not done): `_commit` bump to 1a18f3137887 + pkgrel +
  `pmbootstrap checksum` + package build — note debug-int tip includes the
  smd-rpm XO EXPERIMENT commit the phone already runs.

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

## Second-latch experiment ladder (2026-08-21 afternoon, instrumented boot)
Instrument: LPASSDBG dev_info prints in q6afe/q6adm/q6asm (built from the
debug-int tree in /mnt/1TB/pmos/linux-fp3 — NOT the sensor worktree, whose
q6afe.c lacks the voice-category ADSP_EALREADY handling; .ko hot-swapped,
originals in .ko.bak). Kernel #62-fp3. Boot 14:57 local.
- Boot capture: UCM probe at ~25.3-31.4 s cycles port 0x1016 (+0x4001 TX once);
  ALL AP-side calls balanced: 11 port_start / 11 port_stop, 11 adm_open /
  11 adm_close+copp_free, 10+1 asm opens closed. Latch still engages (count
  froze at 63, exit>enter) ⇒ NOT an unbalanced AP-side teardown.
- ☠️ RPM master-stats counters SURVIVE an AP reboot (RPM keeps running):
  per-boot behaviour must be read as deltas, not absolutes.
- ☠️ rpm_master_stats did NOT autoload this boot — modprobe by hand.
- exp1 (sensors stopped+rmmod smgr*, SSR): audio re-probed after SSR
  (balanced), latch re-engaged. CONFOUNDED: snsregd was stopped too.
- exp2 (audio daemons also stopped, SSR, nothing re-opens): +3 sleeps during
  SSR then frozen at 67. Still latched with NO AP sessions at all. CONFOUNDED
  same way (registry down; ADSP sensor PD may busy-wait on it).
- exp3 (snsregd back UP, audio down, SSR): +7 sleeps during bring-up, then
  frozen at 74 ⇒ registry alone does not fix it; plain ADSP bring-up +
  AP reattach latches. Next suspect: SLIMbus NGD re-enumeration / wcd9335
  reattach (the NGD controller runs on the ADSP).
- exp4 IN FLIGHT: card+wcd9335+regmap_slimbus+slim_qcom_ngd_ctrl rmmod-ed,
  then SSR — if LPASS duty-cycles, the SLIMbus side is the holder.
- Separate NEW lead (do not lose): `apcs-cpu0/cpu4-pll failed to enable!`
  wait_for_pll WARNs from sugov, 346× on the previous boot, recurring and
  quickening this boot. First seen after the 08-17 RPM-handshake fix made
  cluster power-collapse real ⇒ likely relock fallout of APSS PC and/or the
  smd-rpm XO sleep-vote EXPERIMENT commit. Needs its own investigation.
- Phone audio is torn down for these experiments (irq-143 trap makes rebind
  impossible) — REBOOT restores; r62 package exists but do NOT install while
  the instrumented .ko-s are the measurement.

## Second-latch: where the ladder ended (2026-08-21 ~14:45)
- exp4: SSR with NO slim-ngd and NO sensors → LPASS enters XO shutdown and
  STAYS down (cores 0x0) ⇒ the holder is on the SLIMbus/NGD side.
- Fresh boot with ONLY `install snd_soc_wcd9335 /bin/false` (NGD up, the
  physical codec enumerated as 217:1a0:0:0 + 217:1a0:1:0, sensors up):
  LATCHED (count frozen at 2, cores 0x1) ⇒ an enumerated-but-driverless
  SLIMbus satellite is sufficient to hold the ADSP awake; wcd9335 driver code
  is NOT required for the latch.
- Unifying candidate (UNPROVEN for the full-stack case): every latched
  configuration had the codec effectively unmanaged — post-SSR re-attach
  breaks anyway (irq-143 leak), driverless boot by construction. Full-stack
  UCM-probe latch might be the same mechanism if stream teardown leaves the
  satellite/bus state the NGD keeps servicing. Needs a boot-matrix.
- Live-reattach traps (measured): a re-modprobed slim_qcom_ngd_ctrl never
  re-probes (waits for a PDR cycle that only happens with the driver present
  at ADSP boot); a late `modprobe snd_soc_wcd9335` fails with
  "Failed to get logical address".
- ☠️ Instrument traps: RPM master-stats counters SOMETIMES survive an AP
  reboot (56→63) and sometimes reset (97→2) — only deltas within one boot are
  meaningful. `rpm_master_stats` does not autoload. Multi-step fp3-ssh scripts
  die on link drops — run them as `systemd-run --unit=... --collect` device-side.
- NEXT (continuation): scripted boot-matrix over {wcd9335 blocked/up} ×
  {sensors blocked/up} × {card blocked/up} reading LPASS deltas at 3+5 min;
  then read qcom-ngd-ctrl.c/slim core for clock-gear/runtime-PM handling of
  idle vs unmanaged satellites; oracle: UT's NGD sleeps 4344× with the same
  hardware. Fix direction is bus-side, not codec-side.

## CORRECTED picture (2026-08-21 ~15:00, clean boot 14:42)
The 14:42 boot accidentally ran WITHOUT any session audio (leftover
exp2 `autospawn = no` + stopped pulse frontend ⇒ nothing ever probed the
card; dmesg had ZERO LPASSDBG lines) — and with the full driver stack
(wcd9335 attached, sensors up) LPASS reached XO shutdown and STAYED down
(count 47 stable, cores 0x0, enter>exit) from ~14 min uptime. Three states
now separate cleanly:
1. wcd9335 driver ATTACHED + no PCM session ever → ADSP sleeps permanently
   (GOAL state; also exonerates sensors — smgr ran the whole time).
2. codec enumerated but DRIVERLESS (or broken post-SSR re-attach) → latch.
3. after a PCM session (UCM probe or any open/close) → ADSP awake for a
   long hold; whether it EVER releases is being measured right now
   (device-side logger /tmp/lpass-release.log, 30 s × 25 min, one 4 s
   speaker-test session closed 15:01:16 as the trigger; route via
   `amixer cset "SLIMBUS_0_RX Audio Mixer MultiMedia1" 1`, FE open fails
   -22 without it).
☠️ The morning "one-way latch" verdicts rested on minutes-long sampling
windows; a slow release (>8 min) would have looked identical. Do not carry
"one-way" forward until the release logger says so.

## SMOKING GUN (2026-08-21 15:31, boot 15:29)
- A single manual FE session (route on → 4 s speaker-test → route off)
  releases the ADSP in ≤14 s and it stays down 25 min (logger proof).
  The UCM probe does NOT release ⇒ the latch is state the session
  userspace LEAVES ON, not the session itself.
- Live DAPM scan while latched: the ONLY On widgets on the whole card are
  **aw8898.4-0034: IN, SPK PA, OUT** (in 1 out 1) — the speaker amp path
  stays powered after the UCM probe (matches the morning observation).
  NEXT: find the kcontrol gating this path (UCM "Speaker" switch /
  machine-level route), toggle it off live, watch LPASS release within ~30 s;
  then the fix is UCM (turn the switch off when idle) and/or the aw8898
  driver's DAPM (why does closing the stream not power it down —
  compare stream-widget vs pin-switch; likely an always-on pin switch left
  enabled by ucm2).
- ☠️ /tmp is tmpfs — the pre-UCM alsactl snapshot died with the reboot;
  store reference states under /home or pull to host immediately.
- DAPM scan needs `find` + proper quoting: the card dir is "Fairphone 3"
  (space); a naive glob silently matches nothing.

## Single-session bisect (2026-08-21 15:35–15:56) — ALL SINGLE SESSIONS CLEAN
Virgin boot vehicle: `/etc/pulse/client.conf.d/00-noautospawn.conf`
(`autospawn = no`) ⇒ nothing probes the card, LPASS asleep from ~1 min.
Trigger recipe: FE open fails -22 without a route; set route via amixer cset,
play/record, sample LPASS (grep master_stats) ~3× 50 s.
- SLIMBUS_0_RX playback, route turned OFF after: sleeps ≤14 s, 25 min proof.
- Same, route left ON: still sleeps (+6 count then down) ⇒ leftover RX route innocent.
- QUIN_MI2S_RX (0x1016, the speaker/aw8898 BE, the probe's dominant port):
  +3 count then down ⇒ innocent. NO set_lpass_clock calls at all (MI2S clocks
  not via q6afe here).
- VoiceMMode1 open (needs voice routes set; read errors EINVAL — voice PCM is
  control-only): port 0x4001 start+stop, sleeps ⇒ WEAK negative (full
  MVM/CVS/CVP chain may never build without a real trigger).
- Capture arecord plughw:0,1 with TX routes: INVALID negative — no q6 calls at
  all reached the DSP (check dmesg LPASSDBG before believing any such run).
- ★ LIVE REPRO: starting pulseaudio on a sleeping boot (rm the noautospawn
  conf, `sudo -u fp3 XDG_RUNTIME_DIR=/run/user/10000 pulseaudio --start`)
  runs the UCM probe (~105 q6 calls) and LATCHES (count frozen 77, cores 0x1,
  4+ min) — reboot NOT needed to reproduce.
- Post-hoc lever tests all fail (turning off the 5 leftover controls does not
  release) — consistent with a one-way DSP-side latch; only prevention tests
  are meaningful.
- Leftover-ON controls after UCM probe (for reference): AIF1_CAP Mixer SLIM
  TX0, DMIC MUX0, MultiMedia2 Mixer SLIMBUS_0_TX, QUIN_MI2S_RX Audio Mixer
  MultiMedia1, RX HPH Mode. DAPM-On islands while latched: ONLY aw8898
  IN/SPK PA/OUT (static always-complete path IN→SPK PA→OUT, no kcontrol —
  separate lead: ties to the amp-death invariant ~24.5 s ≈ UCM probe time).
- NEXT (the bisect converges here): on a virgin boot reproduce the latch with
  pieces of the UCM probe: (a) REAL capture session on SLIMBUS_0_TX/AIF1
  (fix the arecord so q6 calls appear), (b) genuine voice trigger (full
  MVM/CVS/CVP build-up), (c) multiple simultaneous FE sessions, (d) the exact
  UCM verb sequence via alsaucm. Each followed by 3×50 s LPASS samples.
  Instrument gap: q6voice (mvm/cvs/cvp) has NO LPASSDBG prints yet — add if
  (b) is suspected.

## ★★★ 2026-08-21 16:04 — THE LATCH PIECE FOUND: real SLIMBUS_0_TX capture

Test (a) of the NEXT plan, on the 15:51 boot (voice-open had run on it and left
LPASS asleep, count 49 / cores 0x0 — valid virgin-equivalent baseline):

- Script (root, /tmp/cap-test.sh on phone): set `MultiMedia2 Mixer SLIMBUS_0_TX`
  + `AIF1_CAP Mixer SLIM TX0` + `SLIM TX0 MUX`=DEC0 + `ADC MUX0`=DMIC +
  `DMIC MUX0`=DMIC0, then `arecord -D hw:0,1 -f S16_LE -r 48000 -c 1 -d 5`,
  then all routes back off. arecord rc=0, 480 kB real data.
- dmesg proof the DSP was reached AND the teardown was balanced:
  port_start 0x4001 → adm_open port 0x3 path 2 → port_stop 0x4001 →
  asm_cmd close → adm_close → adm_copp_free. Nothing left open on the AP side.
- LPASS after (3×50 s + 2 min confirm): **exit (13252438482) > enter
  (2193640501), Active cores 0x1, count frozen at 49** — LATCHED.

⇒ **Playback (RX) never latches; one real capture session (TX) latches, even
with a fully balanced AP-side teardown.** The UCM probe latches because it opens
the capture path. The earlier "capture innocent" run was the INVALID one (no q6
calls); this run is the valid measurement.

Next bisect within capture (each needs a virgin reboot, prevention-style):
1. FE-only: `MultiMedia2 Mixer SLIMBUS_0_TX` alone, NO codec-side controls
   (no AIF1_CAP/DMIC) + same arecord → separates QDSP ASM/ADM/AFE-TX from the
   WCD9335/SLIMbus TX channel path.
2. If FE-only stays clean: codec-side TX routes alone (no arecord) — does the
   SLIMbus TX channel allocation latch without any FE session?
3. Suspects by layer: AFE SLIMBUS_0_TX port (0x4001) vs ADM TX copp vs the
   slim TX channel map on the NGD — the voice-open control test also did
   port_start/stop 0x4001 WITHOUT latching, so the bare AFE port is likely
   innocent; prime suspects are the ASM read session / ADM path 2 / SLIM TX
   data channel.

## ★★★ 2026-08-21 16:21 — Latch lever narrowed to the ACTIVE SLIMbus TX data channel

Three prevention tests on one virgin boot (16:09, count 42→…, all baselines
asleep before each test):

| test | q6 chain | SLIM TX data | result |
|---|---|---|---|
| FE-only capture (`MultiMedia2 Mixer SLIMBUS_0_TX` only, no codec routes; arecord errors at 1.4 s, 44-byte wav) | full (port 0x4001, adm path 2, asm) | none | **clean** (47→53, sleeps) |
| codec TX routes only (AIF1_CAP/SLIM TX0 MUX/ADC MUX0/DMIC MUX0), no FE session | zero q6 calls | none | **clean** (53→55, sleeps) |
| full capture with **AMIC** instead of DMIC (rc=0, 480 kB real data) | full, balanced teardown | **5 s active** | **LATCHED** (count frozen 55, cores 0x1) |

Combined with the earlier DMIC-routed capture latch: **any real TX stream
latches (DMIC and AMIC alike, so the DMIC clock is exonerated); neither the
QDSP session objects nor the codec register routes alone do. RX streams never
latch.** The lever is the active SLIMbus TX (source) data channel — the
ADSP-side XO vote taken when a TX channel is activated is never dropped by the
teardown, while the RX equivalent is.

Where to look next (source): TX-vs-RX asymmetry in SLIMbus stream teardown —
`drivers/slimbus/stream.c` (slim_stream_disable/unprepare/free: are source
pipes' channels deactivated/removed the same way as sink pipes?) and
`drivers/slimbus/qcom-ngd-ctrl.c` (NGD channel dealloc messages), plus the
wcd9335 hw_free/shutdown for the capture DAI (slim_stream API usage for
AIF1_CAP). The fix would be upstreamable (audio category? it is the capture
path of the codec — likely `wip/<base>/audio`).

## Phone state right now
- pmOS slot, charging OK. Blacklist file ACTIVE (no sound card, no smgr!),
  watchers disabled, fp3+greetd pipewire masked, autospawn=no. Audio dead
  until step 2+3 reboot. Modem/MM fine. rmtfs untouched.
- ☠️ never reboot with USBIN suspended (check `pmi632-charger/status` = Charging).

## Earlier today (already committed/pushed, no action)
- MM leg valid: ~10 % (e5473f5); MPSS duty-cycle probe: 37 % XO hold =
  network territory (2f670f2); LPASS milestone (aae124e).
