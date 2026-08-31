# The XO duty instrument was inverted, and a second bug hid PRONTO entirely

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed the measurement it rests on.

Measured 2026-08-31, kernel `#80-fp3`, on the live device. Raw:
[`double-sample-120s.txt`](double-sample-120s.txt).

## Why this was taken

`leads/lpass-mclk-gate-state.md` **closed** the "LPASS never sleeps" question on
2026-08-21 with two root causes fixed, and its header states the disambiguation
rule: `Last XO shutdown enter` > `Last XO shutdown exit` with `Active cores
bitmask` `0x0` means **down and staying down**. Three days of write-ups then
reported "LPASS awake 100.0%" from `modem-window-fit.py` anyway. One of the two
had to be wrong, so the instrument was measured instead of either being believed.

`tools/prior-art.sh LPASS` is what surfaced the closed lead, before any window
was spent.

## The measurement

Two samples of all four masters, 120.03 s apart, nothing else changed.
**Pre-registered reading:** if a master is in XO shutdown at both samples with an
unchanged `enter`, and its `XO total duration` delta is **0**, the counter is
updated on *exit* and a permanently-down master reads as "100 % awake" — the
signal is inverted. If the delta is ≈120 s, it accumulates live and the master
really is awake.

| master | XO-dur delta | = s | of the window | XO-count delta | cores |
|---|---:|---:|---:|---:|---|
| APSS | 0 | 0.00 | — | 0 | 0x1 |
| MPSS | 2 192 301 979 | 114.18 | 95.1 % off | 375 | 0x0 |
| **LPASS** | **0** | **0.00** | **0 %** | **0** | **0x0** |
| PRONTO | 1 965 572 026 | 102.37 | 85.3 % off | 1181 | 0x0 |

LPASS at both samples: `enter` 1106369760183 > `exit` 1106369627426, unchanged,
`Active cores 0x0`, count frozen at 75 — **down for 1.68 h**.

⇒ **The counter is edge-updated, and the reading was inverted.** The control in
the same sample is what makes this a measurement rather than an argument: MPSS
toggled 375 times and accumulated 114.2 s, so the counter is not broken.

**LPASS is asleep on pmOS.** The 2026-08-21 `qcom-ngd-ctrl` `disable_stream` fix
(`cff137fdef8e`) holds. LPASS is **not** a suspect for the ~41 mA floor.

## The second bug, found while fixing the first

Every capture carries a `[TZ]` block of all-zero fields directly after
`[PRONTO]`. `TZ` is not in the parser's `MASTERS` tuple, so the old parser kept
writing into `PRONTO` — **every PRONTO number this script ever printed was TZ's
zeros**, read out as "awake 100.0 %".

With both fixed (`87be062`, `474ff79`), a number appears that had never been
seen:

| | pmOS 2026-08-31 | oracle 2026-08-30 |
|---|---|---|
| PRONTO (WCNSS/Wi-Fi) awake | **16.7 – 19.1 %** | **21.3 – 23.1 %** |

Both systems keep the Wi-Fi core similarly awake, so this is **not** the
pmOS↔oracle difference — but it is an unaccounted consumer in a 48 mA floor of
which ~41 mA has no owner.

## Known-positive control on the fix

Run against the committed original (`git show HEAD~:…`) and the fixed script on
the same oracle capture: APSS, MPSS and LPASS are **byte-identical** (6.9 %,
3.0 %); only PRONTO moves, 100.0 % → 23.1 %. A fix that changed a previously
correct value would be a regression, and this shows it changes none.

## What this cost, and the rule it earns

Two saturated values — a flat 100 % and a flat zero delta — were carried as
findings for three days, and one of them was written up as ★★★★★. The rule
promoted to `/fp3-kernel-test` on 2026-08-31 ("a multi-channel instrument read as
a single-channel one hides its own answer") is the right rule and it fired too
late. Its sharper form:

☠️ **A saturated reading is a claim about the instrument before it is a claim
about the system.** 0 %, 100 %, and a counter that does not move are the three
values a broken channel produces most often. The struct being read here carried
its own disambiguation in two other fields the whole time, and the closed lead
had already written down how to use them.
