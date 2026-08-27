# 2026-08-27 — the sensor client is not the LPASS holder (repeat, better instrument)

> ⚠️ **AI-generated.** Claude (Opus 5) under the direction of Lajosházi, László
> Gergely.

A-B-A′ on `iio-sensor-proxy`, 3 × 360 s, panel proven dark, charge cut.

| leg | service | n | p10 | median | p90 | LPASS off-XO | LPASS shutdowns/s | MPSS up |
|---|---|---|---|---|---|---|---|---|
| A | active | 187 | 53 | 97 | 203 | 0.00 % | 0.00 | 36 % |
| B | **inactive** | 187 | 53 | 102 | 208 | **0.00 %** | **0.00** | 39 % |
| A′ | active | 184 | 53 | 98 | 216 | 0.00 % | 0.00 | 36 % |

☠️ **This repeats a negative already recorded on 2026-08-19** — stopping
`snsregd` and `iio-sensor-proxy` did not move the LPASS counter then either. The
repeat was started before the closed lead was re-read, which is the same mistake
as the slot switch that nearly got spent: **check what is already closed before
spending a window.** What it adds is a longer window, a control leg, and the
current alongside — and it makes the negative sharper than "the counter did not
move": the DSP does not shut down **even once** in six minutes, in any leg.

It also gives the LPASS number a spread it did not have: zero, three times, with
`LPASS_sd` (shutdown count) flat at 0/s throughout. Not "rarely" — never.
