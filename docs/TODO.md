# Open items

> Closed sections and items are moved verbatim to [`TODO-DONE.md`](TODO-DONE.md);
> numbering gaps here are deliberate so references by number still resolve.

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

## Where this stopped, 2026-08-20 — read this first after a long gap

☠️ **The version of this section dated 2026-08-14 was still here on 2026-08-20 and
every load-bearing sentence in it had gone false.** It said the application
processor had *never once* told the RPM it was going down, that its shutdown count
was zero, and that "that single zero explains the rest". The count is now **16 991
after ten minutes of uptime**, the zero was fixed on 2026-08-17 by one hex digit,
and `vlow` is *still* 0 — which is precisely the sentence the old section used to
rule out. A "read this first" paragraph that is wrong is worse than no paragraph;
that is why this one now carries its own date in the heading.

**The device is on `linux-fp3-7.1.3-r61`, and the running kernel is ours.**
`/boot/vmlinuz` matches the file owned by that package byte for byte.
☠️ `uname -r` reads `7.1.3-postmarketos-qcom-msm8953`, which looks like the
upstream flavour and is not: the package's own `kernel.release` says so, while its
flavour directory is `fp3`. **But `linux-postmarketos-qcom-msm8953-7.1.3-r0` is
also installed**, owns no `/boot/vmlinuz`, and is what makes every `apk` run end
with `only one kernel release/flavor is supported`. Removing it is housekeeping
nobody has done.

**The one thing worth working on is still idle current, and it is still a platform
gap — but a different one.** Three of the four gates now open:

| gate | state |
|---|---|
| the cores reach `cpu-power-collapse` | ✅ since the genpd `bool` fix |
| the AP tells the RPM it went down | ✅ since `0x42000353`, and it does it thousands of times a minute |
| the audio DSP shuts down | ✅ reachable — an ADSP restart frees it for the rest of the boot |
| **the RPM enters `vlow` / `vmin`** | ❌ **`Count: 0` in every capture ever taken here** |

☠️ **There is no `deep` on this platform.** `mem_sleep` offers `[s2idle]` only, and
s2idle itself works — 6/6 suspends, full duration. "Deep sleep" here means getting
the RPM into `vlow`, not finding a suspend mode that does not exist.

**Where the numbers stand:** awake, panel off, ~58–63 mA · asleep, no cuts,
**79.1 mA** · asleep with the modem stack cut, 43.3 mA · asleep with the ADSP
collapsing, 70.8 mA. The target is under 10.

**What closed on 2026-08-19/20, so nobody re-runs it:** that an ADSP client holds
LPASS (six stages, up to stopping the DSP — nothing moved); that the regulator
sleep-set costs anything droppable here (five suspect rails became one with USB
unbound, and that one is the eMMC's); that USB stops the DSP collapsing (three
alternating rounds, nothing); and that the held ADSP session is the lever (the leg
prices it at ~4 %, inside the instrument's own spread). Full account in
[`power/bringup/leads/lpass-never-sleeps.md`](power/bringup/leads/lpass-never-sleeps.md)
and [`power/bringup/findings-log.md`](power/bringup/findings-log.md).

**So the next question is: what else is voting, now that a master going down is
demonstrably not enough.** And the one thing that has *ever* moved the sleeping
number is the modem stack — a 36 % slope reduction, mechanism still unnamed. That
is where the next measurement belongs, not on the ADSP.

☠️ **The 139–143 mA floor and its daemon subtraction are retracted** — the lens
actuator was powered underneath the whole run. The `ak7375` kernel fix that was
queued as "the cheapest next step" shipped long ago. What remains there is
userspace — nothing returns the lens to rest when the preview stops.

**Two lines of work were deliberately stopped, not abandoned.** Both are written
up so they need no re-investigation:

* the fuel gauge's `.resume_early` rest anchor — written, measured working,
  [parked as a patch](charger/bringup/parked/README.md) because it is a
  workaround for an unreachable precondition, and the `S3_GOOD_OCV` path it
  substitutes for is already in the driver and merely starved;
* automatic sleep — demonstrated working, then switched back off because an
  incoming call cannot wake the phone. See the next section.

## ☠️ Deep sleep: `vlow` has never once been reached

The single open item behind every idle-current number on this page, stated
separately because the section above is a status summary and this is a task.

**What is known.** The application processor collapses constantly and says so to
the RPM; the audio DSP can be made to collapse for the whole of every suspend; and
`vlow` and `vmin` still read `Count: 0`. So a master being down is **necessary and
not sufficient**, which is a measured correction to a claim this project carried
for several days.

**What to measure next, in order:**

1. **What else votes.** The regulator branch is closed and the master branch is
   closed; what remains is another master (MPSS, PRONTO, TZ) or a standing
   resource vote that the `qcom_rpm_smd_write` tracepoint cannot see because it
   was cast once at boot and never changed. ☠️ That blind spot is real and has
   already cost one investigation: `bi_tcxo` never appears in a trace for exactly
   that reason. `clk_summary` is the instrument for standing votes, not the trace.
2. **The modem's 36 %.** The only intervention that has ever moved the sleeping
   slope, and its mechanism is unnamed. Wakeup accounting across a suspend
   separates "the MPSS never idles" from "the MPSS keeps waking the AP", and those
   have different fixes.
3. **Release the internal digital codec's LPASS clocks** —
   `msm8916_wcd_digital_probe()` enables `mclk` and `ahbix-clk` unconditionally and
   drops them only in `remove()`, which pins the ADSP awake for the life of the
   boot. ☠️ **Upstream code, not ours**, and on this board that codec is not in the
   audio path. Worth doing for correctness and upstreamable; it is **not** a power
   fix, because the leg prices the whole mechanism at ~4 %. Detail in the audio
   section above.

☠️ **Do not restart any of this by building a kernel.** Nothing here is blocked on
code that has not been written; it is blocked on not knowing which vote is left.

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
([capture](power/bringup/captures/2026-08-13_pmos_lens-vs-chain.txt)):

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
driver ([capture](power/bringup/captures/2026-08-13_pmos_ak7375-position-power.txt)).

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

## The night harness parks the phone at the greeter, defeating the autologin

Observed 2026-08-22, at the end of the overnight suspend legs. The measurement
scripts (`suspend-leg.sh`, `suspend-slope.sh`) stop `greetd` for the window and
restart it on exit. After that restart the phone sits at the **phrog greeter**
(password screen), not in the auto-logged-in phosh session: the journal shows
the restarted greetd opening the greeter session (`user greetd(uid=113)`)
immediately, with no PAM activity for `fp3` — so `[initial_session]` in
`/etc/phrog/greetd-config.toml` did not run on that start, only the
`default_session`. Its own comment says "the session to be used on boot", and
that is how it behaved.

Consequences, both observed the same morning:

* after every unattended night the phone waits at a password screen until a
  human logs in — the selftest battery's autologin premise
  (`03-autologin`) silently does not hold for the post-leg state;
* an incoming call still rings there (gnome-calls runs in the greeter session
  too, which is the desirable half), but answering/unlocking runs into the
  ~80 s manual-login bring-up, which reads as a frozen GUI. A first PAM attempt
  rejected during that window (`AUTH_ERR`, then the retry succeeded) is what a
  2026-08-22 test call looked like from the outside.

~~Open questions, in test order: does greetd re-run `[initial_session]` on a
plain `systemctl restart greetd` on this version at all~~ — **answered
2026-08-22, measured: it does not.** A plain restart brings up the phrog
greeter (`loginctl` class `greeter` on seat0), so the autologin fires on boot
only, and every harness restore lands at the password screen by design of the
config. The restore step therefore has to do something else — either whatever
boot does, or stop stopping greetd and lock the session instead. Also
worth checking: the monotonic-clock trap while reading this journal —
`short-monotonic` does not advance across suspend, so post-leg timestamps look
hours old; compare against `/proc/uptime` (boottime) before dating any event.

### The same night also strands PulseAudio with the card profile `off`

Second symptom, same morning, found when a test call had no ringback and the
volume control showed "Dummy output". The kernel card was fine and every
profile probed as available (`HiFi (Speaker)` etc. `available: yes`), but the
session's PulseAudio held `Active Profile: off`, had produced only the
`auto_null` sink, and **silently ignored `pactl set-card-profile`** — no error
returned, no line logged, no sink created. The instance was started the
previous evening (socket dir timestamped 23:06) and had lived through the
legs' ~5 h of suspends and two greeter/session cycles. `pulseaudio -k` fixed
it outright: the respawned daemon came up with `HiFi (Speaker)` active and a
real sink, confirmed audibly with a 1 kHz tone.

Consequences worth spelling out: a call *rings* in this state (the modem side
does not need the AP's audio card) but has no ringback, no speakerphone and no
audible path — which is what the earlier "the speakerphone button did not
work" report actually was. So the harness restore step has two jobs, not one:
bring back the session (the autologin question above) *and* leave it with a
freshly spawned audio stack — or at minimum the morning-after check should
assert `pactl list sinks short` shows a real sink, which is a one-line probe
the selftest battery could carry (the audio checks all talk to ALSA directly,
so they stay green while every desktop application is deaf).

Both cheap single-shot discriminators came back negative the same day, which
narrows the reproduction rather than the suspect list: with a healthy PA, one
900 s s2idle with no session cycle left the sink and profile intact
(`suspends=1`, verified), and one `systemctl restart greetd` with no suspend
tore the session down, restarted the user's PA — and the fresh instance came
up *correctly*, real sink, `HiFi (Speaker)`. So neither a single suspend nor a
single session cycle strands it; whatever does needs the full overnight
pattern — repetition, the combination, or the 07:41 `module-alsa-source`
failure cascading — and reproducing it costs a night, not fifteen minutes.

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

~~Not yet established, and both are cheap reads: whether anything currently
consumes the value at all, and how long after boot the modem can first
answer.~~ **Both measured, and the bootstrap is written — 2026-08-16.** It is
[`userspace-system/fp3-nitz-clock`](../userspace-system/README.md#fp3-nitz-clock--a-real-date-on-a-phone-with-no-writable-rtc),
with `71-clock` in the battery to keep it from being lost again. What the two
reads answered:

* **registration takes about 42 s** from boot (`registering -> home` at
  17:11:03 for a boot at 17:10:21), so the bootstrap waits for the modem rather
  than running at a fixed point;
* **nothing consumed the value, and on that boot nothing could have.** The
  `org.freedesktop.ModemManager1.Modem.Time` interface was absent from the
  modem's D-Bus object for the whole session — `mmcli -m 0 --time` answered
  *"modem has no time capabilities"* — while the modem was registered on LTE at
  75 % signal with the packet service attached. Restarting ModemManager, or
  disabling and re-enabling the modem, brought it back immediately, with
  `modem has time capabilities, enabling the Time interface` and QMI
  `Get Network Time` traffic following.

☠️ **That last one is still open, and it is the interesting half.** The
capability check looks as though it is decided once, early, and comes out
negative when it runs before the modem can answer — but that is a hypothesis
from a single boot, not a measurement of the mechanism. If it turns out to be
reproducible, the bootstrap will find nothing on a cold boot no matter how long
it waits, and the fix belongs in ModemManager rather than in a script of ours.
The cheap next read is the next reboot: does the interface come up on its own?

The `allow-set-time` / RTC half of this section is untouched by any of it — the
clock still does not survive a reboot, and the warning above about the secure
world still stands.

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
[`docs/power/bringup/RUNBOOK.md`](power/bringup/RUNBOOK.md); the raw capture is
[`docs/power/bringup/captures/2026-08-16_apcs-cpu0-pll-lock-failures.txt`](power/bringup/captures/2026-08-16_apcs-cpu0-pll-lock-failures.txt).

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

### The `volatile_reg` fix is in, and it turned -110 into -5

*2026-08-16 evening, `linux-fp3-7.1.3-r58` (`#59-fp3`,
`_commit=5db94248edcf39f7b0d1a0aabd77c09173d78813`). The kernel change is
`ASoC: aw8898: mark SYSST volatile so the PLL poll can see it change` on
`wip/7.1.3/audio`, cherry-picked to `integration/7.1.3` and `debug-int/7.1.3`.*

The patch does what it was written to do, and the proof is in the error code.
Before it, `.prepare` logged

```
aw8898 4-0034: iis clock not detected (-110), playing anyway
```

`-110` is `-ETIMEDOUT`: the poll ran its full second without the condition ever
becoming true — which is exactly what a loop spinning on one cached sample
looks like. On the first boot of r58 the same line reads

```
aw8898 4-0034: iis clock not detected (-5), playing anyway
```

`-5` is `-EIO`: `regmap_read_poll_timeout()` now performs a real bus read on
every iteration, and that read **fails**. The timing says the same thing
independently — the eleven lines this boot are spread over 24.81 s to 25.43 s,
a few tens of milliseconds apart, where a one-second timeout would have put
them a second apart.

So the PLL hypothesis is settled in a way that was not on the list of expected
answers. It was never "the PLL fails to lock"; the driver could not read the
register that would have told it either way. **What is actually wrong is one
layer lower: the amplifier does not answer on I²C at all.**

☠️ **And this cold boot had a dead amplifier from the start**, which the
2026-08-16 morning boot did not. `fp3-selftest --only speaker-amp` fails both
arms minutes after boot: the `RX Volume` write (255 → 254) is refused, and the
clock complaint is there. Yesterday's cold boot passed both. So "cold boot
heals it" is not reliable either — the state the phone comes up in varies, and
that variation is now the thing to chase.

What that makes the next question. Not the PLL, and not the poll: **why does a
register access to 0x34 return -EIO on a bus whose controller probed cleanly?**
The driver's own probe succeeded on this boot — there is no `Chip ID check
failed` line, so the very first `regmap_read` of `AW8898_ID` went through — and
the failures start only at 24.8 s, when DAPM first powers the widget. Between
those two points something makes the chip stop answering, and the candidates
worth separating are its supplies, its reset GPIO, and `SND_SOC_DAPM_POST_PMD`
having powered it down earlier in the boot than anyone assumed.

### Narrowed the same evening: it is dead before anything plays

Two more boots of r58, and they move the fault well away from the stream:

| boot | first `iis clock` line | amp answers? |
|---|---|---|
| 18:43 | 24.81 s (eleven of them) | no — both arms of `24-speaker-amp` fail |
| 18:52 | **none at all** until the check's own `aplay` | no — the `RX Volume` write fails **before** that `aplay` |

The second boot is the informative one. Nothing had played, the kernel had said
nothing about the amplifier, and the very first thing anyone asked of it — a
one-step `RX Volume` write — was refused. A raw I²C transaction to `0x34`,
independent of the driver and its cache, **NAKs**. So this is not the stream, not
DAPM's teardown of a stream, and not a regmap artefact: by the time userspace can
ask, the chip is not on the bus.

Yet the driver's own probe succeeded. There is no `Chip ID check failed` line on
either boot, which means the first `regmap_read` of `AW8898_ID` — issued straight
after `aw8898_reset()` toggles the reset GPIO — went through. The chip therefore
answers at probe and stops answering somewhere between probe and userspace, with
no audio anywhere in that window.

Checked and cleared as causes:

* **the supplies.** All three consumers are enabled: `4-0034-vdd` off `vph_pwr`,
  `4-0034-dvdd` and `4-0034-vddio` off `pm8953_l5` at 1.8 V.
* **the reset polarity**, which looked like a promising discrepancy and is not.
  The vendor tree declares `reset-gpio = <&tlmm 21 0>` — flags `0`, active-high —
  where ours declares `GPIO_ACTIVE_LOW`. But the vendor driver uses the legacy
  API and ignores the flag: `aw8898_hw_reset()` drives the line **raw low, then
  raw high**. Ours asks for logical 1 then 0 through `gpiod_`, and with
  `GPIO_ACTIVE_LOW` that is raw low then raw high — the same waveform. The two
  descriptions disagree and the two behaviours agree, which is the only thing
  that matters here.

**The hypothesis worth testing next**, and the one experiment that decides it:
`SND_SOC_DAPM_POST_PMD` calls `aw8898_set_power(aw8898, false)`, which writes
`SYSCTRL.PW = PDN`. DAPM powers widgets down when the card's widgets are first
brought up, not only at the end of a stream — so that write plausibly lands
during card registration, long before anything plays. If the chip stops
acknowledging its address in PDN, then the first power-down is permanent: every
later access fails, `aw8898_set_power(true)` included, because it is itself an
I²C write. That fits every observation on both boots.

☠️ The one thing it does not fit is the rebind, and that has to be explained
before the hypothesis is believed: unbinding and re-probing re-runs
`aw8898_reset()`, and a reset should bring any chip back — but it fails at
`Chip ID check failed, -EIO`. Either PDN survives the reset pulse, or the reset
line is not reaching the chip. Deciding between those two is what the experiment
has to do, so it needs to be run with the reset toggled by hand as well.

### The POST_PMD hypothesis is dead, and `aw8898_cfg.bin` is not on the phone

*Measured on the throwaway branch `wip/7.1.3/audio-debug` (`afad60700184`),
deployed as a module hot-swap over r58 and reverted afterwards.*

The experiment answered cleanly and in the negative:

```
[   15.909845] aw8898 4-0034: component_probe: live chip id read -> 0 (0x1702)
[   24.000970] aw8898 4-0034: iis clock not detected (-5), playing anyway
```

and `POST_PMD` was logged **zero** times on that boot. So the widget was never
powered down, and the chip still died — the power-down write is not what takes
it off the bus. The first line also does what it was added for: a
**cache-bypassed** read at 15.91 s returns the real chip ID, `0x1702`, so the
part is alive on the bus when the card binds the component, and dead eight
seconds later.

That narrows the window to what happens between card bind and the first stream,
and there is exactly one substantial thing in it — `SND_SOC_DAPM_PRE_PMU` calls
`aw8898_cold_start()`, which asks for the amplifier's configuration blob and,
on the callback, writes **arbitrary register addresses out of the file**:

```c
regmap_write(aw8898->regmap, addr, val);	/* addr comes from the blob */
```

☠️ **And the blob is not installed.** `/lib/firmware/aw8898_cfg.bin` does not
exist on this device. So `cfg_loaded` never becomes true, every widget power-up
re-issues the request, and — much more to the point — **the amplifier has never
been given its initialisation registers at all.** It is running on whatever the
part powers up with, which is a perfectly good explanation for an I²S interface
that never comes alive, and a candidate one for a chip that stops answering.

Two things follow, in this order, and neither is a kernel patch:

1. **Find out what the blob is and where it comes from.** The vendor tree
   (`hadk22/kernel/fairphone/sdm632`, `sound/soc/codecs/aw/aw8898.c`) loads the
   same file, so the vendor image should carry it — that is the thing to look
   for, along with its licence, before anything is copied anywhere.
2. **Only then decide what the driver should do without one.** Right now a
   missing file is silent past a single `dev_err` and the part is left
   uninitialised; whether that should be a probe failure, a warning, or a set of
   built-in defaults is a real question for the upstream series, not for us
   alone.

☠️ Note what this costs the earlier write-ups: "the amplifier stops answering
mid-session" was measured, and stays measured, but every explanation offered for
it so far was reasoning about a chip that had never been configured. Re-measure
the variability once the blob is in place; the boot-to-boot difference may
simply be a race with a firmware request that can never succeed.

### The blob was on the phone all along, and installing it changed nothing

Both halves of item 1 above are now answered, and the answer to the second half
made the first half cost nothing.

**Where it comes from.** `aw8898_cfg.bin` is a Fairphone stock vendor file. It
is in the extracted vendor tree at
`hadk22/vendor/fairphone/FP3/proprietary/vendor/firmware/aw8898_cfg.bin`, from a
`FP3-6.A.040.2-gms` stock build — and, decisively, it is **also on this phone's
own `vendor` partition, on both slots**, byte-identical:

```sh
mount -o ro /dev/disk/by-partlabel/vendor_a /mnt/vend
md5sum /mnt/vend/firmware/aw8898_cfg.bin	# bbcda305cedb3a26f5c29b48ae80b3ec
```

so the file never has to be redistributed to reach `/lib/firmware`: it is copied
from the device's own stock partition to the device's own rootfs.

☠️ **The licence question has a tempting wrong answer.** The AOSP build tree
carries a `.meta_lic` next to the blob reading
`license_kinds: "SPDX-license-identifier-Apache-2.0"`. That is soong's *default*
for a `raw` prebuilt with no licence of its own, not a grant from Awinic or
Fairphone — the same file names `build/soong/licenses/LICENSE` as its licence
text, which is the build system's, not the blob's. Treat it as proprietary
vendor content with no stated licence: fine to use on the device it shipped
with, not something to commit to a public repository.

**It is 96 bytes of register writes**, 24 entries of `(le16 addr, le16 val)`, and
the mainline driver's parser matches the vendor's byte-for-byte — vendor
`aw8898_container_update()` does `data[i+1]<<8 | data[i+0]` for the address and
the same for the value, which is exactly `struct { __le16 addr; __le16 val; }`.
The last two entries are `0x04 = 0x0044` (SYSCTRL) and `0x08 = 0x0ea0`
(PWMCTRL), i.e. a plausible real init tail.

**And with it installed, the amplifier still dies.** Measured on the boot after
installing it: the cached register dump shows `04: 0044` and `05: 0c08`, which
are the blob's own values, so the file loaded and the driver ran its writes;
every live (cache-bypassed) read still returns `XXXX`.

☠️ **The cached values are not evidence that the writes reached the chip.**
`_regmap_write()` updates the cache *before* it touches the bus and returns the
bus error afterwards, so a failed write leaves the cache looking exactly like a
successful one. Two instruments that share a layer are one instrument.

### The death window, measured to 220 ms

A boot-armed poller (`/usr/local/bin/aw-poll.sh`, a `Type=simple` unit ordered
`After=sysinit.target`) reads `AW8898_ID` through `cache_bypass` every 200 ms
from the moment the driver's regmap appears. One boot, no playback of ours:

```
regmap appeared at 15.12
15.23 00: 1702      <- alive
...                    (44 consecutive samples, 9 seconds)
24.19 00: 1702      <- last live sample
24.41 00: XXXX      <- gone
```

and the first `iis clock not detected (-5)` follows at 24.45. Filtering the
charger's own log spam away, **there is no other kernel event in the window** —
no regulator change, no SSR, no pinctrl message, nothing but the first audio
stream starting.

So the chip is alive for nine uninterrupted seconds and dies within ~220 ms of
the first stream. That also clears the poller itself of suspicion: 44 bypassed
reads in a row did no harm.

**Two hypotheses died cheaply on the way:**

- *The pinmux collides.* It does not. The amplifier's I²C is `gpio22`/`gpio23`
  (`i2c_6_default`), reset is `gpio21`, its IRQ `gpio20`, and QUIN MI2S is
  `gpio88`/`91`/`92`/`93`. No pin is in both groups.
- *A reset revives it.* It does not. A full unbind/rebind — which re-runs probe,
  including the reset-GPIO pulse — fails at the very first step:
  `Failed to read register AW8898_ID: -5`, `Chip ID check failed`,
  `probe with driver aw8898 failed with error -5`. Once it is gone it stays gone
  until a reboot.

Next instrument, because three indirect exclusions have not separated the cases:
a throwaway driver that does a cache-bypassed ID read at *every* step the stream
makes — `hw_params` around each of its two `I2SCTRL` read-modify-writes,
`.prepare` before the PLL poll, the DAPM power-up before and after
`aw8898_set_power()`, the config write before and after, and the mute — so the
death can be attributed to one register access instead of to "the stream".

### The death has nothing to do with audio, and the kernel never says a word

Every explanation offered above rested on the death coinciding with the first
audio stream. **It does not.** The control that settles it: boot with no audio
server at all (pulseaudio's autospawn off and its xdg autostart masked,
pipewire and wireplumber masked), and with `systemctl set-default
multi-user.target` so there is no graphical session either. On that boot there
is not a single `aw8898` line in `dmesg` — no stream was ever prepared — and the
amplifier still stops answering at 23.87 s.

☠️ The earlier reading was a coincidence of timing: userspace comes up at about
the same second on every boot, so "it dies when the first stream starts" and "it
dies about 25 s in" are indistinguishable until you remove the stream.

**What has been excluded, each by its own A/B boot** (all with the death still
occurring):

| suspect | how it was excluded |
|---|---|
| the audio stream | no audio server, no session, no `aw8898` log line — still dies |
| WLAN (`iris` shares `pm8953_l5`) | `blacklist wcn36xx qcom_wcnss_pil wcnss_ctrl` — still dies |
| our own `spkwatch` diagnostic | `systemctl disable --now spkwatch` — still dies |
| our own liveness poller | poller disabled entirely; a single first read at 60 s already reads `XXXX` |
| ModemManager bringing the modem up | `systemctl disable --now ModemManager` — still dies |
| the i2c controller runtime-suspending | `power/control = on` pinned from boot — still dies |
| the i2c pinmux going to its sleep state | `pin 22/23: device 7af6000.i2c function blsp_i2c6` while dead |
| the reset line being asserted | `gpio21: out high` (`GPIO_ACTIVE_LOW`, so de-asserted) while dead |
| the supplies dropping out | `vdd=1 vddio=1 dvdd=1` in the driver's own sample, taken *at* the transition |

**The instrument that settles the layer.** A driver-side `delayed_work` samples
`AW8898_ID` through `regcache_cache_bypass` every 250 ms and logs the moment the
error code changes, so the death lands on the kernel's own timeline next to
every other message:

```
[   17.047332] aw8898 4-0034: LIVE[cfg_write-exit]: err=0 id=0x1702
[   24.993011] aw8898 4-0034: WATCH: id read 0 -> -5 (id=0xffff0000) reset=0 vdd=1 vddio=1 dvdd=1
```

and **there is nothing else in `dmesg` between 23.5 s and 26.5 s** — not one
line, charger spam included.

**It is the chip, not the bus.** Probing the same adapter through `/dev/i2c-N`:
a nonexistent address (`0x20`, `0x35`) returns `EIO`, which is what this
controller reports for a NAK, so `EIO` from the amplifier means the part is not
acknowledging rather than that the bus is broken. A full `0x03`–`0x77` scan with
the chip dead answers **nothing at all**.

**The blob does load and every write succeeds.** With `aw8898_cfg.bin` in place
the log shows `EXP: loaded aw8898_cfg.bin - size: 96` and all 24 writes
returning `0`, ending `reg 0x0004 = 0x0044`, `reg 0x0008 = 0xa00e`. So the
amplifier *is* initialised now — the missing blob was a real defect, and fixing
it did not fix the silence.

**Death times measured so far** (uptime seconds, various boots and
configurations): 23.92, 24.41, 24.55, 24.99, 25.04, 25.25, 25.51 — and one
outlier at 34.16. Tightly clustered around 25 s and anchored to boot, not to any
event we have been able to name.

Open lead being tested next: the kernel's own late regulator cleanup
(`regulator_init_complete_work_function`, 30 s after `late_initcall_sync`) or
another boot-anchored timer turning off a rail the amplifier needs but our
device tree does not describe — which would explain a chip that is powered
according to the framework, out of reset, and electrically absent.

#### 2026-08-17: four arms, one oracle, and `sync_state()` ruled out

All of this was measured with a new instrument that talks to the chip **straight
on the i2c bus** (`/dev/i2c-N` with `I2C_SLAVE_FORCE`, bus resolved from the
`*-0034` device name because the adapter number moves between boots). That
matters: the driver's `regmap_config` caches and declares no `volatile_reg`, so
anything read through the driver can report a plausible value for a chip that is
not on the bus at all. The tool was first pointed at an already-dead chip and
returned 21 failures out of 21 reads — a verifier that has not been shown failing
proves nothing, so that came first.

It ran from a `Type=simple` unit ordered `After=sysinit.target`, because the
death is earlier than sshd and cannot be caught from the host. Both instruments
are in [`docs/audio/tools/`](audio/tools/): `awpoke.py` for one-shot reads and writes,
`awwatch.py` for the boot-window A/B (`control` / `pdn` / `vendor` / `cp` arms).

**The death is invariant.** Four boots, four arms:

| arm | what it wrote at ~15 s | last good read | died |
|---|---|---|---|
| control | nothing | 23.90 | 24.16 |
| pdn | `SYSCTRL = 0x0007` (as found) | 24.07 | 24.32 |
| vendor | `SYSCTRL = 0x0045` — accepted, read back | 24.12 | 24.37 |
| control, `multi-user.target`, no session | nothing | 24.32 | 24.58 |

So it is not the chip's register state, and it is not the graphical session or
the sound server: the last row had **no `aw8898` line in dmesg at all** and died
on schedule. ⚠️ In an earlier boot the driver's `iis clock not detected (-5)`
messages started at 24.46 s, a fifth of a second *after* the chip had already
stopped answering — those messages are a consequence of the session opening the
sink into a dead chip, not the cause. The window is ±0.3 s across every boot,
which is the signature of a kernel timer rather than of anything userspace does.

**`sync_state()` is ruled out.** The `syncstate-snap.sh` sampler shows **no
`state_synced` flag changing anywhere** — not across the death window, not across
the whole run (14.9 s → 84.5 s). Exactly one device is still unsynced,
`soc@0/1800000.clock-controller`, and it is still unsynced at the end, so its
callback has not run at all.

☠️ The first run of that sampler was worthless and looked clean: its three-level
glob under `/sys/devices/platform` reached **13 of the 39** `state_synced` files
and none of the i2c devices, so it could not have seen the amplifier's own
supplier sync even if that had been the cause. The script now walks the tree with
`find`; the verdict above is the run with 39/39 coverage.

**The Ubuntu Touch oracle, read the same night.** On the vendor 4.9 kernel the
amplifier sits at `6-0034` and **answers every register at 9 minutes of uptime**
— same silicon, so the death is ours, not a property of the part. Two things came
out of the comparison:

* **The vendor device tree gives the aw8898 no supply at all.** Its probe reports
  only `reset gpio provided ok` and `irq gpio provided ok`, and no regulator in
  `regulator_summary` lists it as a consumer. So the mainline `l5` choice is our
  invention, and the `l10` that drifts 2850→2800 mV is consumerless on the oracle
  too. Both directions of the earlier plan are answered: the rail we are looking
  for is not described on either side, which points at an always-on rail or an
  external switch rather than at a PMIC regulator the kernel manages.
* The vendor idles at `SYSCTRL = 0x0045` (charge pump active, I2S enabled) where
  we idle at `0x0007` (both powered down). Writing the vendor's value changed
  nothing — see the table — so this is a difference, not the lever.

Vendor register semantics confirmed from
`hadk22/kernel/fairphone/sdm632/sound/soc/codecs/aw/aw8898_reg.h`: `SYSCTRL`
bit 0 is `PW_PDN` (1 = powered down), which is the polarity our driver already
uses. The golden trace is `docs/audio/` material; the vendor blob stays out of
the repo.

What is left, in order: something un-logged in the kernel at ~24 s takes the
chip's power or reset away. The reset line and the pinmux were excluded earlier
with instruments that read through the driver's cache, so those exclusions are
worth re-running with the bus-direct tool before looking further.

### ☠️ The phone was stuck at a hang and needed a button press — recovered 2026-08-17 00:00

**Resolved.** The way back in was not any of the host-side attempts below: it was
the **UBports recovery**, reached with a button press, whose adb shell can mount
the pmOS filesystems directly. `system_b` (`mmcblk0p31`) carries an embedded
msdos table — `/boot` at offset 1048576, root at 511705088 — so
`losetup -o <offset>` plus `mount` gives read-write access to `extlinux.conf`
without booting pmOS at all. That is worth remembering as the general recovery:
**anything on disk can be fixed from the recovery, no matter how badly the
default boot entry is broken.** The clean `append` line was restored from
`extlinux.conf.bak-aw`, `panic=10` was added to both labels (neither had it), and
`fp3-selftest --only boot-fallback` is green. Full battery afterwards: 29 ok,
1 failed, 3 skipped — the one failure being the open `24-speaker-amp` case.

☠️ The recovery reboot leaves **slot `a`** active (the Ubuntu Touch side), so
`fastboot set_active b` is needed before pmOS will boot again.

The original state, kept because the attempts below are the useful part:

**State, 2026-08-16 ~21:00.** The device does not boot and does not enumerate on
USB at all. The last good boot was 20:54:15; the reboot at 20:57:23 never came
back, and 25 minutes of polling saw nothing on `lsusb`.

**What did it.** I added `fw_devlink=off` to the kernel command line, in
`/boot/extlinux/extlinux.conf`, to test whether a `sync_state()` callback was
turning off a rail the amplifier needs. It hangs before the USB gadget comes up,
so there is no console, no ssh and no fastboot — and the parameter is on disk, so
every reboot repeats it. The watchdog does not save it either, which places the
hang before the watchdog driver probes.

☠️ **The rule this broke is already written down**: *a kernel experiment must
never block boot*. A command-line change is exactly that class of change, and I
made it with no armed fallback — on a device whose only two channels (ssh over
USB and ssh over WiFi) both need userspace to be running. The cost is not the
experiment, which was a fair one, but that it was staged in the one place that
cannot be undone from the outside.

**Recovery, needs a hand on the phone:**

1. Hold **power** for ~15 s to force it off.
2. Hold **volume up** while powering on to reach the lk2nd boot menu, and pick
   the second entry (`postmarketOS-fallback`) — its `append` line was never
   touched and still has the clean command line.
3. Once up, undo the change; the untouched original is already saved next to it:

```sh
sudo cp /boot/extlinux/extlinux.conf.bak-aw /boot/extlinux/extlinux.conf
grep append /boot/extlinux/extlinux.conf	# no fw_devlink=off, no regulator_ignore_unused
```

**What was tried from the host, 2026-08-16 23:00–00:00, and what it settled.**
The phone reached fastboot (ABL, `version-bootloader 6.A.039`, `unlocked: yes`,
`secure: no`), which made it worth asking whether the hang could be undone
without a hand on the phone at all. It cannot, and the attempts are worth
recording because each one looked promising:

| attempt | result |
|---|---|
| `fastboot flash boot_b <our boot image>`, then reboot | flash OKAY, phone returns to fastboot, `slot-retry-count:b` still **6** — never attempted, so the image is rejected by validation |
| same, with the boot header's `id` (SHA1) field filled in | same rejection; the empty `id` was not the difference |
| `fastboot boot` with the gzip `vmlinuz` + appended dtb | `FAILED (remote: 'dtb not found')` |
| `fastboot boot` with the raw `Image` + appended dtb | `FAILED (remote: 'unknown reason')` — so the appended dtb is only found on an uncompressed kernel |
| same, with the ramdisk moved to `0x82000000` (the 28 MB kernel at `0x80008000` overlapped `0x81000000`) | unchanged: `unknown reason` |
| **`fastboot boot lk2nd.img`** — the image that boots perfectly when flashed | `FAILED (remote: 'unknown reason')` |

The last row is the one that matters: **`fastboot boot` fails identically for a
known-good image**, so it is broken on this bootloader for every input, and the
whole dtb / `id` / load-address investigation above was chasing a message that
was never about the image. The lesson is now rule 22 in `fp3-kernel-test`, and
the procedure lives in [`../deploy/README.md`](deploy/README.md) under *If the
phone does not boot at all*. `lk2nd.img` was flashed back to `boot_b` afterwards,
so the normal boot chain is intact and the button press is all that is missing.

☠️ The fastboot USB link freezes if a command is interrupted (an outer `timeout`
firing mid-transfer is enough) and every later command then hangs; a
`USBDEVFS_RESET` on the device node clears it immediately.

**Also left on the device, all deliberate and all reversible from a shell:**

| change | undo |
|---|---|
| `graphical.target` → `multi-user.target` | `systemctl set-default graphical.target` |
| pulseaudio autospawn off, xdg autostart masked | `sed -i 's/^autospawn = no/; autospawn = yes/' /etc/pulse/client.conf`; `rm ~/.config/systemd/user/app-pulseaudio@autostart.service` |
| pipewire/wireplumber masked | `systemctl --user unmask pipewire.service pipewire.socket wireplumber.service` |
| WLAN blacklisted | `rm /etc/modprobe.d/zz-fp3-wlan-off.conf` |
| `spkwatch`, `ModemManager`, `aw-poll` disabled | `systemctl enable --now spkwatch ModemManager` |
| `regsnap.service` (per-second regulator snapshots) | `systemctl disable --now regsnap` |
| the instrumented `snd-soc-aw8898.ko` | `cp /root/aw8898.ko.r58 /lib/modules/$(uname -r)/kernel/sound/soc/codecs/snd-soc-aw8898.ko && depmod -a` |
| `/lib/firmware/aw8898_cfg.bin` | **keep it** — it is stock content from the phone's own vendor partition and it is what the driver has always been asking for |

The experiment kernel is preserved on the fork as `wip/7.1.3/audio-debug`, tagged
`archive/wip-7.1.3-audio-debug-watch`; nothing on any shipping branch changed.
