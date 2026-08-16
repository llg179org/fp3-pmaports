# Open items

> ⚠️ **AI-generated.** This page — and the code, device tree and tooling it
> describes — was written by Claude (Opus 5) working under the direction of
> Lajosházi, László Gergely, who reviewed every change and made or reviewed
> every measurement it rests on. Kernel commits carry `Co-authored-by: Claude`;
> anything prepared for the LKML carries `Assisted-by:` instead and never a
> `Signed-off-by` from the assistant, since only a human can certify the DCO.

Things that are known-broken, deliberately unfinished, or parked with enough
context to pick up later. Each entry says what was measured, not what was
guessed. Items that are already written up elsewhere are linked rather than
repeated.

## Where this stopped, 2026-08-14 — read this first after a long gap

Three facts and one direction. Everything else on this page is detail under one
of them.

**The device is on `linux-fp3-7.1.3-r53` and nothing is half-applied.** The
package pins `_commit=fa5d294c702d75aa447fe8ca90b65d49b1075c36`, that commit is
the tip of `debug-int/7.1.3`, it is what the phone is running, and the kernel
working tree is clean. Automatic sleep is off, the `smp2p-modem` wake experiment
is reverted, and no transient units are left on the device.

**The one thing worth working on is idle current — and as of 2026-08-14 evening
it is a platform gap, not a tuning problem.** The application processor has
**never once told the RPM it is going down**: its shutdown count is zero while
the modem's is 170 and the WLAN subsystem's is 284, and the SoC has consequently
reached neither `vlow` nor `vmin` since boot — not while idle, and not across
suspends of 60, 120, 300 and 600 s. That single zero explains the rest: the
unreachable 10.4 mA S3 threshold, the fuel gauge's rest anchor that never fires,
and why removing ten userspace daemons moved the floor by nothing. The whole
measurement, and the instruments that had to be added to make it, are in
[`power/README.md`](power/README.md#measured-2026-08-14-the-soc-never-reaches-an-rpm-low-power-mode).

**So the next question is: what should send the APSS sleep vote on mainline
msm8953, and why does nothing send it.** Everything below about milliamps is
downstream of that answer.

☠️ **The 139–143 mA floor and its daemon subtraction are retracted** — the lens
actuator was powered underneath the whole run. And the `ak7375` kernel fix that
was queued as "the cheapest next step" **already shipped**: `fa5d294c` is that
commit and r53 pins it. What remains there is userspace — nothing returns the
lens to rest when the preview stops.

**Two lines of work were deliberately stopped, not abandoned.** Both are written
up so they need no re-investigation:

* the fuel gauge's `.resume_early` rest anchor — written, measured working,
  [parked as a patch](charger/bringup/parked/README.md) because it is a
  workaround for an unreachable precondition, and the `S3_GOOD_OCV` path it
  substitutes for is already in the driver and merely starved;
* automatic sleep — demonstrated working, then switched back off because an
  incoming call cannot wake the phone. See the next section.

☠️ **Do not restart either by building a kernel.** Neither is blocked on code
that has not been written; both are blocked on the same 140 mA.

## An incoming call cannot wake the phone from s2idle

Measured 2026-08-14, and the reason automatic sleep is off. Across an 8 min 3 s
sleep (wall-clock log gap, `suspend_stats/success` 3→4) a call reached the modem,
the AP never woke, and on the button wake the queued event replayed — the dialer
showed busy and closed.

Of 151 IRQs, **three** are wake-armed: `wcn36xx_rx` and two thermal sensors.
Nothing modem-related is:

```
140:  2379  GIC-0  57  Edge  smd-edge   →  wakeup=disabled     (DT: GIC_SPI 25, the modem edge)
 15:     3  GIC-0  59  Edge  smp2p-modem →  wakeup=disabled
```

`drivers/rpmsg/qcom_smd.c:1421` requests the edge IRQ with plain
`IRQF_TRIGGER_RISING` and registers no wake IRQ at all, so there is not even a
userspace knob. During s2idle `suspend_device_irqs()` masks it, the call
interrupt waits, and it is replayed at resume.

**The one knob that does exist was tried and is measured useless.** `smp2p.c:731`
does `device_set_wakeup_capable()` + `dev_pm_set_wake_irq()`, disabled by default,
with a comment citing *"to not miss phone calls"*. Enabling
`/sys/devices/platform/smp2p-modem/power/wakeup` changed nothing: the `smp2p`
counter did not move once across the whole sleep, which is what proves the call
does not travel that line. It travels the SMD data edge.

**The fix, when it is worth building:** mirror smp2p in `qcom_smd_parse_edge()`,
after `edge->irq = irq`. `device_register()` happens first (`:1500` before
`:1507`), so the sysfs attribute lands correctly, and it is off by default like
its precedent:

```c
device_set_wakeup_capable(dev, true);
ret = dev_pm_set_wake_irq(dev, irq);
```

`CONFIG_RPMSG_QCOM_SMD=y`, so this needs a full build and flash — no module
hot-swap. A second layer is untested: even once the AP wakes, something must hold
an inhibitor while ringing or the system re-suspends immediately.

**Open question, not decided:** this belongs to no branch category. It is not
FP3-specific — `qcom_smd.c` is upstream and every SMD-era Qualcomm SoC is
affected, which with the smp2p precedent makes it unusually defensible on the
LKML. Functionally it is the call path, so `voice` is the closest fit.

☠️ **SSH does not wake the phone either**, despite `wcn36xx_rx` being wake-armed
— it times out with `No route to host`. Useful, because a logger left running
under `systemd-run --collect` cannot be contaminated by the observer polling it;
and a warning for anything that assumes the device is reachable while asleep.

## Open before anything is submitted

A red-team pass over the five `submit/7.1.3/*` branches on 2026-07-30 produced
this list. Everything here is measured — `checkpatch.pl --strict`, and
`dtbs_check` run against the base and against this tree so that only the errors
*we add* are counted (the base fails it 44 times on its own). The per-branch
summary is in [`kernel/README.md`](kernel/README.md#what-the-checkers-say).

~~**The camera series is the one that must not be sent as it stands.**~~ **Fixed
2026-07-30.** Its commit message claimed the driver was derived from `imx258.c`
with register tables read back from the sensor; both were false. The original was
found on GitLab (`sdm670-mainline/linux`, **Joel Selvaraj**, `5130bc702ea2`) and
fetched by SHA, the delta measured at **+68 / −21 on 1514 lines**, and the series
rebuilt as import → our change → device tree, with the original `Signed-off-by`
chain preserved. Details and the checkpatch split in
[`kernel/README.md`](kernel/README.md#camera-imx363c). The DCO chain turned out to
be **intact**, so the camera never had the sensor series' problem.

Then, in rough order of cost:

1. ~~**The camera has no binding and no MAINTAINERS entry.**~~ **Fixed
   2026-07-31.** `sony,imx363.yaml` is written, the MAINTAINERS block claims the
   driver, and the leftovers came out in a **third** commit after the import, so
   the imported commit stays byte-identical to Joel Selvaraj's original — that
   byte-identity is the only thing that makes our delta checkable.

   What the binding is worth is measurable, and the measurement is the point:
   until it existed, `dtbs_check` **skipped the camera node in silence**, because
   a node whose `compatible` nothing documents produces no output at all rather
   than being reported as unchecked. With the binding in place the node is
   checked for the first time and **adds nothing**: the board goes from the
   base's own 44 errors to 45, and the one addition is item 5's battery node,
   already known.

   Two places where copying `sony,imx258.yaml` would have been wrong. Its
   `data-lanes` pins the entries to 1..4; this driver only ever switches on *how
   many* there are, and 176 endpoints in mainline's arm64 device trees start
   their lane list at 0 — nearly every qcom board — so the value constraint would
   reject them for nothing. And imx258 leaves the supplies optional, where this
   driver takes all three with a plain `devm_regulator_bulk_get()`.

   The cleanup removed 97 lines: ninety-odd commented-out register writes, a
   dead 19.2 MHz input-clock path whose config table never existed, and two
   `printk(KERN_INFO)` calls. Two of those comments carried a **finding** rather
   than code — that a set of downstream writes, and a set taken from imx258,
   change nothing in the output — so they are kept as an ordinary comment.
   `checkpatch --strict` on the new patches: **0, 0 and 1**, the one being
   "does MAINTAINERS need updating?" which the next patch answers. The import's
   own 34 complaints are untouched on purpose.

2. ~~**The audio device tree adds six undocumented codec properties**~~ —
   `qcom,micbias{1..4}-microvolt`, `qcom,dmic-sample-rate`,
   `qcom,mbhc-vthreshold` on the `slim217,1a0` node. **Fixed 2026-07-30.** The
   WCD9335 binding now carries all of them, taking wording and limits from
   bindings that already describe the same hardware: the four mic-bias voltages
   verbatim from `qcom,wcd93xx-common.yaml`, the DMIC rate in the plain-uint32
   form the LPASS macro bindings use. The button thresholds were **renamed** on
   the way — `qcom,mbhc-vthreshold` in millivolts was this port's invention, and
   the rest of the family spells it
   `qcom,mbhc-buttons-vthreshold-microvolt` (wcd934x, wcd937x, wcd938x). The
   driver divides by 12500 instead of `(mV * 2) / 25`, so the value programmed
   into the BTNx field is unchanged. All six are disallowed on the SLIMbus
   interface device, where they mean nothing.
3. ~~**`divclk1` and `wcd-vout-1p8` sit under `soc@0`**~~, where `simple-bus`
   requires `ranges`. **Fixed 2026-07-30**: both moved to the root of the board
   file, and the regulator renamed to the `regulator-*` node-name form the file
   uses throughout.
4. ~~**`wcd-intr-default-state` fails the `qcom,msm8953-pinctrl` schema.**~~
   **Fixed 2026-07-30** by dropping `input-enable`, which
   `qcom,tlmm-common.yaml` disallows outright (`input-enable: false`): the TLMM
   input buffer is always on, so on this pin controller the property only ever
   cleared the output-enable bit, and gpio73 is put in input mode anyway when
   the codec's intr1 interrupt is requested. `sdm845-wcd9340.dtsi` describes the
   same codec interrupt without it.

   Items 2-4 were verified together rather than assumed: `dtbs_check` with
   `dtschema` 2026.6 reports **nothing** for the audio nodes now, on
   `wip/7.1.3/audio`, `integration/7.1.3` and `debug-int/7.1.3` alike, and
   sorted `dtc` decompiles of the board DTB before and after differ **only** in
   the two node moves, the dropped property and the renamed one.

   Confirmed on the device too, on `linux-fp3-7.1.3-r27`: the eight `BTN0..7`
   threshold registers read back **byte-identical** across the rename
   (`18 30 48 90 a0 a0 a0 a0`), the moved `divclk1` still claims the PM8953
   MCLK mux (`pin 0 (gpio1): divclk1 ... function func1`) and reaches
   `enable_count = 1` while playback runs over `SLIMBUS_0_RX`, and
   `23-audio-slimbus` passes with a headset plugged in — a 1 kHz tone crossing
   the bus in both directions, **999.76 Hz at 32.97 dB**. The jack still
   detects: `SW_HEADPHONE_INSERT` is active.
5. ~~**The battery node's `qcom,*` properties cannot stay there.**~~ **Moved
   2026-08-12**, in the shape `charger/README.md` had already argued for, as
   four commits: the generic property, the charger binding, the driver, the
   board.

   There were **five**, not four - the count in this item predated
   `qcom,auto-recharge-microvolt`. Four of them moved to the charger node: both
   JEITA threshold pairs, the soft-zone currents and the recharge voltage. The
   argument that decides it is not the schema but the layering: a threshold here
   is a **raw BAT_THERM ADC code**, and which code a temperature produces
   depends on the PMIC's ADC full scale and on the board's pull-up as much as on
   the cell, so it cannot travel with a pack. The battery-ID tolerance follows
   the pull-up onto the charger for the same reason - it has to cover the
   divider and the ADC, not only the resistor.

   The fifth stays with the pack, because the identification resistor really is
   inside it, and became the **generic `id-resistor-ohms`** added to
   `battery.yaml`. An ID resistor is not a Qualcomm idea, and a vendor-prefixed
   name on that node is rejected outright.
6. ~~**`-ohm` should be `-ohms`.**~~ **Done in the same commits.**
   `qcom,batt-id-ohm` is gone entirely (it is `id-resistor-ohms` now) and
   `qcom,batt-id-pullup-ohm` became `qcom,batt-id-pullup-ohms`. Nothing outside
   this tree can have been relying on either spelling: both are this port's own
   additions.
7. **Every branch is based on `v7.1.3-r0`.** Sending means rebasing first: ASoC
   onto `sound/for-next`, device trees onto mainline. Trial-rebased on
   2026-07-30, so this is no longer a guess: **11 of the 21 commits apply with no
   conflict**, the charger (9) and sensor (1) series entirely. Full table in
   [`kernel/README.md`](kernel/README.md#does-any-of-it-apply-to-a-maintainer-tree).
8. **The camera driver conflicts on two lines of `Kconfig`** — the neighbouring
   IMX355 entry gained `select V4L2_CCI_I2C` upstream. Trivial, but it has to be
   resolved by hand at rebase time.
9. **The audio series has a real prerequisite and it is stalled.**
   `qcom,msm8953-qdsp6-sndcard`, `msm8953_qdsp6_add_ops` and `use_ibit_clk` are
   not upstream; nor is the `&sound_card` label the audio DT patch attaches to.
   The functionality *was* posted — Adam Skladowski, *MSM8953/MSM8976 ASoC
   support* **v3**, 8 patches, 2024-07-31,
   [series 875540](https://patchwork.kernel.org/project/alsa-devel/list/?series=875540),
   still in state `new`. We need its patches 1/8, 5/8 and 6/8. Because it has a
   cover-letter message-id it can be declared as a dependency the way the kernel
   expects (`b4 prep --edit-deps`, or a `prerequisite-patch-id:` block) rather
   than silently assumed. Worth asking on the list whether it is still alive
   before building on it.
10. **The voice patch duplicates existing prior art and cannot be sent at all.**
    Joel Selvaraj's `5a63debde2db` (2022-10-02, `sdm670-mainline/linux`) already
    contains the same SLIMbus voice routing, line for line, and for SLIMBUS_0
    through SLIMBUS_6 rather than only SLIMBUS_0. Separately, `q6voice` has
    **never been posted to the LKML** — patchwork returns nothing for "q6voice"
    or "Q6 Voice" — so there is no message-id to depend on and the file does not
    exist upstream to patch. Archived as
    [`vendor/q6voice-sdm670`](https://github.com/llg179org/linux/tree/vendor/q6voice-sdm670);
    the realistic move is to offer the SLIMBUS_0 work to that series' authors
    rather than to send anything ourselves.
11. ~~**Two more WCD9335 properties are this port's invention, and their default
    is inverted.**~~ — `qcom,hphl-jack-type-normally-open` and
    `qcom,gnd-jack-type-normally-open`, against the family's
    `-normally-closed` spellings with the opposite default. **Fixed
    2026-07-31**, and the fix removed the question rather than answering it: the
    codec was moved onto the kernel's shared `wcd-mbhc-v2` (with a new legacy
    comparator backend, since this codec has no MBHC ADC), so it now calls the
    family's own `wcd_dt_parse_mbhc_data()`. Both invented names were deleted
    from the driver, from the binding and from the board file, and the board
    relies on the shared default — which is normally-open, the behaviour it
    already had. Verified with a headset on the device: a 4-pole headset, a
    3-pole headphone, the button and both removals all report correctly.
12. ~~**The measured rebase table no longer describes the audio series.**~~
    **Re-measured 2026-07-31**, all nine rows, against fresh bases
    (`broonie/for-next` `b8f7ea37085e`, `psy/for-next` `c57cb36f76eb`,
    `torvalds/master` `6269cc6f52c6`) and the regenerated thirteen-patch series:
    **22 of 27 commits apply with no conflict**, 23 after one one-hunk
    resolution. Audio went from "conflicts on the first patch" to **11/12** — the
    only conflict left is the machine driver, which is item 9's missing
    prerequisite and nothing else. Table in
    [`kernel/README.md`](kernel/README.md#does-any-of-it-apply-to-a-maintainer-tree).

    Two things the re-run corrected about the *method*, not the result. The
    camera's `Kconfig` conflict is no longer the IMX355 entry but `VIDEO_OV9282`:
    it lands on whichever entry sits next to ours, so naming the neighbour dates
    the note for nothing. And counting per commit while aborting each failure
    makes a cascade look like a catastrophe — the camera import fails on
    `Kconfig`, so the delta commit has no `imx363.c` to patch and the group reads
    **0/2** when the honest answer is one hunk, after which the second commit is
    clean.

13. ~~**`submit/7.1.3/audio` no longer matches the branch it is distilled
    from.**~~ **Regenerated 2026-07-31**, from thirteen commits: the binding, the
    machine driver, four wcd9335 fixes, q6afe, the OCP interrupts, the shared-MBHC
    work split three ways (function-table refactor with no functional change →
    legacy backend → the choice as a `wcd_mbhc_init()` parameter), the wcd9335
    conversion, and the device tree alone at the end. Every patch is
    single-domain; `checkpatch --strict` is clean apart from the two entries below
    that were checked and are not defects. The previous tip is the tag
    `archive/submit-7.1.3-audio-pre-mbhc-rework`.

    Three deliberate differences from `wip/7.1.3/audio`, none of them accidental:
    the `aw8898` `.prepare` fix is **excluded** (that driver is carried by
    msm8953-mainline and is not in Linus' tree, so it has no upstream destination
    in this series); the two q6afe commits are squashed into one; and the new
    `DEC*` volume controls are aligned to the open parenthesis while the
    pre-existing `RX*` ones above them are left exactly as mainline has them —
    the earlier series realigned those too, which is drive-by churn on code this
    work does not otherwise touch.

14. **Review feedback on the audio device tree — accepted in principle, not yet
    acted on.** An msm8953-mainline reviewer read the DTS commit
    (`2f76a315`, *wire up WCD9335 audio*) on 2026-08-02 and raised three things.
    Nothing below is implemented: each point needs the pro-and-contra written out
    and confirmed before anything is changed, because two of them touch the
    device tree the phone currently runs on.

    * **"Does it really have 6 digital mics?"** — no, and this one is already
      **measured**. The six-DMIC / AMIC1..6 block was transcribed from
      Fairphone's downstream `msm8953-audio.dtsi`, which is Qualcomm reference
      boilerplate: it also lists ANC headset mics, `Analog Mic6` and
      `SpkrLeft/Right IN`, none of which exist on this phone (the speaker is a
      single mono AW8898 on Quinary MI2S). Swept on the device with a 1 kHz tone
      from its own speaker, `DEC0` capture on `hw:0,1`, Goertzel at 1 kHz, three
      repeats per input:

      | input | 1 kHz bin | verdict |
      |---|---|---|
      | DMIC0 / DMIC1 | ~2200–2700 | live — bottom mic, next to the speaker |
      | DMIC2 / DMIC3 | ~520–630 | live — top mic, 5× quieter because it is further away |
      | DMIC4 / DMIC5 | exact 0 (3/3, every run) | not populated |
      | AMIC2, headset plugged in | 1437 | live — headset mic |
      | AMIC2, empty jack | 0.25 | noise floor only |
      | AMIC1, 3, 4, 5, 6 | exact 0 | not populated |

      The headset gives the positive control the first sweep lacked: AMIC2 moves
      from noise floor to 1437 while every other analog input stays at exact
      digital zero, so those zeroes are absence, not a broken measurement.
      `wcd9335_codec_enable_dmic()` maps DMIC0/1 → `CPE_SS_DMIC0_CTL`, DMIC2/3 →
      `DMIC1_CTL`, DMIC4/5 → `DMIC2_CTL`, i.e. three clk/data pad pairs of two
      channels each — so **two populated DMIC lines, which is exactly the two
      built-in mics the FP3 has**, and the odd slots are the same data line read
      on the other edge.

      Two corrections fall out of this. `"AMIC5", "MIC BIAS3"`, which the commit
      message describes as the handset mic, is **measurably wrong** — AMIC5 is
      dead and the built-in mic is DMIC0, which is also what
      `fp3-mic-select handset` uses. And `qcom,micbias4-microvolt` has nothing
      left to bias.

      ☠️ **Measurement trap for whoever redoes this:** individual captures
      occasionally return exact digital silence (the decimator power-sequencing
      quirk described in
      [`../userspace-audio/README.md`](../userspace-audio/README.md)), and on
      back-to-back mux changes the previous value leaks into the next reading —
      DMIC3 came out identical to DMIC2 in two separate sweeps. Repeat at least
      three times per input and do not conclude from a single run.

    * **"Only one other sdm632/sdm450 device tree defines `audio-routing`, and
      not with a list this long."** The comparison is against the wrong family
      and the answer is defensible: every other msm8953/sdm450 board drives the
      **PM8953 internal codec**, whose routes live in the codec driver, so three
      `AMIC → MIC BIAS` lines suffice. FP3 is the only msm8953 board with an
      external WCD9335 over SLIMbus, where `MCLK` and `MIC BIAS1..4` are
      `SND_SOC_DAPM_SUPPLY` widgets with no in-codec route, so the board has to
      pull them in. The precedent is on the msm8996 side —
      `msm8996-oneplus-common.dtsi` and `apq8096-db820c.dtsi`. The *length*,
      though, is only justified for the inputs that exist, so this point is
      settled by the DMIC pruning above rather than argued away.

    * **"The wcd9335 codec node looks weird too — any similar examples?"** Yes,
      and the node is near-verbatim from them: `msm8996-xiaomi-common.dtsi`
      (same `slim217,1a0` `codec@1,0`, `slim-ifc-dev`, `intr1`/`intr2`,
      `reset-gpios`, mclk + slimbus clocks, the `vdd-*` set, and a `divclk1`
      `gpio-gate-clock` even carrying the same `divclk1_cdc` label),
      `apq8096-db820c.dtsi`, `msm8996-oneplus-common.dtsi`,
      `msm8996pro-xiaomi-{natrium,scorpio}.dts`. Only the msm8953 addresses and
      the FP3 supply/GPIO/pinmux instantiations are new, because no msm8953
      board in-tree instantiates the SLIMbus NGD at all. **One genuine defect
      surfaced by the question:** on msm8996 the `slimbam` and `slim_msm` nodes
      live in the SoC `.dtsi` (`msm8996.dtsi`) and the board only writes
      `&slim_msm { ... }`; ours sit in the board `.dts` under `&soc`. They
      belong in `msm8953.dtsi`, status `disabled`, with the board enabling them
      and adding the codec child.

    The reviewer also confirmed the quinary DAI link is fine as it stands.

    **What a v2 would be**, once confirmed: cut `audio-routing` to `RX_BIAS`/
    `MCLK`, AMIC2 on MIC BIAS2, DMIC0 on MIC BIAS1 and DMIC2 on MIC BIAS3; drop
    `qcom,micbias4-microvolt`; move the NGD/BAM nodes to `msm8953.dtsi`. It
    touches `wip/7.1.3/audio`, `integration/7.1.3` and `debug-int/7.1.3`, and
    the mics have to be re-measured on the device afterwards, since the pruned
    routes are the ones that power the capture path. Open sub-question, not
    needed for the pruning but worth one test: which slot of each pad pair is
    the real capsule — covering one mic port and re-sweeping answers it.

15. **Review feedback on the audio *driver* commits — nothing implemented, each
    point needs confirming first.** The same reviewer read three commits of
    `wip/7.1.3/audio` on 2026-08-02 — `ca9aaa72` (mic bias and DMIC rate from
    the DT), `377269e4` (the TX front-end hold) and `254359e1` (MBHC jack
    detection) — and checking the comments turned up five more things we found
    ourselves. As in item 14, none of it is done, and each point is written with
    the argument against it, because three of them are cheaper to get wrong than
    to leave alone.

    One question the pass raised is **already answered**: *"where are
    `qcom,micbias1-microvolt` … and `qcom,dmic-sample-rate` defined? I can't see
    them in the bindings."* Item 2 above — the binding has carried all six since
    2026-07-30. What misleads a reader is that `wip/7.1.3/audio` is
    discovery-ordered, so there the driver commit precedes the binding commit; on
    `submit/7.1.3/audio` the binding is patch 1 of 13. Nothing to change, but the
    reply has to say so.

    * **A bare `BIT(2)` goes into `WCD9335_CODEC_RPM_CLK_MCLK_CFG`** in
      `wcd9335_codec_init()`, where every other field in this driver has a named
      macro in `wcd9335.h`. *Against naming it:* we cannot name it **truthfully**
      — there is no datasheet, and downstream has no name either, only an
      unnamed `tasha_codec_reg_defaults[]` entry (`{MCLK_CFG, 0x04, 0x04}`, and
      `0x05, 0x05` in the I²C variant, so the bit is independent of the MCLK
      rate). A confident invented name is the mistake of item 11 repeated. The
      honest options are a neutral name plus a comment saying the function is
      undocumented, or an A/B on the device to find out whether the write is
      needed at all — the commit claims garbled playback without it, and that
      claim is not backed by a recorded measurement. Two adjacent
      `regmap_update_bits()` on the same register should become one either way.
    * **The `0x20` written into the EFUSE sense-state field is a dead value.**
      `WCD9335_CHIP_TIER_CTRL_EFUSE_SSTATE_MASK` is `GENMASK(4, 1)` = `0x1e`, so
      `0x20 & 0x1e == 0`: the call clears bits 4:1 and does nothing else. That
      happens to be the intended "select state 0", but the constant reads as
      "set bit 5". Writing `0` is arithmetically identical, so **no device time
      is needed**. The oddity is inherited, not ours — downstream does the same
      `0x1E, 0x20` — so the only argument against is that it stops being a
      verbatim copy, which a comment covers. Cheapest item here.
    * **`WCD9335_CODEC_RPM_CLK_MCLK_CFG_12P288MHZ` is `BIT(0)`**, the same as
      `_9P6MHZ`; downstream writes `0x03,0x00` for 12.288 MHz, so it should be
      `0`. Pre-existing upstream, independent of this series, and a clean
      standalone patch. *Against:* the define is **unused**, so a maintainer may
      prefer deleting it to fixing it, and a patch found by reading rather than
      by measuring is easy to read as noise. Low priority, own submission cycle.
    * **The `usleep_range(1000, 1100)` before the TX-hold release has no cited
      source.** It runs per-ADC on every wcd9335 board. Downstream has no sleep
      at that site — its settle time came from the HPF delayed work's scheduling
      delay, which mainline dropped along with the release itself. *Against
      touching it:* removing it risks bringing back the silent capture this
      commit fixes, and proving that costs cold-boot A/B time on the device.
      Keeping it with a measured justification is an acceptable outcome; keeping
      it with none is not. The same commit message should also say why the
      release sits in the ADC widget's `POST_PMU` and not the decimator's — DAPM
      powers the decimator and its mux first, so the amic lookup there runs
      before the analog front end is up. Without that sentence the first review
      comment will be "move it to the decimator handler".
    * **The reviewer asked for a table instead of the `switch`** in
      `wcd9335_get_dmic_clk_val()`. Cheap, no functional change, and the six
      `WCD9335_DMIC_CLK_DIV_*` values are `0x0`–`0x5` in the same order as the
      dividers `{2, 3, 4, 6, 8, 16}`. *Against:* the `switch` is a deliberate
      copy of mainline `wcd934x_get_dmic_clk_val()` (`wcd934x.c`, same divider
      set, same fallback), and converting only ours ends the symmetry that makes
      folding both into one helper obvious later. Converting wcd934x too doubles
      the work on a driver **we cannot test**. Decide which, do not drift into it.
    * **The MBHC provenance needs checking, not patching.** `254359e1` links the
      v3 **cover letter** of Srinivas Kandagatla's 2018 WCD9335 series, which
      never mentions MBHC — hence the reviewer's "I cannot find references to
      the MBHC support dropped from the series". It is there: MBHC is patch
      11/13 in v3 and 11/14 in v4 (patchwork
      [10587057](https://patchwork.kernel.org/patch/10587057/), with its bindings
      patch [10587061](https://patchwork.kernel.org/patch/10587061/)), gone in v5
      (8 patches), and v6 — also 8 — is what was accepted, which is why mainline
      has never carried MBHC. But `254359e1` is a **superseded** commit: item 11
      replaced that private implementation with the shared `wcd-mbhc-v2`, and
      `f5759717`, the legacy comparator backend, cites only its OnePlus
      downstream source. So the open question is not the broken link, it is
      whether **anything** in `f5759717` derives from the 2018 patch. If it does,
      it must be cited; if it does not, adding the citation would be a false
      derivation claim — the camera mistake in mirror image.

      **Read and answered 2026-08-08: nothing derives from it, so it must not be
      cited.** The two are different code, not two versions of one. Kandagatla's
      10587057 touches `wcd9335.c` and nothing else — a codec-private
      implementation (`wcd9335_mbhc_sw_irq`, `wcd9335_mbhc_btn_press_irq`,
      `wcd9335_program_btn_threshold`, `wcd9335_mbhc_initialise`), with no
      reference to `wcd-mbhc-v2` or `wcd-mbhc-legacy`. `f5759717` adds a backend
      to the shared `wcd-mbhc-v2.c` through its function table, in the
      `wcd_mbhc_*` namespace, ported from OnePlus's `wcd-mbhc-legacy.c`
      (Copyright 2015-2017 The Linux Foundation) — a different file, a different
      namespace and a different integration model. The one thing they share is
      the comparator-and-current-source FSM instead of an ADC read, and that is
      dictated by the hardware — the WCD9335 has no MBHC ADC — and traces to the
      common Linux Foundation downstream that predates both, which each derived
      from independently. So the reviewer reply states this and adds no
      Kandagatla citation; citing him would be the false-derivation mistake the
      camera series taught, run in reverse.
    * **The TX-hold fix is codec-wide, and one other mainline board notices.**
      Mainline takes the hold in `wcd9335_codec_enable_adc()` and never releases
      it, so the change cannot regress anyone: it supplies a missing half. By
      inspection of the device trees — not measured, and it has to be worded that
      way — `msm8996-oneplus-common.dtsi` is the only other wcd9335 board wiring
      analog mics (AMIC2/4/5), so OnePlus 3/3T gain working analog capture, while
      `apq8096-db820c.dtsi` and the Xiaomi msm8996/msm8996pro boards declare no
      AMIC routes and their ADC widgets never power up. Worth stating in the
      cover letter and worth a Cc to the OnePlus 3 maintainers, who have hardware
      we do not. *Against:* a Cc invites a wait, and an unverified cross-board
      claim is worse than none — hence "by inspection".

    **Order, if any of it is confirmed:** the EFUSE constant first (no device
    time, no judgement call), then the DMIC table and the cover-letter wording,
    then the provenance read. The `BIT(2)` naming and the 1 ms sleep are last
    because both really want a measurement, not a decision.

Two things were checked and are **not** defects: the three `ENOTSUPP`
comparisons in the audio machine driver (the ASoC core returns exactly that, and
the base file plus six other qcom machine drivers compare against it), and the
undocumented `slim217` vendor prefix (absent from `vendor-prefixes.yaml`, but
already used by four device trees in Linus' tree).

## Licence and provenance

An audit on 2026-08-02 asked one question — *is anything in this work copied from
closed-source Android code, or otherwise carried under the wrong licence?* — and
walked all five `wip/7.1.3/*` categories, the SPDX header of every `.c`/`.h` they
touch, the authorship of every import commit, and the provenance tables in
[`kernel/README.md`](kernel/README.md#provenance) and
[`sensors/README.md`](sensors/README.md#provenance).

**The headline is negative: there is no closed-source Android driver in the fork
and no file carried under the wrong licence.** Every source file the five
categories touch is GPL-2.0 by SPDX — the single exception,
`scripts/mod/file2alias.c`, carries no SPDX line upstream either and this work
adds ten lines to it. No firmware blob is checked into either repository; the
ADSP, modem and WCNSS images stay on the phone's own partitions and are
referenced by name.

What the audit did find, in descending order of exposure. **None of it is acted
on**; each item needs its pro and contra written out and confirmed first, and the
first one is a legal judgement rather than a technical one.

1. **`drivers/media/i2c/lc898217.c` is the one part derived from closed
   source.** The actuator's whole register interface — slave address, address
   and data widths, position register, code width, power-up write — was read out
   of `libactuator_lc898217xc.so`, the proprietary vendor userspace library
   shipped with this board's Android firmware. There was no GPL source to take
   it from: Qualcomm's downstream keeps no register map in the kernel for this
   part at all (the node is a bare `qcom,actuator` with a CCI master number, and
   the generic engine in `msm_actuator.c` is fed the map from that library over
   an ioctl), and searching the downstream tree for the part number returns one
   hit, an unrelated string in `sound/pci/hda/patch_realtek.c`.

   In favour: what came out is a hardware register map for a **third-party ON
   Semiconductor part** — facts about hardware, not expression; it was read from
   the library's `.data` section rather than decompiled; and the decode was
   validated against a known answer (the same layout applied to
   `libactuator_dw9714.so` reproduces, field for field, what `dw9714.c` already
   does in-tree, and recovers that part's documented power-up sequence). The EU
   Software Directive's Article 6 interoperability exception and the US
   *Sega v. Accolade* / *Sony v. Connectix* line both point the same way, and the
   kernel takes reverse-engineered drivers routinely. The method is stated in the
   commit message rather than left implicit, which is the right shape.

   Against: any EULA on the firmware is a separate, contractual question that
   none of the above answers, and on the LKML this is the point a maintainer will
   ask about first. ☠️ **This is a decision for a human, not something to resolve
   by writing a better commit message.**

2. **The imported sensor base cannot carry a DCO.** `bc02a8f70f69` *WIP: iio:
   Add Qualcomm Sensor Manager driver* and `e4f194b29e8a` *WIP: iio: accel: …*
   are Yassine Oudjana's code and carry **no `Signed-off-by` at all**, not even
   his own. The licence is fine — GPL-2.0-only by SPDX — but the certification
   chain is not, and only he can supply it. His other two QRTR commits are
   properly signed off. Already the first of the three reasons
   `submit/7.1.3/sensor` is a single patch; see
   [`sensors/README.md`](sensors/README.md#why-the-submit-series-is-one-patch).

3. **Checked and clean, recorded so the question is not reopened.**
   `imx363.c` is Joel Selvaraj's reverse-engineering work under GPL-2.0, keeping
   `Copyright (C) 2018 Intel Corporation` from the driver it is structured on,
   and the import preserves the full chain (Joel → panpanpanpan → Richard Acayan
   → us). Every value taken from the vendor — DT addresses, mic-bias voltages,
   the DMIC rate, the JEITA thresholds, the actuator inversion in
   `msm_actuator.c` — comes from Fairphone's **published GPL kernel release**,
   the same licence as the files it lands in. `qcom_smbx.c`, `wcd9335.c`,
   `wcd-mbhc-v2.c`, `apq8016_sbc.c`, `q6afe.c` and `q6voice-dai.c` are all
   in-place extensions of GPL code that was already in the base.

4. **Four compliance gaps in this repository**, none in the kernel fork, all of
   them small:

   * There is **no `LICENSE` or `COPYING` file**. The
     [top-level README](../README.md#license) states GPL-2.0-only and nothing
     else does.
   * [`device_tree/downstream/fairphone/3.A.0136/`](device_tree/downstream/fairphone/3.A.0136/)
     redistributes 938 of Fairphone's GPL-2 device-tree files. Each one keeps its
     Linux Foundation copyright and GPLv2 notice — checked, not assumed — but
     **the licence text is not shipped alongside them**, which GPL-2 §1 asks for.
     Copying in a `COPYING` closes it.
   * [`sensors/bringup/data/sns.reg`](sensors/bringup/data/sns.reg) and the 1437
     pairs decoded from it in
     [`../userspace-sensors/registry.conf`](../userspace-sensors/registry.conf)
     are the phone's factory sensor registry — third-party vendor data, under no
     stated licence, in a public repository.
   * [`../userspace-sensors/groups.txt`](../userspace-sensors/groups.txt) is the
     group map taken from upstream
     [`sns-reg`](https://gitlab.com/msm8996-mainline/sns-reg)'s `map.c`, and
     **that project's licence is recorded nowhere here**.

   The libcamera and Snapshot changes are shipped as patches against their own
   upstreams, so they raise nothing.

Separately from licensing, the AI-authorship policy is already settled and needs
no work: local fork commits carry `Co-authored-by: Claude`, anything prepared for
the LKML carries `Assisted-by:` and never a `Signed-off-by` from the assistant.
That is also why the LKML is the only open destination — see
[`FP3-TODO.md`](FP3-TODO.md) and the top-level README.

## Holding the camera open costs ~100 mA of idle current

Measured 2026-08-13, and it accounts for most of the pmOS-versus-Ubuntu-Touch
idle gap: three twelve-minute phases on one discharge, one change between each,
72 samples apiece — **166 mA as found, 68 mA with the camera released**, and
stopping wireplumber outright saves nothing beyond that. Full numbers and the
two explanations that were tested and failed (it is not CPU, and `clk_summary`
is identical) in [`power/README.md`](power/README.md).

The mechanism is a pair of behaviours that are each defensible alone:

* `ak7375_open()` takes a runtime-PM reference, so **opening** the subdev powers
  the voice-coil motor — the upstream pattern for VCM drivers;
* libcamera's pipeline handler keeps every device of a camera open for as long
  as the `CameraManager` lives, and wireplumber keeps one alive to publish the
  camera to PipeWire.

Together they mean a phone with an autofocus motor pays for it whenever anything
enumerates cameras, whether or not a picture is ever taken.

☠️ **Disabling wireplumber's `monitor.v4l2` / `monitor.libcamera` is the
measurement, not the fix** — it removes the camera from PipeWire entirely. What
a fix looks like is the open question, and the options sit in different projects:
have libcamera close the subdevs when no camera is acquired; give the actuator an
autosuspend delay so an idle open costs nothing; or have the session manager
enumerate and then let go.

**Which of them is worth doing is now measured.** The hold was split on
2026-08-13, using a bare shell as the holder (`sh -c 'exec 3</dev/v4l-subdev17;
sleep 100000'`) so that exactly one node is open per phase — three more
twelve-minute phases on one discharge
([capture](power/2026-08-13_pmos_lens-vs-chain.txt)):

| phase | held open | median current | median power |
|---|---|---|---|
| P0 | nothing | 79.7 mA | 0.342 W |
| **P1** | **the `ak7375` subdev alone** | **152.4 mA** | **0.643 W** |
| P2 | `media0`, `video0`, CSIPHY/CSID/ISPIF/VFE, `imx363` — all but the actuator | 76.4 mA | 0.323 W |

P2 lands on P0: **the sensor and the whole CSI/VFE front end cost nothing while
merely open, and the entire hold cost is the lens motor** — +0.30 W on its own,
with `cam_af_2p85`/`cam_io_1p8` `enabled` in P1 and `disabled` in both others.

So the fix belongs in **`ak7375`**: `ak7375_open()` takes the runtime-PM
reference and only `ak7375_close()` drops it, so the motor is up for as long as
any file descriptor lives. Closing the subdev in libcamera would work too, but
it treats the symptom in one consumer while the driver keeps charging every
other one.

☠️ **Adding an autosuspend delay is not the fix**, however much it sounds like
one: autosuspend acts when a device goes idle, and this device never does — the
reference is held, not slow to expire. ☠️ **And moving the reference to the
position write with a delay after it is not the fix either** — a voice coil
holds its position only while driven, so a timer expiring under a focused
preview would let the spring pull the lens out of focus.

**Written and measured 2026-08-13.** Power follows the **requested position**: a
reference is taken for the first position away from rest and dropped when the
lens is asked back to it. Focus is never lost, because a non-zero position keeps
the reference; idle costs nothing, because idle *is* the rest position.
Hot-swapped into the running kernel and measured with the same phases: **holding
the subdev costs +2.8 mA / +0.011 W**, against +72.7 mA / +0.30 W on the stock
driver ([capture](power/2026-08-13_pmos_ak7375-position-power.txt)).

What is left on it:

* **the autofocus regression is unrun** — a real capture must still focus and
  *hold* focus. It could not be done in the swap session: unbinding the subdev
  left the media graph inconsistent (`Failed to find MediaObject with id 0`) and
  libcamera stopped enumerating the camera until a reboot. Note that `cam` alone
  does not exercise AF — `focus_absolute` stays 0 — so this needs the AF path
  the camera app uses;
* **the verdict must come from a package build**: `insmod` of a locally built
  module raised an `ftrace_bug` warning. It is a hot-swap artefact, but it makes
  the vehicle unfit for a final answer;
* **`driven` is one flag shared by all consumers**, so with two opens a
  `close()` could drop the reference out from under the other. Consumers are
  single here, but this has to be resolved before the driver goes to
  `linux-media`, where other boards use it.

Left open underneath all of it: why a VCM that is powered and commanded nowhere
dissipates a third of a watt at all — a question about the part, and the only
one a rail probe could still answer.

☠️ Compare those phases against the earlier A/B/C **in power, not in current**:
they ran at a different state of charge, and the same power draws less current
at a higher terminal voltage.

☠️ Kill such holders **by PID found in `/proc/*/fd`**: `pkill -f` matches the
very SSH command line that carries the pattern, and kills the shell issuing it —
silently, with no output and no error.

## ~~`15-hwtest` cries wolf twice, and is the one check that is audible by default~~ — settled 2026-08-13

**Settled by narrowing what `hwtest` is asked to judge.** The check and the
reference now skip the same eleven components, and both list them, so `--verify`
keeps its regression semantics over what is left: the framebuffer, the DRM
connector and every input device — touchscreen, power key, volume keys and the
headset jack's input node, which nothing else in the suite covers. It runs
silently in two seconds and passes; the vibrator coverage it gave up came back
as a new `16-vibrator`, which reads the device and its force-feedback mask
without shaking the phone.

Three things were measured on the way, and each changed the answer:

* ☠️ **`--skip` takes one component per flag.** It is `action='append'` and the
  test is `c.__name__ in args.skip`, so `--skip Camera,Audio` matches nothing
  and skips nothing, silently.
* ☠️ **`hwtest --export` crashes on this device**, which is why the skip list is
  eleven long rather than three. It writes each result's path as a
  comment-shaped key, and Python 3.14's configparser refuses a key containing
  the delimiter — every IIO path has one (`iio:device2`), and so does the LED
  (`rgb:status`). The export dies with `InvalidWriteError` partway through,
  leaving a truncated file. Worth reporting upstream.
* ☠️ **The suite could not run over WiFi at all**, and the symptom was
  `device <ip> unreachable`. `lib/common.sh` forced
  `PreferredAuthentications=password -o PubkeyAuthentication=no`, while sshd
  here accepts a password only on the USB subnet — so our own SSH hardening
  locked the tests out of the wireless link. Fixed by letting the key be tried
  first, with the password as the fallback it always was.

The original report follows.

Two components of `hwtest` call this device broken when a check of our own says
otherwise, measured 2026-08-12 with `--verbose`:

* **camera** — it asks for a 320x240 and then a 640x480 JPEG and gets neither
  (`[Errno 2] ... '/tmp/320x240.jpg'`), on a sensor that captures its full
  4032x3024 on demand. `40-camera` judges the sensor, its subdev and its link
  into CAMSS, and passes.
* **proximity** — it wants `in_proximity_scale`, which this driver does not
  expose and does not have to: the channel reports raw counts with no physical
  unit. `25-sensor` reads `in_proximity_raw` (274 counts) and the
  iio-sensor-proxy properties in-call blanking depends on, and passes.

Separately, this is the **only check that makes noise without `--acoustic`** —
its audio component drives the loudspeaker (at half volume, since the check
borrows the level helpers) and its vibrator component runs the motor. The
suite's rule everywhere else is that anything audible is opt-in, and a full run
at night is not the moment to find the exception.

☠️ **`--skip` alone is not the fix.** A skipped component is *missing* from the
run, and `hwtest --verify` exits 1 on a removal as well as on a regression:
skipping components on the run but not in the reference turns one failure into
several. Whatever is skipped has to be skipped when the reference is exported
too — which is what was done above, and it is a decision about what the
baseline means rather than an edit to the check.

## ~~The handset microphone is dead on a fresh boot~~ — solved 2026-08-14: a package upgrade overwrote our UCM verb

**Cause, measured:** `/usr/share/alsa/ucm2/Fairphone/fp3/HiFi.conf` on the
device was **not ours**. It was the 423-byte stock file shipped by
`soc-qcom-msm8953-ucm-20-r0`, carrying a single `Speaker` device — where ours is
4057 bytes with Speaker, Earpiece and Headphones. The whole `ucm2/` tree was
rewritten `Aug 6 22:37`, when a package install last resolved `world`. Nothing
outside the tree was touched: `90-fp3-mic.pa`, `fp3-mic-select`, `fp3-voiced`,
the vibra rule and both services were all still in place, because they live in
`/etc` and `/usr/local` and are not package-owned.

That one file explains every symptom at once, and both mechanisms are already
written down in `userspace-audio/README.md`:

* our verb pre-routes MultiMedia1 to a backend, because a q6asm front end
  returns `EINVAL` on open until it is routed. The stock verb does not, so
  PulseAudio's profile probe failed, it found no working profile, and the card
  sat at `Active Profile: off` behind an `auto_null` sink — which is also why
  no `module-alsa-source` ever appeared.
* our verb pre-routes `DMIC0 → DEC0 → SLIMBUS_0_TX`, which is what makes
  `hw:0,1` openable. The stock verb does not, hence `Invalid argument`.

**Fix applied:** copied `userspace-audio/ucm2/Fairphone/fp3/HiFi.conf` back into
place and restarted the sound server with `pulseaudio -k`. Verified immediately
after: `Active Profile: HiFi (Speaker)`, the real sink back, `fp3-handset-mic`
present, and both checks green — `20-audio` (`capture PCM hw:0,1 opens`) and
`35-pulse`. No reboot, no kernel change.

☠️ **It was never a kernel regression, and the planned fallback-kernel A/B would
have proved nothing** — both kernels would have failed identically, since the
fault was a userspace file neither of them ships. The reboot was queued because
"whether this is a regression is not known"; what actually answered it was
looking at the file the failing layer reads. **Read the config the failing
component actually loaded before bisecting the thing underneath it.**

☠️ **Two files were reverted, not one — and the second was still broken after
the microphone came back.** The master config
`ucm2/conf.d/Fairphone_3/Fairphone_3.conf` was stock too (274 bytes against our
280), and the stock one does not register the `Voice Call` verb at all. So the
voice-call routing had no verb to apply, silently, and the passing microphone
checks said nothing about it. Found only by inventorying every file the package
ships against the repo, rather than by stopping at the one that explained the
reported symptom.

**Durability, done the same day:** the hand-copy is replaced by a package,
`userspace-audio/fp3-audio-ucm/`, which owns all three paths through
`replaces="soc-qcom-msm8953-ucm"`. Verified rather than assumed — reinstalling
the stock package left our files untouched and still owned by ours:

```
before:  4057  280
(1/1) Reinstalling soc-qcom-msm8953-ucm (20-r0)
after:   4057  HiFi.conf         owner=fp3-audio-ucm-1-r0
          280  Fairphone_3.conf  owner=fp3-audio-ucm-1-r0
```

`alsaucm` now lists both verbs (`HiFi`, `Voice Call`), and `20-audio`,
`35-pulse` and the new `19-ucm-ownership` all pass. That last check asserts
**identity and ownership separately**, since either can hold while audio is
broken: the right content with no owner is correct only until the next upgrade.

<details>
<summary>The original report and the three dead ends it recorded (2026-08-13)</summary>

Measured 2026-08-13 on `linux-fp3-7.1.3-r53`, in a full `fp3-selftest` run:

```
FAIL: 20-audio   capture PCM hw:0,1 (MultiMedia2) does not open
FAIL: 35-pulse   no fp3-handset-mic source - the mic drop-in did not load
dmesg:           MultiMedia2: ASoC: no backend DAIs enabled for MultiMedia2,
                 possibly missing ALSA mixer-based routing or UCM profile
```

Everything userspace is present and running: `90-fp3-mic.pa` is installed,
`fp3-mic-select` is enabled and active (and restarting it changes nothing), the
UCM files are in place, and PulseAudio is up with the speaker sink. What is
missing is the **capture routing**, and with it the source: `pactl list short
modules` shows no `module-alsa-source` at all, because the drop-in loads it
inside `.nofail` and it fails silently.

What has been established, so the next session does not repeat it:

* **Setting the route by hand gets further, and says where the wall is.**
  `amixer -c0 cset name='MultiMedia2 Mixer SLIMBUS_0_TX' 1` makes `arecord`
  *open* the PCM; the read then fails with `I/O error`. So the front end is a
  routing question and there is a second problem behind it on the SLIMbus TX
  side. The control was set back to `off` afterwards.
* ☠️ **"Nobody is logged in" was a good hypothesis and it is wrong.** The phone
  was indeed sitting at the greeter (`loginctl` showed `greetd ... greeter tty7`
  and no user session on seat0), and the drop-in's own comment says the capture
  routing comes from the HiFi UCM verb's `EnableSequence` when the card profile
  activates. But after a real login — `c68 fp3 seat0 tty7`, greeter gone,
  PulseAudio restarted — the source is still absent and `hw:0,1` still returns
  `Invalid argument`.
* **The UCM verb cannot even be queried** by that card name: `alsaucm -c
  "Fairphone 3" get _verb` answers *"No such file or directory"*, and `set _verb
  HiFi` changes nothing. Whether the card is addressable under another name is
  the obvious next thread.

**Whether this is a regression is not known**, and the cheapest way to find out
is already in place: `/boot/extlinux/extlinux.conf` has a `postmarketOS-fallback`
entry pointing at the previous kernel, so one reboot answers it. Nothing in r53
touches audio — its only kernel change is `ak7375` — so a fault on both sides
would point at userspace or at the boot-time SLIMbus race visible in the same
log (`wcd9335-slim: Failed to get logical address`, `SLIM TX timed out`, then a
recovery two seconds later).

</details>

## `pd-mapper.service` is permanently failed, and the RTC cannot be set

Two findings from one investigation, 2026-08-14. Neither is urgent; both are
written down because each looks like something worse than it is.

### `pd-mapper` — nothing to serve, and a restart policy that gives up

`systemctl` reports it `failed (Result: start-limit-hit)`. Run by hand it says
what it means:

```
# /usr/bin/pd-mapper
no pd maps available
```

It reads the protection-domain map files the vendor firmware ships, and
`find /lib/firmware -name '*.jsn'` returns **zero** on this device — the FP3
firmware carries none. The package ships only the binary
(`apk info -L pd-mapper` → `usr/bin/pd-mapper`), so there is nothing to supply
them either. The unit then has `Restart=always` with no `RestartSec` or
`StartLimit` tuning, so it burns the default five restarts in ten seconds and
stops for good.

**Nothing is broken by it.** All three remoteprocs are `running`, and the two
subsystems that would care — audio over APR and the SSC sensors over QMI — work.
On this SMD-era SoC nothing asks for a PD map. The honest fix is to **disable the
unit rather than repair it**, and the reason to bother at all is that a
permanently-failed unit is noise in `10-health`, which asserts no new failed
units.

### The RTC is read-only, which is why the failure looks a month old

`systemctl` dates the failure to 2026-07-15 — four weeks before a boot that
happened eleven hours earlier. The clock explains it:

```
# date                → Fri Aug 14 17:13:07 CEST 2026
# uptime -s           → 2026-08-14 06:09:34        (agrees with /proc/uptime)
# hwclock -r          → 1970-01-01 12:03:46
# hwclock -w          → ioctl(RTC_SET_TIME) ... failed: No such device
```

The hardware clock never advances past the epoch, so early boot runs on a
fictional date until NTP corrects it, and anything that fails before then is
stamped with that fiction. `rtcwake` is unaffected — an alarm is relative to
whatever the counter reads — which is why the suspend work never noticed.

**Why it cannot be set**, from `drivers/rtc/rtc-pm8xxx.c`: mainline offers three
ways to persist time and the FP3 device tree enables none of them. Without
`allow-set-time` the driver takes the offset path (`:353`), and
`pm8xxx_rtc_update_offset()` returns `-ENODEV` immediately when there is neither
an `offset` nvmem cell nor `qcom,uefi-rtc-info` — which is exactly the error
`hwclock` printed. Our `rtc@6000` node (`pm8953.dtsi:106`) has none of the three.

☠️ **`allow-set-time` is the tempting one-line fix and the wrong first move.** On
Qualcomm the RTC counter is commonly owned by the secure world, so a direct write
can fail or be silently discarded; the offset-in-nvmem path exists precisely
because of that. Establish first whether pm8953 exposes an SDAM cell for it —
and check what the vendor kernel does on this board — before adding a property
and declaring victory.

### The cellular network already supplies the time, and nothing consumes it

Measured 2026-08-14, registered on Vodafone HU at 78 % signal. This is NITZ,
carried on the signalling channel — **no mobile data and no data subscription are
involved**, which makes it the one time source available when there is no WiFi:

```
# mmcli -m 0 --time            (needs root; polkit refuses the plain user)
  Time     | current: 2026-08-14T15:37:52+02
  Timezone | current: 120
```

☠️ **The value is UTC and the string labels it as local.** Real local time at
that instant was 17:37:53 CEST, so UTC was 15:37:53 — which is what the modem
reported, to the second. The appended `+02` claims it is already local, so
anything parsing that string at face value sets the clock **two hours slow**. The
offset itself is separately reported and correct (120 minutes). Whether this is
ModemManager's assembly or the QMI plugin is not established; what is established
is that the two fields are individually right and the composed string is not.

**The shape of a fix that is safe without resolving that.** Use it only as a
bootstrap: if the system clock is near the epoch — the state this device boots
into every time — set it from the network value; if the clock is already
plausible, do nothing. A two-hour error is irrelevant against 1970, and it is
enough to make TLS, `apk` and log timestamps work until NTP refines it. That way
the ambiguity above never has to be decided, and the rule stays simple enough to
be correct on any phone and any operator.

Not yet established, and both are cheap reads: whether anything currently
consumes the value at all (`timedatectl`, ModemManager's `NetworkTimeChanged`),
and how long after boot the modem can first answer — if registration takes
minutes, the bootstrap has to wait for it rather than run at a fixed point.

## ~~The notification LED blinks forever after a missed call~~ — closed 2026-08-16, it does end

**Closed on the user's own observation:** the LED stopped when *all* notifications
were closed. So the feedback is ended after all — just not by dismissing the one
notification that started it, which is what "forever" was inferred from. Nobody
had tried clearing the whole tray before calling it endless.

Left below as it was measured, because the mechanism is still worth knowing and
the item may come back in the narrower form "dismissing one notification does not
end its own LED feedback". Item 1 stays the real question if it does.

**Original symptom:** after a missed call the LED keeps blinking; dismissing the
notification does not stop it.

It is **not** the camera flash — the phone exposes no flash or torch LED at all:

```
/sys/class/leds/ →  mmc0::   mmc1::   rgb:status
```

and the device tree contains no flash node (see the parked one below). What
blinks is `rgb:status`, the RGB status LED on the PMI632 LPG.

**Measured on the device:**

* `rgb:status` uses the `pattern` trigger with **`repeat = -1`** — repeat forever;
* feedbackd's `default.json` defines `phone-missed-call` as a `Led` feedback,
  `#00FFFF`, and `notification-missed-generic` as a blue one at frequency 500 —
  **neither carries a duration**, so the feedback runs until the client ends it;
* there is **no `fairphone,fp3.json` theme** installed (the FP5 has one, the FP3
  does not), so those generic rules are what apply.

**Immediate workaround:** `echo 0 | sudo tee /sys/class/leds/rgb:status/brightness`,
or restart feedbackd.

**Two things to do, in this order:**

1. Find out who fails to call `EndFeedback` when the notification is dismissed —
   phosh or the calls app. That is the actual bug; everything else limits the
   damage.
2. ~~Ship a `fairphone,fp3.json` feedbackd theme that gives those LED feedbacks a
   bounded duration.~~ ☠️ **Not possible with this feedbackd**, measured
   2026-08-13: an LED feedback has no duration to bound. The JSON keys the
   binary understands are `event-name`, `type`, `color`, `frequency`,
   `duration`, `effect`, `magnitude` and `parent-name`, and `duration` belongs
   to the vibra feedbacks alone — the only accessors are
   `fbd_feedback_vibra_get/set_duration`, there is no `max-duration` string in
   the binary at all, and `FbdFeedbackLed` has nothing but colours and
   `fbd_feedback_led_run`. An LED feedback runs until the client ends it, by
   construction.

   The timeout that does exist is **client-side**: `fbcli -t` passes one when
   triggering, so a caller can bound its own feedback. That makes item 1 the
   only real fix rather than merely the deeper one.

   What a `fairphone,fp3.json` theme *could* do is override
   `phone-missed-call` and `notification-missed-generic` with a bounded feedback
   of another type — a short `VibraRumble`, say — which stops the endless blink
   by removing the LED notification altogether. That is a decision about what
   the phone should do, not a bug fix, so it is not shipped here unasked. The
   theme would live next to the other userspace drop-ins this repo carries
   (`userspace-audio/udev`, `pulse`, `ucm2`).

   ☠️ Note also that those LED rules live in the theme's **silent** profile, not
   in `full` — the profiles cascade, so reading only `full` finds nothing and
   suggests, wrongly, that no rule applies.

## ~~Parked: the PMI632 camera flash~~ — it works, 2026-08-03

The parking reason was right and the fix was small. `leds-qcom-flash.c` accepts
three flash-module subtypes and refuses everything else with *"flash LED subtype
%#x is not yet supported"*; read over the SPMI regmap on the phone, the PMI632
module answers `0x18` in `FLASH_TYPE` and **`0x05`** in `FLASH_SUBTYPE`, which is
none of them. Enabling the node as it stood would have failed the probe exactly
as feared.

☠️ **The module is on the second USID, not the first.** `0xd300` reads back all
`XX` on `0-02` and the real values on `0-03`. The charger at `0x1000` on `0-02`
is the positive control that tells "wrong USID" from "the read path is broken".

It is the three-channel block with two channels bonded out, so the fix is a
fourth branch taking `mvflash_3ch_regs` with `max_channels = 2`. Measured with
the module idle, the live registers are that layout exactly — timers at
`0x40..0x42`, target currents at `0x43..0x45`, module enable `0x46`, current
resolution `0x47`, strobe `0x49..0x4b`, channel enable `0x4c`, torch clamp
`0xec` — which is also the map Qualcomm's downstream `qpnp-flash-led-v2` uses
for this PMIC, from the same code path as PMI8998 and PM8150, rejecting only
channel ids above 1. `CONFIG_LEDS_QCOM_FLASH` also had to be turned on; it was
not in the config at all.

Measured on `linux-fp3-7.1.3-r34` (`#35-fp3`), three ways, because the first
instrument lied:

| | |
|---|---|
| probe | `white:flash` under `/sys/class/leds`, nothing in dmesg |
| the hardware is programmed | `CHAN_EN 0x03` (both ganged channels), `MODULE_EN 0x80`, `ITARGET 0x3b` on both — 0x3b is 59, so (59+1) × 5 mA = 300 mA a channel, the 600 mA of `led-max-microamp` split in two |
| current flows | USB input ADC, three interleaved passes: off 74 437 / 87 737 / 76 729 against on 139 900 / 153 524 / 144 928 — no overlap |
| light comes out | the rear camera sees the scene go from mean 15.82, σ 0.81, 20 distinct values to mean 70.0, σ 34.4, ~240, repeatable to 0.09 across three passes |

☠️ **The battery is the wrong ammeter here, twice over,** and believing it
produced a confident "no current flows" about a flash that was visibly lit.
`pmi632-battery` exposes **no `current_now` at all** — the charger driver does
not implement the property — and the check's `|| echo 0` turned that missing
file into a reading of zero. Falling back to battery *voltage* droop was no
better: with a cable attached the torch is fed from USB, so the pack never sees
the load. The instrument that works is the PMIC's own USB input current ADC
(`in_voltage_usb_in_i_uv_input`), and it needs interleaved repeats — a single
on/off pair sits inside its noise. The positive control that would have caught
the second error early is cheap: eight busy loops drop battery `voltage_now` by
180 mV, so the channel *can* see a load of that size; the torch showing nothing
meant the path, not the light.

What is **not** carried over from downstream: on this PMIC the flash is fed by
the charger's boost, and downstream sets `POWER_SUPPLY_PROP_FLASH_ACTIVE` on the
charger around a strobe, via its own `schgm-flash` block at `0xA600`. Nothing in
mainline does that. It does not stop the torch — the charger's `VREG_OK` (bit 4
of `0xA607`) comes up on its own when the LED module is enabled, measured going
`0x00` → `0x36` — but the full 2 A strobe has not been tried and may well need
it. `FORCE_BOOST_CONTROL` at `0xA641` stays `0x00` throughout.

Checks: [`tests/checks/42-camera-flash-test.sh`](../tests/checks/42-camera-flash-test.sh)
for the registers and the current, and
[`userspace-camera/flash-check.py`](../userspace-camera/flash-check.py) for the
optical confirmation, which needs a scene and so cannot live in the unattended
battery.

Still open: the torch now appears under `/sys/class/leds`, which gives feedbackd
something new to blink — see the missed-call item above.
`CONFIG_V4L2_FLASH_LED_CLASS` is deliberately still off, so no
`/dev/v4l-subdev` exists for it and libcamera cannot drive the flash yet; that
was kept out so the bring-up measured one change.

## ~~Parked: the camera, after a WirePlumber crash traced to our own AF code~~ — found and fixed, 2026-08-08

Measured 2026-08-03, `linux-fp3` and `snapshot-50.0-r26` both otherwise fine.
WirePlumber itself segfaulted mid-session — not the Snapshot app, not the
kernel — with a C++ assertion inside our own autofocus algorithm:

```
.../bits/stl_vector.h:1282: ... operator[](size_type) const ...:
  Assertion '__n < this->size()' failed.
```

The stack trace goes straight through
[`0101-simple-autofocus.patch`](../userspace-camera/libcamera/0101-simple-autofocus.patch)'s
own code: `libcamera::ipa::soft::algorithms::Af::interpolatePeak()` indexed a
`std::vector<double>` out of bounds while interpolating the sharpness peak from
the contrast-detection statistics. Not yet localised to a specific input (which
zone table, which frame shape) that triggers it - only that it happened once,
live, during ordinary preview use.

systemd restarted WirePlumber on its own, but the app that had a camera stream
open when it died could not reattach - every resolution the viewfinder tried
came back with the same "Element failed to change its state", because the
PipeWire/portal session itself was gone, not the chosen size. This is the same
shape as the documented "restart wireplumber after a libcamera upgrade" trap in
[`userspace-camera/README.md`](../userspace-camera/README.md), just triggered by
a crash instead of an upgrade: killing and relaunching the app (which reopens
the portal session fresh) recovered it immediately, and no amount of
resolution-probing on the app side could have.

**Localised and fixed 2026-08-08** (`059c6de`, in `0101-simple-autofocus.patch`).
The out-of-bounds read was not in the zone grid but in the peak fit itself:
`interpolatePeak()` took its bound from `positions_`, but `planScan()` appends a
revisit of the first position and `detrend()` drops its sample, so `scores_` is
one entry shorter — and a peak at the last swept position made the `i+1`
neighbour lookup read one past the end of `scores_` every time. The fit now
bounds `i` against `scores_.size()` (empty-guard, a `< 3` early return, and the
`i==0`/`i+1>=size` clamp), so the three neighbour reads are always in range.
**Still unverified on hardware:** the fix builds and the reasoning is closed, but
nothing has re-run the live preview to confirm the crash is gone — fold that into
the next camera session on the device rather than a separate cold-boot.

## Two autofocus experiments held back for want of evidence

Both were sitting uncommitted in the working tree on 2026-08-15 with no recorded
rationale, and both were reverted so that r13 changed exactly one thing (the
manual-focus clamp). Neither has ever been built or measured. If either is picked
up it needs its own leg, not a ride on someone else's:

* **`kCoarseSteps` 12 → 9 and `kFineSteps` 7 → 6.** A scan is currently 19
  measurements, ~3.5 s at 1920×1080; this would make it 15. The question is
  whether the settled position stays within a step or two of the 385-394 band
  that [`camera/README.md`](camera/README.md) records for a lit indoor scene —
  same scene, same light, both builds, several scans each.
* **`interpolatePeak()` → `bestPosition_`**, i.e. dropping the parabolic peak
  fit. ☠️ This looks like a leftover from bisecting the out-of-bounds crash,
  which was localised and fixed in `059c6de`, so it probably has no reason left
  to exist. It argues against [the recorded rationale for taking the fit from the
  Raspberry Pi algorithm](camera/bringup/README.md#what-a-shipped-autofocus-does-differently),
  and against the other experiment as well: with **fewer** steps the answer is
  quantised more coarsely, so interpolation matters more, not less. Restore it
  only on a measurement showing the fit lands worse than the raw best sample.

## Untested: interconnect path for the SCM/crypto node

An idea from the SLIMbus framer investigation that was never confirmed:
downstream's `pil-tz` votes MASTER_SPS→EBI bandwidth around the PAS SCM calls,
while mainline's `qcom_scm_bw_enable()` is a no-op here because the `scm` node
carries no interconnect path. Adding one would make `bw_enable()` vote during
`pas_init_image` / `mem_setup` / `auth_and_reset`:

```dts
&scm {
	interconnects = <&pcnoc MAS_CRYPTO RPM_ALWAYS_TAG
			 &bimc SLV_EBI RPM_ALWAYS_TAG>;
	interconnect-names = "crypto-ddr";
};
```

The audio path works without it, so this is not a blocker — it is kept in case
ADSP boot timing ever needs revisiting.

## Settled: the two QDSP6SS framer pokes were not needed

Removed on 2026-07-29. `integration/<base>` used to carry two commits clearing
QDSP6SS `0x0c20002c` bit 3 — one in `qcom_q6v5_pas.c` after `AUTH_AND_RESET`,
one in `qcom-ngd-ctrl.c` before the capability exchange. Both are reverted,
along with the `qcom,slim-framer-quirk-reg` device tree property that armed the
second one (76 lines gone).

What settled it, on the same phone with the same protocol, one variable:

| | audio opens | tone across SLIMbus both ways | `MC:0x21` | codec |
|---|---|---|---|---|
| without the pokes | 8/8 cold boots | 8/8 | 8 | 1 |
| with the pokes | 8/8 cold boots | 8/8 | **8** | 1 |

Not a trace of a difference. Three things worth keeping from getting there:

* **The PAS poke never wrote anything.** Its own log line reads
  `QDSP6SS 0xc20002c 0x101->0x101` — by the time it runs, bit 3 is already
  clear. Only the SLIMbus one wrote (`0x10b->0x103`).
* **`MC:0x21` is not a fault signal.** It is `SLIM_USR_MC_DEF_ACT_CHAN`,
  "define and activate channel", from `qcom_slim_ngd_enable_stream()`. It
  appears eight times per boot **with and without** the pokes while audio works
  — the count tracks how many streams are started, not how many failed. Same for
  `MC:0xd` (`ADDR_QUERY`, which is why `Failed to get logical address` is
  followed 200 ms later by the codec answering) and `capability exchange
  timed-out`.
* **A boot with nobody logged in measures nothing.** The first version of this
  test counted `MC:0x21` in the kernel log and found none in twenty-five boots,
  because without a user session nothing starts audio and the log ends at
  twenty seconds. The metric has to open the audio path.

Reverting the PAS commit does **not** change which ADSP firmware is loaded: the
descriptor it added differed from the msm8996 one only in the firmware name and
the quirk register, and the FP3 device tree sets `firmware-name` on `&lpass`,
which the driver prefers. The `required-opps` CX-turbo idea that used to share
this experiment was already disproven separately —
`qcom_pas_pds_enable()` votes `INT_MAX` on every proxy power domain, measured
live as `cx_perf = 2147483647` for roughly 160 ms across the ADSP boot window,
so it was a no-op.

## Also open, written up elsewhere

* **Charging asks for 2 A**, where it used to be capped at 1 A, and the battery
  it asks on behalf of is now verified before its limits are applied. What is
  left, in order: the **mismatch path has never run on hardware** (a
  device-tree-only cycle with a deliberately wrong `id-resistor-ohms` would
  measure it), **2 A has not been seen flowing** (needs a wall charger and a low
  state of charge), and the **input side** — without high-voltage negotiation the
  USB port supplies about 1.9 A into the cell. Still open beyond that: selection
  between the two packs the FP3 ships, which needs a binding for more than one
  `monitored-battery`; the float-voltage half of JEITA; step charging; and the
  thermal trip temperatures, which are a choice rather than a measurement. See
  [`charger/README.md`](charger/README.md).
* **Only the discharge half of the two-OS comparison is matched.** The idle
  discharges were run against each other deliberately; the charges were not.
  Ubuntu Touch charged from a wall charger, and both pmOS captures came off an
  SDP port at `usb_imax_uA 500000` — about 340 mA into the pack — so they show
  *that* charging terminates, not how it compares. A like-for-like charge needs
  the same charger and the same starting state of charge on both sides, and it
  pairs naturally with the two hardware measurements above, since all three want
  a wall charger and a low battery.

  ☠️ **The two halves age differently.** A charge measurement stays valid across
  the idle-current work; a discharge measurement does not, because the floor it
  rests on is the thing being changed. Re-running the matched discharge before
  the `ak7375` fix lands is work thrown away.
* **Sensors work**, including proximity blanking during a call and ambient
  light. What is left there is calibration rather than bring-up: the
  magnetometer has an unknown hard-iron offset and scale, and the mount matrix
  is inherited from msm8996. See [`sensors/README.md`](sensors/README.md).
* ~~**Camera streaming is not working end to end.**~~ **Stale — it streams.**
  `VIDIOC_STREAMON` succeeds and frames arrive at the full
  `SRGGB10_1X10/4032x3024`, 15 240 960 bytes each, which is exactly
  4032 × 3024 × 10 / 8: packed 10-bit, no padding, no short frames. See
  [`camera/README.md`](camera/README.md). The lead that remains from the original
  entry is narrower than it was: the driver's two modes carry link frequencies
  that disagree with the device tree's `link-frequencies`, and one is commented
  `// NOT SURE HOW TO FIND THIS VALUE` by its author — worth resolving before the
  series is sent, but it is not what blocks streaming, because nothing does.

## The package moved to `debug-int/7.1.3`

`linux-fp3/APKBUILD` pinned `_commit=c8974511d585` through two rewrites and ended
up unreachable from any branch: the camera-provenance rebuild on 2026-07-30 moved
it onto an archived lineage, and the debug split later the same day added a second
one. It was also, concretely, a kernel **without the watchdog** — the safety net
commit landed after it.

So on 2026-07-30 the pin moved to `debug-int/7.1.3` and `pkgrel` went to 23. That
is the branch the package builds from now on: `integration/<base>` plus the debug
layer, so what runs on the phone always carries the watchdog started at probe.
`integration/<base>` deliberately does not, because it is the branch that has to
keep matching the `submit` series.

The build and the deploy followed, and have been repeated many times since, so
the kernel the phone runs is built from that branch and carries the watchdog.

What is worth keeping an eye on is that the package and the device stay in
step. Between a hurried fix and the next bump the phone can end up running
hand-copied modules and a hand-copied DTB on top of an older package - a state
where `uname -v` and `apk info` disagree, and where any `apk` operation on
`linux-fp3` silently reverts the DTB through the mkinitfs trigger. The check
that catches it is `tests/fp3-selftest --only identity,modules,dtb`, which
compares the build stamp, the installed package, the source commit, the module
tree and the booted DTB against each other rather than trusting any one of them.

Both old tips are kept alive as tags —
`archive/integration-7.1.3-pre-camera-provenance` and
`archive/integration-7.1.3-pre-debug-split` — because GitHub serves a source
tarball only while its commit is reachable from some ref. Rewriting `integration`
without them would have left the pinned package un-buildable, a failure that
shows up much later than the change that caused it. The one-line check is in
[the branch model](../README.md#the-branch-model).

## AfWindows cannot reach the camera through PipeWire

> **✅ Layers 1 and 2 are done and measured (2026-08-16).** A focus window now
> travels from `pw-cli` to the metering: `libcamera` r18 offers the control in
> the sensor's active pixel array and aims at it, and `pipewire` r6 carries it
> across the node. Only layer 3 is left — the application still sends nothing.
> Both layers are held by checks proved in both directions:
> `44-camera-af-windows` (libcamera r17 fails, r18 passes) and
> `45-camera-af-windows-pipewire` (pipewire r5 fails, r6 passes).
>
> Measured end to end with a stream open, reading the IPA's own line:
>
> ```
> AfMetering=Windows alone -> Metering 9 of 25 zones (0 windows) [the centre fallback]
> [0, 0, 400, 300]         -> Metering 1 of 25 zones
> [3600, 2700, 400, 300]   -> Metering 1 of 25 zones
> [0, 0, 4032, 3024]       -> Metering 25 of 25 zones
> ```
>
> ☠️ **The claim below that no PropInfo in 1.6.8 publishes `container` together
> with a range is wrong.** `SPA_PROP_channelVolumes` does exactly that —
> `spa/plugins/audioconvert/audioconvert.c:582-584`, a `CHOICE_RANGE_Float`
> followed by `SPA_PROP_INFO_container, SPA_POD_Id(SPA_TYPE_Array)`. The pattern
> was established; the grep that concluded otherwise was too narrow.
>
> ☠️ **And a fourth gate that only the device showed: `pw-cli` does not send an
> array as a POD array — it sends a struct.** `spa_json_to_pod_part()`
> (`spa/utils/json-pod.h:68`) has only the static type table to work from, every
> camera control is published past `SPA_PROP_START_CUSTOM` and so appears in no
> table, and with no type a JSON array becomes a struct of ints. The very first
> `set-param` printed it:
>
> ```
> Struct: size 64
>   Int 0 / Int 0 / Int 100 / Int 100
> ```
>
> A plugin accepting only POD arrays would have published a control that cannot
> be set — indistinguishable, from outside, from not publishing it. Both shapes
> are accepted.
>
> **☠️ Update 2026-08-16: the chain breaks in three places, not one.** The
> PipeWire gate below is real and still has to be opened, but opening it alone
> changes nothing. Measured with `cam -c1 --list-controls` on the device:
>
> ```
> Control: [inout] libcamera::AfWindows: [(0, 0)/0x0..(0, 0)/0x0]
>    Size: n
> Control: [inout] libcamera::AfMetering:
>   - AfMeteringAuto (0) [default]
>   - AfMeteringWindows (1)
> ```
>
> `AfWindows` **is** advertised, and so is `AfMeteringWindows` — but the
> control's own bounds are **both the empty rectangle**. That is the same shape
> as the `LensPosition` defect that took two rounds to find: a control offered
> with a degenerate range, where every request clamps to nothing. So the work is
> layered, and the order matters because each layer is untestable until the one
> below it carries a value:
>
> 1. **libcamera / the soft IPA** — ✅ **done 2026-08-16**, patch `0106`
>    (`libcamera` r15). See the correction below: the algorithm already metered
>    arbitrary windows, so the work was narrower and in different places than
>    this line assumed.
> 2. **PipeWire** — ✅ **done 2026-08-16**, patch `spa-libcamera-array-controls`
>    (`pipewire` r6). The three `isArray()` gates below, plus the struct shape
>    `pw-cli` actually sends.
> 3. **aperture / Snapshot** — send a rectangle array rather than a scalar.
>    **The only layer left.**
>
> #### ☠️ Correction, 2026-08-16: layer 1 was not what it looked like
>
> "Make the AF algorithm honour the windows instead of falling back to
> `selectCentre()`" was **wrong** — `Af::selectZones()` has metered an arbitrary
> set of windows since the autofocus went in, and `queueRequest()` already
> called it. Reading the source before writing any of it turned one guessed
> defect into three measured ones:
>
> * **the degenerate `ControlInfo` is real**, and its cause is a comment that
>   promised something the plumbing cannot do: *"the bounds are filled in at
>   `configure()` time"*. They never were, and they never could have been — the
>   `ControlInfoMap` a camera advertises is taken **once**, when `SoftwareIsp`
>   constructs the IPA (`software_isp.cpp`, `ipa_->init(…, ipaControls, …)`),
>   and is never read again. `context_.sensorInfo = sensorInfo` happens in
>   `IPASoftSimple::init()` *before* `createAlgorithms()`, so `Af::init()` is
>   where the size is both available and effective.
> * **`AfWindows` was applied under `AfMeteringAuto` too**, contrary to the
>   control's own documentation (*"used by the AF algorithm when AfMetering is
>   set to AfMeteringWindows"*), and the reverse order was worse: switching to
>   `AfMeteringWindows` **after** windows had been given did nothing at all,
>   because the old `windowsSet_` flag made that branch a no-op and the zones
>   stayed on the whole frame. Both controls are now kept as requested and the
>   zones derived from the pair, so the result no longer depends on arrival
>   order.
> * **`selectZones()` silently metered the whole frame** when no window
>   survived clipping — the one thing a caller asking for windowed metering did
>   not ask for. It now reports whether it selected anything, and windowed
>   metering with no usable window falls back to the centre.
>
> ☠️ **The coordinate space is a deviation, stated rather than hidden.**
> `AfWindows` is documented as being in `ScalerCropMaximum` pixels; the simple
> pipeline handler publishes no such property (`git grep ScalerCropMaximum` hits
> only `rpi` and `rkisp1`), so there is nothing there for an application to
> read. The IPA measures against the sensor's **active pixel array**, and the
> control's own maximum states that space, which is machine-readable and — on a
> pipeline that cannot crop — is the same rectangle `ScalerCropMaximum` would
> name.
>
> ##### ☠️☠️ A fourth defect, found only by measuring end to end (`r17`)
>
> Two things the source review could not have found, both caught the first time
> a window ever reached the code:
>
> * **A single window aborts the IPA process.** `cam` — and anything built on
>   `ControlValue::set(Rectangle)` — holds one window as a **scalar**, not as a
>   one-element array, and reading a scalar through the array accessor asserts:
>   `Assertion failed: isArray_ (controls.h: get: 204)`. Fixed by reading the
>   raw `ControlValue` and accepting both shapes. Nothing had ever hit it
>   because no window could reach this code before.
> * **The coordinate space follows leftover driver state.** Measured two-sided:
>
>   ```
>   after a 1920x1080 capture:  AfWindows: [(0, 0)/1x1..(0, 0)/1920x1080]
>   after a 4032x3024 capture:  AfWindows: [(0, 0)/1x1..(0, 0)/4032x3024]
>   ```
>
>   `context.sensorInfo` is taken **once**, in `IPASoftSimple::init()`, from
>   `sensor->sensorInfo()` — which reports the sensor's *currently applied* V4L2
>   format. That format persists in the driver between processes, so the space
>   an application is told to compute in is decided by whoever used the camera
>   last. `selectZones()` clips against the same member and has had this
>   dependency since it was written; the new `ControlInfo` did not introduce it,
>   it made it visible. The symptom that exposed it: a window at
>   `(3000, 2200, 400, 300)` selected 9 of 25 zones — the centre fallback —
>   because it lay wholly outside a 1920x1080 clip, while `(1900, 1050, 20, 20)`
>   selected 1.
>
>   **Fixed in `r18`** by using the sensor's *active pixel array*, which is a
>   fixed hardware property and does not move — `PixelArrayActiveAreas =
>   [ (8, 24)/4032x3024 ]` read identically after a 1080p capture and after a
>   full-res one. `IPACameraSensorInfo::activeAreaSize` carries it, so the
>   stale init-time snapshot is no longer a problem: the one field that moves is
>   the one that is no longer read. `selectZones()` maps a window onto the zones
>   proportionally and needs no absolute size of its own.
>
>   Measured after the fix — the space no longer follows what the last user of
>   the camera left in the driver:
>
>   ```
>   after a 1920x1080 capture:  AfWindows: [(0, 0)/1x1..(0, 0)/4032x3024]
>   after a 4032x3024 capture:  AfWindows: [(0, 0)/1x1..(0, 0)/4032x3024]
>   after a  640x480  capture:  AfWindows: [(0, 0)/1x1..(0, 0)/4032x3024]
>   ```
>
>   and the two windows that used to fall back to the centre now aim:
>
>   ```
>   [0, 0, 4032, 3024]     -> Metering 25 of 25 zones      (was 25)
>   [2000, 1500, 400, 300] -> Metering  1 of 25 zones      (was 9 — centre fallback)
>   [3900, 2900, 100, 100] -> Metering  1 of 25 zones      (was 9 — centre fallback)
>   [0, 0, 100, 100]       -> Metering  1 of 25 zones      (was 1)
>   ```
>
>   ☠️ The mapping assumes the stream covers the active area. A sensor mode that
>   cropped rather than scaled would need `analogCrop` — which is known only for
>   the format the IPA was initialised with, and is therefore no more dependable
>   here than the output size was. Stated in the code and the commit rather than
>   silently assumed.
>
>   ☠️ `cam` cannot set a control from the command line — `-s` is stream
>   configuration. Controls go through `--script`, and that is how the scalar
>   shape above arrives:
>
>   ```sh
>   printf 'frames:\n  - 0:\n      AfMetering: 1\n      AfWindows: [ 0, 0, 100, 100 ]\n' > /tmp/af.yaml
>   LIBCAMERA_LOG_LEVELS=IPASoftAf:INFO cam -c1 -C4 --script /tmp/af.yaml
>   ```
>
> The working half is measured too — windows do aim, once they land inside the
> clip: `[0,0,4032,3024]` → 25 of 25 zones, `[0,0,100,100]` → 1,
> `[1900,1050,20,20]` → 1. The `Metering N of M zones` line that makes any of
> this visible is part of `0106`; without it a window that reached nothing looks
> exactly like one that was never sent.
>
> Found on the way and fixed in `0102`: `toMicroseconds()` shadowed `exposure`,
> which a host build with `-Werror -Wshadow` rejects. The device build does not
> use those flags, so the defect had shipped. **Build a userspace patch on the
> host before packaging it** — it is minutes, and it is a different compiler
> invocation from the one the aport uses.
>
> One design point from yesterday is now confirmed rather than assumed: there is
> **no `SPA_TYPE_Region` POD type**. `struct spa_region` exists in
> `spa/include/spa/utils/defs.h` and is exactly libcamera's `{x, y, w, h}`, but
> it is a plain C struct with no entry in the `enum` in `spa/utils/type.h` and no
> builder or parser helper, so it cannot be put in a pod. Flattening to four
> `int32`s stands.

Tap-to-focus points at nothing. The tapped position never reaches libcamera,
because PipeWire's libcamera plugin maps only `bool`, `int32` and `float`
controls to node properties and returns early for arrays — and `AfWindows` is
an array of rectangles. Measured 2026-08-15 by dumping what the camera node
publishes:

```sh
pw-dump | python3 -c 'import json,sys
for o in json.load(sys.stdin):
    for pr in o.get("info",{}).get("params",{}).get("PropInfo",[]):
        i = pr.get("id")
        if isinstance(i, str) and i.startswith("id-01"):
            print(i, pr.get("description"), pr.get("type"))'
```

Only `AfMode`, `AfMetering`, `AfTrigger` and `LensPosition` come back. The
stand-in that shipped is `AfMeteringWindows` meaning *the centre 3×3 of the
5×5 zones*, defined in the IPA, which removes the dilution but cannot aim.

### Read in the source 2026-08-16: three gates, not one

PipeWire 1.6.8, `spa/plugins/libcamera/libcamera-source.cpp`. Three functions
each open with the same bail, so an array control is invisible as well as
unwritable:

| function | what it does | line |
|---|---|---|
| `control_details_to_pod` | publishes the PropInfo | `if (cid.isArray()) return nullptr;` |
| `control_value_to_pod` | publishes the current value | `if (cv.isArray()) return false;` |
| `control_value_from_pod` | accepts a written value | `if (cid.isArray()) return {};` |

and none of the three type switches has a `ControlTypeRectangle` case either.
`AfWindows` is `Span<const Rectangle>`, so it fails both tests. That is why the
control does not merely reject writes - it never appears in `pw-dump` at all.

**The shape of the fix is already in the tree, so do not invent one.** SPA
already carries array-valued properties: `SPA_PROP_channelVolumes` in
`spa/plugins/audioconvert/audioconvert.c:580` publishes a PropInfo whose `type`
describes *one element* and adds

```c
SPA_PROP_INFO_container, SPA_POD_Id(SPA_TYPE_Array));
```

to say the value is an array of them, with the value written by
`spa_pod_builder_array(b, sizeof(float), SPA_TYPE_Float, n, vals)`. Follow that:

- **PropInfo** - element range as `SPA_POD_CHOICE_RANGE_Int`, plus
  `SPA_PROP_INFO_container = SPA_TYPE_Array`.
- **value** - `spa_pod_builder_array(b, sizeof(int32_t), SPA_TYPE_Int, 4 * n, …)`,
  four ints per rectangle.
- **write** - read an Array of Int and regroup in fours.

☠️ **Do not use `SPA_TYPE_Rectangle`.** It exists, and it is the wrong type:
`spa_rectangle` is `{width, height}` only, with no origin, while libcamera's
`Rectangle` is `{x, y, width, height}`. A window without an origin cannot aim,
which is the entire point. Flattening to int32 is what keeps the origin.

Measured caveat, so the review is not a surprise: **no PropInfo anywhere in
PipeWire 1.6.8 publishes `container: Array` together with a range** - grep for
`SPA_PROP_INFO_type, SPA_POD_Array` returns nothing. `channelVolumes` is the
precedent for the *mechanism*, and it comes from an internal node rather than
from a device plugin's generic control loop. Expect to have to show that a
client which ignores `container` degrades sanely rather than misreading the
element range as the whole value.

Then the aperture control layer needs a way to write one; today it writes a
single number through `pw-cli set-param`. Note there is no local `pipewire`
aport - Alpine's lives in `community/pipewire` (`master` carries 1.6.8, matching
the device), so this needs a new `pmaports/temp/pipewire`.

## Does centre metering recover the focus signal?

**Not yet measured.** The A/B ran (2026-08-15) and proved only that the code
path works: the score falls to 0.385 of the whole-frame value, against 9/25 =
0.36 of the zones. Both legs were run on a bench scene with no focus peak in
it at all, so neither could show a peak and the comparison says nothing about
whether narrowing the zones recovers the modulation. Repeat it on the scene
that produced the 4.9 % figure — a phone held close over a keyboard, in room
light — with `AfMetering: 0` and `AfMetering: 1` alternating:

```sh
LIBCAMERA_LOG_LEVELS=IPASoftAf:INFO cam -c1 --capture=200 \
    -s width=640,height=480 --script=<script setting AfMode 1, AfMetering N, AfTrigger 0>
```

Only once that number exists is there anything to say about `min-contrast`,
which is 0.08 and was being missed by 3 percentage points.

## The tap moves the lens and nothing else

Three loops run on every frame and the tap reaches only the first:

| loop | what it sets | what it looks at | tap reaches it |
|---|---|---|---|
| AF | lens position | the centre 3×3 of the 5×5 zones | yes |
| AGC | exposure time + analogue gain | the whole frame | no |
| AWB | colour temperature | the whole frame | no |

Measured 2026-08-15 by photographing a lit monitor in a dim room: the letters
came out readable, so the lens went where the tap asked, while the centre of
the screen was blown out because the AGC had averaged the dark room in and
opened up. The camera node publishes no metering control for exposure at all —
`AnalogueGain`, `ExposureTime`, `ExposureTimeMode`, `AnalogueGainMode`,
`ColourTemperature` and `AwbEnable` are all scalars with no notion of *where*.

Two pieces, in this order:

1. carry rectangles through PipeWire (the section above). Nothing here can be
   aimed until a position can cross the socket, and the same fix is what makes
   `AfWindows` work, so it is one job serving both.
2. window the metering inside the IPA's AGC, modelled on the focus zones, and
   publish an `AeMetering`-style control next to `AfMetering` so the pipeline
   can ask for it.

## The shutter still fires mid-sweep in poor light

`FOCUS_SETTLE_MS` and `CAPTURE_FOCUS_SETTLE_MS` are 5500 ms, chosen against a
sweep measured at ~4.8 s. The sweep is not a constant: it is 19 positions plus
2 revisits, and the per-position cost is set by the frame rate, which the AGC
lengthens in poor light. Measured 2026-08-15: ~250 ms/position in room light
(~4.7 s) against ~570 ms/position in a dim room (12.7 s, 4:39:44 → 4:39:56).
So in poor light the capture still happens at an arbitrary lens position.

A longer timeout is the wrong fix — it would make every good-light shot slow.
The right one is for the IPA to say when the scan finished, which today it
does not: there is no completion control and `AfState` is not published. Until
then, note that lowering the position count (`kCoarseSteps` 12, `kFineSteps` 7)
shortens both cases proportionally.

## Deleting a photograph can take the viewfinder down

Undiagnosed. Symptom is a freeze in the gallery on delete, then "could not
play camera stream". The journal at 18:02:45 on 2026-08-15 shows the
**video** branch of camerabin starting without a filename and taking the whole
stream with it:

```
videobin-filesink: No file name specified for writing.
... Failed to start
pipewiresrc0: streaming stopped, reason not-negotiated (-4)
```

Why a delete should start the video branch is unknown, and guessing at it is
what to avoid — the next occurrence with a timestamp gives the full ordering
out of `journalctl --user -b`.

## The face-focus cascade is not archived here

`userspace-camera/snapshot/` now carries every patch the aport applies, but not
`facefinder` — the 234 KB binary cascade that `0020-camera-face-focus-mode`
loads at runtime. It lives only in `/mnt/1TB/pmos/pmaports/temp/snapshot`, an
upstream clone that is never pushed, so the aport still cannot be rebuilt from
this repo alone. Before copying it across, establish where it came from and
under what licence: a binary blob with no provenance is worse in a public
repository than a missing one, and the README has no row for it.

## `apcs-cpu0-pll` fails to lock, and it took the phone down

`apcs-cpu0-pll failed to enable!` — `wait_for_pll()` returning `-ETIMEDOUT`
from `alpha_pll_huayra_set_rate()` under `sugov_work`, 266 times in one boot on
2026-08-15/16, ending in an unclean power cut with no shutdown sequence in the
journal. Evidence and the analysis are in
[`docs/power/RUNBOOK.md`](power/RUNBOOK.md); the raw capture is
[`docs/power/2026-08-16_apcs-cpu0-pll-lock-failures.txt`](power/2026-08-16_apcs-cpu0-pll-lock-failures.txt).

Two reasons this outranks the power numbers it was found under. It makes the
device **unreliable** — an unclean cut can corrupt the rootfs and did once
already cost a boot to fsck elsewhere in this port. And `clk-alpha-pll.c` has
no retry on this path, so a transient lock failure is fatal to that frequency
transition rather than merely slow.

Not yet known: whether it is voltage-dependent (it started at the lowest
battery voltage of the session, but recurred while charging at 3.89 V), whether
it is specific to the little cluster, and whether it predates the current base.
The first test is a fixed cpufreq sweep at high and at low battery, counting
failures — not another power leg, which would only measure this.

Measured again 2026-08-16 on r56, and it narrows the question. 299 instances in
one 85-minute boot, the first nine seconds in, arriving every 10–40s.

☠️ An earlier version of this paragraph said it was **not load-driven**, on the
strength of a 60s-idle-vs-30s-burn comparison. Withdraw that: the counts came
from a `dmesg` that had already wrapped — noted as unreliable at the time and
used anyway. On the clean r57 boot the picture is different and not yet
explained: **zero** across the whole 27-check battery, which includes a 30s
eight-core burn, then **24 in three minutes** during the three acoustic audio
checks. Whatever drives it, it is not simply CPU load, and the audio path is
now the first place to look. The cluster still reaches every operating point — `policy0`'s
`time_in_state` shows residency at all seven, up to 1804800 — so each failure is
a rate change that is retried, not a clock left stuck, which is why nothing else
on the phone shows it. The battery was at 99–100% throughout, which weakens the
voltage hypothesis without disproving it (this was the terminal voltage, not the
rail the PLL sees).

It is also, as of today, visible: `10-health` greps for `WARNING:` and prints
this line with its count on every run, from `journalctl -k -b` rather than from
a ring buffer these same warnings had been evicting.

## The loudspeaker amplifier dies partway through a session

Measured 2026-08-16 on 7.1.3-r57. The AW8898 smart amplifier at `3-0034` is
present and probes, and then does nothing useful:

- **it does not answer on I²C.** `amixer -D hw:0 cset name='RX Volume' 0` — a
  write of the value the control already holds — fails, and the kernel logs
  `ASoC error (-5)` from both `soc_component_read_no_lock()` and
  `snd_soc_component_update_bits()` on register `0x0f`. The control reads back
  `0`, i.e. −127.5 dB, and cannot be moved off it.
- **it never sees its bit clock.** Every playback start logs
  `aw8898 3-0034: iis clock not detected (-110), playing anyway`.
- **so nothing comes out.** With a 1 kHz tone at full scale on `hw:0,0` and the
  handset DMIC0 capturing on `hw:0,1`, two seconds of capture gave peak 95 /
  RMS 5.8 against peak 38 / RMS 2.8 in silence — about 8 dB, where a working
  speaker a hand's width from the mic is tens of dB. The microphone is fine;
  the baseline proves it is live.

This is the same fault as the 2026-07-31 finding that the amp's PLL never
locks: the dying I²C is the consequence, not the cause. What is new is the
scale of what it hid.

☠️ **Nothing in the default battery measured it.** `20-audio` covers the codec
and the PCM opens, which is the entire digital path and none of the analogue
one. The only check that would have noticed is `21-audio-acoustic`, and that
sits behind `--acoustic` because an over-the-air measurement is too
environment-dependent to gate on — so the phone reported *27 ok, 0 failed* with
a loudspeaker that produces no sound. Worse, every acoustic run ever logged
here, back to 2026-07-29, had failed, and the failure was readable each time as
"the room was noisy" or "the phone was lying wrong". That excuse was written
down as the explanation on the morning of 2026-08-16 and it was wrong.

`tests/checks/24-speaker-amp-test.sh` now measures the amplifier where the room
cannot reach it — a round-trip write on its control bus, and its own clock
complaint after a one-second silent playback. It is in the default battery, and
it **fails today**, which is the honest state: the battery is 27 ok / 1 failed,
and the one failure is a loudspeaker that does not work.

Open, and not diagnosed further than the 2026-07-31 measurement.

## ~~The lock screen went black~~ — settled 2026-08-16: it points at a wallpaper that is not installed

phosh draws the lock screen from `org.gnome.desktop.screensaver picture-uri`,
which is a **different key** from the desktop wallpaper
(`org.gnome.desktop.background picture-uri`). Its value here was
`file:///usr/share/backgrounds/gnome/adwaita-timed.xml`, and that file does not
exist on this system — `gnome-backgrounds` is not installed — so phosh fell back
to plain black while the desktop behind it stayed green.

```sh
gsettings set org.gnome.desktop.screensaver picture-uri \
  file:///usr/share/wallpapers/postmarketos/contents/images/2000x2000.png
```

Verified by screenshot: locked before the change, black with the clock and the
notification; locked after it, the pmOS wallpaper. The lock screen was never
broken — only its background was missing.

☠️ **This was not caused by enabling the autologin, but it became visible
because of it.** With `[initial_session]` off, the first screen after a boot was
phrog, the greeter, which draws its own green background; that is what "the
screen used to be green" was. With autologin on, phrog never runs and the first
screen you meet is phosh's own lock screen, which had this fault all along. A
change in *which component you see* looks exactly like a regression in the one
you were seeing before.

## Tap focus still hunts, and the obvious explanation is not the one

Reported 2026-08-16: with `focus-mode` set to `tap` the camera keeps focusing by
itself, which is what `continuous` is for.

Measured so far, and it rules more out than in:

- **The camera's own default is continuous.** `AfMode`'s PropInfo carries
  `Int 2` as its default, i.e. `AfModeContinuous`. So a mode that is never
  written does not leave the camera idle — it leaves it hunting, which is
  exactly the reported symptom. Anything that drops the write reproduces this.
- **`request_autofocus()` is all-or-nothing:** one missing control, or one that
  is not a labelled choice, and it returns without writing *any* of the pair -
  including the `AfMode` that matters. Since 0021 added `AfMetering` to every
  request, that looked like the answer.
- **It is not.** Both are published properly:
  `AfMetering` is an enum with labels `AfMeteringAuto`/`AfMeteringWindows`, and
  `AfMode` an enum with `AfModeManual`/`AfModeAuto`/`AfModeContinuous`. Every
  name and value `wanted()` asks for exists.

  ```sh
  pw-cli enum-params <camera-node> PropInfo   # as the session user
  ```

☠️ **The measurement that would settle it cannot be driven from a shell.**
Launching Snapshot over SSH as the session user starts the process but never
gets a viewfinder: no `org.freedesktop.portal.Camera` request appears in its
log, and `aperture` then logs "Camera never offered its focus controls; giving
up" — which is the app correctly reporting that no camera turned up, **not**
evidence about the focus path. Two runs were made this way before that was
noticed, and the lens sat at 872 through both because nothing was streaming.
The `giving up` line only means something in a session where `Capture at ...`
was logged first.

Next, in this order: drive the node directly with `pw-cli set-param <node> Props
'{ <AfMode id>: 1 }'` while the camera streams (the recipe is in
`tests/checks/45-camera-af-windows-pipewire-test.sh`) and watch
`v4l2-ctl -d /dev/v4l-subdev17 --get-ctrl focus_absolute` — a lens that keeps
moving with `AfModeAuto` set puts the fault below the app, one that settles puts
it in Snapshot.

## The whole desktop draws on the CPU, by distro policy

Measured 2026-08-16, and it is the answer to "is the camera using the GPU?" —
**no, and neither is anything else GTK4.**

`soc-qcom-msm8953-gpu` ships `/etc/profile.d/adreno-a506-quirks.sh`:

```sh
# Use the 'cairo' GTK renderer, so we prepare for the removal of
# the legacy GL renderer
export GSK_RENDERER=cairo
```

The reason given is portability, not a broken GPU — GTK is retiring its old GL
renderer and the distro is getting ahead of it. The cost is that every GTK4
application on the phone renders in software, the camera viewfinder included,
which is what a stuttering viewfinder looks like. phosh itself runs with
`GSK_RENDERER=cairo` in its environment, and every app it launches inherits it.

The GL renderer works here today: with `GSK_RENDERER=gl`, EGL gives an
**OpenGL ES 3.1 core** context on Mesa 26.1.6 / freedreno a506 under gtk4
4.22.4, with no fallback or error. The earlier measurement of what it is worth
was Snapshot at **130% CPU with cairo against 32% with gl**.

So `/etc/profile.d/zz-fp3-gsk-renderer.sh` now sets `GSK_RENDERER=gl`; it sorts
after the quirk, so it wins, and deleting it goes back. ☠️ **It only reaches the
session at the next login** — the running phosh keeps the environment it was
started with, so nothing changes until a re-login or a reboot.

☠️ The renderer name is `gl`, not `ngl`.

## Does the tap move anything but the focus?

Asked 2026-08-16, because the middle of the frame blows out after a tap. The
answer from the camera's own control list is **no, and it could not**:

```sh
pw-cli enum-params <camera-node> PropInfo | grep -E 'String "(Ae|Awb|Exposure|Analogue|Colour)'
```

Everything exposure-related the node publishes is a *global* control -
`ExposureTimeMode` (Auto/Manual), `ExposureTime`, `AnalogueGainMode`,
`AnalogueGain`, `AwbEnable`, `ColourTemperature`. There is **no** metering-window
or metering-mode control of any kind for exposure or white balance, so nothing
can be aimed at the tapped rectangle even in principle. And our patches write
none of them: the only "metering" anywhere in the series is `AfMetering`, which
is the focus one.

So the blown-out centre is not the tap following the frame — it is the
auto-exposure algorithm's own behaviour, and a separate question from the focus
work. Not yet measured.


### Corrected the same day: it is not permanently dead

Everything above was measured on a boot that had been up about three hours. On a
**fresh boot** the amplifier is healthy: `RX Volume` reads and writes at 255, the
1 s silent playback draws no clock complaint at all, and the speaker is properly
loud — the same 1 kHz tone that moved the handset mic's peak to 95 before the
reboot moved it to **1466** (RMS 765.7 against 3.2 in silence) after it. The
`24-speaker-amp` check passed in the battery on that boot: 28 ok, 0 failed.

So the fault is a **transition during a session**, not a constant, and the open
question is what causes it. The 2026-07-31 measurement said the same thing in
other words — a cold boot heals it until the first failed playback attempt —
and the driver's error path (`aw8898_set_power(false)` after the PLL wait times
out) is the mechanism that would make one failure permanent for the rest of the
boot.

☠️ **What I wrote this morning — "the loudspeaker is silent", "this check has
never been seen to PASS" — was a state of one boot stated as a property of the
phone.** Everything measured was real; the generalisation was not, and it took
one reboot to break it. The corrected claims are in the check headers.

### And the acoustic check is now failing for a third reason

On the healthy boot `21-audio-acoustic` still fails, but the numbers changed
completely: alsabat reports **peak 6000.00 Hz at 22.21 dB, total 35.3 dB in a
5 Hz band** — a real, strong acoustic signal, at the sixth harmonic of the 1 kHz
it played. That is distortion, not silence.

`23-audio-slimbus` passes on exactly this shape, because it judges whether the
target frequency was detected rather than trusting alsabat's exit code (it
records `rc=21 from sidebands above the fundamental`). `21-audio-acoustic` still
requires `rc == 0`, so it calls a working speaker broken. Open: judge it the way
23 does, and separately find out why 1 kHz comes back with its sixth harmonic
dominant — the amp runs at 0 dB (`RX Volume` 255) by default, so clipping is the
first thing to rule out.

### The transition reproduced on one boot, and what it costs to measure it

Measured 2026-08-16, evening, with the jack plugged in. The whole day's
uncertainty came from comparing states across boots; a before/after pair on a
**single** boot settles it. Both halves used the same validated instrument, the
mixer round-trip in `24-speaker-amp`:

```sh
fp3-selftest --only speaker-amp                     # before
fp3-selftest --acoustic --only audio-acoustic,audio-headset
fp3-selftest --only speaker-amp                     # after
```

| | `RX Volume` | |
|---|---|---|
| before the acoustic run | readable and writable at **255** | the amp answers |
| after the acoustic run | reads **0**, writing it back fails | gone for the rest of the boot |

So an acoustic run is what flips it, the flip is one-way, and only a reboot
restores it. A rebind does not: unbinding warns three times at
`_regulator_put+0x5c` and the re-probe then fails with `Chip ID check failed,
-EIO`, so the driver cannot talk to the chip it just reset either.

The `0` is a **failed read**, not a written value: `aw8898_mute()` uses
`PWMCTRL`'s hard-mute bit, not the volume register, so nothing in the driver
writes 0 to `HAGCCFG7`. `amixer` prints 0 because the read returned `-EIO`, and
the kernel logs `ASoC error (-5)` from `soc_component_read_no_lock()` at the
same moment.

Still open: which operation inside the acoustic run does it. The suspect is the
end of the stream — the only surviving `aw8898_set_power(aw8898, false)` is on
`SND_SOC_DAPM_POST_PMD`, and a chip in power-down cannot be woken by a write
that has to cross the bus it just stopped answering. The startup path no longer
powers down on a clock miss (it warns `playing anyway` and returns 0), so that
earlier one-way door is already closed and is not this one.

☠️ **Two instruments lied for most of an hour, and both were unvalidated.**

- A hand-rolled raw-I²C read through `/dev/i2c-N` reported the chip NAKing while
  the driver's own `regmap_read_poll_timeout()` was succeeding in the same
  second. It had never once been shown returning a chip ID.
- Reading `/sys/kernel/debug/regmap/<dev>/registers` with `cache_bypass=1`
  reported every register as `XXXX` on a chip that was answering fine. That dump
  walks all 256 addresses live, and this chip implements a handful, so a
  wholesale `XXXX` is the normal reading for a *healthy* part — it says nothing
  about whether the device is on the bus.

The mixer round-trip was the only path with a known positive behind it, and it
is the one that gave the answer. Same rule as everywhere else in this file: a
check that has never been seen succeeding cannot be read as a failure.

☠️ And the i2c bus number moved again mid-investigation — `4-0034` on one boot,
`2-0034` on the next, `4-0034` on the one after. Two scripts written that
evening hardcoded bus 4 and spent several minutes measuring an empty address on
a boot that had it on bus 2. Resolve it from the device `name`, the way
`24-speaker-amp` does.

### The headset mic hears it too, so the capture path is not the problem

Measured 2026-08-16 with a headset plugged in, on a fresh boot. Both acoustic
checks fail with the same shape rather than with silence: `21-audio-acoustic`
(handset DMIC0) reports peaks at 5500 Hz / 15.7 dB and 6000 Hz / 22.0 dB, and
`22-audio-headset` (analogue headset mic) reports 5500 Hz / 20.5 dB and
6000 Hz / 21.7 dB — for a 1 kHz tone whose fundamental is not the peak in
either. Two independent microphones on two different paths agree, so neither
microphone is at fault and the headset ADC path is alive; what reaches them is a
badly distorted version of what was played. The open question is the amplifier's
output, not the capture side.

☠️ Check order matters here: `21` and `22` sort before `24`, so a battery that
selects all three kills the amplifier in the acoustic checks and then reports
the I²C failure from `24` — which reads as three failures with one cause. To
learn the amp's state *before* an acoustic run, ask for it on its own first.

### Retracting the retraction: the cache was the liar, and here is why

Measured 2026-08-16, later the same evening. The two probes retracted above were
right, and the mixer round-trip that overruled them was wrong. Three probes run
within a second of each other on a fresh boot, at 28.8 s uptime:

| probe | says |
|---|---|
| raw chip-ID read through `/dev/i2c-N` | NAK |
| `cache_bypass=1` regmap dump | `00: XXXX` |
| **a real write** — `cset 'RX Volume' 254` | `-EIO`, refused |
| a `cget` of the same control | `255`, cheerfully |

The `cget` is the odd one out because it never reaches the chip. The driver's
`regmap_config` is:

```c
static const struct regmap_config aw8898_regmap = {
	.reg_bits = 8,
	.val_bits = 16,
	.max_register = AW8898_MAX_REGISTER,
	.cache_type = REGCACHE_MAPLE,
};
```

`cache_type` with **no `volatile_reg` callback at all**, so every register is
cacheable. Three consequences, in rising order of seriousness:

1. **A read of any register can be served from the cache**, which is why `RX
   Volume` reads 255 on an amplifier that is not on the bus.
2. **A write of the value already cached is skipped entirely** — regmap elides
   it — so a "write it back to itself" probe can succeed without a single bus
   transaction. That was the flaw in `24-speaker-amp`'s first I²C arm, now
   fixed: it moves the control by one step (0.5 dB) and puts it back, which
   forces the transaction.
3. **`SYSST` (0x01) is cacheable too**, and that is the register
   `aw8898_prepare()` polls for the PLL-lock bit. After the first read of the
   boot, `regmap_read_poll_timeout()` is polling a cached word that cannot
   change, so a PLL that locks late can never be observed to lock. That is a
   candidate root cause for the entire "the PLL never locks" finding of
   2026-07-31 - not yet confirmed by a patched kernel, and stated here as a
   hypothesis with a source basis, not as a measurement.

The fix is a `volatile_reg` marking at least the status registers volatile.
Kernel change, `audio` category.

What this does **not** explain is why a real write is refused at all. That is
still open, and the earlier claim that "the acoustic run flips it" rests on a
before/after pair whose "before" was a cache read - so it is withdrawn too. Two
things survive the withdrawal, because both used a real write: an `RX Volume`
write is refused on every boot measured tonight, whether or not a stream is
running, and it is refused equally at 254 and at 231, so the level is not the
variable.

☠️ The lesson is one level up from "validate your probe". All three of the
evening's probes were *validated against each other* and agreed - and the
agreement was worthless, because two of them shared a cache. **Two instruments
that share a layer are one instrument.** The write was the only probe that had
to touch the wire, and it was the one worth trusting.
