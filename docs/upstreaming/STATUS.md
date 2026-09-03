# Upstreaming — status

> ⚠️ **AI-generated.** This page was written by Claude (Fable 5.1) under the
> direction of Lajosházi, László Gergely. It is **state only** — every row
> carries the date of the evidence it rests on. The method (what each field
> means, when a state may change, the b4 commands) is in the
> `msm8953-mainline-pr` skill; the analysis of *why* something is blocked is in
> [`README.md`](README.md).

Rules of this page: no state change without its evidence link; every row dated
with the date of the evidence, not of the edit; the merge-window state is never
written here (run the `releases.json` check before a send); a v(N+1) goes out
only when every "asked for" item of the last Rounds row is handled or disputed
with a link.

| series | category | tree | patches | state | last round | ball with | next from us | updated |
|---|---|---|---|---|---|---|---|---|
| wcd9335-audio | audio | ASoC `sound/for-next` | 14 on `upstreaming/wcd9335-audio` | rebased | – | us | checker gauntlet per patch; functional run from the submission base; then the cover letter | 2026-09-03 |
| i2c-qup-pinctrl | audio | i2c-host `i2c/i2c-host-next` | 1 | rebased | – | us | `Fixes:` from blame; decide `Cc: stable` | 2026-09-03 |
| psci-cpuidle-fixes | power | linux-pm `bleeding-edge` | 2 | rebased | – | us | checker gauntlet; then the cover letter | 2026-09-03 |
| smb5-charger | charger | power-supply `for-next` | 6 | rebased | – | us | every board/battery fact out of the driver; `adc5-bat-therm` goes first or with it | 2026-09-03 |
| adc5-bat-therm | charger | IIO `togreg` | 1 | rebased | – | us | prerequisite of `smb5-charger` — decide whether it travels with it | 2026-09-03 |
| imx363-camera | camera | media `next` | 7 | rebased | – | us | reorder binding before driver; then the checkers | 2026-09-03 |
| gcc-msm8953-csiphy | camera | clk `clk-next` | 1 | rebased | – | us | `Fixes:` from blame; it is a fix, not an enablement | 2026-09-03 |
| qmi-encdec-fix | sensor | qcom `for-next` | 1 | rebased | – | us | `Fixes:` from blame on torvalds/master | 2026-09-03 |
| q6voice | voice | ASoC | 1 | unsendable | – | – | the driver it patches was never posted upstream (patchwork: nothing for "q6voice"); revisit only if a q6voice driver appears on the list | 2026-09-03 |
| fp3-dts | all | qcom SoC (`arm64: dts: qcom`) | – | preparing | – | us | sent last; depends on every driver/binding series above having landed | 2026-09-03 |
| qcom-mpm-wakeup-timer | power | irqchip (tglx) | 1 (from 3) | planned | – | us | cut on `tip/irq/core`; squash the three `wip` steps into the one shape upstream never had | 2026-09-03 |
| pinctrl-msm8953-mpm | power | pinctrl (Linus W. / Bjorn) | 1 | planned | – | us | cut on `pinctrl/for-next` | 2026-09-03 |
| qcom-smd-wake | power | rpmsg (Bjorn, Mathieu) | 1 (from 2) | planned | – | us | fold the double-teardown fix into the wake-IRQ patch (bisect rule) | 2026-09-03 |
| smsm-proc-awake | power | qcom `for-next` + DT binding | 2 | planned | – | us | write the binding first; ask whether the bit belongs in DT or in per-SoC match data | 2026-09-03 |
| msm8953-dtsi-idle | power | qcom SoC (`arm64: dts: qcom`) | ≤ 9 | planned, one patch held | – | us | after the three driver series above; **`system-pc` affinity patch held** on Bert's touch regression (#142) | 2026-09-03 |
| wcd-digital-mclk | power | ASoC (Srini, Mark) | 1 | planned | – | us | cut on `sound/for-next` | 2026-09-03 |
| ngd-disable-stream | power | slimbus (Srini) | 1 (from 2) | planned | – | us | squash the alignment fixup | 2026-09-03 |
| camss-rdi-stride | camera | media (Bryan O'Donoghue) | 1 | planned | – | us | cut on `media/next`; name the libcamera half in the cover | 2026-09-03 |
| qcom-flash-pmi632 | camera | LEDs (Lee Jones) + DT binding | 2 (from 3) | planned | – | us | binding, then driver with the Kconfig text folded in | 2026-09-03 |
| ak7375-pm | camera | media (Sakari Ailus) | 3–4 (from 6) | planned | – | us | AK7374 id as its own patch; the PM rework squashed to its final shape; `Fixes:` only where blame on `master` supports it | 2026-09-03 |
| qcom-smd-regulator-suspend | power | regulator (Mark) | 1 | held | – | – | mechanism proven on one rail, **no power win measured** and the board opt-in was reverted — a sendable op with no user; revisit when a rail is measured off-in-suspend | 2026-09-03 |

Patch counts: `gh api repos/llg179org/linux/compare/7.1.3/main...submit/7.1.3/<cat> --jq .total_commits`, 2026-09-03, except `wcd9335-audio`, whose count is now its own series branch. The `submit/7.1.3/*` branches are the **legacy** namespace; each will be tagged `archive/submit-7.1.3-<cat>-final` and replaced by the `upstreaming/<series>` branch named in its section. Until then the `Source:` field names the legacy branch so the content stays findable. All seven `submit/7.1.3/*` branches are tagged `archive/submit-7.1.3-<cat>-final` and superseded, but **none is deleted** — deleting them is a separate call.

☠️ A cut series does not carry everything its category does. Each section's **Left out** table names what stayed behind and where it goes; the sum of the `upstreaming/*` series plus those tables is what reproduces the category.

☠️ **A legacy branch was not one series.** Cutting the six remaining `submit/7.1.3/*`
branches on 2026-09-03 found the categories hiding **two extra destination trees**:
`adc5-bat-therm` (IIO) came out of `charger`, and `gcc-msm8953-csiphy` (clk) came out
of `camera`. Both are on this page now. The lesson for the next category: group the
commits by what `get_maintainer.pl` answers, not by which of our branches they sat on
— our categories are bring-up areas, upstream splits by subsystem.

☠️ **And two bodies of work came out with no series at all**: the fuel-gauge half of
`wip/7.1.3/charger` (~1450 lines) and the `ak7375.c` runtime-PM rework (~91 lines).
Neither is a decision that was made; both are named in their sections' To do. Until
they are resolved this page understates what the fork carries.

---

## wcd9335-audio

```
Category:    audio
Tree:        ASoC, sound/for-next — Mark Brown, Srinivas Kandagatla; CC alsa-devel, devicetree (binding), linux-arm-msm
Source:      upstreaming/wcd9335-audio — b4 prep branch, cut 2026-09-03 from the
             content of wip/7.1.3/audio; change-id 20260903-upstreaming-wcd9335-audio-5909b6e35e3a
             base-commit 27a50351cbc82e9f0811df417c5e7d2a72f60ef5 (sound/for-next, 2026-09-02)
             legacy: submit/7.1.3/audio, tagged archive/submit-7.1.3-audio-final
             sent rounds: – (none yet)
Depends:     – (nothing this series carries needs D-1; the two patches that did were left out, below)
```

Left out of this series, deliberately (2026-09-03, measured):

| left out | lines | where it goes instead |
|---|---|---|
| `sound/soc/qcom/apq8016_sbc.c` — the SLIMbus-backend and channel-map patches | 140 | blocked on **D-1**: MSM8953 support in `apq8016_sbc.c` is not upstream, so the patch conflicts on `sound/for-next` (cherry-pick, 2026-09-03: `U sound/soc/qcom/apq8016_sbc.c`). Add once D-1 lands, or once the open decision below is made |
| `arch/arm64/boot/dts/qcom/sdm632-fairphone-fp3.dts` | 252 | the **fp3-dts** series — a board DTS is always its own series, sent last |
| `drivers/i2c/busses/i2c-qup.c` | 13 | the **i2c-qup-pinctrl** series — different tree |
| `sound/soc/qcom/qdsp6/q6afe.c` — treat ADSP_EALREADY as success | 30 | **D-2 v2 4/4 is the same fix**; a reply with a Tested-by on Otto Pflüger's thread, not a competing patch |
| `sound/soc/codecs/snd-soc-aw8898.c` | 48 | **unsendable**: the driver does not exist upstream (`torvalds/linux` contents API → 404, 2026-09-03) |

Distillation check, 2026-09-03: on the twelve paths the series does carry, the
line set of `fork/7.1.3/main..wip/7.1.3/audio` and of
`27a50351cbc8..upstreaming/wcd9335-audio` are **identical** — 1220 lines each,
`comm -3` empty. Per-file `--stat` totals match one-for-one.

Test:
```
  branch:    –  (not yet run from a submission base)
  device:    –
  battery:   –
  checkers:  checkpatch ✓ (submit branch, 2026-07-30, README) · W=1 – · sparse – · dt_binding_check – · dtbs_check – · allmodconfig – · linux-next –
```

Rounds:
| v | date | lore | reply (who, when) | asked for | handled |
|---|---|---|---|---|---|
| – | | | | | |

To do:
- [ ] **Tested-by from Bert Karwatzki** — asked 2026-09-03 (reply drafted, #145; the person sends it); he ran `integration/7.1.3` @ `5bc4d5ebb7c0` (2026-08-30) with Debian trixie, call audio works. Goes on the cover and on the patches he exercised once his tag arrives, never before
- [x] ~~the series carries `ASoC: q6afe: treat ADSP_EALREADY as success when starting a port`, and **D-2 v2 4/4 is the same fix**~~ — dropped 2026-09-03, see Done — Otto Pflüger's `ASoC: qcom: q6afe: remove "port already open" error`, message-id `20231029165716.69878-5-otto.pflueger@abscue.de`, posted 2023-10-29 and still `new`. Read it before sending ours; a reply on that thread is more likely right than a competing series
- [ ] the machine-driver patch: decide between waiting for D-1 and posting the generic `q6afe` clock-set change into Otto's/Adam's thread (README "The chain is shorter than it looks")
- [ ] measure the AFE `api_version` this ADSP reports (the one number the q6afe redesign turns on)
- [ ] checker gauntlet per patch; functional run from the submission base with the debug layer on top; fill the Test block
- [ ] cover letter with the `generated-content.rst` disclosure — still b4's `EDITME` placeholder

Done:
- 2026-09-03  ☠️ `ASoC: q6afe: treat ADSP_EALREADY as success when starting a port`
              **dropped from the series** (review B3, queue 138): it is the same fix as
              D-2 v2 4/4, still `new`; the reply goes on Otto Pflüger's thread. The
              series is 14 patches; the only tree difference to the 15-patch tip is
              `sound/soc/qcom/qdsp6/q6afe.c`. Old tip tagged
              `archive/upstreaming-wcd9335-audio-pre-b3b6-20260903`. Moved to Left out
- 2026-09-03  the mic-bias/DMIC patch gained its provenance paragraph **on
              `wip/7.1.3/audio` first** (property names reused from the wcd938x and
              lpass-macro bindings; MICB_VOUT programming from the vendor codec
              driver; the FP3 values from Fairphone's published `msm8953-audio.dtsi`,
              which live in the board DTS, not in the patch), then regenerated here
              (review B6, queue 137). wip content unchanged (tree identical to
              `archive/wip-7.1.3-audio-pre-cite-20260903`); the series patch keeps the
              per-patch checkpatch alignment the cut applied, `checkpatch --strict` clean
- 2026-09-03  ☠️ process incident, recorded because it is the kind that hides: while
              regenerating, a `git checkout <old-tip> -- wcd9335.c` meant to restore two
              aligned lines restored the whole file, the replay conflicted, and a
              5-patch conflict-state branch was force-pushed to `fork` for about a
              minute before the guard (`diff vs old tip touches only q6afe.c`) was
              re-run and the branch rebuilt and replaced. Nothing was sent anywhere;
              the lesson is that the shape check must run *before* the push, not after
- 2026-09-03  `upstreaming/wcd9335-audio` cut with `b4 prep -e` on `sound/for-next`
              27a50351cbc8 (2026-09-02); 15 of the 18 legacy commits, all 15
              cherry-picking clean onto that tip with no conflict. Legacy branch
              tagged `archive/submit-7.1.3-audio-final`; branch and tag pushed to
              `fork`
- 2026-08-29  the argument for the series measured against mainline `master` (no jack support in `wcd9335.c`, six in-tree WCD9335 boards) — README
- 2026-08-30  dependency status measured file by file against `v7.1`; the q6afe finding re-checked on `sound/for-next` — README

## i2c-qup-pinctrl

```
Category:    audio   (the speaker-amp fix; its wip home is wip/7.1.3/audio, there is no wip/7.1.3/i2c)
Tree:        i2c — Andi Shyti; CC linux-i2c, linux-arm-msm
Source:      upstreaming/i2c-qup-pinctrl — b4 prep branch, cut 2026-09-03, re-cut 2026-09-03
             change-id 20260903-upstreaming-i2c-qup-pinctrl-7d3ee5a31cab
             base-commit cee9395acd8043be0644b25c34bfa86623f2b935 (v7.3-rc1; branch upstream torvalds/master)
             ☠️ NOT on andi.shyti's i2c/i2c-host-next: that tip (04e9bf1648f8, 2026-06-18) and
             i2c-host-fixes (dc59e4fea9d8, 2026-06-28) both predate a47762633280 ("i2c: qup:
             Propagate clock enable failures", 2026-07-28), which is in v7.3-rc1 and rewrites the
             resume path this patch touches. A fix goes on the -rc; the destination tree is unchanged
             legacy: submit/7.1.3/i2c, tagged archive/submit-7.1.3-i2c-final
             sent rounds: – (none yet)
Depends:     –
```

☠️ The tree is **Andi Shyti's i2c-host**, not Wolfram Sang's `i2c/for-next` —
`get_maintainer.pl` on `drivers/i2c/busses/i2c-qup.c` answers "I2C SUBSYSTEM HOST
DRIVERS / Andi Shyti", and wsa's `i2c/for-next` is still at `Linux 7.1`
(2026-06-14). Measured 2026-09-03. This also explains the second commit that used
to show on the legacy branch: `i2c: nomadik: Use generic definitions for bus
frequencies` is the **base tip**, not our work.

Left out: nothing — the whole of this series' content is the one 13-line change,
and its line set matches `wip/7.1.3/audio` exactly.

Test: not yet run from a submission base. Checkers: –.

Rounds: none yet.

Done:
- 2026-09-03  re-cut onto v7.3-rc1 (review B5, queue 139): the same 13 added lines as the
              wip twin 490c046b339e, applied over the base's own rewrite of
              qup_i2c_pm_resume_runtime(); `checkpatch --strict` clean; b4 reports the new
              base-commit and the unchanged change-id. Old tip tagged
              `archive/upstreaming-i2c-qup-pinctrl-pre-rebase-20260903`
- 2026-09-03  `Fixes:` decided against: GitHub blame on torvalds/master puts the runtime-PM
              functions in 10c5a8425968 ("i2c: qup: New bus driver for the Qualcomm QUP I2C
              controller", 2014). The driver never selected pinctrl states; nothing regressed.
              This is a missing behaviour exposed by a firmware that resets pads, so it is a
              fix in effect but not of any commit — no `Fixes:`, and therefore no `Cc: stable`;
              the cover letter says so in those words
- 2026-09-03  ☠️ the review's B6 claim that `Assisted-by: Claude:claude-fable-5` names a
              non-existent model is **retracted**: the wip commit's own trailer of 2026-08-21
              reads `Co-authored-by: Claude Fable 5`, so the id follows the model that did the
              work, as the convention requires. The claim rested on today's model list, which
              is not a list of every model that has existed. Trailer kept

To do:
- [x] `git blame` on torvalds/master for the `Fixes:` target; decide `Cc: stable` — done, see Done: **no `Fixes:`, no `Cc: stable`**
- [ ] checker gauntlet; cover letter with the `generated-content.rst` disclosure

Done:
- 2026-09-03  series cut on i2c/i2c-host-next; the commit cherry-picks clean

## psci-cpuidle-fixes

```
Category:    power
Tree:        linux-pm — Rafael J. Wysocki, Ulf Hansson (+ Lorenzo Pieralisi, Sudeep Holla,
             Daniel Lezcano on the psci patch); CC linux-pm, linux-arm-kernel
Source:      upstreaming/psci-cpuidle-fixes — b4 prep branch, cut 2026-09-03
             change-id 20260903-upstreaming-psci-cpuidle-fixes-68ffc9e9da1a
             base-commit 208027d2c8957800e199a9e0f55da5fdb9550207
             (rafael/linux-pm bleeding-edge, 2026-09-01)
             legacy: submit/7.1.3/power, tagged archive/submit-7.1.3-power-final
             sent rounds: – (none yet)
Depends:     –
```

**One series, not two — measured, not assumed.** The open question was whether
`cpuidle-psci.c` and `pm_domain.h` answer to different trees. `get_maintainer.pl`
on both, 2026-09-03, returns the same maintainers (Rafael J. Wysocki, Ulf Hansson)
and the same list (`linux-pm@vger.kernel.org`), so by the skill's rule — two
candidate series answering with the same tree and maintainer are probably one
series — they travel together.

Left out of this series (the `power` category is mostly not upstream-shaped):

| left out | lines | why |
|---|---|---|
| `drivers/clk/qcom/apcs-msm8953.c` — the PLL-retune fix | 123 | patches a file that does not exist in the torvalds tree |
| `irq-qcom-mpm.c`, `pinctrl-msm8953.c`, `qcom_smd.c`, `smsm.c` (+ binding), `msm8953.dtsi`, `msm8916-wcd-digital.c`, `qcom-ngd-ctrl.c` | ~330 | **sendable — re-triaged 2026-09-03 into eight planned series**, see [Planned series — the power re-triage](#planned-series--the-power-re-triage-2026-09-03). ☠️ The earlier "not upstream-shaped" verdict lumped these with the experiments below |
| `qcom_smd-regulator.c` `set_suspend_*` ops | 61 | held: mechanism proven on one rail, no power win measured, board opt-in reverted (see the plan) |
| `clk-smd-rpm.c` XO experiment, `smd-rpm.c` + `qcom_smd_rpm.h` tracepoint, `icc-rpm.{c,h}` + `msm8953.c` sleep-set knobs, `qcom_smd-regulator.c` `both_sets` knob, the FP3 sleep-set DTS + its revert | ~320 | instrumentation and experiment knobs; stay on `wip/7.1.3/power` |

Distillation check, 2026-09-03: on the two paths this series carries, `wip` and
the series produce identical diffs (`cpuidle-psci.c` 10+/1-, `pm_domain.h` 1+/1-).

Test: not yet run from a submission base. Checkers: –.

Rounds: none yet.

To do:
- [ ] `PM: domains: Fix the cached power-down state index being a bool` reads like a
      `Fixes:` candidate — get the target from blame on torvalds/master
- [ ] checker gauntlet; cover letter with the `generated-content.rst` disclosure

Done:
- 2026-09-03  series cut on linux-pm `bleeding-edge`; both commits cherry-pick clean
- 2026-09-03  the two-tree question settled by `get_maintainer.pl`: one series

## smb5-charger

```
Category:    charger
Tree:        power-supply, sre/linux-power-supply for-next — Sebastian Reichel,
             Casey Connolly (QUALCOMM SMB CHARGER DRIVER); CC linux-pm, linux-arm-msm, devicetree
Source:      upstreaming/smb5-charger — b4 prep branch, cut 2026-09-03
             change-id 20260903-upstreaming-smb5-charger-f653be687965
             base-commit 2da28b059e0ddcd2e1956eeae383246207965573
             (sre/linux-power-supply for-next, 2026-08-11)
             legacy: submit/7.1.3/charger, tagged archive/submit-7.1.3-charger-final
             sent rounds: – (none yet)
Depends:     adc5-bat-therm (the driver reads the PMI632 BAT_THERM ADC channel)
```

Left out of this series (2026-09-03, measured against `wip/7.1.3/charger`):

| left out | lines | where it goes instead |
|---|---|---|
| `drivers/iio/adc/qcom-spmi-adc5.c` | 2 | the **adc5-bat-therm** series — a different tree (IIO), and a prerequisite of this one |
| `pmi632.dtsi` + `sdm632-fairphone-fp3.dts` | 337 | the **fp3-dts** series, sent last |
| ☠️ the **fuel-gauge (QG) work** in `qcom_smbx.c` — charge counting, OCV correction, the charge-end path, the charging policy | ~1450 of the 2252 lines `wip` adds | **has no series at all.** `wip/7.1.3/charger` carries ~25 commits of it that post-date the legacy submit branch; the series carries 803+/34-. This is not a decision that was made, it is one that is outstanding — see To do |
| `battery.yaml` (`id-resistor-ohms`) and the rest of the binding | 10 + 47 | belongs with the fuel-gauge work above |

Test: not yet run from a submission base. Checkers: –.
  build on the target tree: ✗ as cut (2026-09-03) — `devm_thermal_of_cooling_device_register()`
  takes `u32 cdev_id` on power-supply for-next and linux-next (3570cb58e317, thermal/of,
  2026-06-03); the series passed `dev_of_node()`. Adapted 2026-09-03 (cdev_id 0, the legacy
  node identity); compile of the adapted object still owed

Rounds: none yet.

Done:
- 2026-09-03  ☠️ the cooling-device registration adapted to the cdev_id API **in the series
              only** (review B4, queue 139): the fork base 7.1.3/main still has the
              `struct device_node *` form, so `wip/7.1.3/charger` keeps that and the phone
              keeps building; the series carries the one-call difference, recorded here as the
              deliberate divergence it is, until the base rolls past 7.4 and wip follows.
              The linux-next integration had silently left this patch out — that is now a
              known difference, not a hidden one. Old tip tagged
              `archive/upstreaming-smb5-charger-pre-thermal-api-20260903`

To do:
- [ ] ☠️ decide what happens to the fuel-gauge half of `wip/7.1.3/charger`: a second
      series (`smbx-fuel-gauge`) after this one lands, or a named permanent leave-out.
      Until that is decided this page understates the category by ~1450 lines
- [ ] every board/battery fact out of the driver and into DT (skill: "no board fact hidden in the driver")
- [ ] `defconfig`: check whether the PMI632 needs a `CONFIG_` symbol that is not already there
- [ ] checker gauntlet; cover letter with the `generated-content.rst` disclosure

Done:
- 2026-09-03  series cut on power-supply `for-next`; all six commits cherry-pick clean

## adc5-bat-therm

```
Category:    charger
Tree:        IIO, jic23/iio togreg — Jonathan Cameron; CC linux-iio, linux-arm-msm
Source:      upstreaming/adc5-bat-therm — b4 prep branch, cut 2026-09-03
             change-id 20260903-upstreaming-adc5-bat-therm-73e744791445
             base-commit 183f05a300eab41e4578337eac59335730dfebf9 (jic23/iio togreg, 2026-08-31)
             legacy: part of submit/7.1.3/charger, tagged archive/submit-7.1.3-charger-final
             sent rounds: – (none yet)
Depends:     –
```

A series that did not exist on this page until 2026-09-03. It was one commit
inside the `charger` legacy branch, and it goes to a **different tree**: two lines
adding the PMI632 BAT_THERM channel to `qcom-spmi-adc5.c`. `smb5-charger` reads
that channel, so this is its prerequisite, not an afterthought.

Test: not yet run from a submission base. Checkers: –.

Rounds: none yet.

To do:
- [ ] decide the ordering with `smb5-charger`: send this first and cite it, or ask
      whether one tree can take both (skill: "a dependency that crosses trees is a
      handshake" — ask, do not assume)
- [ ] ☠️ two lines with an `Assisted-by:` trailer is exactly the shape that drew
      *"Claude assisting to write a one-liner patch? It's becoming ridiculous."* on
      the list. Do not drop the disclosure; consider whether it can travel inside
      `smb5-charger` instead of alone

Done:
- 2026-09-03  series cut on IIO `togreg`; the commit cherry-picks clean

## imx363-camera

```
Category:    camera
Tree:        media, git.linuxtv.org/media.git `next` — Sakari Ailus, Mauro Carvalho Chehab;
             CC linux-media, devicetree
Source:      upstreaming/imx363-camera — b4 prep branch, cut 2026-09-03
             change-id 20260903-upstreaming-imx363-camera-2ae977b0269c
             base-commit cee9395acd8043be0644b25c34bfa86623f2b935 (media `next`, 2026-08-30 = v7.3-rc1)
             legacy: submit/7.1.3/camera, tagged archive/submit-7.1.3-camera-final
             sent rounds: – (none yet)
Depends:     –
```

**The provenance split was already done** — the earlier to-do here was stale.
Verified 2026-09-03: the import commit is authored by **Joel Selvaraj
<foss@joelselvaraj.com>**, carries the full citation (gitlab.com/sdm670-mainline/linux,
commit 5130bc702ea2, MR !3), a four-deep `Signed-off-by` chain ending in ours, and
`imx363.c` in it is **byte-identical** to the archival snapshot `vendor/imx363-sdm670`.

**The AK7374 actuator work travels with the sensor**, not as its own series:
`get_maintainer.pl` answers Sakari Ailus for both `ak7375.c` and the IMX363, it is
one hardware-enablement story (rear camera: sensor + focus actuator), and the
skill's first maintainer rule is one branch per subsystem, not sub-split.

☠️ One conflict, and it was the neighbours': the import's `drivers/media/i2c/Kconfig`
hunk carries `VIDEO_OV9282` as context, and upstream has since changed that entry
(`depends on OF_GPIO` → `depends on OF` + `select V4L2_CCI_I2C`). Resolved by
keeping HEAD — this series does not touch OV9282. Everything else cherry-picks clean.

Left out of this series (2026-09-03, measured against `wip/7.1.3/camera`):

| left out | lines | where it goes instead |
|---|---|---|
| `drivers/clk/qcom/gcc-msm8953.c` | 3+/3- | the **gcc-msm8953-csiphy** series — a different tree (clk) |
| `pmi632.dtsi` + `sdm632-fairphone-fp3.dts` | 113 | the **fp3-dts** series, sent last |
| `lc898217.c` + binding (the rear actuator of the *other* FP3 camera module) | ~230 | no series yet. ☠️ The 2026-09-03 review called this untested hardware; **Bert Karwatzki tested it the same day** on his FP3 (IMX363 @0x10 + LC898217 @0x72) and found it needs two supplies — his fix is on `wip/7.1.3/camera` as `78a9e301a72f` (his authorship), binding `e677aed32138`. Send with the two-module DTS decision (#144) |
| `s5k4h7.c` + binding (front camera) | ~370 | no series yet — front-camera bring-up, not claimed to work |
| the CAMSS changes (`camss-vfe-4-1.c`, `camss-vfe-gen1.{c,h}`, `camss-vfe.c`, `camss-video.{c,h}`) | 228 | planned series **camss-rdi-stride** (2026-09-03 re-triage) |
| the flash-LED changes (`leds-qcom-flash.c`, its Kconfig and binding) | 24 | planned series **qcom-flash-pmi632** (2026-09-03 re-triage) |
| ☠️ the **`ak7375.c` runtime-PM rework** — hold a PM reference only while the lens is driven away from rest, measured at 0.30 W on an FP3 with nothing taking pictures | 91+/14- on wip vs 14+/0- carried | **has no series.** It is a generic driver power improvement with a measurement behind it, i.e. exactly the kind of change that belongs upstream — planned series **ak7375-pm** (2026-09-03 re-triage) |
| `lens-focus: true` in `sony,imx363.yaml` | 2 | on `wip` and not on the series; the binding should describe it once the actuator is wired — see To do |

Test: not yet run from a submission base. Checkers: –.

Rounds: none yet.

To do:
- [ ] ☠️ reorder: the skill's shape is *binding → driver + Kconfig → defconfig → DTS*,
      and this series currently puts the imported driver first because that is the
      order it was discovered in. The binding and MAINTAINERS commits move ahead of
      the driver
- [ ] ☠️ decide the `ak7375.c` runtime-PM rework: fold it into this series (it is the
      strongest patch in the category — generic, measured, benefits every AK7375
      board) or name it a permanent leave-out
- [ ] add `lens-focus: true` to `sony,imx363.yaml`, which `wip` has and this does not
- [ ] `defconfig`: `CONFIG_VIDEO_IMX363` is new, so a defconfig patch is owed unless
      the arm64 defconfig already covers it — check, do not assume
- [ ] the driver is a reverse-engineering effort against Android register logs, and
      the imported file says so in its own comments; the cover letter must say it too
- [ ] checker gauntlet per patch (the import carries the style debt — keep it in the
      import commit so it is not blamed on us); cover letter with the disclosure

Done:
- 2026-09-03  the `Assisted-by:` trailer was **dropped from Joel Selvaraj's import
              commit** on `wip/7.1.3/camera` first, then here (review B2, queue 137):
              the tool helped rewrite the message, not the code, and an import commit
              carries no AI trailer; the message rewrite is disclosed in the cover
              letter instead. Trees identical to `archive/wip-7.1.3-camera-pre-import-trailer-20260903`
              and `archive/upstreaming-imx363-camera-pre-trailer-20260903`
- 2026-09-03  ☠️ the import commit was **rebuilt** (queue 136 / review B1): it had
              taken the source tree's whole `drivers/media/i2c` Kconfig and
              Makefile instead of the IMX363 hunk, so it **deleted**
              `config VIDEO_OV2732` and `config VIDEO_T4KA3` with their Makefile
              lines, stripped `select V4L2_CCI_I2C` from `VIDEO_OG01A1B` and
              `VIDEO_OV9282`, and reverted the DS90UB960 help text — **31
              deletions under a message certifying a byte-identical import**.
              Fixed on `wip/7.1.3/camera` and regenerated: the import is now
              **1525 insertions, 0 deletions**, Joel Selvaraj's authorship and
              date preserved, and the message no longer claims the whole files
              are byte-identical — only the driver file is, with the Kconfig
              entry and Makefile line *added* rather than copied over.
              Same content restored on `integration/7.1.3` (d697876d8bfe) and
              `debug-int/7.1.3` (e64849f5d41b) as a commit on top, not a
              rewrite, so the package's pinned `_commit` stays reachable
              (verified: tarball 200, bogus hash 404).
              Tags: `archive/wip-7.1.3-camera-pre-import-fix`,
              `archive/upstreaming-imx363-camera-pre-import-fix`.
- 2026-09-03  ☠️ my earlier "the import is byte-identical" check measured only
              `imx363.c`, while the commit message certified three files. That
              is what let B1 through. A certification is checked against every
              file it names, not the one that matters most
- 2026-09-03  #146 (B7, host half): the four leftover C++ comments and the "NOT SURE HOW TO
              FIND THIS VALUE" note in `imx363.c` replaced (wip `d9245062005f`, twins on
              integration/debug-int, pushed), and folded into the series' cleanup patch
              (`4299ac06294d`; old tip tagged `archive/upstreaming-imx363-camera-pre-b7-20260903`,
              series now `f27ef2d05b11`). The 636 MHz comment says what is known: it came with the
              imported Pixel 3a driver and was not derived from the PLL registers — a reviewer may
              ask for the derivation; that is the honest state
- 2026-09-03  #143: Bert Karwatzki's lc898217 two-supply fix taken onto `wip/7.1.3/camera` with his
              authorship (`78a9e301a72f`) plus a binding patch of ours (`e677aed32138`); twins on
              `integration/7.1.3` and `debug-int/7.1.3`, pushed. Not compiled here (no cross toolchain);
              the phone lane builds it with the next `_commit` bump
- 2026-09-03  series cut on media `next`; original authorship preserved
- 2026-09-03  the AK7374 work folded in rather than split out (same tree, same maintainer)

## gcc-msm8953-csiphy

```
Category:    camera
Tree:        clk, clk/linux clk-next — Stephen Boyd, Bjorn Andersson (QUALCOMM CLOCK DRIVERS);
             CC linux-clk, linux-arm-msm
Source:      upstreaming/gcc-msm8953-csiphy — b4 prep branch, cut 2026-09-03
             change-id 20260903-upstreaming-gcc-msm8953-csiphy-8bf1541e0f8d
             base-commit 551ba775497e93d93bb849f6ee572ca768cbaa3e (clk-next, 2026-09-02)
             legacy: part of submit/7.1.3/camera, tagged archive/submit-7.1.3-camera-final
             sent rounds: – (none yet)
Depends:     –
```

A series that did not exist on this page until 2026-09-03. It was one commit inside
the `camera` legacy branch and it goes to a **different tree**: the CSIPHY timer
source select for GPLL0_DIV2 in `gcc-msm8953.c`. It is a **fix to an existing
in-tree driver**, not part of the camera enablement, and it stands on its own.

Test: not yet run from a submission base. Checkers: –.

Rounds: none yet.

To do:
- [ ] `Fixes:` from `git blame` on torvalds/master — this corrects a wrong parent
      selection, so there is a commit to name (skill: "a `Fixes:` target comes from
      blame, never from the file's age")
- [ ] say in the message what the wrong select produced on hardware, in the words
      someone hitting it would search for
- [ ] checker gauntlet; cover letter with the `generated-content.rst` disclosure

Done:
- 2026-09-03  series cut on `clk-next`; the commit cherry-picks clean

## qmi-encdec-fix

```
Category:    sensor
Tree:        soc/qcom — Bjorn Andersson, Konrad Dybcio; CC linux-arm-msm
Source:      upstreaming/qmi-encdec-fix — b4 prep branch, cut 2026-09-03
             change-id 20260903-upstreaming-qmi-encdec-fix-d9277cbef2bf
             base-commit e61cfc881090cf9de9dbd3b6b7452661dfb0261f (qcom/linux for-next, 2026-09-02)
             legacy: submit/7.1.3/sensor, tagged archive/submit-7.1.3-sensor-final
             sent rounds: – (none yet)
Depends:     – (measured: D-3 does not touch qmi_encdec.c; see the D- list)
```

Left out: everything else in the `sensor` category — the SMGR drivers, the QRTR
prerequisites, `qmi_interface.c`, the `file2alias`/`mod_devicetable` plumbing,
~2775 lines across 29 files. See `docs/sensors/README.md`.

☠️ **And the reason is stronger than "unsendable".** Measured 2026-09-03: **14 of
those 29 files are the subject of D-3**, Yassine Oudjana's posted series. So the
left-out work is not merely un-upstreamable — sending it would be a competing
submission of somebody else's driver. `qmi_encdec.c` is the one file in the
category that mainline already has **and** that D-3 does not touch, which is
exactly why it is the one series.

Test: not yet run from a submission base. Checkers: –.

Rounds: none yet.

To do:
- [ ] `Fixes:` from blame on torvalds/master (regression, this year — skill "A `Fixes:`
      target comes from blame"), and `get_maintainer.pl` puts the author of the
      regression on Cc
- [ ] checker gauntlet — `sparse` especially, this is a width bug; cover letter

Done:
- 2026-09-03  series cut on qcom `for-next`; the commit cherry-picks clean

## q6voice

```
Category:    voice
Tree:        ASoC
Source:      submit/7.1.3/voice (legacy; no upstreaming/ branch will be cut)
Depends:     a q6voice driver in mainline — none exists, none was ever posted (patchwork empty for "q6voice", TODO.md)
```

State `unsendable`: the one-line DAPM route patches a driver that is not upstream. Revisit if a q6voice driver appears on the list.

## fp3-dts

```
Category:    all (audio, charger, camera, sensor — one DTS commit per logical step)
Tree:        qcom SoC — Bjorn Andersson, Konrad Dybcio; CC linux-arm-msm, devicetree
Source:      upstreaming/fp3-dts (to be cut, from the DTS hunks of every category)
Depends:     wcd9335-audio, smb5-charger, adc5-bat-therm, imx363-camera, gcc-msm8953-csiphy
             (binding + driver landed), D-1 (the audio machine driver)
```

The DTS hunks now waiting here, measured 2026-09-03 as every `.dts`/`.dtsi` line
each category's `wip` branch adds and no cut series carries:

| from | file | lines |
|---|---|---|
| audio | `sdm632-fairphone-fp3.dts` | 250+/2- |
| charger | `sdm632-fairphone-fp3.dts` + `pmi632.dtsi` | 337 |
| camera | `sdm632-fairphone-fp3.dts` + `pmi632.dtsi` | 113 |

☠️ These overlap — three categories add to the same board file — so the series is
not a concatenation. It is one commit per logical enablement step, in the
`arm64: dts: qcom: sdm632-fairphone-fp3: <verb> <thing>` form, rebuilt from the
final DTS rather than replayed.

Test: not yet. Checkers: dtbs_check as a differential (the base fails it by itself — skill).

Rounds: none yet.

**Two rear-camera modules — decided 2026-09-03 (#144), to be confirmed on the cover
letter.** Fairphone shipped the FP3 with two rear modules that the firmware cannot
tell apart: IMX363 @0x1a + AK7374 @0x0c (ours, measured) and IMX363 @0x10 +
LC898217 @0x72 (Bert Karwatzki's, tested by him). The board DTS as written
describes ours and leaves his without a camera. Bert proposed a common dtsi and one
dts per module; the tree already has a pattern made for exactly this case, and it
is the one we take: **a build-time overlay per module**, like
`sm8550-hdk-rear-camera-card.dtso` / `sm8650-hdk-rear-camera-card.dtso` and
`apq8016-sbc-d3-camera-mezzanine.dtso` (checked in torvalds/master 940de590b839;
composed in `arch/arm64/boot/dts/qcom/Makefile` as
`<board>-<card>-dtbs := <board>.dtb <board>-<card>.dtbo`).

- `sdm632-fairphone-fp3.dts` keeps its name and its dtb, with no rear camera —
  nothing that boots it today changes.
- `sdm632-fairphone-fp3-rear-camera-ak7374.dtso` and
  `sdm632-fairphone-fp3-rear-camera-lc898217.dtso` carry the `&cci_i2c0` sensor +
  actuator + EEPROM nodes, the `&camss`/`&csiphy0` endpoint and the flash LED
  (whatever is module-specific — measure the diff between the two node sets, do not
  assume); the Makefile composes `sdm632-fairphone-fp3-rear-camera-{ak7374,lc898217}.dtb`.
- Over Bert's dtsi + two dts: no rename of an in-tree dts, the composed dtbs are
  built and `dtbs_check`-ed like any other, and the split is the maintainers' own.
- Cover-letter question, now narrow: *"the module is not detectable from
  firmware; is the rear-camera-card overlay pattern acceptable for a phone, and is
  naming by actuator the right key?"*
- Open: which module is the earlier one (Bert writes "older(?)"); the EEPROM at
  0x50 may say — asked him for its contents.

To do:
- [ ] cut after the driver series are `applied`; one commit per logical step in the `arm64: dts: qcom: sdm632-fairphone-fp3: <verb> <thing>` form
- [ ] every enabled node measured working on the device (unbound-node check from the skill)

Done: –

---

## Planned series — the power re-triage (2026-09-03)

Queue task #141, review §4. Every item below patches a file that exists in
`torvalds/master` (checked at 940de590b839, 2026-09-02: none of the additions is
there — no MPM node, `rpm-stats` or `domain-idle-states` in `msm8953.dtsi`, no
`wakeirq_map` in `pinctrl-msm8953.c`, no wakeup handling in `qcom_smd.c`, no
`disable_stream` in `qcom-ngd-ctrl.c`, no PMI632 in `leds-qcom-flash.c`, no
`proc-awake` in `qcom,smsm.yaml`), has a measurement on the FP3 behind it, and
depends on none of D-1/D-2/D-3. Maintainers from `get_maintainer.pl -f` on a
v7.3-rc1 tree, 2026-09-03. **Nothing is cut yet** — each row is a `b4 prep`
still to be made; when it is, it gets a section of its own above and this table
shrinks.

| series | tree, maintainers | `wip` commits → patches | shape decisions |
|---|---|---|---|
| **qcom-mpm-wakeup-timer** | irqchip — Thomas Gleixner, Radu Rendec; linux-kernel | `97951baf7a85` + `a8cb2c420b3d` + `ff064e2b608c` → **1** | ☠️ the third `wip` step deletes lines the first one added (`MPM_MAX_SLEEP_NS`, the `ktime_get_mono_fast_ns()` read); upstream never had a wakeup timer in this driver, so the logical change is one patch in its final shape. Not a `Fixes:` — an enablement (the RPM was never told when to wake the AP) |
| **pinctrl-msm8953-mpm** | pinctrl — Linus Walleij, Bjorn Andersson, Bartosz Golaszewski; linux-gpio, linux-arm-msm | `aa3fc7ec6a42` → 1 | 14-line `wakeirq_map`, same shape as the msm8909/msm8996 maps already in tree; cite the downstream pin→MPM table as the *finding*, not as copied code |
| **qcom-smd-wake** | rpmsg — Bjorn Andersson, Mathieu Poirier; linux-remoteproc, linux-arm-msm | `8c9b25687119` + `d0e738c107e3` → **1** | the double-teardown crash is only reachable once the edge is wakeup-capable, so a series with only the first patch applied crashes on remoteproc stop — fold it in (bisect rule). Keep the oops in the message, timestamps trimmed. Measurement: incoming call on QRTR port 39 wakes s2idle (2026-08-30) |
| **smsm-proc-awake** | qcom SoC — Bjorn Andersson, Konrad Dybcio; + DT maintainers for the binding | `407669069a90` → **2** (binding first, `Documentation/devicetree/bindings/soc/qcom/qcom,smsm.yaml`, then the driver) | ☠️ no binding exists — write it. Maintainer question to put in the cover, not to guess: is the bit a DT property (`qcom,proc-awake-bit`, current shape) or per-SoC match data? Downstream drives bit 12 on msm8953; whether other SoCs share it decides the answer. The dtsi consumer travels in **msm8953-dtsi-idle** |
| **msm8953-dtsi-idle** | qcom SoC DT — Bjorn Andersson, Konrad Dybcio; devicetree, linux-arm-msm | `3e9b16386eb5`, `a58956fb30c1`, `6052a236ba6b`, `85d0b48961f6`, `14210263b650`, `c2e90281cdfe`, `c12afd4ee241`, `bca898cde190`; **`0314fee3ce35` held** → ≤ 9 | sent **after** the three driver series (the MPM node and `wakeup-parent` are inert without the pinctrl map; the SMSM bit needs its binding). ☠️ **`0314fee3ce35` (system-pc affinity, psci-suspend-param 0x42000353) is held**: Bert Karwatzki reports it breaks hx83112b touch after resume on his FP3 (mail 2026-09-03, queue #142); until reproduced or disproved it does not go out. `rpm-master-stats` (`qcom,rpm-master-stats.yaml`) and `rpm-stats` (`qcom-stats.yaml`) bindings exist upstream — check the compatible strings at cut time, do not assume |
| **wcd-digital-mclk** | ASoC — Srinivas Kandagatla, Mark Brown; linux-sound | `4b09b2158dd8` → 1 | 29 lines; the measurement is the mclk held for the life of the boot on a codec with no stream. Cut on `sound/for-next` like `wcd9335-audio`, but **separate series** — different driver, standalone |
| **ngd-disable-stream** | slimbus — Srinivas Kandagatla; linux-arm-msm, linux-sound | `dbb414e0be28` + `c44534943e82` → **1** | squash the alignment fixup. The ADSP keeps the channel allocated without it — say what was observed (the failure on the second stream), name the capture |
| **camss-rdi-stride** | media — Bryan O'Donoghue, Vladimir Zapolskiy, Loic Poulain; linux-media, linux-arm-msm | `74ea615f447f` → 1 | 228 lines on gen1 VFE; the kernel half is done (ioctl-verified, 2026-08-08), the libcamera half never left libcamera (`planesCount`=0) — say so in the cover so the reviewer knows what exercises it |
| **qcom-flash-pmi632** | LEDs — Lee Jones, Pavel Machek; linux-leds; + DT maintainers | `0dbb575d8ddc`, `a4509f593bdf`, `dc6f36f0a4fe` → **2** | binding first, then driver with the Kconfig wording folded in (the Kconfig line is not a logical change of its own) |
| **ak7375-pm** | media — Sakari Ailus; linux-media | `f6e4c109fb32`, `0b79b9bb25f0`, `de1b32d12750`, `dfa5c7851d6c`, `6da2d3a1a2eb`, `4880a86550ff` → 3–4 | AK7374 id support stands alone. The PM rework (`power for a position`, `last consumer parks`, `no power-up on system resume`) is one logical change in its final shape — measured 0.30 W idle (`98-camera-af-rail`, r53 FAIL / r56 PASS). `retry the first transfer` and `supplies off when resume fails` are candidate standalone fixes: take `Fixes:` from blame on `master` (last upstream change 2023-12-01, df15385e6793) only if the fault predates the rework |
| *(held)* **qcom-smd-regulator-suspend** | regulator — Mark Brown, Liam Girdwood; linux-arm-msm | `5fe5dba65260` (without `117d3d69d58b`) | the ops are upstream-shaped and the mechanism is proven (one-rail probe, `sleep smpa/3 swen=1`, 2026-08-24), but the all-rails board opt-in was reverted (`53e51066c600`) and *on-in-suspend* carries no power benefit — so today it is an op with no in-tree user and no measured win. Held until a rail is measured off-in-suspend; then the ops and that board change go together |

Stays on `wip/7.1.3/power`, deliberately: `apcs-msm8953.c` (file not upstream),
the `clk-smd-rpm.c` XO experiment, the `smd-rpm` tracepoint, the `icc-rpm`
`sleep_init` / suspend-zero knobs, the regulator `both_sets` knob, the FP3
sleep-set DTS and its revert. Each is an instrument or a disproven direction.

Order of sending, forced by content: the driver series in any order, then
**msm8953-dtsi-idle**, then `fp3-dts`.

## Dependencies (foreign series)

| id | what | author, date | link | state | what it needs from us | updated |
|---|---|---|---|---|---|---|
| D-1 | *MSM8953/MSM8976 ASoC support* v3, 8 patches — MSM8953 in `apq8016_sbc.c`, Quinary MI2S, compatible + binding | Adam Skladowski &lt;a39.skl@gmail.com&gt; (code by Vladimir Lypak), 2024-07-31 | patchwork series [875540](https://patchwork.kernel.org/project/linux-arm-msm/list/?series=875540); cover message-id `20240731-msm8953-msm8976-asoc-v3-0-163f23c3a28d@gmail.com` (patchwork API, confirmed against the lore thread mbox, 2026-09-03) | stalled, `new`; review (Stephan Gerhold, 2024-08-01) asked for runtime detection of the Q6AFE clock API; author replied 2024-08-09 that he could not carry it further | the generic `q6afe.c` change (serve `LPAIF_BIT_CLK` from the new clock-set API when the firmware is the newer kind), posted into this thread rather than as a competing series; a Tested-by on the FP3 | 2026-08-30 |
| D-2 | *ASoC: qcom: check ADSP version when setting clocks* v2, 4 patches | Otto Pflüger &lt;otto.pflueger@abscue.de&gt;, 2023-10-29 (v1 2023-10-14, superseded) | v2 cover message-id `20231029165716.69878-1-otto.pflueger@abscue.de` (patchwork API, confirmed against the lore thread mbox, 2026-09-03). ☠️ **patchwork has no *series* object for v2** — only the individual patches, so the only series ids are v1's: [793237](https://patchwork.kernel.org/project/linux-arm-msm/list/?series=793237) (linux-arm-msm) and 793291 (alsa-devel) | not rejected; its foundation (`q6core_get_svc_api_info()`, q6afe reading it at probe, the NULL-port param path) is in mainline `master` and `sound/for-next`; only its 3/4 (the dispatch by firmware version) is missing | the same q6afe change as D-1; also contains `ASoC: qcom: q6afe: remove "port already open" error` — read before sending our own q6afe patch | 2026-08-30 |
| D-3 | *QRTR bus and Qualcomm Sensor Manager IIO drivers* v2, 4 patches — turns QRTR into a bus and adds the SMGR IIO driver (v1 2025-04-06, 3 patches, `20250406140706.812425-1-y.oudjana@protonmail.com`) | Yassine Oudjana &lt;y.oudjana@protonmail.com&gt;, via B4 Relay, 2025-07-10 | cover message-id `20250710-qcom-smgr-v2-0-f6e198b7aa8e@protonmail.com`, [lore](https://lore.kernel.org/all/20250710-qcom-smgr-v2-0-f6e198b7aa8e@protonmail.com/) (thread mbox fetched 2026-09-03) | `changes-requested` on 4/4. On-list: Andy Shevchenko (2/4, 4/4) and Simon Horman 2025-07-10, **Jonathan Cameron** 2025-07-13 and 2025-07-19, Casey Connolly 2025-07-21; the author answered 2025-07-17. ☠️ **Last activity 2025-07-21** — quiet for ~14 months as of 2026-09-03, so "stalled" is the honest word, not "in review" | the **ambient-light channel**. His cover: *"Currently supported sensor types include accelerometers, gyroscopes, magentometers, proximity and pressure sensors. Other types (namely light and temperature sensors) are close to being implemented."* We have light working. Plus a `Tested-by` on the FP3 — his cover names **MSM8953** explicitly as an ADSP-category SoC in scope | 2026-09-03 |

☠️ **D-3 is not a dependency of `qmi-encdec-fix`, and the bringup page says it is.**
Measured 2026-09-03 by diffing his v2 against `wip/7.1.3/sensor`:

- **D-3 does not touch `drivers/soc/qcom/qmi_encdec.c` at all** (0 hits in the
  series). That is precisely why `qmi_encdec.c` was the one sendable commit in the
  sensor category — the only file there that is upstream *and* that nobody else is
  rewriting. `qmi-encdec-fix` applied clean to `qcom/for-next` and depends on nothing.
- **What D-3 does own is 14 of the 30 files our sensor category touches**: the whole
  QRTR bus work (`net/qrtr/af_qrtr.c`, `qrtr.h`, `smd.c`), `drivers/soc/qcom/qmi_interface.c`,
  the `mod_devicetable.h` / `devicetable-offsets.c` / `file2alias.c` plumbing,
  `include/linux/soc/qcom/qrtr.h`, and the `drivers/iio/common/qcom_smgr/` tree.
  Our "sensor prerequisites" and his series are the same ground.
- ☠️ **Our per-sensor drivers are shaped like his v1, which he abandoned.** His
  v1→v2 changelog says *"Remove per-sensor subdrivers and eliminate use of platform
  devices"*, and `wip/7.1.3/sensor` still carries `smgr_accel.c`, `smgr_gyro.c`,
  `smgr_mag.c`, `smgr_prox.c` as exactly those per-sensor subdrivers. Reworking them
  onto his v2 shape is not polish — it is the difference between an offer and a
  competing submission of somebody else's driver.

**D-2, patch by patch** (message-ids from the patchwork API, 2026-09-03):

| # | subject | state | message-id |
|---|---|---|---|
| v2 0/4 | cover: *ASoC: qcom: check ADSP version when setting clocks* | `new` | `20231029165716.69878-1-otto.pflueger@abscue.de` |
| v2 1/4 | `ASoC: qcom: q6core: expose ADSP core firmware version` | `new` | `20231029165716.69878-2-otto.pflueger@abscue.de` |
| v2 2/4 | `ASoC: qcom: q6afe: provide fallback for digital codec clock` | `new` | `20231029165716.69878-3-otto.pflueger@abscue.de` |
| v2 3/4 | `ASoC: qcom: q6afe-dai: check ADSP version when setting sysclk` | `new` | `20231029165716.69878-4-otto.pflueger@abscue.de` |
| v2 4/4 | `ASoC: qcom: q6afe: remove "port already open" error` | `new` | `20231029165716.69878-5-otto.pflueger@abscue.de` |

☠️ **v2 4/4 is the same fix `wcd9335-audio` carries.** Ours is *ASoC: q6afe: treat
ADSP_EALREADY as success when starting a port*; Otto's is *remove "port already
open" error*, posted 2023-10-29 and still `new`. Sending ours without answering
his is a competing submission of somebody else's patch — read it first, and the
right move is probably a reply on that thread, not a fresh series.

**Lore links, verified 2026-09-03** — every message-id below was fetched *and*
its subject read back out of the thread mbox:

| id | message-id | lore |
|---|---|---|
| D-1 cover | `20240731-msm8953-msm8976-asoc-v3-0-163f23c3a28d@gmail.com` | [[PATCH v3 0/8] MSM8953/MSM8976 ASoC support](https://lore.kernel.org/all/20240731-msm8953-msm8976-asoc-v3-0-163f23c3a28d@gmail.com/) |
| D-2 v2 cover | `20231029165716.69878-1-otto.pflueger@abscue.de` | [[PATCH v2 0/4] ASoC: qcom: check ADSP version when setting clocks](https://lore.kernel.org/all/20231029165716.69878-1-otto.pflueger@abscue.de/) |
| D-2 v1 cover | `20231014172624.75301-1-otto.pflueger@abscue.de` | [[PATCH 0/3] same series, superseded](https://lore.kernel.org/all/20231014172624.75301-1-otto.pflueger@abscue.de/) |

☠️ **How to check a lore message-id from a script** — the obvious ways all lie, so
this is the one recipe, measured 2026-09-03 on a 3x3 of endpoint x User-Agent:

```sh
# the ONLY combination that discriminates: real -> 200, invented -> 404
curl -sL -o /dev/null -w '%{http_code}\n' "https://lore.kernel.org/all/<msgid>/t.mbox.gz"
# and read the subject back, so the id is tied to the thread it claims:
curl -sL "https://lore.kernel.org/all/<msgid>/t.mbox.gz" | zcat | grep -m1 '^Subject:'
```

| endpoint | tool UA (curl's own) | browser UA |
|---|---|---|
| `/all/<msgid>/` | **403** real and bogus alike | **200** both — and the body is the Anubis *"Making sure you're not a bot!"* page, 7544 bytes, byte-identical for a real and an invented id |
| `/all/<msgid>/raw`, `/t.atom`, `?q=` | **403** | 200, same challenge page |
| `/all/<msgid>/t.mbox.gz` | **200 real / 404 bogus** ✅ | **200 both** ❌ |

Two traps in that table, and the second is the dangerous one:

1. A 403 is not "the id is bad" and a 200 is not "the id is good" — on the HTML
   paths the status carries no information about the id at all.
2. ☠️ **Sending a browser User-Agent destroys the check.** Anubis challenges
   anything that looks like a browser and waves tool UAs through, so the
   *more* realistic User-Agent is strictly worse: with `Mozilla/5.0` even
   `BOGUS-control@example.invalid` returns 200 on `t.mbox.gz`. Do not "fix" a
   403 by pretending to be a browser.

`b4` is the better tool where it fits and passes the same control — a real id
gives the thread, an invented one prints `Could not retrieve thread: Server
returned an error: 404`. ☠️ Its **shell exit code is 0 either way**, so test the
output or the file, never `$?`:

```sh
b4 mbox -o <dir> '<msgid>'
```

The public-inbox **git transport** is ungated too (`git ls-remote
https://lore.kernel.org/linux-arm-msm/0` works; a non-existent list answers
`Not Found`), which is the route for bulk work. There is **no REST/JSON API** on
lore — public-inbox has never had one; patchwork's API is the JSON one, and it
keeps its own working control (series 875540 -> 200, 99999999 -> 404).

**The kernel-review plugin is not installed on this machine.** The skill's gate
item 3 (`ls ~/.claude/plugins | grep -i kernel-review`) reports MISSING, verified
2026-09-03, so `/track` could not be run and `.claude/tracked-series/` does not
exist. Installing it is one command a person has to type:
`/plugin marketplace add jlelli/claude-kernel-reviews`. Until then this table is
the tracking, refreshed by re-running the patchwork queries.
