<!-- AI-generated (Claude Fable 5.1) under the direction of Lajosházi, László Gergely. -->

# Review of the six `wip/7.1.3/*` branches and the eight `upstreaming/*` series

**As of 2026-09-03.** Every claim below rests on a command run against
`/mnt/1TB/pmos/linux-fp3`; where it rests on a project record instead, the record is
named. Nothing has been sent to any list; all eight series still carry b4's `EDITME`
cover template, and the `Rounds` tables on [`STATUS.md`](STATUS.md) are empty. So
nothing below has cost anything yet — the point of the review is that it stays that
way.

## 0. What was reviewed, and how

- The cumulative diff `origin/7.1.3/main..wip/7.1.3/<cat>` for all six categories
  (13 316 diff lines), read in full.
- The 34 patches on the eight `upstreaming/*` branches: trailers, authorship,
  patch-id against `wip`, line-set against `wip`, non-ASCII content, leftover
  comments, and the diff of each against its own b4 base.
- Every `wip` branch has the current base tip as its merge-base — so the
  cumulative diffs are our work and nothing else. (Checked, because one of them
  looked like base drift; it was not — see B1.)

## 1. Blockers — these would embarrass the sender on the list

Ordered by how badly.

### B1. The IMX363 "unchanged import" deletes two other drivers and breaks two more

`upstreaming/imx363-camera` commit `7b5eb48928cd` (`media: i2c: add the Sony IMX363
image sensor driver`, author Joel Selvaraj) says in its message: *"imported here
unchanged"*, *"byte-identical to the source commit. Nothing in this commit is new
work."* Its stat is `3 files changed, 1527 insertions(+), 30 deletions(-)`, and
the 30 deletions are:

- `config VIDEO_OV2732` — the whole block, and its `obj-$(CONFIG_VIDEO_OV2732)`
  Makefile line: **the OmniVision OV2732 driver is removed from the build**;
- `config VIDEO_T4KA3` — likewise, block and Makefile line: **the Toshiba T4KA3
  driver is removed from the build**;
- `select V4L2_CCI_I2C` stripped from `VIDEO_OG01A1B` and `VIDEO_OV9282` —
  **two drivers that use the CCI helpers lose the symbol that provides them**;
- the `VIDEO_DS90UB960` help text reverted to an older wording.

Cause: the import took `drivers/media/i2c/Kconfig` and `Makefile` **wholesale**
from the sdm670-mainline tree, whose upstream base predates those four drivers,
instead of adding only the IMX363 hunk. The same defect is on
`wip/7.1.3/camera` (`cda174905a83`, 25 deletions), so regenerating the series
does not fix it — the `wip` commit has to be rebuilt.

Why this is the worst item: a maintainer applying the series would see four
unrelated drivers regress in patch 1, under a commit message that certifies the
patch changes nothing. The provenance work around this commit is otherwise
exemplary, which makes the false certification land harder, not softer.

**Fix:** on `wip/7.1.3/camera`, redo the import commit so it adds `imx363.c`
plus *only* the IMX363 `config`/`obj-` lines (diff against the base must show no
`-` lines in Kconfig/Makefile), keep Joel's authorship and the citation, then
regenerate the series.

### B2. `Assisted-by:` on somebody else's byte-identical commit

The same `7b5eb48928cd` carries `Assisted-by: Claude:claude-opus-5` under Joel
Selvaraj's authorship. The tool assisted in *rewriting the commit message*, not in
producing the code — and `Assisted-by` is a statement about the change. On an
import it tells the maintainer that an AI helped write Joel's driver. **Fix:**
drop the trailer from the import commit; disclose the message rewrite in the
cover letter, where the `generated-content.rst` disclosure lives anyway.

### B3. A patch that competes with a posted one

`50e424881f1e` (`ASoC: q6afe: treat ADSP_EALREADY as success when starting a
port`) is in `wcd9335-audio`. Otto Pflüger's still-`new` v2 4/4 (`ASoC: qcom:
q6afe: remove "port already open" error`, 2023-10-29) is the same fix — STATUS.md
says so itself and says it must not go out unanswered. It is still in the series.
**Fix:** drop it from the series (14 patches); reply on Otto's thread with a
Tested-by and the measurement.

### B4. `smb5-charger` does not build on the tree it targets, and the record does not say so

`include/linux/thermal.h` on `next-20260902` has
`devm_thermal_of_cooling_device_register(struct device *dev, u32 cdev_id, ...)`;
the series still passes `dev_of_node(chip->dev)`. The linux-next integration
silently **omits** the cooling-device patch (`793bef280420` has no twin on
`upstreaming-int/next-20260902`), so what was built is not what would be sent.
STATUS.md still says `rebased` and records neither fact. **Fix:** adapt on
`wip/7.1.3/charger` (the fork base will get the same API at the next bump),
regenerate, and write the failed build into the series' `Test:` block with the
date.

### B5. `i2c-qup-pinctrl` sits on a tree tip that has not moved since 2026-06-18

Upstream has since changed `qup_i2c_enable_clocks()` to return an error, and the
series' resolution differs from the integration's (patch-id `DIVERGED`). **Fix:**
re-cut on the current `i2c-host` tip (or linux-next), and take the `Fixes:` from
`git blame` on torvalds/master.

### B6. Provenance and identity gaps

- `a914aa40e576` (`take the mic bias voltage and DMIC clock rate from the DT`)
  names no source for its values, which come from Fairphone's downstream
  `msm8953-audio.dtsi`. The `msm8953-mainline-pr` skill uses this very patch as
  its worked example of an uncited import; it is still uncited. **Fix on `wip`,**
  then regenerate.
- `62292a23d4fa` carries `Assisted-by: Claude:claude-fable-5`. No such model id
  exists; the model is `claude-fable-5-1`. A fabricated identifier in the
  disclosure trailer is precisely what a reviewer will poke at.

### B7. Leftovers in the IMX363 driver that the "remove commented-out code" patch did not remove

On the series tip, `drivers/media/i2c/imx363.c` still has:
`636000000ULL, // NOT SURE HOW TO FIND THIS VALUE` (line 438), `3136 //0c40`
(line 28), and four `// analog cropping` / `//subsampling` style comments. The
skill names the `NOT SURE` line as the one that contradicts any claim of measured
values. Also in the FP3 fix-up patch `8285a9cfaecd`:
`regulator_set_voltage(vdig, 1175000, 1175000)` — a rail voltage, which is the
board's regulator constraint, not the driver's; `msleep(200)` justified as *"On
the FP3 the GPIO-switched camera rails settle slowly"*; and a five-try chip-id
warm-up loop explained by *"the FP3's cold first-I2C-transaction timeout"*. Three
board facts inside a generic sensor driver. **Fix:** move the voltage to the
board's `l2` constraints, state the delays as the sensor's datasheet timing or
drop the board name from the comment, and either justify the retry loop by the
bus or remove it.

## 2. Test-only and experimental content in `wip` — must never travel

All of it is already outside every series; this is the list that makes that
deliberate rather than accidental.

| branch | what | evidence |
|---|---|---|
| power | `clk-smd-rpm.c` `xo_sleep_off` module parameter | comment: *"EXPERIMENT, not a fix. Do not send this upstream"* |
| power | `icc-rpm.c` `sleep_init` and `sleep_bw_off` parameters, `qnoc_pm_ops`, and the `.pm` hookup in `msm8953.c` | comment: *"experiment (sleep_bw_off) … May wedge resume"* |
| power | `qcom_smd-regulator.c` `both_sets` parameter | comment: *"Experiment knob, boot-time only"* |
| power | `smd-rpm.c` + `include/trace/events/qcom_smd_rpm.h` tracepoint | instrumentation; acceptable upstream in principle, but not part of any fix |
| power | `apcs-msm8953.c` PLL/idle hold (124 lines) | patches a file that does not exist upstream |
| audio | the two SLIMbus framer commits and their revert | net zero in the cumulative diff |
| power | the FP3 DTS sleep-set commit and its revert | net zero |
| audio | `snd-soc-aw8898.c` (48 lines) | driver not upstream |
| voice | `q6voice-dai.c` (19 lines) | driver never posted upstream |

## 3. Content to leave out of the sendable set (unsendable or untested)

| where | what | why |
|---|---|---|
| sensor | the QRTR bus, SMGR core, accel driver and everything on them (~2 775 lines) | Yassine Oudjana's work, in flight as D-3; two of his commits still carry `WIP:` subjects. Not ours to send. Our prox/light channel is the piece to *offer* him |
| sensor | our gyro and magnetometer drivers | the mag scale comment says it is *"two assumptions deep"* and unverified; gyro is fine but shaped like his v1, which he abandoned on review |
| camera | `s5k4h7.c` bring-up driver | *"identifies the sensor and registers no subdevice"* — a driver that does nothing is dead code upstream |
| camera | `lc898217.c` + binding | the actuator is not on this phone's module (bus scan: nothing at 0x72); untested hardware does not get enabled |
| audio DTS | `DMIC4`/`DMIC5` and `AMIC5` routes and mic-bias pairs | the project's own measurement (`project_fp3_mic_topology`, 2026-08-02) found DMIC4/5 and AMIC5 exactly silent: two DMIC pairs plus the headset AMIC2 exist. *Only what is measured goes into the DTS* |
| audio DTS | `slimbam` and `slim_msm` nodes in the **board** DTS | SoC-level hardware; belongs in `msm8953.dtsi` as its own patch |
| audio DTS | `cdc_reset_active` pinctrl with `output-high`, `interrupt-parent`+`interrupts` | pin *levels* are the driver's (`reset-gpios`), not pinctrl's; use `interrupts-extended` |
| charger DTSI | 48 `interrupt-names` on `pmi632_charger` | the binding — on the series too — allows four; `dtbs_check` fails. Either the binding describes the hardware's full interrupt set, or the node lists what is consumed |
| charger DTS | the long bring-up comments (register dumps `0x12e2`…, connector-thermistor history) | not device-tree content; move to `docs/` |
| charger driver | the fuel-gauge (QG) work, ~1 450 lines | reads and **writes** peripherals outside the charger node's `reg` (QG at 0x4800, SDAM at 0xb100); upstream will want the gauge as its own node and driver. Correctly has no series yet — the decision now has a reason |

## 4. Sendable work that the "left out" tables call "not upstream-shaped"

The `power` leave-out table lumps experiments with fixes. These patch files that
exist in Linus' tree, are shaped like upstream patches, and have measurements
behind them:

| file(s) | change | tree |
|---|---|---|
| `drivers/pinctrl/qcom/pinctrl-msm8953.c` | the MPM `wakeirq_map` (14 lines) | pinctrl (Linus Walleij / Bjorn) |
| `drivers/irqchip/irq-qcom-mpm.c` | program the vMPM wakeup timer before hand-over; suspend-safe time accessor; drop the one-second cap | irqchip |
| `drivers/rpmsg/qcom_smd.c` | edge IRQ as a (disabled-by-default) wakeup source; do not tear the wakeup source down twice | rpmsg |
| `drivers/regulator/qcom_smd-regulator.c` | `set_suspend_enable/disable/voltage` ops (without the `both_sets` knob) | regulator |
| `drivers/soc/qcom/smsm.c` + `qcom,proc-awake-bit` | mirror suspend into the SMSM "AP awake" bit — **needs a binding patch**, none exists | qcom SoC |
| `arch/arm64/boot/dts/qcom/msm8953.dtsi` | `domain-idle-states` rename, drop `local-timer-stop` from domain states, `system_pc` + `system_pd`, MPM node + pin map, `rpm-master-stats`, `rpm-stats`, `wakeup-parent` | qcom DTS |
| `sound/soc/codecs/msm8916-wcd-digital.c` | hold mclk only while a stream runs | ASoC |
| `drivers/slimbus/qcom-ngd-ctrl.c` | implement `disable_stream` | slimbus |
| `drivers/media/platform/qcom/camss/*` | RDI write-master line stride (228 lines) | media |
| `drivers/leds/flash/leds-qcom-flash.c` + binding | two-channel PMI632 | LEDs |
| `drivers/media/i2c/ak7375.c` | runtime-PM rework (power for a position, retry the first transfer, park on last close) — measured 0.30 W | media |

Each needs the same treatment the eight series got: `get_maintainer.pl`, a trial
rebase, a `Fixes:` where it is a fix. None of it is blocked by D-1/D-2/D-3.

## 5. Per-series review notes — the questions a maintainer will ask

**wcd9335-audio (15 → 14 after B3).**
Sound: the TX front-end hold release (capture is silent on every WCD9335 board
without it), the version-read check (reads uninitialised stack today), the list
heads (NULL dereference), the SLIMbus UP/DOWN teardown, the OCP interrupts, the
shared-MBHC refactor ordered refactor → implementation → API. Expect:
(a) `wcd9335_mbhc_init()` hard-codes `HSDET_PULLUP_CTL_1_2P0_UA`,
`BD_ISRC_100UA`, `HS_VREF_1P5_V` with a comment saying *"on this board"* — if it
is the board's, it is a DT property; if it is the codec's default, say so and
drop "this board"; (b) the jack is created in the codec, with a fixed
`KEY_MEDIA/VOICECOMMAND/VOLUMEUP/VOLUMEDOWN` map — every other qcom board does
this in the machine driver; the justification (the generic card only hands its
jack to MI2S codecs) must be in the cover letter; (c) `wcd9335_mbhc_map_irqs()`
fills a struct through `offsetof()` arithmetic where seven assignments would do;
(d) the `do { cross_conn = …; } while (try < swap_thr)` loop keeps only the last
result; (e) `pm_runtime_get_sync()` + `put_noidle()` copies the file's existing
idiom, which reviewers now ask to be `pm_runtime_resume_and_get()`; (f) the
legacy backend is *"ported from the downstream implementation"* — expect the
question whether it is a rewrite or a copy, and have the diff ready.
`qcom,dmic-sample-rate` and the `micbias*-microvolt` names are prior art
(lpass-*-macro, wcd934x, wcd938x bindings) — good.

**smb5-charger (6).** Sound: the `smb_variant` generalisation, JEITA, battery-ID
verification, the `I_TERM_BIT`/recharge-field findings measured against the
vendor stack. Expect: (a) **raw ADC codes as DT thresholds**
(`qcom,jeita-*-thresholds = <0x5675 0x1987>`) — the binding argues codes are the
only expressible form; reviewers will ask for temperatures and a conversion in
the driver, since the pull-up and full scale are known; (b)
`qcom,thermal-mitigation` as a table of currents — expect "why not the standard
cooling-device states"; (c) the battery supply is named `"pmi632-battery"` in a
driver that has a variant name field; (d) an em-dash in a C comment
(`ae5496758fe2`); (e) B4.

**imx363-camera (7).** Beyond B1/B2/B7: `reset-gpios = <… GPIO_ACTIVE_HIGH>` with
the driver writing 1 to *release* reset — XCLR is an active-low reset, so the DT
flag states the electrical level, not the logical one; the skill records
Krzysztof Kozlowski's FP5 ruling on exactly this. `clock-frequency` alongside
`assigned-clock-rates` is redundant. The `mode_common_regs` table is
reverse-engineered downstream register writes; the commit says so, which is the
right disclosure — expect Sakari Ailus to ask about each undocumented register.

**psci-cpuidle-fixes (2).** Moving `psci_idle_init` to `late_initcall_sync` is a
hammer; the comment explains why a faux device cannot defer. Expect Ulf Hansson
to ask whether the PM-domain provider should not be made to probe earlier
instead. Have the measurement (which domain, which driver it waited on) in the
message. The `bool` → `unsigned int` fix is clean; find its `Fixes:`.

**adc5-bat-therm (1), gcc-msm8953-csiphy (1), qmi-encdec-fix (1).** Correct and
small — which is the risk: an `Assisted-by:` on a two-line patch drew *"It's
becoming ridiculous"* on 2026-05-30. Each message must carry the measurement that
makes it non-trivial (the wrong parent map's effect, the three-byte over-read's
symptom, the missing channel's consequence). `adc5` should travel inside
`smb5-charger` with the IIO maintainer's Ack rather than alone.

## 6. Order of work

1. **B1** — rebuild the IMX363 import on `wip/7.1.3/camera`; nothing from that
   series goes anywhere before this.
2. **B2, B6** — trailer and citation fixes, on `wip`, then regenerate.
3. **B3** — drop the q6afe patch; reply on Otto's thread (D-2).
4. **B4, B5** — re-cut `smb5-charger` and `i2c-qup-pinctrl` on current tips;
   record the build result.
5. **B7** and the §3 DTS items — before `fp3-dts` is cut.
6. **§4** — re-triage `power` into series; add the `qcom,proc-awake-bit` binding.
7. The **§5** cover-letter material: every "expect" above is a paragraph the
   cover letter answers before it is asked.

## 7. What the review found sound

- 34/34 patches: human `Signed-off-by`, no AI `Signed-off-by`, no
  `Co-authored-by` leftovers.
- Six of eight series are line-set identical to their `wip` category on the
  paths they touch (audio 1081, i2c 13, adc5 2, csiphy 6, psci 12, qmi 17);
  imx363 is a clean subset; smb5 differs only in line wrapping.
- The `upstreaming-int/next-20260902` integration is local only and keeps
  Adam Skladowski's and Vladimir Lypak's authorship on the D-1 patches — right for
  a test integration, and it must stay a test integration.
- The `wip` branches are all on the base tip; the discovery-order history is
  intact, including the reverts that make the experiments net zero.
- `wcd9335-audio` is, B3 aside, the strongest series here: three of its patches
  fix bugs every WCD9335 board has.
