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
| PRONTO | 19.1 % · 9.44/s · 20.3 ms | 28.1 % · 8.69/s · 32.3 ms | rate −8 %, length ×1.6 — ☠️ **transport covariate unrecorded**, see below |
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

## ☠️ The PRONTO row is not admissible, and the reason is the measurement itself

Added 2026-09-01 20:45, after outside review.

Neither window recorded **what the Wi-Fi core was actually carrying at the
time** — whether `wlan0` was up, associated, and in particular whether the ssh
session that took the measurement was riding it. That is not a small omission
here:

**a Wi-Fi ssh session *is* PRONTO wake length.** This device has two working
links to the host, USB NCM (`172.16.42.x`) and Wi-Fi (`192.168.x.x`), and the
tools do not care which one they arrive on. A window measured over Wi-Fi and one
measured over USB differ in PRONTO by construction, before the modem is
considered at all.

So the "same shape as MPSS, an order of magnitude smaller" reading above — and
the LTE/WLAN coexistence story built on it — rests on a column whose main
confound was not held. It is **withdrawn as evidence** and kept only as a
description of two numbers.

What replaces it costs nothing: **PRONTO rides along as a passenger** in every
future four-master window, and the prediction is written down now —

> when MPSS goes cheap, PRONTO returns to ~17–19 % and ~20 ms.

If that holds across windows *with the transport recorded and held*, the
coexistence reading earns its place. Until then no window is to be spent on
PRONTO on its own.

For the record, the transport of the overnight window opened at 20:24 tonight is
**USB NCM** (`SSH_CONNECTION` = `172.16.42.2 → 172.16.42.1`). ☠️ That is not the
same as "PRONTO is idle": `wlan0` is **up and associated** (`192.168.x.x`,
`carrier=1`) through the whole night, so the Wi-Fi core is still serving an
association — it simply is not carrying the measurement. Both facts are recorded
in that run's `transport.txt`, which had to be written **by hand** because
`modem-decay-watch.sh` does not collect them; the next revision of the tool
should, since this is the very covariate the review says decides the column.
