# FP3 charging on pmOS mainline

> ⚠️ **AI-generated.** This page — and the code, device tree and tooling it
> describes — was written by Claude (Opus 5) working under the direction of
> Lajosházi, László Gergely, who reviewed every change and made or reviewed
> every measurement it rests on. Kernel commits carry `Co-authored-by: Claude`;
> anything prepared for the LKML carries `Assisted-by:` instead and never a
> `Signed-off-by` from the assistant, since only a human can certify the DCO.

The PMI632 charger on the Fairphone 3 under a mainline kernel: what it does
today, which values the board supplies, and how to check any of it on the
device.

**How it got this way is not on this page.** The investigation — what was
believed at each step, what was measured, and the six claims that had to be
retracted — is in [`bringup/`](bringup/README.md). This page is the reference;
that one is the reasoning, and it is not revised when the device changes.

## The shape of it

Everything is one PMIC. The charger, the fuel-gauge inputs and the thermistor
the safety logic reads all live inside the PMI632, and the AP only writes
registers over SPMI:

```
USB  -->  PMI632 charger (CHGR @ 0x1000)  -->  battery
             |                |
             |                +-- JEITA comparators  <-- BAT_THERM (PMIC ADC ch 0x4a)
             |
   qcom_smbx (AP) --- SPMI --+
             |
             +-- BAT_ID (PMIC ADC ch 0x4b)  ->  is this the described battery?
             +-- QG gauge (@ 0x4800)        ->  battery volts and signed amps
             |
             +-- power_supply "pmi632-charger"   (USB side: online, type, I/V)
             +-- power_supply "pmi632-battery"   (capacity, charge, temp)
             +-- thermal_zone "pmi632-battery"   (free, from the power supply core)
             +-- cooling_device "qcom-smbx-charger"  <-- thermal zone "pmi632-thermal"
```

Two things follow from that picture and explain most of this page:

* **The JEITA block is hardware.** It compares the thermistor against four
  comparator thresholds and acts on the result with no software in the loop —
  which is what makes it worth programming correctly before raising the current.
* **So is termination.** The charger decides when a charge is over, by comparing
  its own ADC against a threshold; the driver's job is to program that threshold
  and to report what the hardware then does, not to decide it.

## Status

Measured on the device unless a row says otherwise.

| | state |
|---|---|
| charging works | yes |
| **a charge finishes** | **yes** — the charger reaches `TERMINATE` within a minute of the current crossing the threshold, ending at `BATTERY_CHARGER_STATUS_1 = 0x45`, the value the vendor stack shows in the same state. Last measured on the packaged `r52` kernel: taper crossing at 99.3 mA, then `Full` at `0x45` inside the minute ([capture](../power/bringup/captures/2026-08-13_pmos_r52-charge-to-termination.txt)) |
| the termination threshold | from the battery's `charge-term-current-microamp`; read back as `0xFD71` = 99.9 mA against the 100 mA asked for |
| a finished charge is restarted when the pack falls back | yes — SMB5 recharge selected on battery voltage, threshold 4.30 V from the device tree, read back at `0x107E/7F = 56 4c` |
| a finished charge reads as full | yes — the completion is remembered through the inhibit that follows it, and survives the input flickering |
| capacity | integrated from the PMIC's QG gauge, corrected against the OCV table only while the current is quiet |
| how long until full | yes — `charge_full`/`charge_now` are reported, which is what UPower needs to estimate a time |
| battery current and open-circuit voltage | `current_now` and `voltage_ocv` on `pmi632-battery`, both from the QG peripheral |
| battery temperature | yes — [how, and why the curve is approximate](../kernel/README.md#battery-temperature) |
| hardware JEITA | on, with this pack's characterised thresholds: soft `22 04 44 ff`, hard `19 87 56 75` — byte-identical to what the stock stack programs |
| JEITA soft-zone compensation | `0x1092 = 0x28` (−1000 mA hot), `0x1093 = 0x38` (−1400 mA cold) |
| thermal mitigation | live: `qcom-smbx-charger`, `max_state 3`, bound to `pmi632-thermal` at 70 / 80 / 90 °C |
| fast-charge current | `FAST_CHARGE_CURRENT_CFG = 0x28`, i.e. 2 A |
| the battery is identified before its limits are applied | yes — the ID reads 10.0 kΩ against the 10 kΩ the battery node declares |
| the fallback when the ID does *not* match | implemented, **not measured** — no second pack here to fit |
| 2 A actually flowing | **not measured** — needs a low state of charge and a wall charger |
| the device-tree binding | written and validated; `dt_binding_check`, `yamllint` and `dt-validate` clean, and the battery node adds **no** `dtbs_check` error |

## Provenance

### Imported unchanged

`qcom_smbx.c` is **Casey Connolly's** (Linaro) SMB2 driver for the pmi8998 and
pm660. The interrupt handling, the status decoding, the AICL setup and the
power-supply plumbing are all his.

### Imported and extended here

| component | what was added | why |
|---|---|---|
| `qcom_smbx.c` | SMB5 (PMI632) support, as a variant structure rather than open-coded branches | the register *map* is largely shared with SMB2; what differs is the status-register prefix, the current step, the charge-status bit positions and where the JEITA status bits moved |
| `qcom_smbx.c` | `POWER_SUPPLY_PROP_TEMP` from the pack thermistor | nothing read the thermistor, so there was no temperature and no battery thermal zone |
| `qcom_smbx.c` | the hardware JEITA thresholds and soft-zone currents, from the device tree | the driver read the JEITA *status* for `POWER_SUPPLY_PROP_HEALTH` but nothing programmed the thresholds |
| `qcom_smbx.c` | charge termination on SMB5, and the threshold the board names | the init sequence cleared `I_TERM_BIT`, so the charger never left taper |
| `qcom_smbx.c` | the SMB5 recharge field and its threshold | the field was inherited from SMB2 as `00`, under which a finished charge never restarts |
| `qcom_smbx.c` | a fuel gauge integrated from the PMIC's QG samples | capacity was the terminal voltage looked up in an open-circuit table |
| `qcom_smbx.c` | `CHARGE_FULL_DESIGN`, `CHARGE_FULL`, `CHARGE_NOW` | without a capacity, nothing can turn a percentage into a time |
| `qcom_smbx.c` | the fast-charge current as a thermal cooling device | there was no path from "the phone is hot" to "charge slower" |
| `qcom_smbx.c` | the fast-charge current from `constant-charge-current-max-microamp`, bounded by the PMIC's hardware maximum | the property was parsed and then ignored |
| `qcom_smbx.c` | verification of the battery ID before any of the battery's limits are applied | a board can name only one battery, and this one ships two |
| `qcom-spmi-adc5.c` | the `ADC5_BAT_THERM_100K_PU` channel | the channel was missing from the table, so a device tree referencing it was rejected at probe |

Per-file detail, with commit links: [**Charger: `qcom_smbx.c`**](../kernel/README.md#charger-qcom_smbxc)
and [**Battery temperature**](../kernel/README.md#battery-temperature) in the
kernel page.

### Values taken from the vendor

Almost none of the numbers below are ours. They come out of Fairphone's
published Fairphone 3 kernel source release, checked in under
[`../device_tree/downstream/fairphone/3.A.0136/`](../device_tree/downstream/fairphone/3.A.0136/):

| value | where in the downstream tree |
|---|---|
| register offsets, the JEITA threshold block layout, the 25 mA compensation step, the 50 mA current step | `drivers/power/supply/qcom/smb5-reg.h`, `smb5-lib.c`, the `smb5_pmi632_params` table in `qpnp-smb5.c` |
| charger interrupt numbers and ADC channel assignment | `arch/arm64/boot/dts/qcom/pmi632.dtsi` |
| cell parameters, OCV curve, JEITA thresholds, per-zone currents, termination current | `qg-batterydata-Fuji-3000mah-Jan22th2019-pmi632.dtsi` — [the pack this phone has](#which-battery-this-phone-has) |
| the recharge voltage | `qcom,auto-recharge-vbat-mv = <4300>` on the downstream pmi632 node |
| the thermal mitigation current table | `qcom,thermal-mitigation` on the downstream charger node |

**New here** is the variant abstraction, the device-tree interface for JEITA and
for termination, the QG-based gauge, the cooling device, and the per-generation
ceiling on the charge current.

## Which battery this phone has

The FP3 ships **two different 3000 mAh packs**, told apart at runtime by a
battery-ID resistor. They are not interchangeable on paper:

| pack | `batt-id` | rated fast charge | JEITA cool band starts |
|---|---|---|---|
| Kayo (`qg-batterydata-Kayo-3000mah-Nov4th2019-pmi632`) | 50 kΩ | **2.7 A** | 20 °C |
| Fuji (`qg-batterydata-Fuji-3000mah-Jan22th2019-pmi632`) | 10 kΩ | **2.0 A** | 15 °C |

**This phone has Fuji**, confirmed on two independent paths. The oracle slot's
stock stack names it outright (`battery_type` =
`Fuji_3000mAH_FG_averaged_MasterSlave_Jan22th2019`, `resistance_id` = 9843), and
mainline can measure the resistor for itself, because `pmi632.dtsi` describes
the channel and the ADC driver exposes it:

```
$ cat /sys/bus/iio/devices/iio:device1/in_temp_bat_id_input
170891
```

That is the divider voltage in µV against the PMIC's 100 kΩ pull-up on its
1.875 V reference, so R = 100k × V/(1.875 − V) = **10.03 kΩ**; Kayo's 50 kΩ
would read 625 mV, not 171. The two agree to 2 %.

That matters twice over: the 2 A below is the pack's **full rating**, not a
reduction of it, and the JEITA cool threshold is 15 °C, not 20.

A `simple-battery` node cannot choose between the two, so the device tree
describes Fuji. What the driver can do is **check that the described pack is the
fitted one before applying any of its limits**:

```
                    qcom,batt-id-pullup-ohms     (charger node: board wiring)
                             |
BAT_ID pin --> ADC --> uV -->+--> R = pullup x uV / (1.875 V - uV)
                                            |
          id-resistor-ohms (battery node) -->  compare, +/-15%
                                            |
                        match  -> apply the battery's current and JEITA
                     mismatch  -> leave the init sequence's ~1 A, and say so
```

Note what this is not: the ID does **not** select a profile and does not derive
a current. It is a gate on trusting the one description the device tree carries.
Selecting between two would need a binding for more than one
`monitored-battery`, which does not exist.

The gate is also its own instrument: on a phone where it passed,
`FAST_CHARGE_CURRENT_CFG` reads `0x28`; where it failed it stays at `0x14`. The
charge current *is* the proof, with no debug print needed.

## The device-tree interface

Split by whose fact each value is, which is the reason it looks like this rather
than all in one node. The argument for the split is in
[Where these properties belong](#where-these-properties-belong).

**On the battery** — everything that describes the cell:

```dts
fp3_battery: battery {
	compatible = "simple-battery";
	voltage-min-design-microvolt = <3400000>;
	voltage-max-design-microvolt = <4390000>;
	charge-full-design-microamp-hours = <3060000>;
	constant-charge-current-max-microamp = <2000000>;
	constant-charge-voltage-max-microvolt = <4390000>;
	charge-term-current-microamp = <100000>;
	factory-internal-resistance-micro-ohms = <120000>;

	id-resistor-ohms = <10000>;

	ocv-capacity-celsius = <25>;
	ocv-capacity-table-0 = /* … the downstream QG profile … */;
};
```

`charge-full-design-microamp-hours` is **3060 mAh, not the 3000 the pack is sold
by**: it is what the vendor profile declares and what its gauge integrates
against, and it is the capacity the OCV table was characterised with, so the two
have to agree or a full sweep of the table does not add up to a full battery.

**On the charger** — the board's and the PMIC's own facts, and the charging
policy expressed in this PMIC's units:

```dts
&pmi632_charger {
	monitored-battery = <&fp3_battery>;
	qcom,batt-id-pullup-ohms = <100000>;
	qcom,auto-recharge-microvolt = <4300000>;
	qcom,jeita-hard-thresholds = <0x5675 0x1987>;   /* cold 0 degC, hot 55 degC */
	qcom,jeita-soft-thresholds = <0x44ff 0x2204>;   /* cool 15 degC, warm 45 degC */
	qcom,jeita-soft-fcc-microamp = <600000 1000000>;
	qcom,thermal-mitigation = <2000000 1500000 1000000 500000>;
};
```

Each threshold pair is `<cold hot>`, as raw ADC codes; a higher code is a colder
battery, so the driver rejects a pair whose hot value is not the smaller one.

`qcom,jeita-soft-fcc-microamp` is the current to be **left** in each soft zone,
not the register's own offset — so the board describes a charge current and the
driver works out the delta. It reads the fast-charge current back out of the
hardware to do that, rather than trusting the device tree to match.

An optional `qcom,batt-id-tolerance-percent` overrides the default 15, which is
the window the vendor's `batt-id-range-pct` uses on this board.

`qcom,auto-recharge-microvolt` is the voltage a finished charge is started again
at. It is optional: a comparator left at its power-on threshold still works, and
a made-up threshold for an unknown pack does not improve on it. SMB5 only — on
SMB2 the same decision is configured elsewhere.

The pull-up follows from the ADC channel chosen in `pmi632.dtsi`, but nothing in
the IIO consumer interface exposes which channel a consumer was given, so the
board states it. The mitigation table is a thermal-design fact, not a cell one.

☠️ **No `qcom,connector-internal-pull-kohm`**, although the downstream device
tree gives 100 for this PMIC and the driver can act on it. With the property
present and nothing else changed, charging stopped outright. The part *is*
fitted and the vendor stack regulates against it happily; what is missing is on
this side, in an ADC configuration this driver does not touch. The measurement
and the four registers involved are in
[the bringup notes](bringup/README.md#step-9--the-connector-thermistor-and-a-conclusion-drawn-from-one-side).

### Where these properties belong

Settled 2026-08-12, and the schema is the smaller half of the argument.

* `battery.yaml` sets `additionalProperties: false` and contains **no**
  vendor-prefixed property at all, so every `qcom,*` name on that node was a
  `dtbs_check` error this board added on its own.
* More importantly, a JEITA threshold here is a **raw BAT_THERM ADC code**, and
  which code a temperature produces depends on the PMIC's ADC full scale and on
  the board's pull-up as much as on the cell. A code cannot travel with a pack —
  a board fitting two packs would have to repeat the same codes on both.

So the thresholds, the soft-zone currents, the recharge voltage and the ID
tolerance are properties of the **charger**. The identification resistor stays
with the battery, because it physically is inside it, as the **generic**
`id-resistor-ohms` — an ID resistor is not a Qualcomm idea, and naming it
generically is what lets it sit on a node that admits no vendor properties.

Verified with `dtschema` 2026.6 against the DTB the package shipped: **the
battery node reports nothing at all.**

```sh
dt-mk-schema -j Documentation/devicetree/bindings > /tmp/schema.json
dt-validate -s /tmp/schema.json .../boot/dtbs/qcom/sdm632-fairphone-fp3.dtb
```

☠️ Validate `integration/<base>`, not `debug-int/<base>`, when the question is
whether the submit series is clean: the debug layer gives the charger node 40
interrupts for its event tracer and the binding documents four, so
`interrupts` and `interrupt-names` are *too long* there for reasons that have
nothing to do with the charger work.

## How a charge begins, ends and begins again

**Termination** is the hardware's decision. The driver programs
`CHGR_ADC_ITERM_UP_THD` from the battery's `charge-term-current-microamp` and
selects the ADC comparator; the charger then reaches
`BATTERY_CHARGER_STATUS_1` code 5 on its own and settles into inhibit.

**Reporting it** cannot be done by catching that state, because the charger
leaves it as fast as it can: once terminated, the cell is by definition above
the recharge threshold. So the driver *remembers* that a charge was running and
treats the inhibit that follows as its tail. That pairing survives any polling
interval, and survives the input flickering — an APSD re-run drops `online`
briefly, and losing the history there would cost a full pack its full reading.

**Recharge** is `CHGR_CFG2[2:1]` on SMB5, a two-bit field naming what restarts a
finished charge: `00` nothing, `10` the battery voltage, `11` the state of
charge. This port selects the battery voltage, takes three comparator samples
before acting as the vendor driver does, and programs the threshold from
`qcom,auto-recharge-microvolt`.

## The fuel gauge

`qcom_smbx` carries the QG base per PMIC variant (`smb_variant.qg_base`), polls
the voltage/current pair every ten seconds and integrates it. Between fixed
points the capacity is counted, not read off the live voltage: a voltage taken
under load is not an open-circuit voltage, and on the flat middle of this
discharge curve — eighteen table points inside forty millivolts — the tens of
millivolts the series-resistance correction cannot recover become a large,
one-directional error. So the live sample steers nothing, and correction comes
only from readings the hardware took at rest: the gauge's own `S3_GOOD_OCV` and
the charger's completion.

The seed comes from the open-circuit voltage the PMIC measured at power-on with
nothing drawing, rather than a live sample taken while the machine is busy
booting. The IR correction uses `factory-internal-resistance-micro-ohms`;
because it is only applied at low current, the choice between the PMIC's
measured 120 mΩ and the profile's 166 mΩ is worth a few millivolts.

Load sensitivity, measured: **229 mV of sag moves the reported capacity by zero
points.**

### None of those rest paths is reachable on this board

Every correction listed above depends on catching the pack at rest, and measured
here **not one of them is**. Read the QG block to check, at 0x4800 in
`/sys/kernel/debug/regmap/0-02/registers` (nine bytes per line, so
`dd bs=9 skip=$((0xNNNN)) count=N`):

| register | read | means |
|---|---|---|
| `0x485E` | `0x11` | S3 entry threshold = 17 × 610 µA = **10.4 mA** |
| `0x485F` | `0x21` | S3 exit = 20.1 mA |
| `0x485D` | `0x02` | qualifying FIFO length 3 |
| `0x4874/75` | `0x8000` | `S3_GOOD_OCV` = `QG_ADC_INVALID` — **never captured since boot** |
| `0x48CC/CD` | `0x8000` | `LAST_S3_SLEEP_V` — never latched either |
| `0x480A` | `0x00` | STATUS3: not in S3 |
| `0x4870/71` | `0x4593` | PON OCV = 3.467 V — valid, this is the boot seed |

Read `LAST_S3_SLEEP_V` as well as `S3_GOOD_OCV`: it latches even when the
good-OCV qualification fails, so it is a second and independent witness to
whether the PMIC ever entered S3.

Against that 10.4 mA hardware threshold — and the driver's own 50 mA software one
— this board idles at **68 to 166 mA** and bursts to 546 mA on wake. Both
corrections are gated on a quiet current the phone never reaches.

The suspend path fails one way only, which is worth knowing when reading a
reported capacity. Across a suspend nothing is counted: the interval falls into
the stale-poll branch, which zeroes the residue and leaves the count untouched
unless the wake sample is quiet, which it never is. The pack does draw while
suspended and cannot charge without a cable, so the uncounted charge is always
discharge — every suspend leaves the figure slightly above the truth, and nothing
pulls it back. On this device the error stays latent, because
[automatic sleep is deliberately switched off](../power/README.md#suspend-works-and-is-switched-off-on-purpose)
— not because the phone cannot suspend, which it demonstrably can.

A patch closing that suspend gap exists, works and is **not** on any branch:
[`bringup/parked/`](bringup/parked/README.md) says what it does and why shipping
it would be solving the wrong problem. The short version is that the
`S3_GOOD_OCV` path above is not missing code, only a quiet board — so the fix
worth making is to the idle current, not to the gauge.

How this was found, including the hypothesis it disproved, is in
[`bringup/README.md`](bringup/README.md#step-13--the-gauge-had-no-rest-reference-at-all).

## Thermal mitigation

The charger is registered as a thermal cooling device, so a thermal zone
throttles charging the way it throttles a CPU. State 0 is the unmitigated
current and each further state is lower.

Downstream drives the same table from a userspace thermal daemon through a
vendor power-supply property (`POWER_SUPPLY_PROP_SYSTEM_TEMP_LEVEL`). Driving it
from a thermal zone instead is what is new here.

The zone it binds to is **`pmi632-thermal`, the PMIC's own die temperature** —
which is the charger's die. Downstream calls the same idea
`qcom,hw-die-temp-mitigation`. The trip temperatures are **ours**: downstream's
thresholds live in its thermal daemon's configuration, not in its device tree,
so there was nothing to copy. They sit below the PMI632's own alarm at 95 °C
with room to taper first, against a die that idles at 37 °C on this board:

| trip | cooling state | fast-charge current |
|---|---|---|
| 70 °C | 1 | 1500 mA |
| 80 °C | 2 | 1000 mA |
| 90 °C | 3 | 500 mA |

The mitigation and the JEITA compensation compose without either knowing about
the other, because the compensation is a subtraction from whatever is
programmed: a mitigated current stays mitigated inside the soft zones too.

☠️ Each state is **clamped** to the current actually programmed, not validated
against it. That matters in exactly the case the ID check creates: if the fitted
battery cannot be identified the charger stays on ~1 A, while the board's table
still starts at the 2 A it was written for. An earlier revision rejected that as
a device-tree error and failed probe — so the outcome of a safety fallback was a
phone with no charger driver at all. Mitigation may only ever reduce.

## Building and installing

Nothing here is charger-specific and all of it is documented centrally:

* **kernel config** — `CONFIG_CHARGER_QCOM_SMB2` is built as a module, enabled
  by the package's `prepare()` rather than by the checked-in config, along with
  the other symbols the inherited config does not set:
  [`../kernel/config.md`](../kernel/config.md)
* **building and deploying** the kernel package, including the device-tree-only
  shortcut: [`../deploy/README.md`](../deploy/README.md)

There is no userspace component. Unlike the sensor stack, the charger needs
nothing installed beyond the kernel package.

## Testing

Four `fp3-selftest` checks, deliberately kept apart:

| check | what it proves | needs |
|---|---|---|
| [`50-charger`](../../tests/checks/50-charger-test.sh) | both power supplies bound, capacity and voltage in range, and either current flowing or a charge that has legitimately finished | a cable |
| [`51-battery-temp`](../../tests/checks/51-battery-temp-test.sh) | the thermistor reads, and the `pmi632-battery` thermal zone exists | nothing |
| [`52-fuel-gauge`](../../tests/checks/52-fuel-gauge-test.sh) | a load step reaches the battery, and the reported capacity does **not** follow the sag | nothing |
| [`53-charge-termination`](../../tests/checks/53-charge-termination-test.sh) | the comparator threshold matches what the battery node names | nothing |

☠️ They are separate on purpose. `50-charger` declares `Requires: cable` and is
skipped **whole** without one, while the thermistor is read through the ADC
whether anything is charging or not. Folding the temperature check into it would
have hidden the property in exactly the runs that do not plug the phone in.

☠️ `53-charge-termination` reads the **float voltage first** and stops if it
disagrees with the battery node. That positive control is the point: a register
window that is wrong makes every other read on the page meaningless, and a
threshold that happens to look plausible is exactly what a wrong window
produces.

Neither check covers charging *safely at current*. That needs a low state of
charge, a USB power meter, and both a high-current wall charger and a plain SDP
port, watching what the meter says against what the driver reports and against
the die and connector temperatures. Raise in steps — 1.0 → 1.5 → 2.0 A.

The registers are their own check, and the fastest one. The debugfs file is
fixed-width at 9 bytes per line, so it seeks:

```sh
dd if=/sys/kernel/debug/regmap/0-02/registers bs=9 skip=$((0x1061)) count=1
dd if=/sys/kernel/debug/regmap/0-02/registers bs=9 skip=$((0x1090)) count=12
```

What they should read on a working device:

| register | value | meaning |
|---|---|---|
| `0x1051` `CHGR_CFG2` | `0d` | VBAT recharge + inhibit + **`I_TERM_BIT` set** |
| `0x1061` fast-charge current | `28` | 2 A — and the proof the battery-ID check passed |
| `0x1090` `JEITA_EN_CFG` | `1f` | the block was never off |
| `0x1092` / `0x1093` | `28` / `38` | −1000 mA hot, −1400 mA cold |
| `0x1094`…`0x1097` soft thresholds | `22 04 44 ff` | 45 / 15 °C |
| `0x1098`…`0x109b` hard thresholds | `19 87 56 75` | 55 / 0 °C |
| `0x107e` / `0x107f` recharge | `56 4c` | 4.30 V |
| `0x1006` `BATTERY_CHARGER_STATUS_1` | `45` on a finished charge | terminated |

☠️ `bs=1 skip=$((0x1090*9))` returns **nothing at all**, silently, and `cat`-ing
the whole file means 65536 SPMI reads.

## Known gaps

* **The gauge has no learned capacity and no cycle counting.** It integrates
  against `charge-full-design-microamp-hours`, so an aged pack reads optimistic
  by however much it has faded. The PMIC's SDAM keeps a learned capacity and a
  cycle-count table that the vendor stack maintains; nothing here writes or
  reads them.
* **State of charge does not survive a reboot.** It is re-seeded from the PMIC's
  own power-on open-circuit measurement each boot, which is a good seed but not
  a continuation — the SDAM slot that would carry it across (`0xb147`, still
  holding whatever the vendor stack last wrote) is not read.
* **The capacity lags the oracle near the top of a charge**, by about six points
  at full and three mid-charge. The cause is visible in the gauge's own numbers:
  near full it reported 90 % while its own open-circuit estimate put the pack at
  98 %, and the correction that would catch that is gated on current — this
  phone charges at about 300 mA the whole way, above the 150 mA band. The gate
  is on the wrong quantity: what decides whether an OCV reading is worth
  anything is how much a millivolt of error in it costs, and forty millivolts
  covers eighteen points in the flat middle against about two at either end.
  Fixing it wants a full charge and discharge measured against the oracle.
* **Unplugging a full pack drops the reading**, because nothing has re-anchored
  the table's top to the OCV this pack actually rests at once full.
* **`current_now` on `pmi632-charger` disagrees with the input current.** It
  reports about 199 mA where the vendor stack reports 499 mA for the same
  supply, and where the QG says 300–390 mA is reaching the battery — which
  199 mA of input cannot deliver. The `usb_in_i` scaling is the suspect.
* **No high-voltage negotiation**, so the input side caps the whole thing near
  1.9 A into the cell — just under the 2 A the charger is programmed for. This
  is the next thing worth doing on this side.
* **The device tree can still describe only one of the two packs.** The ID is
  read and checked, so the wrong pack is no longer charged to the wrong limits —
  it falls back to ~1 A. What is missing is *selection*: a binding for more than
  one `monitored-battery`. A Kayo phone therefore charges at 1 A rather than its
  rated 2.7 A, and still gets the wrong OCV curve.
* **The mismatch path has not been exercised on hardware.** The cheap way to
  measure it is a device-tree-only cycle with `id-resistor-ohms` deliberately
  set to the other pack's 50000: the log should carry *"Battery ID is … ohm, but
  the described battery is 50000 ohm"* and `0x1061` should stay at `0x14`. Two
  DTB deploys, no kernel build.
* **A mismatch leaves the previous boot's JEITA thresholds in place**, not the
  PMIC's defaults: nothing writes those registers unless the battery verifies,
  and a warm reboot does not reset the PMIC. After a pack swap the comparators
  keep the *old* pack's thresholds until a cold boot. The current is safe; the
  temperature limits are stale.
* **The connector-thermistor path is unusable until its ADC side is
  understood** — four BATIF registers differ from the vendor stack and none is
  named by this driver.
* **The float-voltage half of JEITA is left alone.** The two `*_SL_FCV` bits are
  whatever the PMIC defaults them to, because the register that scales the
  voltage reduction is not documented for this generation in any source
  available here.
* **Hardware JEITA has one threshold per side, downstream's profile has five
  bands.** The 40–45 °C step at 1500 mA cannot be expressed. Implementing the
  full table would mean software JEITA, driven by the approximate temperature
  curve rather than by the comparators.
* **The trip temperatures are a choice, not a measurement.** They are bounded by
  the PMI632's own alarm above and the idle die temperature below, but nobody
  has yet charged this phone hard enough to see which one it reaches.
* **No step charging.** Downstream sets `qcom,step-charging-enable`; worth
  copying once the above is exercised.

## Pitfalls

* **A green build is not the change.** `CONFIG_CHARGER_QCOM_SMB2` is set by the
  package's `prepare()`, not by the checked-in config — reading
  `config-fp3.aarch64` alone says `is not set` and means nothing.
* **☠️ A precise citation is not a check.** The JEITA thresholds here were, for
  one revision, the *other* pack's — copied out of the vendor tree and
  documented with the exact filename, which is what made the mistake survive.
  Naming the file you copied from says nothing about whether it applies. That is
  what the ID check is for.
* **☠️ An inherited comment is not documentation.** `I_TERM_BIT - Current
  termination ?? 0 = enabled` came across from the SMB2 half of the driver, and
  the two question marks were the author saying they did not know. On SMB5 the
  answer is the other way round, and following that comment meant this port
  never finished a charge.
* **☠️ The same register offset can be two different registers.** `CHGR + 0x7D`
  is a selector on SMB2 and a threshold on SMB5; writing it read back exactly as
  programmed and changed nothing, which is the signature of writing a register
  that is not the one you meant.
* **The JEITA compensation is relative to the programmed current**, so it has to
  be computed after the fast-charge current is set — which is why both it and
  the cooling device are initialised below that point in probe, and why both
  read the register back rather than trusting the device tree.
* **`50-charger` is skipped without a cable**, and a skipped check is not a
  passing one. Check what the run actually reported.
* **A unit suffix already types a device-tree property.** An explicit `$ref` to
  `uint32` on a `-ohms` name contradicts it rather than narrowing it, and the
  board then fails validation with *"100000 is not of type 'array'"*.
