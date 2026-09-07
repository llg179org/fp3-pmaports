# #142 arm B — tapping after a real suspend, with the driver BOUND

**2026-09-07**, pmOS `linux-fp3-7.1.3-r88` (`#89-fp3`), source
`6113869dcc3d602a7d9a25d80899a14b0c703a86`, branch `debug-int/7.1.3`.

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, whose finger is the measurement.

## ☠️ STATUS AT THE TIME OF WRITING: ARMED, NOT YET RUN

**The deliberate suspend has not happened.** `/sys/power/suspend_stats/success`
read **0** after 8 h 19 min of uptime and still reads 0. Everything below is the
instrument setup and the pre-suspend control leg. **No arm-B result exists yet**,
and nothing in this directory should be read as one.

## Why this arm exists at all

[`../2026-09-07_142-affinity-vs-touch-after-resume/`](../2026-09-07_142-affinity-vs-touch-after-resume/)
ran arm A and found its pre-registered criterion **unreachable by its own
instrument**: `142-trigger.sh` unbinds the touch driver as its first action, and
the rail fix (`cd2745d8d321`) *is* that driver's `devm_regulator_bulk_get_enable()`
vote. devm releases it on unbind, so arm A can never test the fix.

Confirmed again here, directly, before touching anything —
`regulator_summary-before.txt`, driver **bound**:

```
       l6                         2    2      0 unknown  1800mV
          2-0048-iovcc            1
          1a94000.dsi.0-iovcc     1
```

`use=2 open=2`, both consumers present. That is the state arm A destroys and
arm B preserves.

## Baseline (`baseline.txt`, captured 17:10:27 +02:00)

| | value |
|---|---|
| kernel | `7.1.3-postmarketos-qcom-msm8953 #89-fp3` |
| package `fp3-commit` | `6113869dcc3d602a7d9a25d80899a14b0c703a86` |
| boot_id | `1be64a5f-1d76-4e0c-9349-8a41872d2b0a` |
| uptime | 29945 s (8 h 19 min) |
| `suspend_stats/success` / `fail` | **0** / 0 |
| himax IRQ 138 count | **115** |
| touch driver | `/sys/bus/i2c/drivers/Himax-hx83112b-TS` — **bound** |
| `card0-DSI-1/dpms` / backlight | `On` / 160 |
| logind `IdleAction` drop-in | **absent** (`/etc/systemd/logind.conf.d/` empty) |
| journal cursor | recorded in `baseline.txt`, closing the window's near edge |

☠️ The `=== l6 consumers ===` block **in `baseline.txt` is wrong** and is kept
rather than deleted. Its `awk` matched the *first* ` l6 ` in
`regulator_summary`, which is a bare rail line with no consumers, and printed
`l6 0 0 0` — which reads exactly like "the touch vote is missing", the opposite
of the truth. `regulator_summary` lists rails twice; the load-bearing occurrence
is the one nested under `s4`. `regulator_summary-before.txt` holds the full file
and is the reference. **A selector that silently matches the wrong occurrence
produces a confident wrong reading, not an error.**

The absent logind drop-in is why the phone has not suspended in 8 h — and it is
also what makes this arm safe to run: nothing will suspend the phone in the
middle of the tapping.

## Instruments

Both deployed to `/home/fp3/armb/`, **md5-verified against the repo copies**
(identity, not merely well-formedness) and compiled with the device's own
`python3`:

| file | md5 | role |
|---|---|---|
| `docs/power/bringup/tools/fp3-taptest.py` | `cf1e4b59d02333b16429650e43596ed9` | the `.O` target — `.` left half, `o` right half, MARK bar, per-layer counters (`irq / contact / raw / gest / tap / shown`) |
| `docs/power/bringup/tools/kernel-contacts.py` | `e8308b5960f0bdc07a0e3e4742a82bce` | the evdev witness on `/dev/input/event4` |

☠️ **`fp3-taptest.py` is blind on its own** — its own header says so. It sees
only what the compositor hands it, so a touch that never arrives leaves nothing
in its log, and *"the finger did not land"* and *"the driver dropped it"* become
indistinguishable. The second is the fault this task exists to find. Hence the
second reader.

Launched 17:12:11 as system units (so they survive the ssh session):

```
sudo systemd-run --unit=fp3-kcontacts --collect /usr/bin/python3 \
  /home/fp3/armb/kernel-contacts.py /dev/input/event4 /var/log/kernel-contacts.log

sudo systemd-run --unit=fp3-taptest --collect --uid=10000 \
  --setenv=XDG_RUNTIME_DIR=/run/user/10000 --setenv=WAYLAND_DISPLAY=wayland-0 \
  --setenv=GDK_BACKEND=wayland --setenv=HOME=/home/fp3 \
  /usr/bin/python3 /home/fp3/armb/fp3-taptest.py
```

Both reported `active`; the app logged `DRAW #1` and
`geometry: 360x720, halves 180 + 180 px, divider at 180`.

☠️ **The 2026-09-06 logs were moved aside first** (`taptest-0906.log`,
`kernel-contacts-0906.log`). A stale log at the expected path is read as the new
run's output and looks entirely normal — the "wait for the result file matches
the previous run's file" trap.

## The pre-suspend control leg

Tapping began before any suspend: himax IRQ **115 → 327** in the first ~2
minutes. This is a **control**, not arm B. Its value is that it establishes the
fault rate with the driver bound, the rails held and *no resume involved* — the
counterfactual arm B needs.

## What arm B still requires

1. A **deliberate** suspend (RTC alarm — proven to fire on this platform despite
   the clock being stuck in 1970, because the alarm is relative to the counter).
2. A resume, with the operator present.
3. **Minutes** of tapping, driver bound. The `#178` exposure floor applies:
   fewer than 500 touch interrupts means nobody touched it. The 2026-09-04 rate
   was roughly one `-110` per active minute.
4. Read both logs together, pairing kernel `CONTACT` against app `RAW
   touch-begin` by timestamp, and grep the journal between the recorded cursors
   for `-110`, `-6`, `-5` and `Disabling IRQ`.

☠️ **It may be unreachable until #183 clears.** phoc cannot restore DSI-1 on
resume (6/6), so the screen may not come back and there would be nothing to tap.
**That outcome is itself the datum** and must be written down as one, not as a
failed attempt.

☠️ **`-110` may now be absent for two different reasons.** `fb68b1bd764f` retries
a failed event read, so a transient fault produces **no log line at all** — as
`#178` records, "zero errors" is ambiguous between *no faults* and *faults
absorbed*, and the driver has no counter that separates them. A clean arm B
therefore bounds the *user-visible* behaviour, not the fault rate.

---

# The pre-suspend control leg, measured 17:12–17:21

☠️ **Still pre-suspend.** `/sys/power/suspend_stats/success` read **0**
throughout. This is the control, not arm B.

## Exposure — well past the `#178` floor

| | |
|---|---|
| himax IRQ 138 | 115 → **15 560** = **15 445** interrupts |
| kernel contacts (`kernel-contacts.py`, evdev) | **1 725** |
| `SYN_DROPPED` | **0** — the reader never fell behind |
| taps recorded | `.` 867 + `o` 850 = 1 717 |

`#178` says fewer than 500 touch interrupts means nobody touched it. This leg is
**30×** that, from real two-finger tapping.

## ★ No loss above evdev — 1725 = 1725, from two independent readers

The app's own evdev watch counted `RAW` **1 725** and `CONTACT` **1 725**; the
separate `kernel-contacts.py` process, reading its own ring off `/dev/input/event4`,
counted **1 725**. Exact agreement.

So **nothing was lost between the kernel and the client** — not in the driver's
delivery to evdev, not in phoc, not in libinput. The 8-tap gap to 1 717 is the
MARK press plus record-area touches, which are not targets.

☠️ **What this does NOT exclude.** `CONTACT == RAW` bounds losses *above* evdev.
A touch the panel or driver dropped *before* evdev produces no CONTACT and no
RAW, and leaves this equality **perfectly intact**. It is invisible to exactly
this comparison.

## Zero i2c faults

`journalctl` since 17:10 and `dmesg`: **no `-110`, no `-6`, no `-5`, no
`Disabling IRQ`, no himax error line of any kind.** The only i2c traffic is
`i2c_qup 78b7000.i2c: pm_runtime: suspending/resuming`.

On 2026-09-04 the rate was roughly **one `-110` per active minute**. This leg ran
~9 minutes of dense tapping and produced **none**.

☠️ **And that is ambiguous, by `#178`'s own argument.** `fb68b1bd764f` retries a
failed event read, so an absorbed transient emits **no log line at all**. "Zero
errors" here is not distinguishable from "faults absorbed" without a counter the
driver does not have. What the leg does bound is the **user-visible** behaviour.

## The operator's MARK, and what the logs say about it

MARK #1 at 17:16:17.584, pressed because a tap felt lost. It follows a run of
**8 consecutive `.`** (17:16:15.840 → 17:16:17.080), all at x = 73–78 / 360 —
the left half throughout.

The kernel log for that window shows the second finger's slot vanish:

| | |
|---|---|
| last `slot=1` CONTACT before | 17:16:15.612 (#1593) |
| next `slot=1` CONTACT after | 17:16:18.282 (#1607) |
| gap | **2.67 s** |

and `slot=0` continuing normally throughout it — **12 contacts** at
17:16:15.834, .043, .260, .483, .693, .892, 17.076, .274, .358, .573, .913,
18.090.

### ☠️ The tempting reading, and why it is wrong

2.67 s sits close to the **2.05 s** QUP bus-clear recovery that arm A measured
as a constant, which invites reading this as a bus stall. **It cannot be one.**
The same i2c bus delivered twelve `slot=0` contacts *inside* the gap. A stalled
bus delivers nothing to anybody; this bus was demonstrably working the whole
time. The journal agrees — no error, and not even a `pm_runtime` transition in
that window (the neighbouring ones are 17:15:20 and 17:16:32).

### What it is not separable from

A finger that was lifted. `fp3-taptest.py`'s own counting rules say it outright:
*"A BREAK is NOT [lost taps]: it only says the alternation broke, which a
deliberate double-tap on one side does too."* Eight taps at x = 73–78 with
regular ~200 ms spacing is equally the signature of one finger tapping one spot.

**So the MARK is recorded and left unresolved.** It is not evidence of a driver
fault, and it is not evidence against one. The instrument that would separate
them — a per-contact link from the chip's interrupt to a delivered event — does
not exist here.

## Verdict of the control leg

With the driver **bound**, the rails **held** (`l6 use=2`), the bus **awake** and
**no suspend at all**, ~9 minutes and 15 445 touch interrupts produced **zero**
i2c faults and **zero** losses above evdev.

That is the counterfactual arm B needs, and it did not exist before today.

---

# ★ The interrupt bursts that produce no input event — and where they sit

The operator asked the sharp question: during the run of `.....`, did the
**kernel** fail to report the `o` presses too?

## For that run, no

The per-second `WINDOW` rows carry a per-layer count, `irq` read straight off
`/proc/interrupts` (`_irq_count()` matches the `hx83112b` line and sums the
eight CPU columns — verified in the source, not assumed):

```
17:16:13   irq 105   contact 10   raw 10   gest 10   tap 10
17:16:14   irq 108   contact  9   raw  9   gest  9   tap  9
17:16:15   irq  90   contact 10   raw 10   gest  8   tap 10
17:16:16   irq  37   contact  6   raw  6   gest  4   tap  6   <- the ..... run
17:16:17   irq  49   contact  6   raw  6   gest  6   tap  6   <- the ..... run
17:16:19   irq  73   contact  9   raw  9   gest  9   tap  9
```

The interrupt count **fell with** the contact count, 105/108/90 → 37/49. A
driver-side drop has the opposite signature — `irq` staying high while
`contact` collapses — and the app colours `contact` red for exactly that case.
It did not fire. The `.....` run is a one-finger regime, not a lost `o`.

## ☠️ A claim made and withdrawn in the same session

It was put to the operator that `shown` fell to ~51 % of `tap`, i.e. half the
frames never reached the screen. **That is not a measurement, and it is
withdrawn.** `shown` counts **frames, not touches** — `_resolve_present()`
resolves at most *one* pending frame per 400 ms cycle, and the app's own
instructions say `irq` and `shown` "are NOT one per touch, so they are counts
only, never judged". Comparing `shown` against `tap` is the comparison the
instrument explicitly forbids, and it was made anyway before the source was
read. Nothing about the display path is established here.

## ★ But elsewhere in the run there IS a signature, and it pairs 7 of 7

Seven windows have `irq > 0` and `contact == 0` — the chip raised interrupts and
**no input event came out of them**. Every one of the seven coincides with an
`i2c_qup 78b7000.i2c` runtime-PM transition:

| window | irq | i2c bus at that second |
|---|---:|---|
| 17:13:12.238 | 1 | suspending |
| 17:13:16.242 | 11 | suspending **and** resuming |
| 17:15:14.999 | **29** | suspending |
| 17:15:20.021 | **27** | resuming (suspended 17:15:19) |
| 17:16:32.515 | **21** | suspending |
| 17:16:50.530 | 1 | suspending |
| 17:22:48.058 | 1 | suspending |

☠️ **The converse does not hold**, which is what stops this being a coincidence
of density: 17:15:00, 17:15:01, 17:20:43, 17:22:41 and 17:23:50 are bus
suspends with no such window. The pairing runs one way — every burst sits on a
transition, not every transition produces a burst.

### The held-finger confound, excluded

`kernel-contacts.py` logs CONTACT and RELEASE only, so a finger held down and
sliding produces interrupts and no logged event — the same signature. It is
excluded for all three large bursts by reading the events either side:

| gap | last before | first after | panel |
|---|---|---|---|
| 17:15:13.847 → 17:15:16.260 | **RELEASE** #1042 | CONTACT #1043 | empty for 2.41 s |
| 17:15:18.871 → 17:15:20.401 | **RELEASE** #1071 | CONTACT #1072 | empty for 1.53 s |
| 17:16:31.321 → … | **RELEASE** #1725 | — | empty |

A RELEASE before the gap means no finger was down. So 21–29 interrupts fired
with **an empty panel** and produced nothing.

### Why the line can repeat: it is level-triggered

`/proc/interrupts` reads `msmgpio 65 **Level** hx83112b`. A level-triggered
source that is not cleared re-asserts, so a read that does not complete gives
tens of interrupts rather than one — which is the shape observed.

### ☠️ What this does NOT establish

1. **No touch was lost.** In all three large bursts the panel was empty, so
   there was no finger to lose. Across the whole run `contact` 3366 → `raw`
   3362: **four** events lost above evdev, 0.12 %.
2. **Direction is unproven.** "The suspended bus stalls the read" and "an idle
   panel lets the bus autosuspend while the chip churns" both predict this
   table. Nothing here separates them.
3. **A benign reading survives.** The chip may raise a no-fingers report after
   each release which the driver reads correctly and emits nothing for. That
   produces this signature with no fault at all.
4. The `irq` column is polled every 500 ms into a 1000 ms window, so edge
   attribution is ±0.5 s.

### ★ Why it is worth recording anyway

`#178` states that with `fb68b1bd764f` retrying silently, "zero errors" cannot
be told from "faults absorbed", and that separating them "needs a counter the
driver does not have". **`/proc/interrupts` paired with the evdev event count is
that counter** — it sees interrupts the driver consumed without producing
anything, which is precisely what an absorbed fault looks like. Whether these
particular bursts are absorbed faults or benign no-touch reports is not settled;
that the instrument exists is new.

**Next measurement, and it needs no finger:** disable i2c-qup runtime PM
(`echo on > /sys/bus/platform/devices/78b7000.i2c/power/control`) and repeat.
If the bursts vanish, the bus transition is in the path; if they persist with an
empty panel, they are the chip's own post-release reports.
