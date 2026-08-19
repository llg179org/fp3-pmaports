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

## The next measurement, not the next patch

1. Trace `qcom_rpm_smd_write` across a suspend and print the **resource ids**,
   not just the counts, so the 14 rails have names.
2. Cross the names against the FP3 DT's 19 declared rails (3 SMPS + 16 LDOs,
   `sdm632-fairphone-fp3.dts`) and against what each one supplies.
3. Only then decide whether any of them can be dropped, and by whose intent.
