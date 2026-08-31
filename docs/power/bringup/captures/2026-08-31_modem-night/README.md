# ★★★★★ terse is the difference between a 602 s sleep and a 28 s one — and the modem is awake anyway

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed the measurement it rests on.

2026-08-31, 11:48→19:49, **86 rounds**, cable out at 11:43:48 (host `dmesg`,
`cdc_ncm … unregister`), Wi-Fi down, panel dark, ModemManager **running** and
registered on LTE. Battery 100 % → 86 %, rest voltage 4.244 → 3.939 V.

Tool: [`../../tools/modem-night.sh`](../../tools/modem-night.sh); analysis
[`fit.txt`](fit.txt) from
[`../../tools/modem-night-fit.py`](../../tools/modem-night-fit.py); raw per-round
data in [`raw/`](raw/).

The daemon was the locally patched build (upstream `5e91dd2` + the three
`qmi-report-failed-unregister` commits), so every terse step reports from its
completion callback and a refusal would have appeared as `<wrn>`. **None did, in
43 terse applications.**

## The internal A/B — 43 rounds each, alternating, one night, one cell

| path | rounds | mean sleep | ended by | MPSS awake | QMI during the sleep |
|---|---:|---:|---|---:|---|
| **`logind`** (terse applied) | 43 | **602 s** | **56 `pm8xxx_rtc_alarm`**, 43/43 | 33.6 % | **0 / 0 / 0** |
| **`rtcwake`** (logind never runs, so terse never applies) | 43 | **28 s** | **141 `smd-edge`**, 43/43 | 20.1 % (n=12) | not captured — see below |

The separation is total: **43/43 against 43/43**, no overlap, a 21× difference in
sleep length, alternating round by round so no drift between days can produce it.

## ☠️ This retracts "terse buys no residency"

[`leads/modemmanager-suspend-modes.md`](../../leads/modemmanager-suspend-modes.md)
concluded on 2026-08-30 that *"terse is harmless and useless here"*, from six legs
that slept 52 / 61 / 62 / 61 / 63 / 63 s. That verdict is **withdrawn**. With
n=43 per arm and the alternation inside one night, terse is the difference
between a phone that sleeps out its alarm and one the modem wakes within half a
minute.

The earlier six legs are not contradicted so much as explained: that page already
records that they were taken across a regime it could not identify, and its own
"what a real terse residency measurement now requires" list — a return leg, one
regime, radio context on the record — is what this run finally supplies.

## ☠️ And the second half is the uncomfortable one

In those same 43 full-length sleeps the modem was **33.6 % awake**, and **not one
QMI packet arrived** while the AP was frozen.

That zero is validated rather than assumed. The kprobe armed in **86 of 86**
rounds, the system-sleep hook bounded a window in **43 of 43** logind rounds, and
in each of those the trace held ~38 QMI lines of which **0** fell between
`FP3_FREEZE` and `FP3_THAW`. The channel demonstrably reports traffic; there was
none inside the sleep.

⇒ **Nobody is keeping the modem awake. It simply does not go down.** This is the
third candidate from the run's own pre-registration — not the AP talking to it,
not the network waking us — and it is now the measured one.

The two problems therefore separate cleanly, and they have different owners:

| problem | status |
|---|---|
| the modem **wakes the AP** (the R track's blocker) | **solved by terse**, which this distribution already ships |
| the modem **is awake at all** (the D track) | untouched by terse, and not traffic-driven |

## ☠️ Half the census is blind, and it is my instrument's fault

The 43 `rtcwake` rounds carry **no QMI data**: `rtcwake -m mem` writes
`/sys/power/state` directly, so systemd never runs the `system-sleep` hooks and
the `FP3_FREEZE`/`FP3_THAW` markers never fire. `modem-night-fit.py` prints `?`
for those rounds and excludes them from the totals rather than adding their zeros
— which is the guard that stopped this from reading as "no traffic on either
path".

So the zero-traffic finding covers the **terse** arm only. The `rtcwake` arm's
traffic was never captured, and its wake source (the modem edge, 43/43) says
there certainly was some.

## Open, and not smoothed over

- **LPASS reads 72–97 % awake in the logind rounds**, against this morning's
  measurement of the same counters with ModemManager *stopped*, where it never
  left XO shutdown (`../2026-08-31_xo-dur-semantics/`). Unexplained.
- **The model needs re-checking.** `mA = 54.9 + 135 × duty` was fitted on *awake*
  windows and predicts ~100 mA at 33.6 %. This run was 93 % asleep at that duty
  and fell 305 mV in 8.0 h. Converting that slope through the pack's curve is the
  next step; if it lands far below 100 mA, the model does not transfer to a
  sleeping phone and the D track is worth much less than the arithmetic assumed.
- **`pm_wakeup_irq` names are boot-local and were read from this boot**: 56 is
  `pm8xxx_rtc_alarm`, 141 is `smd-edge`.
