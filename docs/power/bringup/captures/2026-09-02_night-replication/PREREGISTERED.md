<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# Pre-registration — the 2026-09-02 night replication, written BEFORE the data arrived

This page was written **between 19:08 and 03:15**, while the measurement was
running, and **not one of its numbers was visible**. The only host-side touch for
the whole night was one poll at 19:23:49, during the opening rest.

☠️ **Why this is needed.** This project retracted four published stories this
week, and all four came from the same class of error: **an explanation fitted
after the data arrived**. A prediction written afterwards is not a prediction. If
the morning's numbers fall inside the bands below, the closure will not merely be
*measured* but **predicted** — and if they do not, the bands written here say
which assumption failed, rather than my memory.

## What the night does (from the script's source, not from memory)

| step | segment | USB input | expected length |
|---|---|---|---|
| 0 | opening rest + OCV (radio off) | **suspended** | adaptive, ≤ 90 min |
| — | reboot + convergence + band pin | **switched back on** | ~10–15 min × 3 |
| 1, 3, 5 | legs 1–3, IMS off, 90 s alarms | **suspended** | 75 min × 3 |
| end | closing rest + OCV (radio off) | **suspended** | 30 min |

## ☠️ The structural problem that has to be stated before the prediction

**The outer OCV pair does NOT bracket a clean discharge.** `night-run.sh`
deliberately switches the charger input back on before every reboot (the suspend
bit lives in the PMIC and would survive a warm boot, so the phone would come back
silently unable to charge) — so **on three segments the input is on**. If the
cable is physically plugged in, the pack **charges** during those, and the
night's ΔQ is not the integral of consumption but consumption **minus** charge.

This is not a defect in the script — reboot safety matters more — but a term that
has to be entered into the balance. Two cases, and the log **decides which**,
because `pmi632-charger/status` is recorded at the start of every step:

- **The cable is not plugged in** ⇒ no current flows even on the "switched back
  on" segments, the night is a discharge throughout, and the balance closes.
- **The cable is plugged in** ⇒ the reboot segments carry a positive term that
  cannot be unpicked from the voltage. The whole-night OCV bound then **falls**,
  and the `|ε|` bound can only be stated for the *within-leg* segments, or not at
  all. That has to be said out loud in the morning, not glossed over.

## Pre-registered predictions

The acceptance threshold, **in advance**: the balance closes if the two sides
agree **within 10 %**. Nothing looser will be allowed afterwards.

| item | prediction | what it rests on |
|---|---|---|
| leg means (3) | around **40.3 mA**, **within ±5 mA** of each other | the 09-02 census B leg, 19/30 windows, ±1.3 within-leg |
| the boot-to-boot spread | **< 5 mA** (the spread of the three leg means) | this is the object of the measurement; if it is larger, 40.3 must not be quoted as one number |
| rest current (radio off, input off) | **25–35 mA** | the radio-off segment is the cheapest known state |
| reboot + convergence | **150–350 mA**, 10–15 min per segment | awake, with the modem coming up; my loosest term |
| opening rest length | 60–90 min (adaptive, 90 ceiling) | already −2 mV/2 min at 19:22 |
| **ΔQ for the night, if the cable is UNPLUGGED** | **270–330 mAh** | 90′×30 + 3×75′×40.3 + 3×12′×250 + 30′×30 |
| the same in SoC | **12–15 points** | on a 2185 mAh pack |
| the same by voltage | **60–80 mV** | the local slope of the 08-28 curve in the 4.0–4.2 V band |

☠️ My ΔQ prediction is **higher** than the reviewer's (230–280 mAh), and the
difference is almost entirely in the reboot term — the one segment this project
has no measured number for. If the morning's balance lands in the 230–280 band,
that means **the reboot is cheaper than I thought**, not that the legs are wrong;
I say so in advance so that I cannot pick an explanation afterwards.

## What may and may not be done with the curve

- **May:** use the 2026-08-28 discharge curve for a **local slope** (mAh/mV)
  around tonight's voltage range.
- **May not:** use it for absolute SoC. The curve was taken *under* a 110 mA
  load, so every point sits ≈ 16 mV (R≈0.15 Ω) below the true OCV; that cancels
  to first order in a Δ, but not in an absolute assignment.
- **The Peukert term is negligible**: in the C/20–C/55 range the exponent is
  ~1.0 and the deviation is under 1–2 %.

## ☠️ One number corrected, still before the analysis

The offset bound had been stated as `|ε| ≤ 1.6 δ`, with `Ī = 110 mA`. 110 is the
discharge's **median** (108); but the mAh axis is an **integral**, so the correct
scale is the **mean: 2185 mAh / 17.94 h = 121.8 mA**. With that,

$$I_{QG}-I_{OCV}=\varepsilon\left(1-\frac{I}{\bar I}\right),\qquad
1-\frac{40}{121{.}8}=0{.}672 \;\Rightarrow\; |\varepsilon| \le 1{.}49\,\delta$$

instead of the earlier 1.57. So the published bound was **conservative, not
wrong** — and counting the curve's own slope error (`g`), the honest form is
`|ε| ≤ 1.49 (δ + I·|g|)`, a loosening of ~1–2 mA for a few-percent `g`.

Both numbers were in the source all along:
`2026-08-28_discharge-to-shutdown/analysis.md` — *"p10 56, **median 108**, p90 217
mA (**mean 122**, and the mean is not the number)"*. The end of that sentence is
true — of the question it was answering there. To scale an integral, **the mean
is the number**.
