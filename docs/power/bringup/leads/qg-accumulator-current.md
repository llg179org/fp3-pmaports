<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# ★★★★★ The fuel gauge has a hardware current accumulator, it runs across suspend, and it works

**Status:** measured and validated 2026-09-02. Tool:
[`../tools/qg-accum.sh`](../tools/qg-accum.sh).

## Why it was needed

The current front had two instruments and both failed:

- `voltage_now` sampled right after wake reports the **IR drop**, not state of
  charge — leg A ended at 4 070 638 µV and leg B *started* at 4 172 433 µV, a
  100 mV rise between consecutive readings minutes apart.
- `current_now` can only be sampled with the AP awake, and a 30-minute leg at a
  600 s alarm yields three samples. Their scatter — **A at −148.0 mA against A′
  at −202.9 mA, the same configuration twice** — was larger than the effect.

`charge_counter` does not exist here and `charge_now` is frozen at the
3 060 000 µAh nameplate, so coulometry looked unavailable. It was not: the
counter is in the PMIC, one layer below the driver that froze.

## What it is

QG peripheral base **0x4800** on the PMI632 — the value our own `qcom_smbx.c`
carries as `.qg_base`, and the vendor 4.9 device tree confirms as
`qcom,qgauge@4800`. Three registers, readable through the SPMI regmap debugfs at
`/sys/kernel/debug/regmap/0-02/registers`:

| register | offset | |
|---|---|---|
| `QG_V_ACCUM_DATA0` | 0x4888–0x488a | 24-bit LE |
| `QG_I_ACCUM_DATA0` | 0x488b–0x488d | 24-bit LE, **signed** |
| `QG_ACCUM_CNT` | 0x488e | samples in the accumulator |

The vendor's own conversion, from `qg-defs.h`, applied to accumulator ÷ count —
that is, the firmware reads it as the **average over the window**:

```
V_RAW_TO_UV(x) = 194637 * x / 1000     I_RAW_TO_UA(x) = 152588 * x / 1000
```

## What was measured

**It agrees with `current_now`, and it is far steadier.** Three reads 8 s apart
while charging: **146.4, 146.1, 146.0 mA**, against `current_now` = 144.2 mA.
Two independent instruments within ~2 mA, and the accumulator's own spread is
0.4 mA where single `current_now` samples scattered by 55 mA.

☠️ **The sign is inverted** relative to `current_now`: charging reads negative in
the accumulator.

★ **It runs across AP suspend, which is the whole point.** Read, `rtcwake -m mem
-s 60`, read again on wake: the count had rolled over *during* the sleep and the
window it reported covered the sleeping phone. At the wake instant `current_now`
read −9 mA — a transient — while the accumulator read −148 mA, consistent with
the −150 mA before the sleep and the +149 mA `current_now` gave three seconds
later.

## ☠️ What it does not do

`ACCUM_CNT` is 8 bits and samples arrive at ~3.35/s, so the window is **at most
~76 s**. This is not a charge counter over an hour, and it cannot be differenced
across a long sleep — it reports the average over the last minute or so. To make
that minute the quiet part of a sleep, keep the wake interval short (~60–90 s)
rather than 600 s, or read it knowing it covers only the tail.

Two smaller traps, both already paid for elsewhere in this repo:

- **All four bytes must come from one `grep` pass.** The accumulator can roll
  over between reads, and then the sum and the count describe different windows.
- **busybox `awk` has no `strtonum`.** It does not warn; it prints
  "Call to undefined function" where a number should be. The tool uses shell
  arithmetic (`$((0x...))`).

## What it changes

The planned rest-endpoint OCV census exists to work around instruments that
could not see a sleeping phone. This one can. Before spending a night on the OCV
ladder, re-examine whether a short-interval census sampling the accumulator gives
the same answer in an hour.
