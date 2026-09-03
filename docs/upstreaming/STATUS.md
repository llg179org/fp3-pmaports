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
| wcd9335-audio | audio | ASoC `sound/for-next` | 18 on `submit/7.1.3/audio` (measured via API; README's earlier count was 13 — reconcile when the series branch is cut) | preparing | – | us | cut `upstreaming/wcd9335-audio` from wip, trial-rebase on `sound/for-next` | 2026-09-03 |
| i2c-qup-pinctrl | audio | i2c | 1 (`submit/7.1.3/i2c`, based off a different base than `7.1.3/main` — API compare overflows) | preparing | – | us | cut the series branch; standalone bugfix, candidate for `Fixes:` + `Cc: stable` | 2026-09-03 |
| psci-cpuidle-fixes | power | cpuidle / pmdomain | 2 | preparing | – | us | cut the series branch; confirm each patch is upstream-shaped (no `apcs-msm8953.c`) | 2026-09-03 |
| smb5-charger | charger | power-supply `for-next` | 9 | preparing | – | us | cut the series branch; binding + driver + defconfig, DTS excluded | 2026-09-03 |
| imx363-camera | camera | media | 10 | preparing | – | us | provenance split (import commit with original authorship) before anything else | 2026-09-03 |
| qmi-encdec-fix | sensor | soc/qcom | 1 | preparing | – | us | cut the series branch; `Fixes:` from blame on torvalds/master | 2026-09-03 |
| q6voice | voice | ASoC | 1 | unsendable | – | – | the driver it patches was never posted upstream (patchwork: nothing for "q6voice"); revisit only if a q6voice driver appears on the list | 2026-09-03 |
| fp3-dts | all | qcom SoC (`arm64: dts: qcom`) | – | preparing | – | us | sent last; depends on every driver/binding series above having landed | 2026-09-03 |

Patch counts: `gh api repos/llg179org/linux/compare/7.1.3/main...submit/7.1.3/<cat> --jq .total_commits`, 2026-09-03. The `submit/7.1.3/*` branches are the **legacy** namespace; each will be tagged `archive/submit-7.1.3-<cat>-final` and replaced by the `upstreaming/<series>` branch named in its section. Until then the `Source:` field names the legacy branch so the content stays findable.

---

## wcd9335-audio

```
Category:    audio
Tree:        ASoC, sound/for-next — Mark Brown, Srinivas Kandagatla; CC alsa-devel, devicetree (binding), linux-arm-msm
Source:      upstreaming/wcd9335-audio (to be cut) — content today: submit/7.1.3/audio
Depends:     D-1 (for the machine-driver patch and the board DTS only; 10 of the driver/binding patches have no fork dependency — README "Dependency status", 2026-08-30)
```

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
- [ ] cut `upstreaming/wcd9335-audio` with `b4 prep`, from `wip/7.1.3/audio`, on `sound/for-next`; tag the legacy branch `archive/submit-7.1.3-audio-final`
- [ ] trial rebase onto `sound/for-next`, record the `base-commit:`
- [ ] the machine-driver patch: decide between waiting for D-1 and posting the generic `q6afe` clock-set change into Otto's/Adam's thread (README "The chain is shorter than it looks")
- [ ] measure the AFE `api_version` this ADSP reports (the one number the q6afe redesign turns on)
- [ ] checker gauntlet per patch; functional run from the submission base with the debug layer on top; fill the Test block
- [ ] cover letter with the `generated-content.rst` disclosure

Done:
- 2026-08-29  the argument for the series measured against mainline `master` (no jack support in `wcd9335.c`, six in-tree WCD9335 boards) — README
- 2026-08-30  dependency status measured file by file against `v7.1`; the q6afe finding re-checked on `sound/for-next` — README

## i2c-qup-pinctrl

```
Category:    audio   (the speaker-amp fix; its wip home is wip/7.1.3/audio, there is no wip/7.1.3/i2c)
Tree:        i2c — Andi Shyti; CC linux-i2c, linux-arm-msm
Source:      upstreaming/i2c-qup-pinctrl (to be cut) — content today: submit/7.1.3/i2c
Depends:     –
```

Test: not yet run from a submission base. Checkers: –.

Rounds: none yet.

To do:
- [ ] cut the series branch; `git blame` on torvalds/master for the `Fixes:` target; decide `Cc: stable`
- [ ] "applies clean" check against the current `i2c-qup.c` (`gh api …/contents` + `git apply --check`)

Done: –

## psci-cpuidle-fixes

```
Category:    power
Tree:        cpuidle (psci) and pmdomain — Ulf Hansson, Sudeep Holla; CC linux-pm, linux-arm-kernel
Source:      upstreaming/psci-cpuidle-fixes (to be cut) — content today: submit/7.1.3/power
Depends:     –
```

Test: not yet run from a submission base. Checkers: –.

Rounds: none yet.

To do:
- [ ] cut the series branch; confirm neither patch touches `apcs-msm8953.c` (not upstream)
- [ ] two maintainers, possibly two series — ask `get_maintainer.pl` per patch

Done: –

## smb5-charger

```
Category:    charger
Tree:        power-supply, sre/linux-power-supply for-next — Sebastian Reichel; CC linux-pm, devicetree
Source:      upstreaming/smb5-charger (to be cut) — content today: submit/7.1.3/charger
Depends:     –
```

Test: not yet run from a submission base. Checkers: –.

Rounds: none yet.

To do:
- [ ] cut the series branch: binding (`qcom,pmi8998-charger.yaml` extended) → driver → defconfig; the FP3 DTS hunks move to `fp3-dts`
- [ ] every board/battery fact out of the driver and into DT (skill: "no board fact hidden in the driver")

Done: –

## imx363-camera

```
Category:    camera
Tree:        media (linux-media) — Sakari Ailus; CC linux-media, devicetree
Source:      upstreaming/imx363-camera (to be cut) — content today: submit/7.1.3/camera
Depends:     –
```

Test: not yet run from a submission base. Checkers: –.

Rounds: none yet.

To do:
- [ ] provenance: the driver was imported from a third-party out-of-tree branch — import commit with the original authorship and citation, our changes in the next commit, style cleanup in a third (skill: "Find the immediate source")
- [ ] then the series cut

Done: –

## qmi-encdec-fix

```
Category:    sensor
Tree:        soc/qcom — Bjorn Andersson, Konrad Dybcio; CC linux-arm-msm
Source:      upstreaming/qmi-encdec-fix (to be cut) — content today: submit/7.1.3/sensor
Depends:     –
```

Test: not yet run from a submission base. Checkers: –.

Rounds: none yet.

To do:
- [ ] cut the series branch; `Fixes:` from blame on torvalds/master (regression, this year — skill "A Fixes: target comes from blame")
- [ ] the rest of the sensor work is unsendable (patches files that are not upstream) — stays on wip, see `docs/sensors/README.md`

Done: –

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
Depends:     wcd9335-audio, smb5-charger, imx363-camera (binding + driver landed), D-1 (the audio machine driver)
```

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
| D-1 | *MSM8953/MSM8976 ASoC support* v3 — MSM8953 in `apq8016_sbc.c`, Quinary MI2S, compatible + binding | Adam Skladowski (code by Vladimir Lypak), 2024-07-31 | patchwork series 875540 | stalled, `new`; review (Stephan Gerhold, 2024-08-01) asked for runtime detection of the Q6AFE clock API; author replied 2024-08-09 that he could not carry it further | the generic `q6afe.c` change (serve `LPAIF_BIT_CLK` from the new clock-set API when the firmware is the newer kind), posted into this thread rather than as a competing series; a Tested-by on the FP3 | 2026-08-30 |
| D-2 | *check ADSP version when setting clocks* (q6afe) | Otto Pflüger, 2023-10-29 | lore (message-id to be recorded when tracked) | not rejected; its foundation (`q6core_get_svc_api_info()`, q6afe reading it at probe, the NULL-port param path) is in mainline `master` and `sound/for-next`; only its 3/4 (the dispatch by firmware version) is missing | the same q6afe change as D-1; also contains `ASoC: qcom: q6afe: remove "port already open" error` — read before sending our own q6afe patch | 2026-08-30 |

Tracked with `jlelli/claude-kernel-reviews` (`/track <cover message-id>`) in the kernel checkout's `.claude/tracked-series/` once the cover message-ids are fetched; until then the patchwork series id is the reference.
