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

---

## ★★★★★ Priced: 86 ± 4 mA — and it moves the goal within reach of the modem track alone

[`../../tools/modem-night-to-rounds.py`](../../tools/modem-night-to-rounds.py)
feeds the logind arm's rest voltages to the already-validated
[`sleep-night-fit.py`](../../tools/sleep-night-fit.py) rather than re-implementing
the curve lookup. Against
[`../2026-08-28_discharge-to-shutdown/discharge.txt`](../2026-08-28_discharge-to-shutdown/),
43 rounds over 7.81 h, 91.7 % of the run asleep:

| fit start | rounds | average draw |
|---|---:|---:|
| 0 h | 43 | 89.2 mA |
| 1 h | 38 | 88.2 mA |
| 2 h | 32 | 83.3 mA |
| 3 h | 27 | 87.4 mA |
| 4 h | 21 | 83.7 mA |

Stable across every cut of the flat top ⇒ **86 ± 4 mA**, rms residual ~40 mAh.

### The model, refitted on a phone that is actually asleep

Two measured points, both with the AP asleep for >90 % of the run:

| | MPSS duty | draw |
|---|---:|---:|
| step-0 night, ModemManager **stopped** | 5.0 % | **48 ± 5 mA** |
| this run, ModemManager **running** | 33.6 % | **86 ± 4 mA** |

```
slope     = 133 mA per unit duty      (the awake-window fit says 135)
intercept =  41.4 mA                  (the awake-window fit says 54.9)
```

**The slope reproduces to 1.5 %. The intercept does not — it is 13 mA lower.**

☠️ **And the intercept is the same number as the unexplained floor.** This morning
closed with "~41 mA of the 48 mA floor has no owner" after four RPM masters were
accounted for. The refit puts the sleeping phone's intercept at **41.4 mA**. They
are the same quantity seen from two directions: the floor minus the modem's share
*is* the intercept, and neither has an owner yet.

### ☠️ This retracts "the modem track buys parity, not the goal"

Said several times on 2026-08-31, from `NEXT-RUN.md`'s arithmetic: the ≤50 mA
target sits below the model's 54.9 mA intercept, so no amount of modem-duty work
can reach it. **That intercept was fitted on awake windows.** On a sleeping phone
it is 41.4 mA, and the same line then says:

```
duty 33.6 % (now)              -> 86.0 mA
duty  6.1 % (the oracle's)     -> 49.5 mA
```

⇒ **Bringing the modem to the oracle's duty reaches the goal on its own**, with no
progress on the floor at all. The D track is not the consolation prize; on this
arithmetic it is the whole thing.

### What this rests on, stated so it can be attacked

- **n=2.** Two points define a line and cannot test it.
- ☠️ **The two points differ in more than duty.** The floor arm ran WiFi **up**
  with the cable in and the PMIC input suspended; this run had WiFi **down** and
  no cable. Both differences push the slope the wrong way for the story (the
  floor arm carried an extra consumer, so its 48 mA overstates a WiFi-free
  baseline, which would *steepen* the fitted slope). The agreement with the
  independent awake-window coefficient is what keeps it credible, not the fit
  itself.
- **The 6.1 % is the oracle's measured duty**, not a demonstrated target for our
  stack. Reaching it is the D track's entire unsolved problem.

**The experiment that settles it is one more run of exactly this census with
ModemManager stopped** — same eight hours, same WiFi-down, same cable-out, same
alternation. That yields a third point at ~5 % duty with *only* the daemon
differing, and turns a two-point line drawn through two configurations into a
controlled one.
