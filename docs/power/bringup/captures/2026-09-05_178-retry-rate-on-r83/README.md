# #178 — the instrument for the himax retry half, and what it has bounded so far

Armed 2026-09-05 19:10 on r83 (`#84-fp3`, `_commit=9af3de4d21f2`).

## Why a new instrument at all

The #157 reproducer cannot see this half: it times one raw i2c transaction to an
unused address, not the driver's event read. And the retry changes what a clean
log *means* — three attempts now absorb a transient failure without writing a
line, so on r83 "zero errors" is ambiguous between **no faults** and **faults
absorbed**. The driver has no counter that would separate them.

So this measures the thing that is still comparable across r82 and r83: the rate
of faults that survive all three attempts, per hour and per 1000 touch
interrupts.

## The instrument

`touch-sample.sh`, installed as `/usr/local/bin/fp3-touch-sample`, run every two
minutes by `fp3-touch-sample.timer`, appending to `/var/log/fp3-touch/r83.tsv`:

```
epoch  touch_irqs  err110  err6  err5  boot_id
```

Counts are cumulative for the boot; rates are differences between lines.

## ☠️ The gate it had to pass before any of its numbers were quoted

Run over the **previous** boot, whose answer was already on record from
`../2026-09-05_157-fault-rate-on-r82/`:

```sh
BOOT='-b -1' sh touch-sample.sh
#  ->  1788628211 - 5 5 28608 -
```

**5, 5, 28608** — exactly the recorded r82 totals. The gate also caught a defect
in this script: the first version printed `/proc/interrupts` and the boot_id
next to a past boot's error counts, because both are *always* the current boot.
That put `2671` on the same line as r82's totals — two regimes in one row, in
the very run meant to validate the instrument. Past boots now print `-`.

## What it has bounded so far — very little, and say so

At 19:12, ~10 minutes into r83: **2671 touch interrupts, 0 errors of any code.**
Above check 59's 500-interrupt floor, so the panel *was* used; below every
threshold that would make the number mean something.

Check `59-touch-i2c-stall-test.sh` states the arithmetic: the r82 stalls were
separated by 23–726 s, so any run shorter than a few times 726 s can come back
clean with the fault fully present. By the rule of three against the recorded
rate of one stall per ~200 s of active use:

| clean run | what it establishes |
|---|---|
| ~10 min | only "no worse than r82" |
| ~100 min | 10x better |
| ~17 h | 100x better, i.e. gone |

**Ten minutes is the first row.** The measurement needs the operator to use the
phone normally for at least an hour, which is why #178 is marked as needing a
person rather than left running as if it were finished.

---

# ☠️ Correction, 21:00: the r83 run measured nobody touching the phone

The boot ran 19:10–20:54 and logged **2002 touch interrupts, zero errors of any
code**. Read as a result that looks strong. It is not one.

`touch-exposure.py r83.tsv` on the same file:

```
boot 2fc31e47  19:10-20:54  wall    104 min   ACTIVE      4 min   irqs   2002
    -110=0  -6=0  -5=0
    ☠️ 4 min active is BELOW the ~36 min floor
```

The panel was touched in **2 of 52 two-minute intervals**, one of them carrying
1590 of the 2002 interrupts:

```
19:12 ............X...X................................... 20:54
```

So 100 of the 104 minutes are a measurement of the operator's absence. The
earlier draft of this page called this window "10 minutes clean, which only
rules out worse than r82"; the honest figure is **four minutes of exposure**,
which by check 59's own arithmetic rules out nothing at all.

## What this corrects in the instrument, not just in the reading

☠️ **check 59's gate is the wrong quantity.** It accepts a clean result once the
boot has `>= 500` touch interrupts, and this boot passed it with 2002 while
sitting untouched for an hour and forty minutes: a single four-minute burst
clears that bar. The #142 fault is per *first access after an idle*, so what
bounds a clean run is **active time**, never interrupt count - a phone nobody
touches generates no vulnerable moments and its clean log says only that.

`touch-exposure.py` is added here and reports active minutes as the denominator,
refusing to call a run meaningful below the ~36 minute floor that check 59
derives from the r82 inter-stall gaps (23-726 s).

☠️ It also groups by `boot_id` before differencing anything. The first run of
this analysis differenced across the r83 -> r84 reboot and reported "delta
-2670" touch interrupts, because /proc/interrupts resets at boot. The boot_id
column caught it; without that column the number would have looked merely odd
rather than impossible.
