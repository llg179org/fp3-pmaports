# 2026-08-27 — the awake burst, asked of the RPM masters

> ⚠️ **AI-generated.** Claude (Opus 5) under the direction of Lajosházi, László
> Gergely.

`burst-master.sh 360`, pmOS `7.1.3-postmarketos-qcom-msm8953 #78-fp3`, panel
proven off for all 74 samples of the idle-ab window, charge input cut, 189
samples at 2 s. Current p10 **52**, median **98**, p90 **211**, max 293 mA.

## What the split by the effect said — and why it was wrong

Splitting burst (≥1.5× floor) from quiet and taking each master's median, the way
every earlier burst tool did:

| column | burst | quiet |
|---|---|---|
| `MPSS_xopct` | 66 | 68 |
| `PRONTO_xopct` | 82 | 84 |
| `MPSS_cores` | 0 | 0 |
| `LPASS_*` | 0 | 0 |

Verdict printed: *no master changes its XO duty by more than 5 points.* That is
the **fifth** instrument in a row to answer "not me".

☠️ **And the answer was in the same file.** A master that is up a third of the
time has a median of 0 on **both** sides of a current split, so the split by the
effect cannot see it at all. Split the other way — by the candidate cause, and
report the current — and it separates immediately:

| condition | n | p10 | median | p90 |
|---|---|---|---|---|
| **MPSS cores up** | 62 | 62 | **166** | 254 |
| MPSS cores down | 127 | 52 | **74** | 172 |
| PRONTO off-XO <70 % | 44 | 53 | 130 | 217 |
| PRONTO off-XO ≥70 % | 145 | 52 | 85 | 197 |

The two are not the same variable — they agree on only 107 of 189 samples — and
the 2×2 comes out close to additive:

| | PRONTO asleep | PRONTO awake |
|---|---|---|
| **MPSS core down** | **63 mA** (n=95) | 108 mA (n=32) |
| **MPSS core up** | 163 mA (n=50) | 188 mA (n=12) |

So: **MPSS core up ≈ +100 mA, PRONTO awake ≈ +45 mA, and the true floor with both
down is 63 mA.** MPSS is up in 33 % of samples; 0.33 × 100 mA ≈ 33 mA of median,
which is the size of the residual that the wlan cut left behind.

Pearson against the current over all 189 samples, for scale: `MPSS_cores` **+0.46**,
`PRONTO_cores` +0.07, `MPSS_xopct` −0.14, `PRONTO_xopct` −0.17, `v_mV` **−0.82**
(the pack sags as it draws — the same real-power witness as every other capture).

## What this reconciles

The modem A-B-A′ was flat because `mmcli --disable` stops the **RF**, not the
**MSS core**. Nothing in that experiment ever asked the modem firmware to stop
waking, and nothing here says it did.

## What it does not establish

* ☠️ **This is a correlation on one window, not an intervention.** Something wakes
  MPSS; that something could be paying the 100 mA itself.
* ☠️ **The duty cycle is point-sampled at 2 s.** 33 % is an unbiased estimate of a
  signal that may be oscillating far faster; it is not a measured on-time.
* ☠️ **No spread.** n = 1 window. A single median difference is not a number yet.
* The instrument did **not** resolve the wlan effect that is known to be present
  (~15 mA of median, measured the same day) — so its *nulls* rule out nothing at
  that magnitude. Only its positive separations carry weight here.

## One thing that is not about the burst at all

`LPASS_xopct` is **0 in every sample**, and `XO total duration` for LPASS is 9.4 s
against 5½ hours of uptime. The audio DSP essentially never releases the crystal.
It cannot explain the burst — it is constant — but a master that never lets the XO
go is exactly the shape of the standing `vlow = 0` item, and it belongs to the
**floor**, not to this measurement.
