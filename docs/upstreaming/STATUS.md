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
| wcd9335-audio | audio | ASoC `sound/for-next` | 15 on `upstreaming/wcd9335-audio` | rebased | – | us | checker gauntlet per patch; functional run from the submission base; then the cover letter | 2026-09-03 |
| i2c-qup-pinctrl | audio | i2c-host `i2c/i2c-host-next` | 1 | rebased | – | us | `Fixes:` from blame; decide `Cc: stable` | 2026-09-03 |
| psci-cpuidle-fixes | power | linux-pm `bleeding-edge` | 2 | rebased | – | us | checker gauntlet; then the cover letter | 2026-09-03 |
| smb5-charger | charger | power-supply `for-next` | 6 | rebased | – | us | every board/battery fact out of the driver; `adc5-bat-therm` goes first or with it | 2026-09-03 |
| adc5-bat-therm | charger | IIO `togreg` | 1 | rebased | – | us | prerequisite of `smb5-charger` — decide whether it travels with it | 2026-09-03 |
| imx363-camera | camera | media `next` | 7 | rebased | – | us | reorder binding before driver; then the checkers | 2026-09-03 |
| gcc-msm8953-csiphy | camera | clk `clk-next` | 1 | rebased | – | us | `Fixes:` from blame; it is a fix, not an enablement | 2026-09-03 |
| qmi-encdec-fix | sensor | qcom `for-next` | 1 | rebased | – | us | `Fixes:` from blame on torvalds/master | 2026-09-03 |
| q6voice | voice | ASoC | 1 | unsendable | – | – | the driver it patches was never posted upstream (patchwork: nothing for "q6voice"); revisit only if a q6voice driver appears on the list | 2026-09-03 |
| fp3-dts | all | qcom SoC (`arm64: dts: qcom`) | – | preparing | – | us | sent last; depends on every driver/binding series above having landed | 2026-09-03 |

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
- [ ] ☠️ the series carries `ASoC: q6afe: treat ADSP_EALREADY as success when starting a port`, and **D-2 v2 4/4 is the same fix** — Otto Pflüger's `ASoC: qcom: q6afe: remove "port already open" error`, message-id `20231029165716.69878-5-otto.pflueger@abscue.de`, posted 2023-10-29 and still `new`. Read it before sending ours; a reply on that thread is more likely right than a competing series
- [ ] the machine-driver patch: decide between waiting for D-1 and posting the generic `q6afe` clock-set change into Otto's/Adam's thread (README "The chain is shorter than it looks")
- [ ] measure the AFE `api_version` this ADSP reports (the one number the q6afe redesign turns on)
- [ ] checker gauntlet per patch; functional run from the submission base with the debug layer on top; fill the Test block
- [ ] cover letter with the `generated-content.rst` disclosure — still b4's `EDITME` placeholder

Done:
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
Source:      upstreaming/i2c-qup-pinctrl — b4 prep branch, cut 2026-09-03
             change-id 20260903-upstreaming-i2c-qup-pinctrl-7d3ee5a31cab
             base-commit 04e9bf1648f846976b543e91c1838a712433772a
             (andi.shyti i2c/i2c-host-next, 2026-06-18 — the tree's tip has not moved since)
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

To do:
- [ ] `git blame` on torvalds/master for the `Fixes:` target; decide `Cc: stable`
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
| `msm8953.dtsi`, `clk-smd-rpm.c`, `icc-rpm.{c,h}`, `msm8953.c`, `irq-qcom-mpm.c`, `pinctrl-msm8953.c`, `qcom_smd-regulator.c`, `qcom_smd.c`, `qcom-ngd-ctrl.c`, `smd-rpm.c`, `smsm.c`, `qcom_smd_rpm.h`, `msm8916-wcd-digital.c` | ~650 | bring-up and instrumentation work, not upstream-shaped; stays on `wip/7.1.3/power` |

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

Rounds: none yet.

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
| `lc898217.c`, `s5k4h7.c` and their bindings (front camera + its actuator) | 596 | no series yet — front-camera bring-up, not claimed to work |
| the CAMSS changes (`camss-vfe-4-1.c`, `camss-vfe-gen1.{c,h}`, `camss-vfe.c`, `camss-video.{c,h}`) | 228 | no series yet |
| the flash-LED changes (`leds-qcom-flash.c`, its Kconfig and binding) | 24 | no series yet |
| ☠️ the **`ak7375.c` runtime-PM rework** — hold a PM reference only while the lens is driven away from rest, measured at 0.30 W on an FP3 with nothing taking pictures | 91+/14- on wip vs 14+/0- carried | **has no series.** It is a generic driver power improvement with a measurement behind it, i.e. exactly the kind of change that belongs upstream — see To do |
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

To do:
- [ ] cut after the driver series are `applied`; one commit per logical step in the `arm64: dts: qcom: sdm632-fairphone-fp3: <verb> <thing>` form
- [ ] every enabled node measured working on the device (unbound-node check from the skill)

Done: –

---

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
