> ⚠️ **AI-generated.** Maintained by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

# The RPM sleep set, and the nine-year hole in the mainline regulator driver

## The claim

**Mainline never sends a sleep-set request for any PM8953 rail.** The vendor
sends one for every rail whose sleep aggregate differs from its active
aggregate. On the RPM, a resource with an active request and no sleep request
uses the active request *at all times, including while the Apps processor is
power-collapsed*. So on mainline, every rail a consumer turned on stays on
through suspend, by construction.

This is read out of both drivers, not inferred. It is **not yet measured to be
worth any particular number of milliamps** - see "What this does not say".

## The vendor side, from the source on disk

`drivers/regulator/rpm-smd-regulator.c` in
`hadk22/kernel/fairphone/sdm632/`. Its own comment states the RPM rule:

> Regulator requests sent in the active set take effect immediately. Requests
> sent in the sleep set take effect when the Apps processor transitions into
> RPM assisted power collapse. For any given regulator, if an active set
> request is present, but not a sleep set request, then the active set request
> is used at all times, even when the Apps processor is power collapsed.
>
> The rpm-regulator-smd takes advantage of this default usage of the active set
> request by only sending a sleep set request if it differs from the
> corresponding active set request.

Each regulator device carries two RPM handles, `handle_active` and
`handle_sleep`, and each *consumer* node carries `qcom,set`, a mandatory
bitmask - `BIT(0)` active, `BIT(1)` sleep - that decides which aggregates it
contributes to:

```c
list_for_each_entry(reg, &rpm_vreg->reg_list, list) {
        if (reg->set_active) { rpm_vreg_aggregate_params(param_active, reg->req.param); ... }
        if (reg->set_sleep)  { rpm_vreg_aggregate_params(param_sleep,  reg->req.param); ... }
}
```

The two aggregates then differ exactly when some consumer is in one set and not
the other, and only then is a sleep request sent.

**On this SoC's own DT the mechanism is in use.** Of the 30 `qcom,set`
properties across `pm8953-rpm-regulator.dtsi` and `msm8953-regulator.dtsi`:

| value | count | meaning | which nodes |
|---|---|---|---|
| 3 | 26 | both sets | everything ordinary |
| 1 | 3 | **active only** | `pm8953_s2_level_ao`, `pm8953_s7_level_ao`, `pm8953_l7_ao` |
| 2 | 1 | **sleep only** | `pm8953_s7_level_so` |

The `_ao` nodes are how a consumer says *hold this up while I am awake and let
it drop when I am not*; `pm8953_s7_level_so` is the vendor voting a **lower
corner in sleep** than it holds awake. Neither has any expression in mainline.

## The mainline side

`drivers/regulator/qcom_smd-regulator.c` contains **exactly one**
`qcom_rpm_smd_write()` call, in `rpm_reg_write_active()`, and it is hard-coded:

```c
qcom_rpm_smd_write(vreg->rpm, QCOM_SMD_RPM_ACTIVE_STATE, ...)
```

There is no sleep path at all - no second handle, no `qcom,set` equivalent, no
aggregate. Every rail therefore has an active vote and no sleep vote, and the
RPM rule above turns that into "stays as it is through power collapse".

This matches the tracepoint measurement already taken on this device: at
suspend entry, `rpmpd`, `icc-rpm` and `clk-smd-rpm` all vote in the sleep set;
**the LDOs vote 14 active and 0 sleep.**

## Why the obvious patch is wrong

☠️ **Mirroring the active vote into the sleep set is a no-op by construction.**
That is precisely the state the RPM already assumes when no sleep request
exists. Writing it explicitly changes nothing except the number of messages.
The only thing that saves current is a sleep vote that is *lower* than the
active one.

☠️ **A blanket "disable everything in sleep" is unsafe.** Some of these rails
feed things that must survive suspend - the RPM's own island, the modem's
retention, the eMMC's I/O rail on a device whose eMMC has already fallen off
the bus once. The vendor does not do this either: it drops specific rails
because specific consumers declared themselves active-only.

So the correct shape is the vendor's shape: **the sleep vote must come from
consumer intent**, not from a global policy in the provider driver. In mainline
terms that means a rail's sleep state follows from which consumers keep it
enabled across suspend, which is a genuine design question and not a one-liner.

## What this does not say

- It does **not** say the LDOs are worth the ~60 mA gap. Sixteen LDOs left
  standing is a plausible tens-of-milliamps story and nothing more until it is
  measured. The XO branch was also a plausible mechanical story, moved the APSS
  XO shutdown count from 0 to 1952, and changed the discharge slope by nothing.
- It does **not** identify which of the 14 are droppable. That needs the census:
  the resource ids from the `qcom_rpm_smd_write` tracepoint at suspend entry,
  matched against the rail table in the FP3 DT.
- It does **not** explain `vlow`/`vmin` staying at 0. A rail left up is a
  current cost; the RPM refusing to enter a low-power mode is a *vote* problem,
  and those are different failures that happen to live in the same driver.

## Who holds what: the FP3 rail map

Parsed out of `sdm632-fairphone-fp3.dts` - every `*-supply = <&pm8953_*>` with
the node that asks for it. This is what turns a census line like `ldoa/8` into
a decision.

| rail | consumers in the FP3 DT |
|---|---|
| `s3` | `&camss:vdda`, `&mdss_dsi0:vdda`, and the parent of `l1`, `l2`, `l3` |
| `s4` | the parent of `l4 l5 l6 l7 l16 l19` |
| `s5` | **none** |
| `l1` | **none** |
| `l2` | `camera@1a:vdig` |
| `l3` | `&hsusb_phy:vdd`, `&mdss_dsi0_phy:vcca` |
| `l5` | `&sdhc_1:vqmmc`, `&wcnss:vddpx`, `&wcnss_iris:vdddig`, `aw8898:dvdd`, `aw8898:vddio` |
| `l6` | `panel@0:iovcc` |
| `l7` | `&hsusb_phy:vdda-pll`, `&mpss:pll`, `&wcnss_iris:vddxo` |
| `l8` | `&sdhc_1:vmmc` |
| `l9` | `&wcnss_iris:vddpa` |
| `l11` | `&sdhc_2:vmmc` |
| `l12` | `&sdhc_2:vqmmc` |
| `l13` | `&hsusb_phy:vdda-phy-dpdm` |
| `l16` | **none** |
| `l17` | **none** |
| `l19` | `&wcnss_iris:vddrfa` |
| `l22` | `camera@10:vdda`, `camera@1a:vana` |
| `l23` | **none** |

Two things fall out of it.

**☠️ Five of the nineteen declared rails have no consumer at all** - `s5`, `l1`,
`l16`, `l17`, `l23`. If any of those turns up in the census with `swen=1`, it is
not being held by a Linux driver, and no amount of consumer-intent work in the
regulator layer will drop it. That would point at the RPM's own boot state or at
another master, and it is a different investigation.

**☠️ Four rails must not be dropped in sleep under any circumstances.** `l8`
(`sdhc_1:vmmc`) and `l5` (`sdhc_1:vqmmc`) are **the eMMC**, and `l11`/`l12` are
the SD slot. The eMMC on this device has already fallen off the bus once, on the
night of 2026-08-18, with `-110` and `emergency_ro`. Any future sleep-vote work
treats those four as untouchable until someone has a reason better than "it
saves current", and that reason has to survive the question of what happens to a
filesystem when its rail comes back.

`l7` is the next most dangerous: it feeds `&mpss:pll`, the modem's PLL, and the
modem is one of the masters whose sleep vote the RPM is waiting for.

## ★ Measured 2026-08-19: the census, taken across a real suspend

Run as job 2 of the first unattended night. `qcom_rpm_smd_write` traced across a
30 s `rtcwake` suspend, decoded by
[`../tools/rail-census-parse.py`](../tools/rail-census-parse.py). Raw and decoded:
[`../captures/2026-08-19_rail-census.txt`](../captures/2026-08-19_rail-census.txt).

**35 resources voted; 22 of them cast no sleep vote at all.** Of those, five are
PMIC rails that are *enabled* — held up through the suspend by the absence of a
sleep vote rather than because anything asked for them:

| rail | consumers | verdict |
|---|---|---|
| `ldoa/3` | `hsusb_phy:vdd`, `mdss_dsi0_phy:vcca` | USB PHY — see the confound below |
| `ldoa/7` | `hsusb_phy:vdda-pll`, **`mpss:pll`**, `wcnss_iris:vddxo` | ☠️ feeds the modem PLL; off the table |
| `ldoa/8` | `sdhc_1:vmmc` (eMMC) | ☠️ **NOSLEEP** — off the table |
| `ldoa/13` | `hsusb_phy:vdda-phy-dpdm` | USB PHY — see the confound below |
| `smpa/3` | `camss:vdda`, `mdss_dsi0:vdda`, parent of l1/l2/l3 | the interesting one |

☠️ **The confound, and it is ours.** This census was taken with USB attached and
the phone on the charger — which is how every measurement here is taken, because
that is how the data leaves the phone. Three of the five enabled rails are USB
PHY rails, and a USB PHY held up while a USB cable is plugged in is not a finding.
**Repeat it on the WiFi link with USB detached before reading anything into those
three.** What survives that repeat is `smpa/3`, and `ldoa/8` which is not
droppable anyway.

The remaining 17 no-sleep-vote resources are interconnect masters and slaves and
one RPM clock, not PMIC rails. ☠️ The parser used to print those as `pm8953_lNN`,
inventing rails that do not exist; fixed the same day.

## ★★ The repeat without USB, an hour later: five became one

[`../tools/usb-off-census.sh`](../tools/usb-off-census.sh) unbinds `7000000.usb`
from `dwc3-qcom` and `79000.phy` from `qcom-qusb2-phy`, re-runs the census over
the WiFi link, and rebinds on every exit path and on a `RuntimeMaxSec` deadline.
Raw and decoded:
[`../captures/2026-08-19_rail-census-usb-off.txt`](../captures/2026-08-19_rail-census-usb-off.txt).

| | USB attached | USB unbound |
|---|---|---|
| resources voted | 35 | 31 |
| no sleep vote | 22 | 18 |
| **enabled PMIC rails with no sleep vote** | **5** | **1** |

The one that remains is `ldoa/8` — `sdhc_1:vmmc`, the eMMC, which is marked
NOSLEEP in the rail map and has to stay up. `ldoa/3`, `ldoa/7`, `ldoa/13` and
`smpa/3` do not appear in the vote list at all with the PHY gone: they were not
"voted active and never sleep", they were **the USB PHY's, and it released them**.

`clk1/0` and `clk1/1` moved too — they voted `KHz=87500` in both sets with USB
attached and `KHz=0` for sleep without it.

**So the sleep-set gap is real in the code and costs nothing droppable here.**
Mainline's `qcom_smd-regulator.c` still only ever writes the active state, and
that is still a nine-year divergence from the vendor worth fixing upstream — but
on this device, in the state that matters, it leaves exactly one rail up and that
rail is the eMMC's. No patch on this page buys any current on the FP3.

☠️ **The measurement that produced the five-rail list was not wrong, it was
mis-set-up** — and it looked like a finding, complete with consumers named from
the DT. What separated it from a real one was asking what else was true of the
phone at the time. The answer was "a USB cable", which is true of every
measurement in this investigation.

## ★ 2026-08-20: prior art checked — no solution exists, and the obvious shape is disputed

Searched before writing any code. Nothing adds sleep-set support to
`qcom_smd-regulator.c` anywhere: not mainline, not a lore series, not the
msm8916-mainline tree. The closest thing is the discussion under Stephan
Gerhold's 2023 series "[PATCH 8/8] arm64: dts: qcom: msm8916-pm8916: Mark
always-on regulators" (with Konrad Dybcio), and it rules out the
implementation a regulator developer would reach for first:

* **RPM sleep votes are not the regulator framework's suspend states.** The
  sleep set takes effect whenever cpuidle reaches the deepest cluster state —
  any time at runtime — while `regulator-state-mem`/`set_suspend_*` model
  system suspend. Mapping one onto the other is semantically wrong.
* Gerhold confirms the RPM rule this page reads out of the vendor comment:
  every active request counts as active+sleep **until the first sleep vote
  for that resource arrives**.
* The direction he suggests is per-rail **active-only** support (as `rpmpd`
  already has), or treating CPU-feeding rails as power domains — a binding
  design conversation, not a driver one-liner.
* Sibling-device data point: on msm8916, L7 (CPU PLL) "seems to stay
  always-on no matter what" — the vendor's `_ao` trio (s2/s7/l7 on msm8953)
  is exactly the CPU-rail set this feature exists for.

Thread: https://lore.kernel.org/all/ (search: msm8916-pm8916 Mark always-on
regulators, 2023-05); archived copy: https://lkml.indiana.edu/2305.3/03307.html

Combined with the census above — one rail left standing and it is the eMMC's —
the conclusion stands: **no patch here buys current on the FP3 today**, and if
`vlow` turns out to be gated on a missing vote, the fix should take the
active-only shape from that thread, not the suspend-ops shape.

## The next measurement, not the next patch

1. Trace `qcom_rpm_smd_write` across a suspend and print the **resource ids**,
   not just the counts, so the 14 rails have names.
2. Cross the names against the FP3 DT's 19 declared rails (3 SMPS + 16 LDOs,
   `sdm632-fairphone-fp3.dts`) and against what each one supplies.
3. Only then decide whether any of them can be dropped, and by whose intent.

## 2026-08-22: the driver side exists now — what remains is the DT opt-in

`regulator: qcom_smd: cast sleep-set votes for suspend states` is on
`wip/7.1.3/power` (`5fe5dba65260`, all three layers, pushed): the driver
gains `set_suspend_enable/disable/voltage` writing `swen`/`uv` into
`QCOM_SMD_RPM_SLEEP_STATE`. Without DT it is a no-op — the regulator core
only calls the suspend ops for a regulator whose constraints carry a
`regulator-state-mem` child.

The opt-in step, deliberately not rushed overnight:

1. **Re-run the rail census over the WiFi link with USB detached** — the
   three USB-PHY rails above are confounded until then.
2. Start with the survivors only: `smpa/3` first
   (`regulator-state-mem { regulator-off-in-suspend; }` — but it parents
   l1/l2/l3, so read the vendor DT's own sleep config for it first:
   `qcom,init-*` / `regulator-*-sleep` properties in the downstream tree at
   `hadk22/kernel/fairphone/sdm632/arch/arm64/boot/dts/`), never `ldoa/7`
   (modem PLL) or `ldoa/8` (eMMC, NOSLEEP).
3. One rail per experiment, the three-window capture as the instrument, vlow
   `Count` and the APSS/master stats as the readout, combined with
   `xo_sleep_off=1` (the `-xo` boot entry) since the two blockers are
   additive.
4. The failure mode to fear is a rail some active-but-unvoted consumer needs
   mid-suspend-entry: gate every such boot behind the fallback entry and the
   30 s guard window, exactly like the xo experiment.

## 2026-08-23 dawn: the interconnect trail, where it stands

The both_sets census left only icc resources without sleep votes; mapped via
`drivers/interconnect/qcom/msm8953.c` they are the **bus bridge/internal
nodes** (`mas/slv_bimc_snoc`, `mas/slv_snoc_pcnoc`, `pcnoc_int_2`,
`pcnoc_s_6`, `snoc_int_1`) **plus `slv_sdcc_1`/`slv_sdcc_2`**, all at
bw=50000000 or 0. `icc-rpm.c` mechanics read so far: `qcom_icc_rpm_set` loops
BOTH rpm contexts per node, and an untagged consumer vote defaults to
`RPM_ALWAYS_TAG` (both buckets) — so these nodes' votes must come from a
consumer that explicitly tags `QCOM_ICC_TAG_ACTIVE_ONLY` (sleep bucket left
at 0, so "no sleep write" = sleep bw genuinely 0... note that means the RPM
*should* see sleep bw 0 for them — check whether "no vote ever written"
differs from "sleep vote of 0" in RPM semantics: qcom_icc_rpm_set only sends
when the value CHANGES from applied, and both start at 0, so a sleep bucket
that stays 0 never gets a write — **the absent sleep vote may be a
no-change-elision, not a tag issue at all**). Next: find who casts the 50 MB/s
votes (sdcc paths suspect the mmc DT `interconnects`), and answer the
elision question — if RPM treats "never written" as inherit-active, the fix
is one explicit zero-write at probe, which is small and upstreamable.

## 2026-08-23: the Client Votes mask — raw material for a decode

> ☠️ **Superseded and partly retracted.** The mask was decoded later the same
> day (bit 0 APSS, 1 MPSS, 2 PRONTO, 3 TZ, 4 LPASS), and the "bit 4 is a bit
> the mainline side never sets" claim below is **false** — see the retraction in
> the 2026-08-23 section at the end of this page. Kept for the raw samples only.

Samples collected across the night (pmOS, various knob combinations):
`0x7030703 0x3070307 0x5010501 0x10001 0x5040001 0x10501 0x1000105 0x3070607
0x7030203 0x7030105 0x7060703` — and from the oracle (UT 4.9): `0x11011101
0x11010501 0x07051505`. Observations, not conclusions: four bytes; the two
16-bit halves are often equal on pmOS; pmOS bytes stay within {0,1,3,4,5,6,7}
(low three bits only), UT bytes also show 0x11/0x15 (bit 4 set) — a bit the
mainline side never sets. If each byte is one voting client's bitfield (four
clients — plausibly APSS/MPSS/PRONTO/LPASS, the TZ casting nothing), then
bit 4 is a downstream-only vote component and a candidate name for what the
RPM is waiting for. Decode needs the RPM firmware or a Qualcomm header;
empirically, the next lever would be finding what downstream action toggles
bit 4 (a sleep-driver handshake? the vMPM?).

## ★★★ 2026-08-23: measured after six real suspend windows — the ADSP is the master that stopped sleeping

Queue item ③ (*read the `Client Votes` mask immediately after a suspend window,
from the `postmarketOS-xo` label*) is closed, and it answered a bigger question
than it asked.

Instrument: [`../tools/votes-post-resume.sh`](../tools/votes-post-resume.sh).
Raw: [`../captures/2026-08-23_votes-post-resume-xo.txt`](../captures/2026-08-23_votes-post-resume-xo.txt).
Boot: r73 on the `postmarketOS-xo` label (`clk_smd_rpm.xo_sleep_off=1`), 10 awake
control samples then 6 × 30 s `wakealarm` suspend windows, each followed by an
8-sample burst.

**Sanity rows first, because both of them nearly did not exist:**

| row | value |
|---|---|
| `/sys/power/suspend_stats/success` | 6 → 12, **delta 6, expected 6** |
| APSS XO shutdown count | 15298 → 17008 (**+1710**) |

So the windows really suspended, and the APSS really power-collapsed inside them.

**The readout:**

| master | at start | at end | delta over six windows |
|---|---|---|---|
| APSS | 15298 | 17008 | **+1710** |
| MPSS | 1452 | 2086 | +634 |
| PRONTO | 3302 | 3659 | +357 |
| **LPASS** | **65** | **65** | **0** |
| TZ | 0 | 0 | 0 |

`vlow Count` and `vmin Count` read **0 in all 58 samples** — control and
post-resume alike, on the one label where the APSS demonstrably goes down.

**And LPASS's own file says when it stopped.** RPM timestamps are 19.2 MHz ticks
(checked: APSS `Last shutdown @ 16557043975` ÷ 19.2e6 = 862 s, against an uptime
of 849 s at the same read):

```
LPASS:
	Last shutdown @ 889662089        ->  46.3 s of uptime
	XO shutdown count: 47
	Shutdown count: 65
	Active cores bitmask: 0x0
```

**The ADSP slept 65 times in the first ~46 seconds of the boot and has not slept
once since** — not in the ten minutes of this run, not in any of the six windows.
Every other master is still cycling normally.

That is a name for what the RPM is waiting for. `vlow`/`vmin` are aggregate
low-power sets: they cannot be entered while a master has not voted itself down.
Four masters vote; one has been pinned awake since second 46 of the boot.

☠️ **TZ is all zeros from boot** — every field, not just the counts. This is not
news and not a second stuck master: the oracle shows the same zeros, and the mask
decode already acquitted it (bit 3, never set anywhere).

### What this does *not* say

- It does **not** identify what pins the ADSP at ~46 s. That timestamp is in the
  neighbourhood of audio bring-up, which makes q6/SLIMbus the obvious suspect and
  therefore exactly the hypothesis most likely to be believed without evidence.
  The measurement is: read LPASS `Shutdown count` at a fixed early uptime, then
  bisect against the things that start around it.
- It does **not** prove LPASS is the *only* blocker. It proves it is *a* blocker
  and the only one currently visible.
- It does **not** connect to any milliamp figure yet.

### ☠️ Retraction: bit 4 is not downstream-only — and it is the same finding

The 2026-08-23 section above says of the vote mask that pmOS bytes stay within
`{0,1,3,4,5,6,7}` and that UT's `0x11`/`0x15` show "bit 4 set — a bit the
mainline side never sets", then builds on it: "bit 4 is a downstream-only vote
component and a candidate name for what the RPM is waiting for."

**That is false.** Measured on this pmOS boot, 1 sample out of 58:
`0x15050105` — top byte `0x15`, bit 4 set. Mainline does set it. The
"downstream-only" reading, and the lever it suggested (find what downstream
action toggles bit 4), are withdrawn.

★ **And the correction lands on the same conclusion from the other side.** The
mask was decoded by subtraction later that day (`TODO.md`, deep-sleep item 2):
the master index is the RPM message-RAM slot, `offset >> 12`, giving **bit 0 ↔
APSS, bit 1 ↔ MPSS, bit 2 ↔ PRONTO, bit 3 ↔ TZ, bit 4 ↔ LPASS**. So "bit 4 set
in 1 of 58 samples" *is* "LPASS almost never votes itself down" — the vote mask
and the master-stats counter are two independent instruments and they agree.
That is also why the ☠️ TZ note above only repeats what the decode already
established: bit 3 has never been set anywhere, oracle included.

### ☠️ Instrument defect: a blank row is not a zero

The first version of this sampler printed **empty** `xo:` rows for an entire
six-window run. The cause was not a missing module — `rpm_master_stats` was
loaded the whole time — it was that `/sys/kernel/debug/qcom_rpm_master_stats` is
root-only and the sampler ran as the user. Blank rows read as "nothing to see"
next to lines that did print.

`votes-post-resume.sh` therefore refuses to start unless it can read the vote
file, the master stats, the suspend counter, and `clk_smd_rpm.xo_sleep_off=1` on
the cmdline. All four were shown aborting before any row was believed — and the
suspend-counter gate fired for real, on a bug of mine:
`/sys/power/suspend_stats` is a **directory** on this kernel, so reading it as a
file returned nothing.

## ★★ 2026-08-23, later: the freeze is at ~34 s of *uptime*, and it is not the sensors

Two corrections and one acquittal, all measured the same evening.

### ☠️ Correction: "46.3 s of uptime" was 46.3 s of *RPM* time

The section above decodes LPASS `Last shutdown @` as 46.3 s and calls it uptime.
**It is not.** The RPM's 19.2 MHz counter runs from SoC reset, so it leads
`/proc/uptime` by the bootloader's share — measured three times at **+13 to
+14 s** (APSS `Last shutdown @` 16557043975 ÷ 19.2e6 = 862 s against an uptime of
849 s at the same read). The freeze is at **~34 s of Linux uptime**.

That was not fixed by better arithmetic but by removing it:
[`../tools/lpass-trace.sh`](../tools/lpass-trace.sh) now writes every sample to
`/dev/kmsg` as well, so the counter lands in the journal beside whatever else
happened in that second and no clock has to be converted into another. It runs as
a boot unit because ssh is not reachable before 34 s.

☠️ **And the first attempt to read that journal window lied by omission.** The
filter was `awk '{gsub(/[][]/,"",$1); if ($1+0>=32 ...)}'` — but
`[   34.583754]` splits into `[` and `34.583754]`, so `$1` was a bracket and
**nothing ever matched**. It printed an empty window and read as "no kernel
events there". Same shape of failure as the `dmesg`-by-timestamp filter in
`docs/audio/ssr-repro.sh`: a filter that silently matches nothing is
indistinguishable from a clean result. Match on `$0` against `^\[ *3[0-9]\.`.

Three boots, three freezes, all at the same place:

| boot | last LPASS shutdown | `Shutdown count` it froze at |
|---|---|---|
| xo label | ~33 s uptime (RPM 46.3 s) | 65 |
| default #1 | 34 s uptime (RPM 48.0 s) | 33 |
| default #2 | 34.6 s uptime (RPM 47.5 s) | 35 |

The *count* varies boot to boot; the *moment* does not.

### The sensor stack is acquitted

`snsregd` starts at 33.6 s and SMGR runs on the ADSP, which made it the obvious
suspect — and therefore the one to test rather than assume.
[`../tools/lpass-bisect.sh`](../tools/lpass-bisect.sh) takes it away and watches,
with a BEFORE window that has to show the counter flat or there is nothing to
bisect. Raw:
[`../captures/2026-08-23_lpass-bisect-sensors.txt`](../captures/2026-08-23_lpass-bisect-sensors.txt).

| window | LPASS | APSS |
|---|---|---|
| BEFORE, 30 s, stack running | **35 → 35** | 3455 → 4483 |
| AFTER, 60 s, `smgr*`/`sns_smgr` unloaded, `snsregd` + `iio-sensor-proxy` stopped | **37 → 37** | 4483 → 6443 |

The premise held (flat for the whole BEFORE window) and the answer is **no**.
The `+2` arrived inside the first five seconds — the teardown itself — and then
the counter froze again for the remaining 55 s. Restore verified in the same run:
six iio devices, both services active, modules loaded.

★ **That `+2` is worth more than the acquittal.** It says the ADSP is still
*able* to shut down at any point in the boot, and that whatever pins it
re-establishes within five seconds of being briefly let go. This is not a
one-time latch at 34 s; it is a continuously held vote.

### What is still open

The remaining always-present ADSP client on this device is the **audio path** —
q6/APR over SLIMbus, up from bring-up and never torn down. That is the next
subtraction, run the same way, with the same BEFORE premise check. ☠️ It is also
the next hypothesis attractive enough to be believed without the experiment;
the sensors were exactly that an hour ago.
