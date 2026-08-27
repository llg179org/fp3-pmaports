<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# burst-modem-ab, 2026-08-27 13:19–13:39, pmOS 7.1.3 `#78-fp3` — the modem is worth nothing

Three 360 s `burst-attrib` legs, `mmcli --disable` between A and B and `--enable`
between B and A′ (the remoteproc was never touched). Panel proven off for all 73
idle-ab samples of **every** leg. Reproduce with
`burst-attrib-fit.py captures/2026-08-27_burst-modem-ab/{A,B,Ap}/attrib.txt`.

| leg | modem | n | floor (p10) | median | p90 | max |
|---|---|---|---|---|---|---|
| A | `registered` | 179 | 53 | 99 | 214 | 305 |
| **B** | **`disabled`** | 179 | **53** | **97** | **213** | 341 |
| A′ | `registered` | 180 | 53 | 102 | 213 | 382 |

**The A↔A′ baseline spread is 3 mA and the A−B difference is 2 mA.** Turning the
RF off does nothing to the floor, nothing to the median and nothing to p90. The
modem is excluded as the source of the awake burst.

Per-column, the picture is the same one the previous two captures gave, on all
three legs: `busy_pct` 1 vs 1, power-collapse residency 100 vs 100–101 %, both
cpufreq policies pinned, `wlan_pps` 2 vs 2. Nothing in the machine moves.

## ★ But the burst is real power, and the voltage proves it

The gauge could in principle have been inventing the swing. It is not — and the
witness is a column that was in the capture all along and had not been read:

| leg | burst I | quiet I | ΔI | burst V | quiet V | ΔV | implied R |
|---|---|---|---|---|---|---|---|
| A | 157 | 54 | 102 mA | 4208 | 4224 | 16 mV | 156 mΩ |
| B | 154 | 54 | 100 mA | 4187 | 4205 | 18 mV | 179 mΩ |
| A′ | 156 | 54 | 102 mA | 4177 | 4197 | 20 mV | 196 mΩ |

**The pack sags in the right direction, by the right order of magnitude, on all
three legs, at a consistent implied series resistance** — 156–196 mΩ, entirely
plausible for an aged cell plus connector and traces. Medians of interleaved
samples, so the discharge drift largely cancels. The current is a real load.

## ☠️ The bug the operator's button press exposed

A key was pressed during A′ to check which OS was running. The panel came back,
and idle-ab waited 30 s for it to go down again (`waited=30s`, against `0s` on A
and B) — all 73 of its own samples were still dark, so its own output was clean.

But `burst-attrib`'s sampler starts *before* idle-ab has the panel, and writes a
`# window_from=` mark at the END of the file, because it only learns the wait when
idle-ab returns. `burst-attrib-fit.py` read the file in one sequential pass and so
set the cutoff *after* it had already kept every row. **The filter silently did
nothing**, and A′ came back with all 195 samples — the first sixteen of them with
a lit panel.

Fixed (two passes; the comment in the tool says why). The difference is exactly
why it matters: **A′ median 109 → 102, p90 261 → 213.** Without the fix the
control leg would have read 7 mA worse than A, and the obvious story — "turning
the modem back on cost something" — would have been sitting right there.

☠️ A lit panel is ~24.5 mA, most of the floor. A mark that is written but not
honoured is worse than no mark, because the file looks filtered.
