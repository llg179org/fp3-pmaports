# Fairphone 3 (sdm632) mainline port — what is still open

> Closed sections and items are moved verbatim to [`TODO-DONE.md`](TODO-DONE.md);
> numbering gaps here are deliberate so references by number still resolve.

> ⚠️ **AI-generated.** This page — and the code, device tree and tooling it
> describes — was written by Claude (Opus 5) working under the direction of
> Lajosházi, László Gergely, who reviewed every change and made or reviewed
> every measurement it rests on. Kernel commits carry `Co-authored-by: Claude`;
> anything prepared for the LKML carries `Assisted-by:` instead and never a
> `Signed-off-by` from the assistant, since only a human can certify the DCO.

This is the **by-branch view** of what is still open: which branch owns which
item, and whether it can be sent anywhere at all. The by-item view, with the
measurements and the reasoning behind each entry, is [`TODO.md`](TODO.md), and
that one is authoritative — this file only says *what is open, on which branch,
and where to read about it*. When the two disagree, `TODO.md` wins.

Until 2026-07-30 this file also shipped at the root of the kernel fork, on
`debug-int/<base>`. It was dropped there: the kernel tree carries kernel source,
and one file maintained in two repositories is one too many to keep honest.

The branch shape it describes:

```
integration/<base>   audio + voice + camera + charger + sensor
                     the pure cherry-pick sum of the upstream-bound categories,
                     so it stays a faithful mirror of what submit/* will carry
      |
      +-> debug-int/<base>   + the debug layer: one commit, the watchdog safety net
                             <- and this is the branch the linux-fp3 package builds
```

The package builds `debug-int/<base>` on purpose. The safety net has to be on the
phone — without the watchdog running from probe, a hang before userspace opens
`/dev/watchdog` leaves a device that has to be switched off by hand, and this one
is often not within arm's reach.

The branch layout itself (`wip/<base>/<category>` → `integration/<base>` →
`submit/<base>/<category>`, and the rule that a change must land on both its wip
branch and its integration) is defined in
[`fp3-pmaports/README.md`](https://github.com/llg179org/fp3-pmaports#the-branch-model);
the base-bump procedure is in
[`docs/rolling-a-new-base.md`](https://github.com/llg179org/fp3-pmaports/blob/main/docs/rolling-a-new-base.md).

Hashes are deliberately absent except where a commit is being *cited* rather than
*tracked* — a head written into a file is wrong by the next push. Re-derive with:

```sh
git for-each-ref --format='%(refname:short) %(objectname:short=12)' \
  'refs/remotes/fork/wip/7.1.3/*' 'refs/remotes/fork/submit/7.1.3/*' \
  'refs/remotes/fork/integration/7.1.3' 'refs/remotes/fork/debug-int/7.1.3'
# note: there is no wip/<base>/debug - see "The `debug` layer" below
```

☠️ **The category list has grown past the five this file has sections for, and
the documented model has not caught up.** Measured 2026-08-24 against
`fork/7.1.3/main`, two more categories carry real commits:

| category | what it carries | why it is not one of the five |
|---|---|---|
| `power` | `wip/7.1.3/power` — 8 commits: the RPM sleep-set work (`regulator: qcom_smd` sleep-set votes plus the `both_sets`/`sleep_init` experiment knobs), `rpmsg: qcom_smd` wakeup-source and edge-interrupt-wake fixes, the APCS PLL-retune fix, and the SLIMbus `disable_stream` pair | it is the deep-sleep track, which started after the five were named |
| `i2c` | `submit/7.1.3/i2c` — the QUP runtime-PM pinctrl fix (the speaker-amp death) plus one adopted upstream cleanup | it began as a charger/audio symptom and ended as an i2c-core change |

Neither appears in the branch table in `~/.claude/CLAUDE.md` or in this file's
per-branch sections below. ★ **The test harness already knew about one of
them:** `tests/checks/CATEGORIES` lists six — `audio voice camera charger sensor
power` — and the runner enforces that every `wip/<base>/*` branch appears there.
So the harness and the prose disagree, and on `power` the harness is right.
`i2c` is in neither, which is consistent: it has a `submit/` branch but no `wip`
one. Treat the table there as **incomplete, not
authoritative**, until it is updated; re-derive the live list with the
`for-each-ref` above rather than from any prose list, including this one.

**And the category is decided by *why* the change is being made, not by which
directory it touches.** `drivers/slimbus/qcom-ngd-ctrl.c` is the worked example,
and it is split across two categories on purpose:

- `wip/7.1.3/audio` carries the QDSP6SS framer-bit commit and its revert — those
  were made to get the codec working.
- `wip/7.1.3/power` carries `implement disable_stream so the ADSP releases the
  channel` — the same file, chased because LPASS would not sleep.

So "a fix in `drivers/slimbus/` has no category" is **false**; ask what the
change is for.

---

## Where the work can go at all

Read this before spending effort on "upstreaming" anything. All of it is
AI-assisted, and that closes two of the three doors:

| destination | AI-assisted work | verdict |
|---|---|---|
| postmarketOS (pmaports, wiki) | banned outright | closed |
| msm8953-mainline (GitHub PR) | "we don't merge AI assisted work" — maintainer, [issue #197](https://github.com/msm8953-mainline/linux/issues/197), 2026-07-25 | closed |
| mainline Linux (LKML) | permitted **with disclosure** | the only path |

So `submit/7.1.3/*` targets the subsystem lists, never a pull request here.
Upstream-bound commits carry `Assisted-by: Claude:<model-id>` and the AI must
**never** carry a `Signed-off-by` — only a human can certify the DCO.

## Does it even apply to a maintainer tree?

Measured by cherry-picking each group onto a detached head at the real
destination, not inferred from "the files exist upstream". Re-measured
**2026-07-31** against fresh bases: Mark Brown `sound/for-next` `b8f7ea37085e`,
Sebastian Reichel `linux-power-supply/for-next` `c57cb36f76eb`,
`torvalds/master` `6269cc6f52c6`. **22 of 27 commits applied clean**, 23 after
one one-hunk resolution.

| group | destination | result |
|---|---|---|
| charger driver + binding | `psy/for-next` | 6/6 clean |
| charger dts | mainline | 2/2 clean |
| charger `adc5` channel | mainline | 1/1 clean |
| sensor (`qmi_encdec`) | mainline | 1/1 clean |
| camera dts | mainline | 1/1 clean |
| camera driver | mainline | one `Kconfig` hunk; the second commit is clean once resolved |
| audio driver + binding | `sound/for-next` | 11/12 — only the machine driver conflicts, on item 8 |
| audio dts | mainline | conflicts — `&sound_card` does not exist |
| voice | `sound/for-next` | the file does not exist upstream |

Audio moved from "conflicts on patch 1" to eleven of twelve, because the binding
was written and the series regenerated. The camera's `Kconfig` conflict moved
from the IMX355 entry to `VIDEO_OV9282`; it follows whichever entry sits next to
ours, so the neighbour's name is not worth tracking.

☠️ Counted per commit, aborting each failure before trying the next, so a group's
figure is "how many of these apply" and not "how far the series gets". Where a
failure cascades the two differ sharply: the camera import creates `imx363.c` and
fails on `Kconfig`, after which the delta commit has no file to patch and the
group reads 0/2 when the truth is one trivial hunk.

Redo this after every base bump; it is the only thing that answers the question.

---

## Before anything is submitted

Cross-cutting, mostly `dtbs_check` fallout. Detail:
[`docs/TODO.md`](https://github.com/llg179org/fp3-pmaports/blob/main/docs/TODO.md).

7. **The camera driver's two-line `Kconfig` conflict** — the neighbouring IMX355
   entry gained a `select V4L2_CCI_I2C`. Trivial, but manual.
8. **The audio prerequisite is named and was posted:** Adam Skladowski,
   *MSM8953/MSM8976 ASoC support* v3, 8 patches, 2024-07-31, state `new`
   ([series 875540](https://patchwork.kernel.org/project/alsa-devel/list/?series=875540),
   cover `<20240731-msm8953-msm8976-asoc-v3-0-163f23c3a28d@gmail.com>`). We need
   1/8, 5/8 and 6/8: `qcom,msm8953-qdsp6-sndcard`, `msm8953_qdsp6_add_ops` and
   `use_ibit_clk` are all out-of-tree today, and so is the `&sound_card` label the
   DTS patch appends to. Declarable with `b4 prep --edit-deps`. Worth asking on
   alsa-devel whether it is still alive before building on it.
9. **Voice is not sendable as-is.** Prior art: Joel Selvaraj's
   `5a63debde2db` (2022-10-02, `sdm670-mainline/linux`) already contains the
   SLIMbus voice routing line for line, including the
   `{ "SLIMBUS_0_RX", NULL, "SLIMBUS_0_RX Voice Mixer" }` edge whose absence we
   booked as our own discovery — and it covers SLIMBUS_0 through 6, where we cover
   0. The `q6voice` driver was never posted to a list, so there is no message-id to
   cite and no upstream file to patch. The realistic move is to offer the
   SLIMBUS_0 work to that series' authors, not to send ours.
10. **Cover-letter disclosure** per `Documentation/process/generated-content.rst`:
    which tools, which prompts, which parts, and how it was tested.
## `wip/7.1.3/charger` — PMI632 SMB5

Fast charge, hardware JEITA, battery ID + thermistor, cooling device. All nine
commits of `submit/7.1.3/charger` apply clean, though to three different trees —
six to `psy/for-next`, two dts and one `adc5` channel to mainline. Gaps, in
[`docs/charger/README.md`](https://github.com/llg179org/fp3-pmaports/blob/main/docs/charger/README.md#known-gaps):

11. **No high-voltage negotiation on the input side** — the port settles near
    1.9 A, just under the programmed 2 A. This is the next real feature here, and
    a piece of work in its own right.
12. **2 A has never been seen flowing.** Needs a wall charger, a low state of
    charge and a USB meter. Physical.
13. **The mismatch path has never run on hardware.** A DTB-only cycle with a
    deliberately wrong `id-resistor-ohms = <50000>`; expected: the refusal message
    plus `0x1061` staying at `0x14`. Two DTB deploys, no kernel build, no flash.
14. **After a mismatch the previous boot's JEITA thresholds stay in the
    comparators**, not the PMIC defaults — a warm reboot does not reset the PMIC.
    The current limit is safe; the temperature limits are stale. Needs a
    characterised safe default.
15. **The DT can only describe one of the two packs** the FP3 ships (this one is
    Fuji). The ID is checked, so a wrong pack cannot be charged on the wrong
    limits — but it falls back to ~1 A, and the OCV curve is still read from the
    battery node even when the ID did not match. What is missing is the
    *selection*: a multi-`monitored-battery` binding mainline does not have.
16. **Half of the float-voltage story is untouched** — the `*_SL_FCV` bits are at
    their PMIC default; the scaling register is undocumented in every source
    available for this generation.
17. **Hardware JEITA gives one threshold per side; the downstream profile has five
    bands.** The 40–45 °C / 1500 mA step cannot be expressed. The full table would
    mean software JEITA — driven by the approximate temperature curve, which is
    the reason not to.
18. **The trip temperatures are a choice, not a measurement.** Nobody has charged
    this phone hard enough to find out which one it reaches.
19. **No step charging and no `auto-recharge-vbat-mv`** (downstream sets both,
    4300 mV). Worth adopting after the above.

## `wip/7.1.3/audio` — WCD9335 on SLIMbus

Playback, microphone, MBHC and the call path all work on the device. Blocked
upstream on item 8. How it works is in
[`docs/audio/README.md`](https://github.com/llg179org/fp3-pmaports/blob/main/docs/audio/README.md),
how it was arrived at in
[`docs/audio/bringup/`](https://github.com/llg179org/fp3-pmaports/tree/main/docs/audio/bringup);
the gaps are here and only here:

20. **The intermittent first-use failure needs a new lead, not another
    workaround.** The QDSP6SS framer-poke suspicion was closed by measurement
    (A/B, 8 cold boots each side, no difference) and the pokes were reverted; see
    [`docs/audio/bringup/qdsp6ss-framer-poke.md`](https://github.com/llg179org/fp3-pmaports/blob/main/docs/audio/bringup/qdsp6ss-framer-poke.md).
21. **The `21`/`22` acoustic selftest checks fail** at −12 dB and at 0 dB while the
    speaker path itself measures clean (999.76 Hz at 31.77 dB). Unexplained, and
    deliberately not filed as environmental.
22. **A stray `Quinary MI2S` backend can attach to the voice front end.**
34. **A bare `BIT(2)` is written into `WCD9335_CODEC_RPM_CLK_MCLK_CFG`.** It
    wants a macro, but neither we nor downstream can name the field truthfully —
    so either a neutral name plus a comment, or an A/B that decides whether the
    write is needed at all. The commit's "garbled playback without it" is not
    backed by a recorded measurement.
35. **The `0x20` written into the EFUSE sense-state field is dead.**
    `SSTATE_MASK` is `GENMASK(4,1)` = `0x1e`, so the call only clears bits 4:1 —
    correct behaviour, misleading constant. Writing `0` is arithmetically
    identical, so no device time is needed. Inherited from downstream.
36. **`WCD9335_CODEC_RPM_CLK_MCLK_CFG_12P288MHZ` is `BIT(0)`**, same as
    `_9P6MHZ`; downstream writes `0x03,0x00` for 12.288 MHz. Pre-existing
    upstream and unused, so a maintainer may prefer deleting the define to fixing
    it. Standalone patch, own cycle, low priority.
37. **The `usleep_range(1000, 1100)` before the TX-hold release has no cited
    source** and runs per-ADC on every wcd9335 board. Removing it risks the
    silent capture returning, so it costs cold-boot A/B time. The same commit
    should say why the release is in the ADC widget's `POST_PMU` and not the
    decimator's.
38. **The reviewer asked for a table instead of the `switch`** in
    `wcd9335_get_dmic_clk_val()`. Cheap — but the `switch` deliberately mirrors
    mainline `wcd934x_get_dmic_clk_val()`, and converting wcd934x too means
    touching a driver we cannot test. Pick one, do not drift.
39. **The MBHC provenance needs reading, not patching.** MBHC really was in the
    2018 series (11/13 in v3, 11/14 in v4, dropped in v5, and v6 is what was
    accepted), but `254359e1` is superseded — item 23 replaced it with the shared
    `wcd-mbhc-v2`, whose legacy backend cites only its OnePlus downstream source.
    The question is whether anything there derives from the 2018 patch; citing it
    otherwise would be a false derivation claim.
40. **The TX-hold fix is codec-wide.** Mainline takes the hold and never releases
    it, so nothing can regress. By inspection of the device trees — not measured
    — OnePlus 3/3T are the only other wcd9335 board with analog mics wired, so
    they gain working analog capture; db820c and the Xiaomi msm8996 boards see no
    change. Belongs in the cover letter, with a Cc to maintainers who have the
    hardware.

41. **The WCD9335 does not survive an ADSP restart — diagnosed and fixed
    2026-08-23.** The SLIMbus NGD master is on the ADSP, so an ADSP SSR takes
    the codec's bus out from under it. The cause is not the bus going away, it
    is that `wcd9335_slim_status()` **ignored its `status` argument** and ran
    the whole bring-up on the *absent* notification, over a bus that was
    already down — leaking a register-map pair per restart and leaving the
    previous interrupt chip installed. Full account, with the before/after
    capture, in [`TODO.md`](TODO.md#-defect-3-diagnosed-the-codec-ran-its-bring-up-on-the-absent-notification).

    Three commits on this branch: `aba7e40c` (check the version-detect reads,
    which were testing uninitialised locals), `1d3ae998` (dispatch on the
    status and tear down on the way down; the irq chip and the ASoC component
    move off `devm` because their lifetime is the bus session, not the driver
    binding), `42b7e745` (free the per-function interrupts, which were `devm`
    on a device that never unbinds).

    **All three are upstream-shaped** — `wcd934x` already dispatches on the
    status, so this is wcd9335 catching up rather than an invention, and none
    of it touches anything out of tree. ☠️ `wcd934x` still has the sibling half
    of the same hole: it leaks its register map and re-adds its irq chip on a
    second present notification. Worth saying so in the cover letter; fixing it
    blind is not, since nobody here has that hardware.
    Proven to `#73-fp3` (r72); r73 carries commit three and is not yet
    deployed.
42. **`slim_rx_mux_put()` could NULL-deref from a mixer write** — fixed on this
    branch (`647cb5a1`) by initialising the channel list heads in
    `wcd9335_codec_probe()` instead of only in `wcd9335_set_channel_map()`.
    **Upstream-shaped and self-contained**; the bug is reachable by any user with
    access to the mixer on any wcd9335 board whose codec re-probes. Verified only
    as "did not crash in four attempts, one of them through the failure burst" —
    the crashing state was entered once, so the evidence is thin.
43. **`apq8016_sbc.c` latched the SLIMbus channel-map setup** for the life of the
    card, guarding state that lives in the codec — fixed here (`2f4ea47a`).
    ☠️ `sound/soc/qcom/sdm845.c` has the same shape and is untouched; deciding
    whether to fix both is part of preparing this one.

## `wip/7.1.3/camera` — Sony IMX363

Three commits: a verbatim import, our power-path delta, the DT node. The driver
is **Joel Selvaraj's** (`sdm670-mainline/linux` MR !3, commit `5130bc702ea2`,
2024-08-15), archived byte-identically on `vendor/imx363-sdm670`; our measured
delta is +68/−21 on 1514 lines, roughly half comments, functionally four things in
the power path.

33. **The focus actuator is at 0x0c and is not an LC898217.** ☠️ **This
    corrects the same item written earlier the same day.** `lc898217.c` plus its
    binding and MAINTAINERS entry landed 2026-08-01 and are worth keeping — the
    register map was read out of the board's vendor library
    `libactuator_lc898217xc.so` and validated against `libactuator_dw9714.so`,
    whose answer mainline's `dw9714.c` already states — but **the board DT node
    was removed again** (`wip/7.1.3/camera`), because it described hardware this
    phone does not have. Measured: with the actuator rail forced on and the
    sensor resumed so the camera IO rail is up, a **forced** scan of the CCI bus
    answers `0x0c 0x1a 0x50` and **nothing at 0x72**. ☠️ The scan must be forced
    (`I2C_SLAVE_FORCE`) or it silently skips every driver-claimed address —
    exactly the ones under investigation. Every `LC898*` in the vendor tree is at
    0x72 and every other family at 0x0c. ☠️ **Resolved later the same day, and
    the resolution is that both parts are real:** the vendor's
    `/vendor/etc/camera/camera_config.xml` pairs module `imx363` with
    `lc898217xc` and both second-source modules (`imx363_2nd`, `imx363pv_2nd`)
    with **`ak7374`** — Fairphone ships this phone two ways, exactly as it does
    with the battery pack. This phone has a second-source module, so `ak7374` it
    is; `dw9800` was never a candidate here, it belongs to a different module in
    the same file. Support is a chipdef plus a compatible in mainline's existing
    `ak7375.c` (register 0x00, 10 bits, shift 6, no standby), with the board node
    restored to point at it. The decode was re-validated against **two** known
    answers, `dw9714` and `ak7345`, after a four-byte base-offset error made
    every field decode to a plausible wrong value — see item 33b. ☠️ The
    downstream `value = 1023 - position` inversion excludes exactly `ak7374` and
    `dw9800`, so the polarity argument built on it does not apply to this board.
    Two side findings, both of
    which had looked like driver bugs: **the CCI bus does not work until the
    sensor's IO rail is up** (timeout `-110` versus `-ENXIO` tells "bus dead"
    from "nobody home"), and **a failed runtime-PM resume latches** into
    `runtime_status: error`, after which every resume returns `-EINVAL` and the
    subdev open fails several steps away from the real error — unbind/rebind
    clears it. Detail in
    [`docs/camera/README.md`](https://github.com/llg179org/fp3-pmaports/blob/main/docs/camera/README.md#the-focus-actuator).
33a. **`lens-focus` is how a lens subdev joins the graph**, and it worked:
    `v4l2_async_register_subdev()` alone leaves the subdev unclaimed, with no
    devnode and no media entity, so the driver is bound and invisible at once.
    `imx363` registers via `v4l2_async_register_subdev_sensor()`, which parses
    `lens-focus`; adding the reference put the lens in the graph immediately. The
    `lens-focus: true` line stays in `sony,imx363.yaml` for whatever part turns
    out to be fitted.
33b. **A vendor-blob decode is only worth what its known-answer control is
    worth.** The actuator parameter structure starts at `.data + 0x04`, not at
    `.data`, and with that four-byte error every field still decoded to a
    plausible value — an I²C address, a bit width, a register number, none of
    them right. Nothing in the output looked wrong. What caught it was running
    the identical decode against parts mainline already documents: `dw9714`
    (0x0c, 10 bits, no register address, shift 4) and `ak7345` (0x0c, 9 bits,
    register 0x00, shift 7). Seven fields across two parts now agree, and the
    AK7374's own numbers satisfy the family invariant that position width plus
    shift fills a 16-bit word (9+7, 10+6, 12+4). **Do not accept a struct decode
    without at least one control whose answer is known independently**, and
    prefer two — the first control is what made the earlier LC898217 decode
    trustworthy, and it is what made this one repairable.
33c. ✅ **SETTLED: the lens moves, and the two earlier verdicts were both wrong -
    in opposite directions - for reasons of measurement design.** Measured
    2026-08-01 on `linux-fp3-7.1.3-r32` (`#33-fp3`) with one capture held open
    for the whole run and the positions visited in interleaved passes of
    alternating direction. Full range, 11 positions x 3 passes: a single interior
    peak at 409 (428.7) with flat tails (0 -> 387.3, 1023 -> 380.6), between
    positions 48.1 against a worst within-position spread of 3.4, and only 1.3 of
    pass-to-pass drift. Zoomed in, 280..480 in 9 steps x 4 passes: peak at **380**
    (437.6), between 43.4, within 3.5, drift 0.9 - and 380 is where the operator
    independently reported the viewfinder looking sharp. ☠️ The two failure modes,
    both worth carrying: (1) the first "it moves" confounded position with capture
    order (0 always first, 1023 always second; order-balancing collapsed 44.0 to
    0.93 against a 0.76 order effect); (2) the "it does not move" restarted the
    stream for every capture - resetting auto-exposure and injecting a transient
    as large as the signal - **and compared 0 against 1023, the pair with the
    least contrast available**: they differ by 6.7 while the peak stands 48 above
    both. The response to this control is a peak, not a ramp, so an
    extremes-vs-extremes test is structurally blind to it. **Choose the contrast
    pair from the shape of the expected response, not from the ends of the input
    range.**
33c-1. **What is eliminated, all measured.** Writes reach the part (no i2c
    error); it is powered (`cam_af_2p85` and `cam_io_1p8` enabled, TLMM 128 and
    130 read `out high`); runtime PM keeps it `active`; the active-mode write
    happens (`ak7375_vcm_resume()` writes `reg_cont = mode_active`
    unconditionally - `has_standby` gates only the suspend-side write, which an
    earlier note here got wrong); nothing else writes the control (a value set
    with the camera app running is unchanged three seconds later, three times,
    and there is no autofocus on this stack); and the vendor does nothing more -
    its parameter block is fully decoded, ten register descriptors of which only
    the first is filled plus a single init write of `0x02 = 0x00`, which is
    exactly what the driver does.
33c-2. **What is still open on the actuator**: the *direction* (no position has
    yet been related to a subject distance - two targets at known distances and
    one sweep each settle it), and the *name* (that it is an AK7374 is inferred
    from the absence of anything at 0x72 plus the vendor configuration, not from
    asking the device; the sweep raises the confidence a long way, since a wrong
    register map would not produce a clean focus curve, but the module EEPROM at
    0x50 is where an identifier would actually be read - its layout is in
    `libmmcamera_ofilm_imx363_bl24s64_eeprom.so`, decodable the same way the
    actuator parameters were).
33d. **The recorded capture command did not work from a cold boot**, and the
    failure looked like a driver bug. The CAMSS pads default to
    `UYVY8_1X16/1920x1080` while the sensor is at `SRGGB10_1X10/4032x3024`, so
    `STREAMON` fails `-EPIPE` from pipeline validation with nothing in dmesg —
    the same symptom the pixel-format trap produces, from a different cause. The
    fix is to propagate the sensor format down `msm_csiphy0`, `msm_csid0`,
    `msm_ispif0`, `msm_vfe0_rdi0` with `media-ctl -V` first. Now done by
    `focus-sweep.py` itself and written into
    [`docs/camera/README.md`](https://github.com/llg179org/fp3-pmaports/blob/main/docs/camera/README.md).

33e. **SETTLED 2026-08-01 - autofocus is written and works.** libcamera's
    `simple` pipeline handler had no autofocus at all: `ipa_soft_simple.so`
    contained no focus symbol, the tuning file listed only
    `BlackLevel`/`Awb`/`Adjust`/`Agc`, and an app saw `Contrast` and `Gamma` and
    nothing else. It now carries a contrast-detection AF, kept as
    [`userspace-camera/libcamera/0101-simple-autofocus.patch`](https://github.com/llg179org/fp3-pmaports/blob/main/userspace-camera/libcamera/):
    a sharpness statistic in the software ISP's existing stats pass, accumulated
    into a 5x5 grid of zones; an `Af` algorithm in the simple IPA doing a coarse
    ladder of twelve positions then a fine ladder of seven; and the lens plumbed
    through the way the IPU3 handler does it. `AfMode`, `AfTrigger`, `AfMetering`
    and `AfWindows` are published. Verified live: a scan settles on **372**
    against the **380** that `focus-sweep.py` measures independently, and takes
    about 3.5 s at 1920x1080 (14 s at 4032x3024, because statistics come once
    every four frames and the software ISP sustains only ~6 fps there). Still
    open underneath it: the metric is not a proper contrast measure of a
    band-limited image, the search does not interpolate between the two best fine
    positions, and `LensPosition` is deliberately **not** advertised because it
    is defined in dioptres and no lens position on this phone has been related to
    a subject distance (see 33c-2). Whether the patch is worth offering upstream
    is a separate question - it is written to their conventions and carries
    `Assisted-by:`, but it has been measured on exactly one sensor.
33f. **Unbinding the ak7375 driver leaves a dangling ancillary media link and
    warns in the regulator core.** Each unbind/rebind adds another
    sensor-to-lens ancillary link instead of replacing it, and one of them ends
    up with a sink id of 0; libcamera then rejects the entire media device with
    `Failed to find MediaObject with id 0`, so the camera vanishes from every
    app until a reboot - while the actuator still works perfectly through V4L2.
    The unbind also produces `WARNING: drivers/regulator/core.c:2657 at
    _regulator_put` from `devm_regulator_bulk_release`, i.e. the supplies are
    still enabled when the driver is released. Both look like upstream bugs
    rather than integration mistakes, but neither has been reduced to a minimal
    reproducer yet, and neither is on any path the phone takes in normal use.
33f-2. **Merely enumerating the cameras can wedge the focus lens until reboot**,
    and this one *is* on a path normal use takes. Opening the lens subdevice
    runtime-resumes the actuator over the CCI bus; do that while another client
    is tearing the camera down and the transfer times out
    (`i2c-qcom-cci 1b0c000.cci: master 0 queue 0 timeout`, then
    `ak7375 0-000c: ak7375_vcm_resume I2C failure: -110`). Runtime PM latches the
    failure, so every later open returns `EINVAL`, libcamera logs *"Lens
    initialisation failed, lens disabled"*, and autofocus disappears for the rest
    of the boot while the camera still streams. Reproduced 2026-08-01 by
    restarting the PipeWire stack on top of a running camera client; **not**
    reproducible sequentially - two clean boots, four camera creations each,
    including one after a streaming run, all fine, and a PipeWire restart with
    nothing else touching the camera is also fine. Unclear yet whether the fault
    is the CCI driver's arbitration, the actuator's resume ordering, or a shared
    regulator dropping mid-transfer; each is a separate measurement.

    ☠️ **It does not take two *clients*, and libcamera's exclusivity does not
    protect against it.** Read in the source 2026-08-02:
    `CameraSensorLegacy::init()` calls `discoverAncillaryDevices()`, which opens
    the lens subdevice — at **camera creation**, so during plain enumeration,
    long before `acquire()` and entirely outside its lock. Measured the same
    day: `cam` was refused the camera with *"Pipeline handler in use by another
    process"* and had **still** powered the VCM up over I²C by then. The rule
    "one client at a time" is therefore not enough; anything that merely lists
    cameras touches the hardware.

    That also points at a fix: open the lens lazily, on `acquire()`, the way the
    uvcvideo pipeline handler already delays opening `/dev/video#` for power
    reasons. It would put the lens inside the exclusivity that already exists
    rather than inventing new arbitration.
33f-3. **The same CCI timeout can take the whole phone down, not just the
    lens.** Measured 2026-08-23 on r73 during a `fp3-selftest` battery: a
    `i2c-qcom-cci 1b0c000.cci: master 0 queue 0 timeout` was followed 2 ms later
    by `imx363 0-001a: Error reading reg 0x0016: -110`, then 60 s later
    `qcom-camss 1b00020.camss: VFE halt timeout`, then **60** `qcom-iommu-ctx
    1e34000/1e35000.iommu-ctx: timeout waiting for TLB SYNC` at 5 s intervals
    over 518 s, and finally `watchdog0: pretimeout event` — the debug layer
    resetting a phone that could not tear the camera down. Capture:
    [`docs/power/bringup/captures/2026-08-23_camss-iommu-wedge-watchdog.txt`](power/bringup/captures/).
    ☠️ **Do not assume 33f-2's fix covers this.** 33f-2's `-110` is on the
    **ak7375 lens**, and its proposed remedy is to open the lens lazily on
    `acquire()`. This `-110` is on the **imx363 sensor**, on a register read, so
    a lazy *lens* open would not obviously prevent it. What the two share is the
    shape — a CCI transfer colliding with a camera teardown — not the victim.
    Reproduced twice at battery scale (2 of 2 runs that include the camera
    block); a battery with `--skip camera` completed without a reset, and one
    with the first half of the pre-camera checks dropped still reset. Not yet
    reduced to a minimal reproducer, and not yet known whether the sensor `-110`
    causes the VFE halt timeout or both are downstream of the same stuck bus.
    ☠️ Two earlier resets in the same investigation were RCU stalls in
    `cpuidle_enter_state` with **no** camss or IOMMU line at all; that boot had
    zero RCU stalls. Two failure modes, one watchdog — do not merge them until
    something links them.

33g. **Focusing on demand works; focusing on a *point* still stops in
    PipeWire.** The zones and the `AfMetering`/`AfWindows` controls a tapped
    point needs are implemented in the IPA, but PipeWire's libcamera plugin maps
    a control to a node property only for `bool`, `int32` and `float` and
    returns early for any array (`if (cid.isArray()) return nullptr;` in
    `spa/plugins/libcamera/libcamera-source.cpp`, read from the source
    2026-08-01), so `AfWindows` never leaves libcamera. `AfMode` and `AfTrigger`
    do, which is enough for "focus now" and is what the app uses: Snapshot's
    autofocus switch and its tap-to-focus bind the PipeWire node directly - the
    `GstDevice` carries the id in `object.id` - because `pipewiresrc` has no
    properties for camera controls either. Verified by hand before any code was
    written: `pw-cli set-param <node> Props '{ 16777249: 1 }'` made the IPA
    scan. What is left for a *point*: the SPA plugin has to carry rectangles
    (SPA's own rectangle type is a size with no origin, so it would have to be
    an array of four ints), and the app has to turn a tap into a window. Both
    are upstream work in PipeWire, not on this phone.
33h. **The front sensor answers, and what is left is a licence question.**
    2026-08-03 on `linux-fp3-7.1.3-r36`: `s5k4h7 1-0010: S5K4H7 detected, model
    ID 0x487b`. It registers no subdevice, so `cam -l` still reports one camera
    and **no application can show a front view**. Every rail it needs was
    already in the board file - `pm8953_l22` also feeds the rear sensor and
    `vreg_cam2_dig_1p2` on GPIO 46 was declared and unused - with reset on GPIO
    129, MCLK1, CCI master 1 and a 270 degree mount, all read out of
    Fairphone's downstream `msm8953-camera-sensor-mtp.dtsi`, which also puts it
    on CSIPHY2/CSID1.

    ☠️ **The one thing that was actually missing was the pinmux, and the board
    file removed it.** `msm8953.dtsi` muxes both CCI buses on the controller
    (`pinctrl-0 = <&cci0_default &cci1_default>`), but this board overrode
    `pinctrl-0` to add its MCLK0 pin and dropped `cci1_default` in the process,
    so the second bus had no pins and MCLK1 never reached the sensor. The
    symptom told the story once read properly: `-110` is a transfer that never
    completed, where an absent device gives `-ENXIO`. Everything else was
    already right, which is what left the pins as the only candidate.

    ☠️ **A `-110` from `imx363 0-001a` at boot is *not* related, and looked
    exactly as if it were.** It lands ~300 ms after the front sensor is
    detected, in every boot. Moving `s5k4h7.ko` aside and rebooting shows the
    same error with the driver absent, so it predates this work; the rear
    camera binds, keeps 24 media entities and captures normally either side of
    the change.

    ☠️ **No port yet, deliberately.** CAMSS does not finish registering until
    every endpoint in its graph binds a subdevice, so wiring this sensor in
    before its driver registers one would stall the notifier and take the
    working rear camera down with it.

    **What blocks it is a licence question, not engineering.** There is no
    mainline V4L2 driver for this part anywhere - searched, and the one
    mainline-adjacent project that mentions the sensor supports the hi846
    variant of the same board instead. The register sequences exist only in
    vendor Android trees (MediaTek `imgsensor`, a Qualcomm CAMX
    `s5k4h7_setting.h`), and the ones found **carry no licence statement at
    all**: no SPDX line, no GPL notice, no `MODULE_LICENSE`. Copying them into a
    GPL-2.0 file is the same class of decision as the actuator in the licence
    audit, and it is a human's. What the bring-up driver does use is the model
    ID and where to read it - register 0x0000 holds 0x487b - which is a fact
    about the hardware, corroborated independently in two vendor trees.
33i. **The libcamera package installs a menu entry for a binary it does not
    build.** The aport ships `qcam.desktop` while building with
    `-Dqcam=disabled`, so `/usr/share/applications/qcam.desktop` points at a
    missing `/usr/bin/qcam`. Either drop the desktop file or build `qcam` - it
    would be a useful instrument, since it can set AF controls without going
    through PipeWire at all, but it pulls Qt onto a phone.

33j. **The focus lens is not related to any distance, so manual focus cannot be
    offered.** Everything else the camera does is now settable by hand -
    exposure time, gain, white balance - but `LensPosition` is defined in
    dioptres, and the IPA refuses to publish a dioptre it cannot mean
    (`0104-ipa-simple-Allow-the-focus-to-be-set-where-the-lens-.patch`). Two
    numbers unlock it, both in the tuning file: `lens-infinity-code`, and
    `lens-closest-code` with the `lens-closest-distance` it focuses at.

    Two ways to get them, in increasing order of trustworthiness. **Measured:**
    point the camera at a detailed target at a tape-measured distance, run
    `focus-sweep.py --lo/--hi` around the peak, and record the code; repeat far
    away for the infinity end. **Read out:** the module carries its own
    calibration EEPROM (`bl24s64` at CCI 0x50, no driver), which is where the
    vendor keeps exactly these two codes - the honest source, and the one that
    would be right for every FP3 rather than for this unit.

    Until then the lens still focuses - by itself, or on a tap - it just cannot
    be told a distance, and the app shows no focus row because the camera
    advertises none.
## `wip/7.1.3/sensor` — SMGR over QMI/QRTR

Accelerometer, gyroscope, magnetometer, proximity, ambient light. Only one commit
has been distilled — `soc: qcom: qmi: read QMI_DATA_LEN at its declared width` —
and that is the whole submittable set, not a backlog. Re-verified **2026-08-01**
against today's `torvalds/linux`: the `Fixes:` hash resolves with a matching
subject, the patch applies clean to the current `qmi_encdec.c`, and
`checkpatch --strict` is silent. ☠️ Everything else is **unsendable rather than
undone**: `smgr_accel.c`, `drivers/iio/common/qcom_smgr/` and `net/qrtr`'s bus
conversion all 404 against mainline, so ten of our eleven remaining commits and
both QRTR prerequisites patch files that do not exist upstream — **including the
mount-matrix fix of item 27, which otherwise looks like an ideal standalone
submission.** The reasoning, and the cheap check that settles it before any
distillation work, are in
[`docs/sensors/README.md`](https://github.com/llg179org/fp3-pmaports/blob/main/docs/sensors/README.md#why-the-submit-series-is-one-patch).
Gaps, in
[`docs/sensors/README.md`](https://github.com/llg179org/fp3-pmaports/blob/main/docs/sensors/README.md#known-gaps):

29. **`snsregd.py` is still a Python stand-in** for upstream's C `sns-reg`; it
    should become an aport. (Userspace, tracked here because the driver depends on
    it.)

## `wip/7.1.3/voice` — q6voice / CS-Voice over SLIMbus

One commit. Working on the device; see item 9 for why it is not sendable.

## The `debug` layer — bring-up aids, never upstream-bound

One commit: the watchdog started at probe. Nothing here gets a `submit/` series,
ever, and it stays off `integration/7.1.3`.

**It is the only category with no `wip` branch.** `wip/7.1.3/debug` was retired on
2026-07-30 (kept as the tag `archive/wip-7.1.3-debug-final`) once the layer became
reproducible without it: every other category needs a `wip` branch because it
carries evolving work against a moving base, while this one is a fixed, additive
change that replays anywhere. It now lives as that one commit on
`debug-int/<base>` plus the payloads in `fp3-pmaports/docs/debug/files/`, and
those payloads are half of the storage rather than a copy — refresh them in the
same commit that changes the layer.

The watchdog commit is the one place in the tree where mixing `.dts` with `.c` is
allowed, and it uses that licence: it adds an undocumented `qcom,start-at-probe`
property. That would be fatal in a `submit/` series and is fine here; the reason
is written into the commit message, along with why there is deliberately no
`ramoops` node (tried at `0x8ee00000` and at `0xd0000000`; nothing survives a
reset on this device, so it would cost 2 MB and imply a post-mortem capability
that does not exist).

### Replaying the debug layer onto any branch

The safety net is worth having on any branch you are about to boot — an
experimental offshoot is exactly where an early hang is likely, and exactly where
nobody wants to walk to the phone. One command, from the target branch:

```sh
git am ../fp3-pmaports/docs/debug/files/0001-watchdog-*.patch
```

The step-by-step — preconditions with defined failure actions, a by-hand
reconstruction for when the patch stops applying, and verification in three
places — is `fp3-pmaports/docs/debug/create_debug.md`.

It applies clean everywhere because the board-side change is a **separate**
`sdm632-fairphone-fp3-debug.dtsi` plus one `#include` among the other includes.
That is not cosmetic: every other category appends its nodes to the *end* of
`sdm632-fairphone-fp3.dts`, so the earlier form — which appended there too —
collided with whichever of them was present. Measured 2026-07-30: the appended
form conflicted on `wip/7.1.3/audio` and on `integration/7.1.3` and applied clean
on `camera` and `charger`; the split form applies clean on all five wip branches
and on integration. Verified again by rebuilding the layer from the stored
payloads onto a fresh branch off `integration/7.1.3`: same tree object as
`debug-int/7.1.3`, same blob for every file it touches.

---

## Not kernel work, kept here so it is not lost

30. **The notification LED blinks forever after a missed call** (`rgb:status`, not
    the flash). The real bug is a missing `EndFeedback` call in whatever raised it
    — phosh or the call app; secondarily, a `fairphone,fp3.json` feedbackd theme
    is missing.
31. **Untested: the interconnect path for the SCM/crypto node.** Non-blocking;
    kept in case the ADSP-boot timing question reopens.
33. **The camera app's *Find Best Size* measures the wrong quantity, and had
    settled on the worst size on the ladder.** It bisects the offered sizes and
    keeps the largest that still delivers frames — and 3840x2400 does deliver
    frames, at 7.1 fps, which is what a choppy viewfinder looks like. The step
    that decides the cost is invisible to it: a request that does not fit inside
    1912x1080 makes libcamera read out the full 4032x3024 sensor instead of the
    1920x1080 mode. Setting `preview-resolution` to 1680x1050 — the largest
    offered size that fits — measured 22.8 fps against 7.1, and is a gsettings
    change, not a rebuild. What should replace the frame-rate criterion in the
    search is the open question; the measurements are in
    [`camera/README.md`](camera/README.md#why-the-sensor-is-always-read-out-whole-and-what-it-costs).

35. **The camera app renders in software, and so does everything else.** The
    distro sets `GSK_RENDERER=cairo` session-wide for the a506; with a
    viewfinder running that costs 130% of a core in the app against 32% under
    `gl`, and it is why an interface stutters while the compositor sits at 2%.
    Overridden per user here, not in the package-owned file. Open: the app is
    reported to freeze under `gl`, with no core dump and nothing in the kernel
    log, so whether the distro's choice is protecting against something real on
    this GPU is not yet settled.

## The `vendor/*` and `archive/*` namespaces

Neither is a base and neither is ever pruned when a base is rolled.

- `vendor/imx363-sdm670`, `vendor/q6voice-sdm670` — **parentless snapshots** of
  third-party imports, made with `git commit-tree` and no `-p`, so the tree is
  byte-identical to the source without dragging in 71,541 unrelated commits.
  `git diff <snapshot> <source>` is empty, which is the check.
- `vendor/asoc-msm8953-base`, `vendor/q6voice-base` — tags, not branches: those
  commits are already in `7.1.3/main`, so they need a name, not a copy.
- `archive/*` — rewritten history kept reachable, so an old pin still resolves
  and its tarball still downloads.
