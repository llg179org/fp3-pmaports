# All four masters, cheap state against expensive

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed the measurements it rests on.

600 s window, 2026-09-01 20:00–20:10, pmOS, expensive state, eutran-3. Raw:
[`raw/`](raw/). The cheap column is recomputed from the untouched raw legs of
[`2026-08-31_mm-duty-ab`](../2026-08-31_mm-duty-ab).

## Why

Everything so far named MPSS. Nobody had asked whether the step from ~5 % to
~35 % is the modem alone or whether the other subsystems move with it — which
decides whether this is a modem problem or a system one.

## Result

| master | cheap (08-31) | expensive (09-01) | what moved |
|---|---|---|---|
| **MPSS** | 5.1 % · 3.14/s · **16.2 ms** | **35.8 %** · 2.46/s · **145.5 ms** | rate −22 %, length **×9** |
| PRONTO | 19.1 % · 9.44/s · 20.3 ms | 28.1 % · 8.69/s · 32.3 ms | rate −8 %, length ×1.6 |
| **LPASS** | **asleep, 0 wakes** | **asleep, 0 wakes** | nothing |
| APSS | never entered XO shutdown | never entered XO shutdown | nothing |

**The step is the modem's.** LPASS is identical in both states — down, zero
wakes — so the audio/sensor DSP is not part of it at all. APSS never enters XO
shutdown in either (the measurement script is running).

PRONTO is not perfectly flat: its wake *rate* barely moves (9.44 → 8.69/s, which
is beacon cadence) while its time per wake grows 20.3 → 32.3 ms. That is the same
shape as MPSS, an order of magnitude smaller, and it is what LTE/WLAN coexistence
signalling would look like — the WLAN core servicing coex messages whenever the
modem is actually transmitting. If so it corroborates the connected/transmitting
story rather than widening it.

## ☠️ Two instrument notes, both mine, both from today

`modem-window.sh` prints the **path** of its output to stdout and writes the data
to `/tmp/modem-window.txt`. Redirecting its stdout captures one line — the path —
and the run looks like it produced nothing. It had produced everything.

And the first tabulation of this very file read the state column backwards: the
static fields are written `Last XO shutdown enter @ 177065661397`, with `@`, and
the parser looked for `:`. The field silently did not match, so LPASS — down,
`enter` later than `exit`, count frozen at 988 — was printed as awake. That is
the fourth time today the same family of bug produced a confident wrong reading,
and the third time on this exact counter.
