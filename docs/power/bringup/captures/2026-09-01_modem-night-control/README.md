# ☠️☠️☠️ The control broke the line it was run to confirm — and the daemon is not the cost

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed the measurement it rests on.

2026-08-31 21:23 → 2026-09-01 05:39, **47 rounds**, cable out at 21:27:05,
Wi-Fi down, panel dark, **ModemManager stopped** for the whole run (the modem was
`registered` when the daemon was stopped). Battery 4.052 → 3.734 V rest OCV.

Tool: [`../../tools/modem-night.sh`](../../tools/modem-night.sh) `8 600 35 stopped`;
[`fit.txt`](fit.txt), [`ma.txt`](ma.txt), raw in [`raw/`](raw/).

This is the control for [`../2026-08-31_modem-night/`](../2026-08-31_modem-night/README.md):
same eight hours, same alternation, same Wi-Fi-down and cable-out, **only the
daemon differs**.

## What was pre-registered, and what happened

> "~48 mA ⇒ the 133 slope and the 41.4 mA intercept are reinforced and the modem
> track reaches the goal on its own; materially different ⇒ the two-point line was
> drawn across two configurations and the conclusion falls."

**It is materially different, in two independent ways, and the conclusion falls.**

| | census (2026-08-31) | **this control** |
|---|---:|---:|
| ModemManager | running | **stopped** |
| rounds | 86 | 47 |
| `logind` arm sleep | 602 s, 43/43 | 602 s, 23/23 |
| `rtcwake` arm sleep | **28 s, 43/43** | **601 s, 24/24** |
| every round ended by | 56 RTC / 141 modem edge | **56 `pm8xxx_rtc_alarm`, 47/47** |
| MPSS awake | 33.6 % | **35.7 %** (logind) / 36.7 % (rtcwake) |
| LPASS, PRONTO | — | **down throughout** (zero delta *and* no `xo_shutdowns`) |
| **draw** | **86 ± 4 mA** | **100 ± 4 mA** |

The draw is stable across every cut of the run: 100.3 / 96.1 / 99.6 / 97.7 /
103.9 mA at skips of 0–4 h, so ~**100 ± 4 mA**.

## ★★★★★ 1. Stopping ModemManager costs 14 mA and changes the modem's duty by nothing

Two nights, one variable. The daemon is **neither** what keeps the modem awake
(33.6 % → 35.7 %, i.e. no change, and if anything slightly worse without it) **nor**
a consumer worth removing (86 → 100 mA, i.e. **the phone draws more with the
daemon gone**).

Whatever the ~35 % MPSS duty is, it is a property of a modem camped on LTE, not
of anything the host daemon does to it.

## ★★★★★ 2. But the daemon *is* the entire reason the modem wakes the AP

The `rtcwake` arm is the one where terse never applies, because `rtcwake -m mem`
writes `/sys/power/state` directly and logind never runs. Last night that arm
died in **28 s, 43/43, on `141 smd-edge`**. Tonight, with no daemon at all, the
same arm slept the **full 601 s, 24/24, on the RTC**.

So the three configurations line up cleanly:

| configuration | AP wake by the modem |
|---|---|
| daemon running, terse applied (`logind`) | none — sleeps out the alarm |
| daemon running, terse not applied (`rtcwake`) | **every round, within ~28 s** |
| **no daemon at all** | **none — sleeps out the alarm** |

⇒ **The wakes are the daemon's own subscriptions.** Nothing in the network or the
modem's own behaviour wakes this phone; what wakes it is the unsolicited
indications ModemManager registered for, and terse is the repair for a wound the
daemon inflicts. That is a *stronger* version of last night's terse result, not a
weaker one, and it is measured from the third side.

## ☠️☠️ 3. What falls: the 133 / 41.4 line, and everything computed from it

The control was supposed to be a third point at ~5 % duty. **It landed at 35.7 %**
— on top of the census point, not opposite it. So:

- **There is no third duty point.** The line cannot be refitted; two points at
  33.6 % and 35.7 % are degenerate.
- **The scatter at fixed duty is 14 mA.** Two nights differing only in the daemon,
  at the same duty, differ by 14 mA. The slope was fitted over a 38 mA rise; a
  14 mA scatter on that gives roughly **133 ± 50 mA per unit duty**, not
  133 ± nothing. The agreement with the awake-window's 135 was luck.
- **The line under-predicts this point** by 11 mA (41.4 + 133 × 0.357 = 88.9 mA
  against 100.3 measured).

Retracted with it, and I stated this one as standing four hours ago:

> ☠️ "the modem track is worth ~37 mA (33.6 % → 6.1 % duty at 133 mA per unit
> duty)". That number **is** the slope, and the slope no longer has an error bar
> anyone should quote.

## ☠️☠️☠️ 4. And the 5.0 % that anchored it was n=1

The 5.0 % MPSS figure came from **one** 602 s window on 2026-08-31 with
ModemManager stopped
([`../2026-08-31_mpss-across-suspend-nomm/`](../2026-08-31_mpss-across-suspend-nomm/README.md)).
Tonight is **47 windows in the same daemon state** and reads 35.7 %. n=47 wins.

What differed: that single window ran with the cable in and Wi-Fi up, during the
day, and it was one sample. This run is a night on battery. Either the 5 % was a
transient the single window happened to catch, or the modem's duty depends on
something neither run controlled — but it cannot be quoted as the MM-stopped duty
any more.

## ☠️☠️☠️ 5. The largest problem: the 48 mA floor and the 5 % duty were never one measurement

The step-0 floor — the number this whole project measures itself against — is
`48 ± 5 mA`, and it has been quoted throughout as "48 mA at 5.0 % MPSS duty".

**Those two numbers come from different runs on different days.**

| number | where it comes from |
|---|---|
| `48 ± 5 mA` | the 58-round `sleep-night.sh` run of **2026-08-30**, whose MPSS duty was never measured |
| `5.0 %` | **one** 602 s window on **2026-08-31** ([`../2026-08-31_mpss-across-suspend-nomm/`](../2026-08-31_mpss-across-suspend-nomm/README.md)), which measured no current |

So the low end of the line was not a measured point. It was a current from one
night paired with a duty from another day's single window, and the pairing was
never flagged because both were taken "with ModemManager stopped" — the same
gate, a different run.

Tonight is the first run in that daemon state where **both** were measured
together, and it reads **100 mA at 35.7 %**. Combined with the census, the only
properly paired points this project has are the two cable-out nights, which are
degenerate in duty. **There is no measured low-duty point at all.**

### ☠️ The instrument hypothesis, raised and then killed from source

Before checking the provenance above, the obvious suspicion was that
`sleep-night.sh`'s charge cut leaves VBUS feeding the system rail, so that the
battery-side OCV slope under-reports the draw. That would have explained the sign
neatly, and it is wrong on two counts, both worth recording so it is not raised
again:

- ` sleep-night.sh` restores an `input_suspend` attribute that **does not exist on
  this device** — `ls /sys/class/power_supply/*/input_suspend` returns "No such
  file"; the glob never expands and that loop has always been a no-op.
- The cut that *does* happen is `echo Unknown > .../pmi632-charger/status`, and in
  our own driver that is a real input-path suspend:

  ```c
  case POWER_SUPPLY_PROP_STATUS:
      return regmap_update_bits(chip->regmap, chip->base + USBIN_CMD_IL,
                                USBIN_SUSPEND_BIT, !val->intval);
  ```

  (`drivers/power/supply/qcom_smbx.c`, `smb_set_property`.) `Unknown` is
  `POWER_SUPPLY_STATUS_UNKNOWN` = 0, so `!val->intval` is 1 and the bit is **set**;
  `Charging` is 1 and clears it. USBIN is suspended at the PMIC, the system runs
  off the pack, and the OCV slope measures the whole load.

☠️ Source is not a measurement and this does not *prove* VBUS carries nothing —
but it removes the mechanism that made the artifact story plausible, and the
provenance defect above explains the discrepancy without needing one. Chasing the
cable would have cost a night and answered a question that a `git grep` and an
`ls` answered in two minutes.

### What this leaves open, and it is the real question

Two nights with ModemManager stopped, one reading ~5 % MPSS duty in a single
window and one reading 35.7 % across 47, are still not reconciled. The
differences between them are Wi-Fi (up vs down), the cable (in vs out), the day,
and n (1 vs 47). Since 33.6 % and 35.7 % agree across the two cable-out nights,
the 5 % is the outlier, and the cheapest test of it is not a night: **repeat that
single window several times, cable in and Wi-Fi up, exactly as it was taken.** If
it still reads 5 %, then something in the cable-in/Wi-Fi-up configuration really
does quiet the modem — which would be the first lever found on the D track, and
worth far more than the floor number it was originally quoted for.

## What still stands, unaffected

- Terse fixes the AP wakes, and the mechanism is now measured from three sides
  (§2). That is the R track's blocker and it is closed.
- LPASS and PRONTO are down through a real sleep; only MPSS and the unowned floor
  remain.
- The QMI census: zero packets in every sleep window, in both nights. Tonight it
  is trivially zero (no daemon), so it adds nothing — it is recorded, not claimed.

## Housekeeping

- ☠️ `capacity` stepped 92 % → 49 % between rounds 34 and 35 with **no
  corresponding step in `v_uV`** (3.8340 → 3.8244 V). That is the frozen software
  integrator re-syncing, exactly as
  [`../../tools/modem-night-to-rounds.py`](../../tools/modem-night-to-rounds.py)
  warns; it is emitted so a reader can see it standing still, and it is not used
  in any fit.
- Rounds 23, 31 and 47 have no bounded sleep window and are excluded by the
  fitter rather than counted as zeros; round 15 produced a negative window
  (`-85799 s`) and is likewise excluded.

## The degeneracy, shown rather than argued

[`../../tools/duty-ma-line.py`](../../tools/duty-ma-line.py) over
[`../../duty-ma-points.txt`](../../duty-ma-points.txt), restricted to the two
rows that actually share a configuration:

```
$ duty-ma-line.py duty-ma-points.txt --only cable-out
n = 2   (--only cable-out)
mA = -138.0 + 667 x duty
at duty 6.1%  ->  -97.3 mA
```

A line through the only two points taken in the same configuration predicts
**negative 97 mA**. That is what "degenerate" means here, and it is why the
three-point fit below should not be quoted either:

```
$ duty-ma-line.py duty-ma-points.txt
n = 3
mA = 39.7 + 154 x duty      at duty 6.1% -> 49.1 mA
```

That 49.1 mA looks like the old headline surviving. It is not: 6.1 % sits next to
the 5.0 % row, so this prediction is again ~96 % the step-0 point — the one row of
the three that §5 argues is an instrument artifact. The arithmetic is restating
the suspect number, not testing it.
