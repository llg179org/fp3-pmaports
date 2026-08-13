# Bringing up the FP3 charger

> ⚠️ **AI-generated.** This page — and the code, device tree and tooling it
> describes — was written by Claude (Opus 5) working under the direction of
> Lajosházi, László Gergely, who reviewed every change and made or reviewed
> every measurement it rests on. Kernel commits carry `Co-authored-by: Claude`;
> anything prepared for the LKML carries `Assisted-by:` instead and never a
> `Signed-off-by` from the assistant, since only a human can certify the DCO.

The investigation behind [`../README.md`](../README.md), kept as a narrative:
what was believed at each step, what was measured, and what that forced us to
conclude — including the places where the belief was wrong and had to be
retracted. The reference material — what the driver does today, which properties
the board carries, how to build and test it — is in the README; this is the
reasoning, and the instruments and raw data that produced it.

Nothing here is needed to charge the phone. The charger has no userspace
component at all: everything that matters ships in the kernel package.

> **Where things stand is deliberately not on this page.** What works today is in
> [`../README.md`](../README.md); what is still open is in
> [`../../TODO.md`](../../TODO.md) and [`../../FP3-TODO.md`](../../FP3-TODO.md).
> This is a record of how the current arrangement was arrived at, and it is
> **not** revised when the device changes.

## Why this one is mostly a measurement story

The charger is not a bring-up in the sense the [sensors](../../sensors/bringup/README.md)
or the camera were. There was no missing driver and no silent co-processor: the
PMI632 is served by Casey Connolly's `qcom_smbx`, it bound on the first try, and
the phone charged. Every problem after that was **a value in a register being
wrong for reasons that looked right**, which is why almost every step below is a
comparison rather than an implementation, and why the instrument that settled
the hardest of them was a two-sided register diff rather than a debugger.

That also shapes the failure mode to watch for. When the code path is right and
only the number is wrong, the system keeps working well enough to hide it: this
port charged for months while never once finishing a charge, and reported a
plausible percentage the whole time.

## The instruments

| what | how, and what it is good for |
|---|---|
| **PMIC registers over the regmap debugfs** | the cheapest ground truth here, and it needs no kernel build. `/sys/kernel/debug/regmap/0-02/registers` is the PMI632 (SPMI slave 2), fixed-width at **9 bytes per line**, so it seeks: `dd if=… bs=9 skip=$((0x1090)) count=12`. ☠️ `bs=1 skip=$((0x1090*9))` returns **nothing at all**, silently, and `cat`-ing the file means 65536 SPMI reads |
| **the same registers on the oracle slot** | slot_a runs Fairphone's own 4.9 kernel with `qpnp-smb5` on the same PMIC and the same pack. Any register whose right value is unknown has a known-good answer 80 seconds away, across a slot switch |
| **the two-sided diff** | dump the same 1280 registers on both slots in the same state and difference them. This is the instrument that found the last and worst bug, and it is described in its own step below because *not* reaching for it first cost half a day |
| **vendor votables** | `/sys/kernel/debug/pmic-votable/FCC/status` on the oracle: which subsystem is limiting the charge current and to what. Answers "why is it 2 A" without reading any downstream source |
| **the QG peripheral** | the PMIC's own gauge at `0x4800`, already running under mainline because the PMIC's boot sequence starts it. `LAST_ADC_V`/`LAST_ADC_I` give a battery voltage and a signed battery current that no sysfs property exposed at the time |
| **`powerlog-pmos.sh` / `powerlog-ut.sh`** | one line a minute, identical fields on both operating systems, so a charge on one can be laid against a charge on the other. In the [FP3 skills](https://github.com/llg179org/Claude-skills-Fairphone3) repository; the captures they produced are in [`../../power/`](../../power/) |
| **the event tracer** | a debug-layer-only change that logs every charger interrupt with the status registers at that instant. It lives on `debug-int/<base>` and never goes upstream — see [`../../debug/README.md`](../../debug/README.md) |
| **`fp3-selftest`** | [`50-charger`](../../../tests/checks/50-charger-test.sh), [`51-battery-temp`](../../../tests/checks/51-battery-temp-test.sh), [`52-fuel-gauge`](../../../tests/checks/52-fuel-gauge-test.sh), [`53-charge-termination`](../../../tests/checks/53-charge-termination-test.sh). The last one carries a **positive control**: it reads the float voltage first and stops if it disagrees with the battery node, because a register window that is wrong makes every other read meaningless |

## Raw data

All of it in [`../../power/`](../../power/), with its own README on what the
files are worth:

| file | what it holds |
|---|---|
| `2026-08-11_regs-pmos.txt`, `2026-08-11_regs-ut.txt` | the 1280 CHGR/DCDC/BATIF/USB/MISC registers on each OS, same pack, same state. 45 differed |
| `2026-08-11_ut_discharge-charge.txt` | the vendor stack over a night, a load and a full charge |
| `2026-08-12_ut_terminates.txt` | the vendor stack terminating within a minute of the threshold |
| `2026-08-12_pmos_iterm-fix-terminates.txt` | the same on this port, after `I_TERM_BIT` was left set — the single-change A/B |
| `2026-08-12_pmos_day-to-r51-termination.txt` | the first termination reached by the packaged kernel rather than by hand-deployed pieces |

---

## Step 0 — the premise this work started from was wrong

The plan was "hardware JEITA is off, switch it on". Before writing any code the
four JEITA registers were read off the running phone. `JEITA_EN_CFG` came back
**`0x1f`** — every bit set:

```
1061: 14      FAST_CHARGE_CURRENT_CFG  20 * 50000 = 1 000 000 uA
1090: 1f      JEITA_EN_CFG             hard limit + both float-voltage + both current bits
1092: 0a      CCCOMP_HOT               250 mA reduction
1093: 0a      CCCOMP_COLD              250 mA reduction
1094: 1b ff 44 c7    soft thresholds   hot ~50 degC, cold ~16 degC
1098: 15 aa 4a ff    hard thresholds   hot ~58 degC, cold ~11 degC
```

The observation behind the plan — that nothing in the driver writes the enable —
was true. The conclusion drawn from it was not. **Hardware JEITA had been
protecting this phone all along**, against the PMIC's power-on defaults, which
are generic values for no particular cell. The work was never to switch
protection on; it was to replace those thresholds with the ones Fairphone
characterised for this pack.

☠️ **Thirty seconds of `dd` overturned the premise.** That is the cheapest
lesson on this page and the one most worth generalising: read the registers
*before* writing the code, not to check it afterwards.

## Step 1 — thresholds as raw ADC codes, and the cleaner design that lost

The comparators take a raw `BAT_THERM` ADC code. Mainline has the inverse
conversion (`qcom_adc_tm5_temp_volt_scale`), so carrying the thresholds in °C in
the device tree and converting them in the driver was a real option — and the
better-looking one.

It was rejected on a measurement. The generic 100 kΩ pull-up curve mainline
would have used, against Fairphone's four characterised codes:

| °C | Fairphone's code | from the mainline curve | error |
|---|---|---|---|
| 0 | 22133 | 22550 | **+1.54 °C** |
| 15 | 17663 | 17879 | +0.64 °C |
| 45 | 8708 | 8385 | **−1.29 °C** |
| 55 | 6535 | 6150 | **−1.97 °C** |

The errors are small, but **all four point outward** — a colder cold limit and a
hotter hot limit — so every safety window would widen in the unsafe direction. A
raw code involves no curve at all.

The comparison also earned something it was not asked for: all four landing
within 2 °C **confirms the comparators work in the ADC5 raw code domain**, which
is the assumption the whole approach rests on and which nothing else verified.

## Step 2 — which pack, and a citation that was precise and wrong

The FP3 ships **two** 3000 mAh packs, told apart by a resistor in the pack:
"Fuji" at 10 kΩ rated 2.0 A, "Kayo" at 50 kΩ rated 2.7 A with a different cool
band. A `simple-battery` node cannot choose between them.

☠️ **For one revision this port programmed the other pack's thresholds**, copied
out of the vendor tree and documented with the exact filename — which is what
made the mistake survive review. The vendor ships several `qg-batterydata-*`
files and the board includes two of them; naming the file you copied from says
nothing about whether it applies to the cell in your hand.

The fix is not a better citation but a check: the driver measures the ID
resistor through the PMIC's divider and **refuses to apply the described pack's
limits to a pack that is demonstrably a different one**, falling back to the
init sequence's ~1 A. Measured here at 10.0 kΩ against the declared 10 kΩ.

That check comes with a free instrument: on a phone where it passed,
`FAST_CHARGE_CURRENT_CFG` reads `0x28`, and on one where it failed it stays at
`0x14`. **The charge current is its own proof that the gate opened** — no debug
print needed.

## Step 3 — why 2 A, and the ceiling that is not the battery

For the Fuji pack fitted here 2 A is simply its rating, so the arithmetic did
not decide the number. It still matters, because it is what a Kayo phone would
run into and why raising the SMB5 limit is not a one-line change.

**The compensation register runs out.** The JEITA soft-zone reduction is a
six-bit field of 25 mA steps — at most 1575 mA of reduction from whatever
fast-charge current is programmed. Both packs are characterised for 600 mA in
the cool zone:

| fast-charge current | lowest reachable soft-zone current | profile wants |
|---|---|---|
| 2700 mA (Kayo's rating) | 1125 mA | 600 mA — **not expressible** |
| 2000 mA (Fuji's rating) | 425 mA | 600 mA — fine |

So on a Kayo phone the hardware **cannot implement Fairphone's own profile at
the pack's rated current**. It also explains why downstream compensates in
software: it is not bound by that register at all.

**And the port runs out first anyway.** Without high-voltage negotiation, which
mainline `qcom_smbx` does not do, a DCP gives 1.5 A at 5 V — about 1.9 A into a
3.8 V cell. Above roughly 2 A the binding constraint stops being the charger and
becomes the USB port.

## Step 4 — what the stock stack actually does

Reading the same registers on the oracle confirmed the encoding and caught a
wrong threshold:

| register | stock (UT / 4.9) | this port | comment |
|---|---|---|---|
| `0x1061` fast-charge current | `28` | `28` | both 2 A |
| `0x1090` `JEITA_EN_CFG` | **`10`** | `1f` | see below |
| `0x1092` / `0x1093` soft compensation | `0a` / `0a` | `28` / `38` | stock leaves them at default |
| `0x1094` soft thresholds | `22 04 44 ff` | `22 04 44 ff` | **identical** |
| `0x1098` hard thresholds | `19 87 56 75` | `19 87 56 75` | **identical** |

The hard thresholds and the soft-hot threshold matching **byte for byte** is an
independent check that the big-endian hot-then-cold layout and the raw-code
encoding are right — derived from downstream source, confirmed against the
hardware it programs.

`JEITA_EN_CFG` differs because downstream sets `qcom,sw-jeita-enable` and then
calls `smblib_disable_hw_jeita()`: it programs the hardware thresholds but does
the compensation itself, from a five-band table. This port does the opposite,
which costs resolution and buys not needing software in the loop.

And the votable said why both settle on 2 A, without reading any source:

```
FCC: BATT_PROFILE_VOTER:   en=1 v=2000000
FCC: JEITA_VOTER:          en=1 v=2000000
FCC: THERMAL_DAEMON_VOTER: en=0
FCC: effective=BATT_PROFILE_VOTER type=Min v=2000000
```

## Step 5 — the capacity was a voltmeter

Until `r42` the reported capacity was the terminal voltage looked up in the
battery node's `ocv-capacity-table-0`. That table is the downstream QG profile
and it is correct — but it maps an **open-circuit** voltage, and a phone's
terminal voltage is nothing like one. It also spends eighteen points of charge
on the forty millivolts between 3.80 V and 3.84 V, so a small voltage error is a
large capacity error exactly where the battery spends most of its life.

Measured against the oracle, alternating on the same charge and the same cable:

| | this port, before | stock (`qpnp-qg`) |
|---|---|---|
| at rest, charging at ~380 mA | 59–65 % | **55–57 %** |
| terminal voltage, same moment | 3.96 V | 3.96 V |
| after 3 min of eight-thread `sha256sum` | **6 %** | **57 %** |
| terminal voltage under that load | 3.72 V | 3.64 V |

The terminal voltages agree to 1.3 mV, so nothing is wrong with the measurement
— and the stock gauge does not move at all across a 330 mV swing, so it is
plainly not reading the terminal voltage either.

That also ruled out the obvious cheap fix. Fitting a resistance to the load step
gives ~380–420 mΩ on **both** systems while the pack's real internal resistance
is 118–166 mΩ; the rest is the difference between a bursty load and an averaged
current sample. Subtracting `I·R` does not recover the open-circuit voltage, and
a resistance large enough to make it look like it did would be wrong everywhere
else.

**What the PMIC already had.** The QG peripheral at `0x4800` was already running
— the PMIC's own boot sequence starts it, so nothing here had to configure it.
The earlier note that "no coulomb counter exists for this PMIC in mainline" was
about the absence of a *driver* and had been read as the absence of the
hardware. Controls that made it trustworthy before any driver change:
`LAST_ADC_V` agreed with the independent ADC5 `vbat_sns` channel to within
1.3 mV, followed the load step within one sample period, and `LAST_ADC_I`
changed sign at the charge-to-discharge crossing.

After the change the load sensitivity is gone outright: **229 mV of sag moves
the reported capacity by zero points**, where the same step used to move it by
tens.

## Step 6 — ninety-one percent on a charger that had finished

A phone left on a wall charger stopped climbing in the low nineties and the
interface said the charge was over. That read as a charger giving up early. It
was not.

**Termination is a state the charger passes through, not one it sits in.** Once
it has terminated, the cell is by definition above the recharge threshold, so
the hardware moves straight to inhibit and stays there. A ten-second poll has to
land inside a window the hardware leaves as fast as it can — and even when it
does, the next poll resumes correcting toward the OCV table and walks a
correctly latched hundred percent back down within a minute.

And where it walks down to is not an error in the table: its top entry is an OCV
of 4.3756 V, which a cell held at a 4.39 V float only shows while it is still
being held there. Let go, it settles some seventy millivolts lower — six percent
down this curve.

So since `r43` the driver **remembers** the completion instead of catching it.
Inhibit alone is not evidence of a full pack — it is equally what a charger does
when handed a cell that was already above the threshold — but inhibit *after a
charge that was actually running* is the tail of that charge. That pairing needs
no knowledge of where the inhibit threshold sits and survives any polling
interval.

☠️ **And it must survive the input flickering.** Re-running APSD on a source
change drops `online` briefly, and so does anything at the other end of the
cable; clearing the history there costs a full pack its full reading. Seen three
times before it was understood — twice from the cable being handled, once from
APSD alone — each time leaving a terminated pack reporting 96 % and *not
charging* while sitting at 4.33 V with nothing drawn from it. A full pack stops
being full once charge leaves it; that a charge *happened* does not unhappen
because the cable flickered.

## Step 7 — a recharge that could never happen

☠️ The two gauge bugs above were found first and made a tidy story: the charger
had done its job and only the reporting was wrong. **That story was tested by
letting the pack fall, and it did not survive.** At 4.24 V of a 4.39 V float,
with 500 mA available, the charger delivered exactly zero current. Pulling the
cell to 4.14 V under a full-core load did not start it either — which rules out
the inhibit threshold, since no inhibit setting on this part reaches that far
down.

`CHGR_CFG2` is where a recharge is configured, and **its lower bits are not the
same on the two PMIC generations**. SMB2 has `AUTO_RECHG` at BIT(2) and
`EN_ANALOG_DROP_IN_VBATT` at BIT(1); SMB5 replaces both with one two-bit field
naming what a recharge is decided *by*:

| `CHGR_CFG2[2:1]` | meaning on SMB5 |
|---|---|
| `00` | nothing restarts a finished charge |
| `10` | the battery voltage |
| `11` | the state of charge |

The pmi632 init sequence was derived from the SMB2 one and carried the same
value across, so the field came out `00` — the one setting under which a
terminated charge is never restarted while the cable stays in.

Measured as a controlled A/B, same load, same voltage range, only that field
different:

| | charger status under load, at ~4.13 V |
|---|---|
| before | 147 consecutive samples of status code 0 — inhibit, `Not charging` |
| after | code 3, **`FULLON_CHARGE`**, post-JEITA current `0x28`, `Charging` |

☠️ **A wrong register was written first, and the phone said so.** The same fix
was attempted a revision earlier against `FG_UPDATE_CFG_2_SEL`, which is what
the SMB2 half of the driver uses — but that is `CHGR + 0x7D`, and on SMB5 the
same offset is `CHARGE_RCHG_SOC_THRESHOLD_CFG_REG`, a threshold rather than a
selector. The bit read back exactly as programmed and nothing else changed,
which is the signature of writing a register that is not the one you meant. The
disproven commit is kept at `archive/wip-7.1.3-charger-smb2-recharge-register`
with the verdict in its tag message.

☠️ **What settled it was the vendor's own `smb5-reg.h`, which was on disk the
whole time.** An earlier search for it had been abandoned when a `find` across
the big disk timed out. **A timed-out search is not a negative result.**

## Step 8 — proving the device tree, not just the driver

The recharge threshold then had to be shown to come from the board rather than
from the PMIC's power-on value, which is a different claim from "the driver
writes it". On a package carrying the property, `0x107E/0x7F` read `56 4c` =
**4.30 V**, against `0x544a` = 4.199 V on the kernel booted before the deploy —
a clean before/after with nothing else changed. The running kernel's
`/proc/device-tree` carried no `auto-recharge` node before the reboot, so the
4.199 V was the property *not being present*, not the write failing.

That distinction is worth keeping: a register holding a plausible value proves
nothing about where the value came from.

## Step 9 — the connector thermistor, and a conclusion drawn from one side

The charger can regulate its input current against a thermistor in the USB
connector, and the downstream device tree gives one for this PMIC. Enabling it
here **stopped charging outright**: `MISC_TEMP_RANGE_STATUS` reported
`TEMP_ABOVE_RANGE` and `TLIM` while `MISC_DIE_TEMP_STATUS` stayed clear — so it
was the connector reading, and it read hot on a phone lying idle at 32 °C. The
input limit went to zero: the Type-C block saw its 5 V, the charger's USBIN saw
nothing, and the battery discharged with the cable in.

The property came out, with a comment saying the board did not appear to
populate the part.

☠️ **That comment was wrong, and the oracle disproved it.** The vendor stack on
the same phone runs with the connector channel and the regulation source both
enabled (`BATIF_ADC_CHANNEL_EN 0xd5`, `MISC_THERMREG_SRC_CFG 0x13`) and reads
`MISC_TEMP_RANGE_STATUS 0x02`, in range. The part is fitted and it works there.
What is missing is on **this** side, in the ADC configuration: four BATIF
registers differ and none of them is named by this driver — `0x12e2`
(`0x43` here against `0x07` there), `0x12e5`, `0x12ea`, `0x12ed`.

The observation still stands and the property still stays out. What changed is
the reason: **because we cannot configure it yet, not because the hardware lacks
it.** One-sided evidence supports "it does not work here"; it never supports
"the hardware is not there".

## Step 10 — the charge that never ended, and the instrument I should have used first

Eight hours on a 2 A charger left the pack at 81 %. The charger had been in
taper for **8 h 26 min**, of which **1 h 49 min** was spent below its own
termination threshold, and `BATTERY_CHARGER_STATUS_1` never once reached code 5.

Half a day went into eliminating hypotheses one at a time — the threshold value,
the sample count, which comparator source was selected, the connector
thermistor. Every one of them was wrong, and every one of them was *closed by
the same measurement* that eventually found the answer.

**That measurement was the two-sided diff**: 1280 registers dumped on each slot
in the same state, differenced. Forty-five differed. `CHGR_CFG2` was `0x05` here
against `0x2c` there, and bit 3 is `I_TERM_BIT` — cleared by this port's own
init sequence, on the strength of a comment inherited from the SMB2 half of the
driver:

```c
/* I_TERM_BIT - Current termination ?? 0 = enabled */
```

**The two question marks are the original author saying they did not know**, and
on SMB5 the answer is the other way round. Everything the decision depends on
was already identical between the two stacks — termination threshold 99.9 mA,
the ADC comparator selected, the same sample count — so the diff pointed at one
bit out of 1280 registers.

Proved by single-change A/B, twice: from 97 % on a 500 mA supply and from 59 %
on a 2 A one, the charger terminated **within one 60-second sample** of the
current crossing the threshold, both ending at `0x45` — the value the vendor
stack shows in the same state. Left as it was, this was not only a reporting
problem: a charge that never terminates holds the pack at the float voltage
indefinitely instead of letting it relax.

Only that one bit was changed. `CHGR_CFG2` also differs from downstream in
`CHARGER_INHIBIT` and `PRETOFAST_TRANSITION`, and those were left alone: with
three bits moved at once, a charger that then worked would not say which one had
been the problem.

☠️ **The lesson is about order, not about the bit.** The differential was twenty
minutes' work and was available from the first hour. *One-sided is not a
differential* — and when there is an oracle running the same hardware, the
question "what is different" is nearly always cheaper than the question "what is
wrong".

## Step 11 — how long until it is full

The driver reported a percentage and nothing else, which leaves anything wanting
to say *how long* with no way to work it out: UPower derives its estimate from
the charge remaining and the power going in. Reporting `CHARGE_FULL_DESIGN`,
`CHARGE_FULL` and `CHARGE_NOW` gave it one — checked against its own arithmetic,
`(13.4334 − 9.6707) Wh / 4.09352 W = 55 minutes`.

There is no learned capacity here, so full and full-design are the same value,
the one the device tree states. Reporting a learned figure it has not learned
would be worse than reporting the design one.

## Step 12 — where these properties belong

The board carried five `qcom,*` properties on its `battery` node, and
`battery.yaml` sets `additionalProperties: false` with no vendor-prefixed
property at all — so every one of them was a `dtbs_check` error this board added
on its own.

The schema is the smaller argument. The layering one is that a JEITA threshold
here is a **raw BAT_THERM ADC code**, and which code a temperature produces
depends on the PMIC's ADC full scale and on the board's pull-up as much as on
the cell. A code cannot travel with a pack; a board fitting two packs would have
to repeat the same codes on both. So the thresholds, the soft-zone currents, the
recharge voltage and the ID tolerance are properties of the **charger**, and the
identification resistor — which physically is inside the pack — stays with the
battery as a **generic** `id-resistor-ohms`.

Measured after the move: every register programmed from the new location with
the same value, and the battery node reports **nothing at all** to `dt-validate`.

☠️ **And the checker caught a defect reading would not have.** A recognised unit
suffix already gives a property its type. `qcom,batt-id-pullup-ohm` was carrying
an explicit `$ref` to `uint32` because `-ohm` is *not* a recognised suffix — so
the moment it was renamed to `-ohms`, that `$ref` became a contradiction and the
board failed with *"100000 is not of type 'array'"*. The rename silently took
away the thing that had been doing the work.

---

## Every claim on this page that had to be retracted

Collected because the pattern matters more than any one of them: each was
self-consistent, each survived until a *second* source was consulted, and in
four of the five cases that second source was the oracle slot running the same
hardware.

| the claim | what disproved it |
|---|---|
| "hardware JEITA is off, we must switch it on" | `JEITA_EN_CFG` read `0x1f` on the running phone before any code was written |
| "these are this pack's JEITA thresholds" (they were the other pack's) | the vendor ships several profiles and the board includes two; the ID resistor now decides |
| "the charger finished and only the reporting is wrong" | letting the pack fall to 4.14 V produced exactly zero current |
| "the board does not populate a connector thermistor" | the vendor stack reads it in range on the same phone, with four BATIF registers configured differently |
| "no coulomb counter exists for this PMIC in mainline" | true of the *driver*, false of the hardware — QG was already running at `0x4800` |
| "the termination threshold is not programmed" | it was: `0xFD65` = −101.8 mA, with the ADC source already selected. What was wrong was *whose* number it was |

## What is still open here

Deliberately not listed on this page — it would rot. See
[`../README.md`](../README.md#known-gaps) for the current list, and
[`../../TODO.md`](../../TODO.md) for everything else.
