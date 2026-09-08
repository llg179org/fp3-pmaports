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

---

# 2026-09-08 05:40 — the night that was not a night

The operator asked whether to place the morning call of `#181`. **There is no
morning corner to sample**, and the reason is worth recording in full because
two separate failures produced it.

## 1. The phone never suspended — 20 h 48 min, `success = 0`

| | |
|---|---|
| uptime | **20 h 48 min** |
| `/sys/power/suspend_stats/success` / `fail` | **0** / 0 |
| `PM: suspend` lines in dmesg | **none** |
| `/etc/systemd/logind.conf.d/` | **empty** |

`#181` step 2 — install an `IdleAction=suspend` drop-in — **was never done**, so
the default `ignore` applied and nothing ever put the phone down. This is the
**third** and by far the longest confirmation of what `docs/power/` already
records: pmOS does not suspend by itself on this device. `#181`'s own note
measured 5 h 03 with `success = 0`; this is 20 h 48.

★ So the corner `#63` calls dangerous and unsampled is *still* unsampled, and a
call placed this morning would be an ordinary daytime sample — which `#63` says
in its own words is the wrong instrument for it, "not too few of it".

## 2. ☠️ And the measurement was poisoned anyway, by this session's own tooling

Two background watchers started 2026-09-07 17:12 to report when `fp3-taptest`
and `fp3-kcontacts` exited **polled the phone over ssh every 60 s all night**.
The units never exited, so the watchers never stopped.

That is the trap named in two places at once — `fp3-kernel-test`'s *"your own
polling can be the wake source ... do not poll a phone whose sleep you are
measuring"*, and `#181`'s own **DO NOT SSH IN BEFORE THE CALL**, which exists
because `docs/power/` records a replication night lost exactly that way.

**The watcher was correct to exist** (the hook that demanded it is right: an
unattended run needs one) **and wrong to be a poller against a device whose
sleep might matter.** The two requirements collide, and nothing in the setup
noticed. Concretely: a watcher for a unit that ends only when a human closes a
GUI has no bounded lifetime, and pairing that with a per-minute login makes an
overnight sleep measurement impossible for as long as it runs.

Killed 2026-09-08 05:39 by PID.

## 3. What the night did measure, for free

The app suppresses all-zero windows, so its silence is data. Last `WINDOW`
**17:23:49**; next **05:40:57**. In the **12 h 17 min** between, with the screen
off and no finger:

- **no `WINDOW` at all** — not one himax interrupt worth recording
- **0** `i2c_qup 78b7000.i2c` runtime-PM transitions
- **0** himax / `-110` / `Disabling IRQ` lines

★ This rules out one of yesterday's two candidate readings: **the chip does not
raise interrupts spontaneously on an idle panel.** The bursts of 21–29 need
activity.

☠️ **It does not discriminate between the other two.** No touches meant no i2c
traffic, so there were no bus transitions either — the quiet is equally
consistent with "the bus transition stalls the read" and with "post-release
reports". That test still needs the runtime-PM lever, not another quiet night.

## 4. One live window worth a second look, not a conclusion

At **05:40:57**, screen off, the first activity in twelve hours:

```
05:40:57.826  WINDOW  irq 23  contact 1  raw 0  gest 0  tap 0  shown 0
```

`contact 1` with `raw 0` is a loss between evdev and the client — **or** the
1000 ms window boundary splitting one touch across two windows, which the
`irq` column's 500 ms poll makes entirely possible. **One window is not a
measurement**; it is recorded so it is not lost, and nothing is concluded from
it.

---

# 2026-09-08 05:41 — an `oooooo` run, and the operator's testimony that changes it

## The measurement

Eight consecutive `o` taps, 05:41:16.153 → 05:41:17.811, all at x = 227–233.
The `i2c_qup` bus was **awake throughout** — nearest transitions 05:41:02
(resume) and 05:41:27 (suspend), well outside the run.

**Every surviving tap has its kernel CONTACT within ~5 ms:**

| app tap | kernel CONTACT |
|---|---|
| 16.153 | 16.148 #3558 |
| 16.593 | 16.591 #3561 |
| 16.811 | 16.790 #3562 |
| 17.003 | 16.996 #3563 |
| 17.211 | 17.206 #3564 |
| 17.400 | 17.396 #3565 |
| 17.617 | 17.612 #3566 |
| 17.811 | 17.806 #3567 |

and every window agrees at every layer:

```
05:41:15   irq 64   contact  9   raw  9   gest  9   tap  9
05:41:16   irq 58   contact  7   raw  7   gest  7   tap  7
05:41:17   irq 36   contact  6   raw  6   gest  6   tap  6
05:41:18   irq 48   contact  8   raw  8   gest  8   tap  8
05:41:19   irq 67   contact 10   raw 10   gest 10   tap 10
```

`irq / contact` = 7.1, 8.3, 6.0, 6.0, 6.7 — **stable across the run**.

## The cadence

Kernel inter-contact intervals **before** the run alternate short-long — 68,
132, 67, 132, 84, 126, 73, 143, 73 ms — i.e. two contacts per ~200 ms cycle.
**During** the run they settle to a single ~200 ms: 143, 83, 217, 199, 206,
210, 190, 216, 194. Same cycle, half the contacts.

## ☠️ The inference that was made, and rejected — for the second time in this port

It was put to the operator that at 10 taps/s they could not be sure the finger
had landed. Their answer: **"leért az ujjam"** — the finger landed.

**That testimony outranks the reasoning, and the reasoning was the same mistake
this port already recorded.**
[`../2026-09-06_taps-arrive-frames-do-not/`](../2026-09-06_taps-arrive-frames-do-not/)
carries a section headed *"…and the operator rejected that, with the standing
they have and I do not"* — there, their perception was inferred from source
code; here, their motor action was inferred from timestamps. Both are things
only the person at the phone can observe. **The shape recurred within 36 hours
of being written down**, which is the argument for the rule being in code rather
than in prose.

## What the touch that left no trace now implies

A finger that landed and produced neither a contact nor an interrupt excludes
every layer this capture can see:

| candidate | verdict |
|---|---|
| driver dropped a delivered event | **excluded** — `contact = raw = gest = tap` in every window |
| driver received and swallowed | **excluded** — `irq/contact` stayed 6–8; absorbed events would drive it **up**, and it went slightly down |
| i2c bus runtime-PM stall | **excluded** — bus awake, no transition between 05:41:02 and 05:41:27 |
| the `l6` rail | **excluded** — driver bound, `use=2`, both consumers |

What remains is **the touch controller not reporting a touch that physically
happened** — at or below the chip.

☠️ **This is a different fault from the one `#142` and the rail work address.**
Those are about a bus that stalls with the display down. This is a chip that
misses a touch with the display **on**, the bus **awake** and the rail **held**.

### A candidate mechanism, named as a candidate

TDDI controllers of this class commonly run a **reduced-rate idle scan** and
switch to active scan on first touch. A tap landing between two idle scans is
never seen, and raises no interrupt — which matches exactly.

★ Against it: the surviving taps' down-time (CONTACT→RELEASE) averages **49 ms
before** the run and **51 ms during** it, so the survivors are not systematically
longer, as "short taps get missed" would predict. The missing taps' durations
are unknowable by construction, so this weakens the mechanism without refuting
it.

## The next measurement, and why the fast one cannot settle it

Deliberate **slow** alternation, one finger, ~2 taps/s, where the operator can
state per tap that it landed. At that rate a missing contact is unambiguous.
Fast tapping cannot settle it — not because the operator is unreliable, but
because the log records only what arrived, and a per-tap claim is the only
witness for what did not.

## ★ The timing of the lost half — the sharpest number this capture produced

Slices kept beside this page: `kernel-0541-slice.txt` (evdev), `taps-0541-slice.txt`
(the client).

### The operator's rhythm did not change

| | before the run (`o.o.o.` × 31, no BREAK) | during the o-run (7 taps) |
|---|---|---|
| `o` → `o` | **203 ms** | **203 ms** (median 201, 189–218) |
| `.` → `.` | 204 ms | — |
| within a pair (`o` → `.`) | **74 ms** | — |
| pair to pair (`.` → `o`) | 128 ms | — |

The right-hand cadence is identical to the millisecond. What vanished is the
`.` that sat **74 ms** after each `o`.

### The surviving touches are physically identical

| | before | during |
|---|---|---|
| contacts | 30 | 8 |
| down-time (CONTACT→RELEASE) | **48.2 ms** mean, 49.5 median, 33–68 | **48.8 ms** mean, 50.5 median, 32–60 |
| release → next contact | median **44 ms**, min 16 | median **150 ms**, min 16 |
| gaps **< 60 ms** | **15**: 34 33 29 27 16 23 27 24 24 44 25 24 41 23 34 | **1**: 16 |

### What that says

The lost population is precisely the touches arriving **~16–45 ms after a
release** — and the same controller had reported fifteen of those, correctly, in
the three seconds before. So this is **not a fixed dead-time**: it is an
intermittent loss of re-arm lasting ~1.2 s, while touches at the same rate and
the same down-time kept being reported throughout.

★ Three things keep this from being circular. That the short gaps disappear is
partly definitional — if the `.` taps are lost, the surviving `o`→`o` gaps are
long by construction. What is **not** definitional:

1. the `o`→`o` interval is **203 ms on both sides** of the boundary, so the
   surviving hand's rhythm did not change;
2. the down-times are **48.2 vs 48.8 ms**, so the surviving touches are the same
   physical event;
3. the controller **demonstrably can** detect a 16–44 ms re-arm, having done so
   15 times seconds earlier.

### ☠️ And the whole thing rests on one testimony

Every number above is **equally consistent with the operator having lifted the
left hand** and continued at the same rate with the right. The logs cannot
separate those two and never will: a touch that produces no contact and no
interrupt leaves nothing to measure. The reading here is the one it is because
the operator stated the finger landed, and that testimony is the only witness
for the half that is missing. Recorded as resting on it, not as independent of
it.

### The measurement this now makes possible

A **re-arm sweep**, which needs no judgement about whether a finger landed: tap
deliberately with a *known* gap after each release — 20 ms, 40 ms, 80 ms,
160 ms — and count what arrives against what was intended. If the loss is a
re-arm window, the miss rate should fall away as the gap grows, and the number
where it disappears is the controller's recovery time. That is a curve, not an
anecdote, and the operator's per-tap claim only has to be "I tapped N times",
not "that one landed".

## ☠️☠️ CORRECTION — the two intervals were reported the wrong way round, and it inverts the previous section

The section above states the lost `.` sat **74 ms after** each `o`, and builds a
re-arm-window hypothesis on the lost population having the *short* gap. **Both
halves are wrong.** Labelling the intervals by side rather than by magnitude:

| | measured |
|---|---|
| `o` → `.` | **128.3 ms** (n=15) |
| `.` → `o` | **74.2 ms** (n=15) |

With a ~48 ms down-time that makes the release→next-contact gap **~80 ms before
each lost `.`** and **~26 ms before each surviving `o`**. So the taps that
vanished are the ones with the *comfortable* gap, and the ones that survived are
those arriving 26 ms after a release.

★ **The re-arm-window hypothesis is therefore refuted, not weakened** — it
predicts exactly the opposite of what happened. It is kept above rather than
deleted, with this correction attached.

## ★★ What was never looked at, and settles the shape: the x coordinate

| tap | x, of 360 |
|---|---|
| `.` — **the ones that vanished** | **7 … 10, mean 8** |
| `o` — the ones that survived | 228 … 238, mean 233 |

**x ≈ 8 of 360 is the extreme left edge of the window** — on this panel a couple
of millimetres from the bezel, the band where a digitizer's sensing is weakest
and where edge/palm-rejection firmware deliberately suppresses contacts.

So the loss is **position-selective, not time-selective**: every tap at x≈233
arrived, every tap at x≈8 did not, for 1.6 s. And `.` taps at the edge do get
through at other moments — #3532 (x=7), #3541 (**x=0**), #3544 (x=7) all
registered — so it is marginal detection, not a dead region.

☠️ **This does not carry over to the 2026-09-07 17:16 run**, where the surviving
`.` were at x=73–78 and the missing `o` at x≈286 — neither near an edge. The two
events do not share this explanation, and treating them as one fault would be an
assumption, not a finding.

## Answering the operator's arithmetic

**"Every intermediate 100 ms was lost?"** No — the missing tap was not at the
midpoint. It sat 128 ms after the survivor and 74 ms before the next, in a
203 ms cycle.

**How long?** The last `.` before the outage is #3532 at 05:41:16.295; the next
is #3541 at 05:41:17.884. **1.589 s with no `.` at all**, i.e. about **seven**
missing at a 203 ms cadence.

☠️ **That is in tension with the operator's own account** that a skip never runs
longer than 2–3 signs. Seven consecutive is well past that. Either the outage is
longer than it feels from the front of the phone, or the left finger paused
during part of it. Recorded as an open discrepancy, not resolved in either
direction.

**"What sampling Hz catches 200 ms but not 100 ms?"** No single rate can produce
this, and the reason is decisive rather than arithmetic: a periodic sampler
misses by *time*, so it would drop `o` taps at the same rate as `.` taps — both
are 48 ms long. It dropped **none** of the `o` and **all** of the `.`. Put as
arithmetic: catching every 48 ms `o` needs ≥ 21 Hz, and reliably missing an
equally-long `.` needs < 21 Hz; both cannot hold.

**"Which running process could slow the kernel's sampling?"** ★ **The kernel
does not sample the panel.** `/sys/bus/i2c/devices/2-0048/input/input17/` has no
`poll_interval`; the path is interrupt-driven (`msmgpio 65 Level`, IRQ 138). A
busy process can *delay* the handler, and a delayed read still yields a contact —
late, but present. Here there is **no contact and no interrupt**, so the event is
missing upstream of anything a process could affect. Load at the time was 0.71
with nothing heavy running.

★ One thing worth noting without claiming it matters: IRQ 138 is serviced
**entirely on CPU0** (62 639 there, zero on the other seven).

## ★★★ RESOLVED — the hand drifted off the digitizer, and the instrument let it

The operator asked how far the x coordinate moved either side of the outage.
It moved a great deal, monotonically, and **both fingers moved together**.

### The `.` trajectory (the taps that vanished)

```
05:41:10.068  x=29   ┐
                     │  steady leftward drift over ~5.8 s
05:41:15.881  x= 7   ┘
05:41:16.295  x= 7      <-- last tap before the outage
              [ 1.589 s, no '.' at all ]
05:41:17.884  x= 0      <-- first tap after, the extreme value
05:41:18.340  x= 7   ┐
05:41:18.749  x=22   │  back out again
05:41:19.157  x=32   ┘
```

### And the other finger moved with it

| | `.` mean x | `o` mean x |
|---|---|---|
| before the outage | 14.9 (sd 8.9) | 241.4 (sd 11.2) |
| **during** | — none | **229.9** (sd 2.1) — its leftmost |
| after | 28.8 (sd 6.9) | **268.1** (sd 15.5) — its rightmost |

The `o` is at its leftmost precisely while the `.` is missing, and at its
rightmost immediately after. Two fingers of one hand, moving as one.

### The reading

The hand drifted left until the left finger **left the active touch area**.
Nothing was generated while it was off — no contact, no interrupt, which is why
every layer of this instrument was blind to it. The first report on the way back
is at **x = 0**, the boundary value and almost certainly a clamp, then 7, 10, 22,
32 as the hand returns.

★ This is neither a panel fault nor an operator error in any useful sense. **It
is a defect of the instrument**: the `.` target runs to x=0, i.e. to the bezel;
the app gives no indication that a tap is landing at the edge; and a finger
cannot feel where the digitizer ends. The hand walked out over six seconds and
nothing said so.

☠️ **It explains THIS event and not the 2026-09-07 17:16 one**, where the
surviving `.` sat at x=73–78 and the missing `o` at x≈286 — neither near an
edge, and with no drift. Two events, two different causes; the earlier one
remains unexplained.

### It also resolves the tension recorded above

The operator's account that a skip never exceeds 2–3 signs and the measured
seven-tap, 1.589 s outage are both correct: this was not one of their ordinary
skips at all, it was a finger that had left the sensor. The discrepancy was the
tell, and it is now closed.

### ☠️ And it retires the slow-tapping test proposed above

The operator's objection is right and the proposal is **withdrawn**. A 1.6 s
outage at one tap per second costs one or two taps, and a single missing tap is
exactly the observation that gets attributed to the finger. Fast tapping is what
turns an outage into a *run*, which is the only form in which it is legible.
Slowing down destroys the signal it was meant to isolate.

### What the instrument needs instead

1. **Inset the targets** so neither reaches the bezel, and draw the dead margin.
2. **Log every tap's x against the target bounds**, and mark one landing within
   ~15 px of an edge — the drift here was visible six seconds before the outage
   and nobody was watching that column.
3. **Warn on drift**: a monotonic trend in either target's mean x is the early
   signature, and it is cheap to compute per window.

## The instrument after 2026-09-08: the frame is drawn, and it speaks

Screenshot: `armb-frame-with-margins.png` (1080x2160, taken from the running
app with `grim`).

| boundary | margin | tone |
|---|---|---|
| left / right / top | 25 px | 432 Hz, 90 ms |
| **bottom** | **60 px** — raised, on the operator's instruction | 432 Hz |
| **either side of the vertical split** | **±20 px** | 432 Hz |
| alternation broke (BREAK) | — | 864 Hz, 150 ms |

The bottom frame is not symmetric with the others on purpose: that is where the
gesture strip and the chin are, so a downward drift runs out of sensor sooner
than a sideways one. The divider warns because crossing it does not *lose* the
tap — it files it on the **wrong side**, which appears in the record as a BREAK,
i.e. as exactly the failure this instrument exists to measure.

★ The bands are drawn from the same constants the detector uses, so the picture
and the beep cannot disagree. A frame that exists only as a threshold in code
cannot be avoided by a hand: on 05:41 the finger walked from x=29 to x=7 over
six seconds with nothing on screen marking where the sensor ends.

### Verified in pixels, not by eye

Every band edge was measured from the screenshot and lands exactly on the
constant (1080 px / 360 logical = 3.0 px per logical px):

| band | measured logical x/y | predicted |
|---|---|---|
| left ends | **25.0** | `EDGE_MARGIN` |
| divider spans | **160.0 … 200.0** | `w/2 ± DIVIDER_MARGIN` |
| right starts | **335.0** | `w − EDGE_MARGIN` |
| bottom starts | **660.0** | `h − EDGE_MARGIN_BOTTOM` |

☠️ The first scan found only three of the four, and the missing one was a
**defect of the checker, not of the drawing**: the right band composites to
`rgb(95,85,59)` over the blue half, and the warm-tint test asked for
`r > g + 12`, i.e. 95 > 97 — short by two. Measured directly afterwards and the
step is at 335 exactly. A checker that finds three of four looks like a partial
failure of the thing under test, and here it was not.

### Tones, and why they moved

Started at 216 Hz (edge) and 432 Hz (miss). The operator reported the 216 as
much quieter — the micro-speaker's rolloff below roughly 400–800 Hz, which the
source had flagged as a risk and which is now measured by ear. Both doubled at
their request, octave preserved. **A tone the transducer cannot reproduce is a
detector that silently never reports**, so the frequency belongs to the speaker,
not to the theory, and it has to be confirmed audibly before the channel is
trusted at all.

☠️ The stale `.wav` files were deleted before the restart that tested the new
ones. The app regenerates them under the same names, so without that step the
playback test would have played the **old** 216 Hz tone and been read as the
new one.

### The frame closed, 2026-09-08 06:39

Screenshot: `armb-frame-complete.png`.

| boundary | margin | why it is guarded |
|---|---|---|
| left / right / **top of screen** | 25 px | the sensor runs out |
| bottom | 60 px | gesture strip and chin - the frame is raised here |
| vertical split | ±20 px | crossing files the tap on the **wrong side**, which reads as a BREAK |
| **field top** (halves / MARK bar) | ±20 px | crossing turns a half-tap into a **MARK**, i.e. a false "operator felt a lost tap" entry in the very record lost taps are counted from |

★ The screen's top edge had **always** been a detection margin and had never
been drawn, because the bands were painted only inside the halves. An unseen
guard is the exact failure this whole change exists to fix, so it is now drawn
even though its code is unchanged.

Measured from the screenshot, scanning at x=300 (clear of text and the split):

| logical y | what | predicted |
|---|---|---|
| **25.0** | top band ends | `EDGE_MARGIN` |
| 360.0 | MARK bar begins | `h·MARK_TOP` |
| **430.0** | field-top band begins | `h·HALVES_TOP − 20` |
| 450.0 | halves begin | `h·HALVES_TOP` |
| **470.0** | field-top band ends | `h·HALVES_TOP + 20` |

☠️ **The case table found a real defect before deployment.** The divider check
had no vertical scope, so it fired for taps in the *record area* — where there
is no split at all and a tap wipes the record rather than picking a side. A
false warning there would have taught the operator to ignore the tone, which is
the one way this instrument can fail completely. It is now conditioned on
`y >= h·HALVES_TOP`. 14 cases, four of them known negatives, 0 mismatches.

☠️ And one "mismatch" the table reported was **the table being wrong, not the
code**: at (180, 10) it expected `top` and got `divider`, because x=180 sits
exactly on the split, distance 0, which really is the nearest boundary. The
rule that separates the two is that a failing case is a question, not a verdict
— read which of the two is wrong before changing either.

### MARK pulled clear of the band, 06:4x

Screenshot: `armb-frame-mark-clear.png`.

The field-top band straddles `h·HALVES_TOP`, so it lay over the bottom 20 px of
the MARK button. The button's **drawn face** now stops at
`h·HALVES_TOP − HALVES_TOP_MARGIN`, with a dark gutter between it and the band.

★ Its **hit area is deliberately unchanged** — a tap anywhere down to
`h·HALVES_TOP` still marks. The visible target is therefore strictly *smaller*
than the area that accepts it, which is the safe direction for a button sitting
against a measurement surface: aiming at what you can see can no longer stray
into the halves, and no press is lost to a shrunken target. The label is sized
and centred against the drawn face rather than the old region, so it stays
inside it.

Measured at logical x=300:

| logical y | transition | predicted |
|---|---|---|
| 360.0 | record area → MARK face | `h·MARK_TOP` |
| **430.0** | MARK face → band | `h·HALVES_TOP − 20`, **no overlap** |
| 450.0 | halves begin | `h·HALVES_TOP` |
| 470.0 | band ends | `h·HALVES_TOP + 20` |

☠️ The 450–470 pixels read `(144,159,204)` rather than the expected dark, which
is not a drawing fault: it is the right half **mid-flash** (`0.40,0.70,0.95`)
under the band's `0.45,0.45` at alpha 0.30, which composites to exactly that.
The operator was tapping while the screenshot was taken. A value that does not
match the prediction is a question about which of the two is wrong, and here it
was the prediction's assumption about the state, not the code.

### ☠️ A double press at the edge sounded like an edge tap — measured, and why

The operator reported that a double press gives the **deeper** tone. The log
settles it, and the fault was mine.

First, two things were **ruled out by measurement** rather than by reading the
code:

- **The tone files are not swapped or stale.** Measured on the device:
  `fp3-tone-edge.wav` 433.3 Hz, `fp3-tone-miss.wav` 860.0 Hz, primer peak 0.
- **The MISS tone does fire.** 124 BREAK lines carry `beep=yes` against 25
  `rate-limited`.

The cause is ordering. `_handle_tap` checked the boundaries **first** and queued
the EDGE tone before the BREAK branch could queue MISS, so a tap that was both
produced the low tone first — indistinguishable by ear from an ordinary edge
tap. And the two coincide far more often than one would guess, because a hand
that has drifted to a boundary is also a hand that mis-hits:

| | |
|---|---|
| EDGE detections | 264 |
| BREAKs | 284 |
| **BREAKs with an EDGE within 0.35 s** | **52 (18 %)** |
| closest pairs | **the same tap**, 1–2 ms apart, same x |

`edge-break-events.txt` holds the extract.

### The rule now: one tap, one tone, and MISS outranks EDGE

The edge detection is **held** rather than played, and decided at the end of the
tap. A BREAK on the same tap takes the sound and the edge line is logged as
`beep=superseded-by-miss`.

★ The reasoning, not just the fix: **being at a boundary is a standing
condition the operator can see** — the bands are drawn — **while the alternation
breaking is an event they cannot see**. The scarce channel belongs to the thing
the eye cannot supply.

☠️ `_pending_edge` is cleared unconditionally at the top of every tap. A leak
would not fail loudly; it would log a boundary with the *previous* tap's
coordinates, which reads as a genuine detection and cannot be falsified
afterwards.

☠️ **NOT YET PROVEN ON THE DEVICE.** The instance carrying this started 06:47:43
and no tap has reached it, so `superseded-by-miss` has fired **0 times**. The
change is deployed and unverified until a double press at a boundary produces
that line together with the high tone.

### ★ The precedence fix, PROVEN on the device 07:07:48

The previous section left the change deployed and unverified. It fired:

```
07:07:48.354  BREAK  . repeated, run=2  (#68)  x=95/360              beep=yes
07:07:48.354  EDGE #23  FIELD-TOP  10 px  at 95,460  beep=superseded-by-miss
```

Same millisecond, same tap, same x: the BREAK took the tone and the boundary
detection went to the log instead. The rule now holds in practice, not only in
the source.

### A third signal: the two-finger overlap

The operator reported hearing nothing when a `0` is written to the record. That
was correct — a `0` marks a tap that landed while another finger was still
down, and it had **no tone and no log line at all**, only a glyph in a strip you
would have to be watching.

It deserves both. The overlap is the condition under which taps were *actually*
being lost: GestureClick dropped **18 of 560** on 2026-09-06, every one with a
second finger already down. And it is the one fault here the operator can
correct on the spot — lift the previous finger before the next lands. It is not
rare: **17 of the 79 taps** after the 06:47 restart were overlaps, 22 %, and
nothing said so.

| signal | tone | ratio to 432 |
|---|---|---|
| EDGE — inside a margin | 432 Hz, 90 ms | root |
| **OVER — a finger was still down** | **648 Hz, 110 ms** | fifth |
| MISS — the alternation broke | 864 Hz, 150 ms | octave |

Rising with how much the operator needs to hear it. Measured on the device
after deployment: 433.3, 654.5, 860.0 Hz — gated the same way as before.

**Precedence is now MISS > OVER > EDGE**, one tap one tone, and the two that
lose still log themselves as `beep=superseded-by-<winner>`. The supersession is
**named** rather than flagged: "superseded" alone would record that a tone was
withheld without recording why, and the log is the only account of what the
operator actually heard.

### ☠️ A tone outliving its tap — the operator heard the previous tap

The operator reported a **high** tone when a `0` is written, where the overlap's
own tone is 648 Hz. The log ruled out the obvious explanation first: of 23
overlaps, `superseded-by-miss` fired **zero** times, so the OVER tone was
queued every time and the precedence rule was not at fault.

The cause is across taps, not within one. **8 of the 23 overlaps had a BREAK on
the *preceding* tap, 10–120 ms earlier**:

```
07:12:34.346  BREAK    o  (#75)  x=240/360           -> 864 Hz queued
07:12:34.393  OVERLAP  .  (#76)  x=97/360  fingers 2 -> 648 Hz queued, 47 ms later
```

A tone lasts 150 ms plus the player's startup; taps arrive every ~200 ms and
sometimes 10 ms apart. So the MISS was still sounding when the `0` appeared, and
the operator — correctly — attributed what they heard to what they saw.

**"One tap, one tone" was only ever true within a tap.** It is now true in time
as well: a new event discards anything queued and `terminate()`s whatever is
playing. The newest tap owns the speaker, which is the only rule under which a
tone can be attributed to what is on screen.

☠️ Cutting mid-tone clicks — the 5 ms fade exists only at the file's end. Taken
deliberately: a truncated tone is honest about being interrupted, a tone that
finishes in the wrong tap's moment is not.

### ☠️☠️ The gate for it failed first, and the gate was the thing that was broken

`beeper-gate.py` runs the `Beeper` class **extracted from the deployed file**.
Its first version reported `played +0, CUT +0` on every case, which reads as
"pre-emption does not work". It tested **nothing**: the regex ended the class at
the first 12-space `return False`, which is the guard on `fire()`'s very first
line, so `fire()` was extracted truncated and queued nothing at all.

This is Step 0c's trap committed while trying to satisfy Step 0c — the stand-in
was not the thing. The extraction now anchors on the next top-level definition
and **asserts that `def fire`, `put_nowait`, `terminate` and `def _run` are all
present** before running a single case, because a silently truncated extract
looks exactly like a broken subject.

With that fixed:

| case | result |
|---|---|
| **known negative** — one tone alone | `played +1`, **`CUT +0`** — not cut |
| **known positive** — three tones 50 ms apart | `played +3`, **`CUT +2`** — newest survives |
| **the measured pair** — MISS then OVER 47 ms later | `played +2`, **`CUT +1`** |

### And a defect the gate exposed in the instrument itself

The worker's `except Exception: pass` meant **a beeper that never played was
indistinguishable from one that did** — the exact failure this whole instrument
exists to prevent, committed inside it. It now counts and logs failures, and the
shutdown line carries `%d FAILED`.

☠️ **One thing is still unverified and only the operator can settle it.**
`terminate()` kills the *player*; whether the sink stops immediately depends on
what PulseAudio has already buffered. The code cuts the process — that is
measured — but "the sound stops" is not, and a 150 ms tone may be short enough
to have been handed over in full before the signal lands.

## ★★ Two tones, and the pitch carries the MEANING

The operator set the constraint from their own use: **two pitches can be told
apart without paying attention, three cannot.** An instrument that needs
attention to be read is useless during a run where the attention has to be on
the finger — and the three-tone version had failed exactly there.

So the tones no longer name the *event*. They answer the only question that
matters while tapping: **is this mine, or is it the device?**

| tone | meaning | fires when |
|---|---|---|
| **432 Hz**, 90 ms | *something went astray* — the grip | the tap landed in a margin, **or** a finger was still down, **or** the alternation broke and one of those explains it |
| **864 Hz**, 150 ms | **the fault itself** | the alternation broke and **nothing** about the hand accounts for it |
| silence | a clean tap | |

★ The rule that makes this work is that **a break is only interesting when the
hand does not explain it.** An overlap or a boundary alongside it *is* an
explanation, so that break goes low with everything else the operator can fix.
This makes the high tone rare, which is what makes it worth hearing — and it is
a narrower, more honest claim than the old MISS tone made, since the app's own
rules have always said a repeat can simply be a deliberate double tap.

Every line still carries `tone=` and `beep=`, and the BREAK line now carries
`explained=overlap|edge|NO`, so the log says which of the two a break was
counted as. The tone answers one question and cannot also say *which* boundary
was approached — one pitch serves five of them — so `EDGE` keeps its own line.

Gated before deployment on the decision block **extracted from the file**, 8
cases including the known negative (a clean alternating tap must make no sound
at all): 0 mismatches. Tones measured on the device after deployment: 433.3 Hz
and 860.0 Hz.

### What this retires

`fp3-tone-over.wav` and the 648 Hz fifth are gone, along with the
MISS > OVER > EDGE precedence ladder. The ladder was not wrong — it was
unreadable, which for an instrument is the same thing. It is recorded here
rather than deleted because the reasoning that produced it (rank by urgency)
is sound and only the assumption underneath it was false: that the operator
could resolve three pitches while attending to something else.

## ★★★ 2026-09-08 09:50:24 — the cleanest outage yet, and a NEW independent signal

Run of 2026-09-08 07:33 onward: **9 556 taps**, 70 BREAKs, of which
**59 `explained=NO`**, 5 explained by an overlap, 6 by a boundary. 137 overlaps,
26 boundary detections, 0 MARKs. Slice: `0950-slice.txt`.

The event at the end is the one this instrument was built for.

```
09:50:24.336  o  #9536  x=267        <- alternation still good
09:50:24.554  o  #9537  x=269   BREAK run=2  explained=NO  tone=caught
09:50:24.763  o  #9538  x=268   BREAK run=3  explained=NO  tone=caught
09:50:24.978  o  #9539  x=272   BREAK run=4  explained=NO  tone=caught
09:50:25.203  o  #9540  x=276   BREAK run=5  explained=NO  tone=caught
09:50:25.341  .  #9541  x=99         <- the '.' returns
```

Every circumstance that has explained a previous outage is **absent**:

| candidate | status |
|---|---|
| a boundary | x = 267–276; the right band starts at 335, the divider band ends at 200 |
| a hand drift off the sensor | the `.` sat at 79–83 before and 91–104 after, nowhere near the 25 px band |
| a two-finger overlap | none logged in the window |
| the i2c bus suspending | transitions at 09:50:15 and 09:50:28 — the bus was awake throughout |
| a driver error | no `-110`, `-6`, `-5` or `Disabling IRQ` |
| loss above evdev | the kernel delivered exactly one contact per recorded tap |

### ★ And the new signal: the surviving finger was down twice as long

This is **not** inferred from the missing taps. It is measured on the contacts
that *did* arrive, so it cannot be an artefact of the absence:

| | contacts | down-time (CONTACT→RELEASE) |
|---|---|---|
| before the run | 10 | **61.6 ms** — 67 57 74 57 51 65 68 59 51 67 |
| **during** | 4 | **127.0 ms** — 66 **167 150 125** |
| after | 7 | **51.3 ms** — 33 59 58 59 50 49 |

More than doubled, exactly across the outage, and back to normal immediately
after. And at the cadence in force (~100 ms between the two sides), a `.` would
have landed **inside** the `o`'s own contact for **three of the four**:

```
o at 24.763  down 167 ms   a '.' at +100 ms falls INSIDE this contact
o at 24.978  down 150 ms   INSIDE
o at 25.203  down 125 ms   INSIDE
```

### Three readings, and what separates them

1. **The controller merged two fingers into one reported contact.** Predicts the
   doubled down-time, the vanished second finger, no overlap logged and no
   error — all four, with nothing left over.
2. **The release is reported late** and the other finger lands in that shadow.
3. **The operator changed grip** — held one finger longer and paused the other.

☠️ Reading 3 cannot be excluded from any log, as always: a touch that produces
neither a contact nor an interrupt leaves nothing behind. But 1 and 2 are now
**testable without any judgement about the finger**, which is new.

### The next instrument, and it needs no operator testimony

`kernel-contacts.py` logs only CONTACT and RELEASE. **Add the position stream
inside each contact** — the `ABS_MT_POSITION_X` range between a contact's begin
and its release.

- A genuine long press stays near its own x (~270).
- A **merge** wanders, or jumps, toward the other half.

That single column separates reading 1 from readings 2 and 3, costs one change
to a reader already running, and asks the operator for nothing at all.

## The discriminator, built 2026-09-08 09:59

`kernel-contacts.py` logged only that a contact ended. It now logs **where it
went**:

```
RELEASE #n slot=0  x 271->268 span 4  y 1612->1620 span 9  pts 7  dur 63ms
```

`span` is the whole point. Of the three readings of the 09:50 event, the first
is now decidable **without asking the operator anything**:

- a genuine long press stays near its own x — a span of tens
- a **merge** of two fingers into one reported contact wanders or jumps toward
  the other half

The header reads the panel's own range out of the driver rather than leaving a
reader to guess the scale:

```
axes: x 0..1079 (fuzz 0, res 0)   y 0..2159   <- DEVICE units, not the app's 360 px
```

Exactly 3× the app's 360×720 grid, so `span / 3` is logical px and the halves
boundary at logical 180 sits at device **540**. A right-half contact that merged
across would show a span near that; a press wobble shows tens.

### Gated on synthetic records before deployment

`kernel-contacts-span-gate.log`. The event format is fixed by this reader's own
probe, so feeding it records whose answer is known tests the **decode**, which
is the thing under test:

| case | expected | measured |
|---|---|---|
| ordinary tap, small wobble | small span | `x 270->273 span 3` |
| **a merge, 270 → 90** | large span | `x 270->90 span 180` |
| positions with no live contact | ignored entirely | no entry |
| contact with no position | said so | `(no position reported)` |
| two slots at once | kept apart | slot 0 span 5, slot 1 span 40 |
| EVIOCGABS on a non-device | says the scale is unknown | it did |

☠️ **The gate found a crash before the device did.** A contact carrying X and no
Y raised `TypeError: unsupported operand type(s) for -: 'NoneType' and
'NoneType'` and killed the reader outright — the guard tested X alone. It would
have died on the phone with the app still running and nobody watching its
stderr, and the kernel side of a run would have been silently missing rather
than empty. Each axis is now guarded separately and an absent one prints `n/a`.

☠️ **Deployed and NOT yet exercised on a real touch.** Since the 09:59 restart
there have been **0** releases, because nobody has tapped. The decode is proven
on synthetic records and the instrument is unproven on the panel.

## The span instrument's first real answer: the merge is REFUTED

Measured 2026-09-08 10:22, over wifi (`wlan0` 192.168.100.17 — the operator
unplugged USB; `FP3_DEV_IP` overrides the wrapper's default 172.16.42.1).

**Every contact reports exactly ONE position.** `pts 1`, `span 0`, on
essentially every tap:

```
10:22:23.054  CONTACT #178
10:22:23.154  RELEASE #178  x 790->790 span 0  y 1656->1656 span 0  pts 1  dur 100ms
```

The input core drops unchanged ABS values, so `pts 1` means the reported
position never moved by a single device unit during a 100–225 ms contact.

★ **That refutes the merge reading of the 09:50 event.** Two fingers folded into
one reported contact would move its position toward the other half — device
units run 0..1079 with the divider at 540, so a merge would span hundreds. The
break tap itself, `#189`, sits at **x=769**, squarely among the other right-side
taps (754–790), and the largest span seen anywhere is **1**.

☠️ **And it is a limit of the instrument, stated plainly.** With `pts 1` the
`span` column is structurally zero and can discriminate nothing on its own. The
refutation does not rest on "the span was small" — it rests on there being **no
motion reports at all**, plus the absolute position of the break tap. Reading
the `span` column alone would have produced a confident nothing.

## The doubling is real in the kernel, and so is the slowdown

```
10:22:25.633  #187  x=296  (left)   dur 199 ms
10:22:25.900  #188  x=754  (right)  dur 215 ms
10:22:26.298  #189  x=769  (right)  dur 200 ms   <- the BREAK, explained=NO
10:22:26.904  #190  x=329  (left)   dur 225 ms
```

Two right-side contacts in a row with **no left contact between them**, so
nothing was lost between the kernel and the app.

| | #178–#186 (before) | #187–#190 (around the break) |
|---|---|---|
| down-time | 84–116 ms | **199–225 ms** |
| tap-to-tap | ~170–200 ms | **267 / 398 / 606 ms** |

Both roughly doubled, exactly there — the same signature as 09:50.

☠️ **What cannot be decided:** whether the finger slowed or the reports were
late. An evdev timestamp is taken when the driver processes the report, so a
late-serviced interrupt carries a late stamp; the two are indistinguishable from
this log. What *is* settled is that the **graphics path did not slow**:

| | 09:45–52 | 10:20–25 |
|---|---|---|
| `ges->draw` | 8.1 ms (n=731) | 8.9 ms (n=165) |
| `draw->present` | 57.7 ms (n=399) | 64.5 ms (n=101) |
| `evt->raw` | 5.8 ms | 7.8 ms |

+7 ms on `draw->present` is under half a refresh interval against a spread
several times that. It is not a result.

☠️ **`cont->raw` is NOT usable as a latency and must not be quoted as one.** It
showed 163–394 ms on the same taps whose `evt->raw` was 4–8 ms. It pairs the
last contact seen by the app's *own* evdev watch with the current GTK event, at
a 2000 ms acceptance window — two delivery paths racing inside one process. When
the GLib fd watch loses the race the pairing shifts by a tap and the number
becomes the gap between two different taps. A real 394 ms kernel delay would
have made `evt->raw` large too, and it did not.

## Freeing the rootfs, 2026-09-08 10:35

91 % → **84 %**, 216 → **356 MB** free. Safety item 9 is a reboot loop and a
frozen graphical session, and it arrives without warning.

**Preserved first, and verified, before anything was removed** — all three
scanned for IMEI, IMSI, ICCID, MAC and phone-number shapes, clean.

| | lines | where |
|---|---|---|
| `logs/journal-i2c-touch.log.gz` | 1 728 | **here** — every `i2c_qup`, himax and `PM: suspend` line the analysis rests on |
| `logs/kernel-contacts-0907-0908.log.gz` | 41 091 | **here** — the independent kernel-side witness, and the only record of the span data |
| `taptest-0907-0908.log.gz` | 119 574 | ☠️ **NOT in git** — `/mnt/1TB/pmos/fp3-raw-logs/2026-09-07_142-armB/`, md5 `cfbc4996…` |

☠️ **The app log was kept out of the repository deliberately.** At 1.44 MB it
would have been the largest tracked file in the whole tree — larger than
`findings-log.md` — while this repo's other raw captures sit at 300–430 KB. It
is also the *derivative* of the two: overwhelmingly `DRAW` and `STAGES` lines,
with every window the analysis actually uses already extracted into the small
slices beside this page. Raw data belongs in a capture; **119 000 lines of
frame-clock noise, carried forever by every clone, does not.**

| step | freed |
|---|---|
| the two superseded kernel apks, r86 and r87 (r88 kept as a rollback) | 60 MB |
| `journalctl --vacuum-size=20M` | 74 MB |
| truncating the two instrument logs | 9 MB |

☠️ **`apk` was not invoked at all.** On apk-tools 3 any operation re-solves the
world, and this port has already paid for that once — a kernel deploy carried
out 39 removals planned by a five-day-old failed upgrade. The cache is plain
files; `rm` cannot re-solve anything.

☠️ **The journal was exported before it was vacuumed**, because
`--vacuum-size` has already faked a perfect cross-boot correlation here by
deleting the evidence that would have broken it.

☠️ **And truncating a file a running process holds open was verified, not
assumed**: both fds read `flags=02402001` in `/proc/<pid>/fdinfo`, i.e.
`O_APPEND`, so writes seek to the end and no 8 MB hole is written back. Read off
the running processes, not off the source.

## ★★★ 2026-09-08 10:41:30 — the largest outage, and the constraint that narrows it

Slice: `1041-slice.txt`. Run since the 10:35 rotation: 1 599 taps, 17 BREAKs,
**16 of them `explained=NO`**, 3 overlaps, 1 boundary.

Thirteen consecutive `o`, 10:41:30.951 → 10:41:33.787 — **2.8 s** — every one
`explained=NO`, every one sounding the high tone.

### It is TWO-PHASE, and that is the new thing

```
10:41:28.058 → 30.057   perfect . o . o alternation, ~130 ms per tap
10:41:30.057  .  x=94  ┐
10:41:30.331  .  x=99  │ three '.' in a row - the RIGHT side is gone
10:41:30.595  .  x=96  ┘
10:41:30.688  o  x=284 ┐
      ... 13 'o' in a row, x=256..270 ...  the LEFT side is gone
10:41:33.787  o  x=262 ┘
10:41:33.961  .  x=99      perfect alternation returns
```

**Each hand vanishes in turn while the other reports perfectly.** The panel did
not stop working — it kept delivering one finger flawlessly throughout. And it
is confirmed on the kernel side: between 10:41:30.860 and 10:41:34.063 every
contact sits at device x = 768–851, i.e. the right half (divider at 540). No
left contact reached evdev at all.

☠️ That two-phase shape is what an operator explanation now has to account for:
pausing the right hand for half a second, then the left for three seconds, then
resuming both in perfect alternation.

### Every environmental cause is absent, and the merge is refuted by measurement

| candidate | status |
|---|---|
| a boundary | logical x 256–284 and 93–103 — nowhere near any margin |
| a hand drift | none: `.` stays 93–103, `o` stays 256–284, before during and after |
| an overlap | none in the window |
| the i2c bus suspending | transitions at 10:41:28 and 10:41:37 — awake throughout |
| a driver error | none |
| loss above evdev | none: the kernel delivered exactly the taps recorded |
| **a merge** | **refuted**: the largest span during the outage is **11** device units (~4 logical px) and every contact sits at 768–851 |

### The signature, now on its third occurrence

| | before | during | after |
|---|---|---|---|
| down-time | 75–110 ms | **176–200 ms** | 72–110 ms |

09:50, 10:22 and now 10:41. **The surviving finger's contacts last about twice
as long, every time.**

### ★ And the interrupt rate halves WITH the contacts, not against them

| second | irq | contact | irq/contact |
|---|---:|---:|---:|
| 10:41:29 | **94** | 8 | 11.8 |
| 10:41:30 | **94** | 7 | 13.4 |
| **10:41:31** | **50** | 5 | 10.0 |
| **10:41:32** | **54** | 4 | 13.5 |
| **10:41:33** | **46** | 3 | 15.3 |
| 10:41:34 | 56 | 6 | 9.3 |
| 10:41:36 | 84 | 7 | 12.0 |

★ This **excludes the driver receiving and discarding** reports: that has the
opposite signature — irq staying at ~94 while contact collapses. It did not.
The chip produced fewer reports; the driver turned every one of them into an
event.

☠️ **On its own it is circular** — half as many touches give half as many
interrupts whether the controller missed them or the hand did not make them.
What the hand does *not* explain is the pair of facts either side of it: the
surviving hand's rhythm is **unchanged** (`o`→`o` 258 ms against a 270 ms cycle
before) while that same hand's contacts last **twice as long**.

### The measurement that removes the operator from the question entirely

Every ambiguity in this whole investigation has the same root: a touch that is
not reported leaves nothing, so "the finger did not tap" and "the panel did not
see it" are indistinguishable. **A held finger has no such ambiguity.**

> One finger rests **continuously** on one half — not tapping, held. The other
> taps as usual.

A held contact cannot fail to happen. If it is released while the finger is
still down, that is a device fault with no judgement about the operator in it at
all — and if it survives while the tapping finger's touches vanish, the
controller is dropping to one *tracked* contact rather than losing touches. Both
outcomes are readable straight off `kernel-contacts.log`, and neither needs the
operator to say what their hand was doing.

## ★ The held-finger control, 2026-09-08 10:47:54 — the instrument works, the fault did not appear

Slices: `held-finger-slice.txt`, `held-finger-window.txt`.

The operator held one finger down while tapping with the other, as asked.

```
10:47:59.989  RELEASE  slot=0  x 247->274 span 37  y 1595->1616 span 21  pts 34  dur 5657ms
```

**One contact, 5 657 ms, never released.** At device x 247–274 it is the left
half (divider 540), with 34 position samples and a 37-unit span — ordinary
finger micro-movement. Meanwhile the tapping finger ran in **slot=1**: 19
contacts, 49–110 ms each, not one of them lost.

★ So **the controller does not drop a held contact**, and it tracks the two
fingers in separate slots correctly. That is the control this test needed and it
passed.

### ☠️ But no outage occurred while the finger was held

The tapping finger's down-times stayed 49–110 ms throughout — no trace of the
doubling that marks an episode. **The discriminating observation is still
outstanding.** The test proves the instrument, not the hypothesis: it needs to
run until an episode happens *with the finger down*.

### ★ New: the interrupt rate depends on a finger being PRESENT

| regime | irq/s |
|---|---:|
| two tapping fingers (ordinary) | ~94 |
| **one held + one tapping** | **~120** |
| **during an outage** | **~50** |

A finger resting on the panel keeps the controller out of its idle scan, so the
rate goes *up*. That gives an argument about the outages: if the missing finger
were physically present and sensed but simply not reported, the chip would be in
active scan and the rate would be **high, like the held case**. Instead it falls
**below both** normal regimes.

☠️ **An argument, not a proof.** The same low rate follows just as well from
there genuinely being fewer fingers on the panel. It narrows "sensed but not
reported"; it does not settle anything.

### Two side observations worth keeping

- `gest` read **0** in every window while a finger was held, against `tap` of
  4–5. GTK's `GestureClick` handles one sequence at a time, so it delivered
  nothing at all — and the measurement survived only because the app takes its
  taps from the **raw touch**, a design change made on 2026-09-06 for exactly
  this reason. It is vindicated here.
- ☠️ **`CONTACT #n` and `RELEASE #n` do not pair.** They come from two separate
  counters in `kernel-contacts.py`, so the same number in the two lines refers
  to different contacts. It reads as a matched pair and is not one. Worth
  fixing, at the cost of restarting the reader — which would end a held-finger
  run in progress, so it waits.

## ☠️☠️ RETRACTED: the halved interrupt rate does NOT exclude the driver

The 10:41 section above says the interrupt rate falling *with* the contacts
"excludes the driver receiving and discarding reports, which has the opposite
signature". **That is wrong, and the driver's own source says why.**

```c
devm_request_threaded_irq(dev, client->irq, NULL,
                          himax_irq_handler, IRQF_ONESHOT, ...)
```

`IRQF_ONESHOT` on a **level-triggered** line keeps the interrupt **masked from
the hard-IRQ until the threaded handler returns**. So the interrupt count does
not measure how often the chip had data — it measures **how often the driver was
free to notice**. A handler that takes twice as long halves the count with the
chip behaving identically.

★ And the same lengthening explains the rest of the signature at once: a touch
that begins *and ends* inside the masked window is never reported, and a release
noticed one long handler-cycle late stretches the contact's measured duration.
One mechanism, all three observations.

The claim is kept above rather than deleted, because the reasoning that produced
it — "an absorbed event would leave irq high while contacts fall" — is correct
for an *unmasked* line and was applied without reading how the IRQ is requested.

## Four ways an interrupt produces no touch, and three of them are silent

Read out of `himax_hx83112b.c`, not inferred:

| path | what it does | trace |
|---|---|---|
| the read fails 3× | `HIMAX_READ_RETRIES` exhausted | `dev_err_ratelimited` — **visible** |
| the read fails once or twice, then succeeds | the `do/while` retries | ☠️ **silent**, and 2–3× the handler time |
| the checksum fails | `return 0` | ☠️ **completely silent — no log at all** |
| zero points in the event | nothing reported | `dev_dbg` — currently **off** |

plus the special case a previous session already instrumented: an **all-zero**
buffer passes `himax_verify_checksum()` trivially, because that sums the bytes
and only requires the low byte of the sum to be zero. Its comment describes this
very investigation — *"taps vanish with the panel otherwise healthy, and the
only evidence is an interrupt that produced no frame"*.

### What the existing instruments say about the three outages

The journal is retained from 01:15 today, so it covers 09:50, 10:22 and 10:41:

| | count |
|---|---|
| `all-zero event accepted by the checksum` | **0** |
| `Failed to read input event` | **0** |

★ So the **all-zero path is refuted** for these outages, and the retry **never
exhausted**. What remains open is precisely the two silent paths: a retry that
*succeeded* on the second or third attempt, and a checksum that failed and was
discarded without a word.

## The instrument for it, armed 2026-09-08, no rebuild and no flash

`himax_handle_input` is **inlined** — absent from `kallsyms` and from
`available_filter_functions`, as a `static` function with one caller. The two
that matter are there:

```
p:hx_rd    himax_read_events            r:hx_rd_r  himax_read_events  ret=$retval
p:hx_irq   himax_irq_handler            r:hx_irq_r himax_irq_handler  ret=$retval
```

- **`himax_read_events`** is the i2c read itself. Its **return value** is the
  silent retry made visible: a non-zero return that is followed by another entry
  *is* path 2, and nothing else in the system records it.
- **`himax_irq_handler`** entry→return **is the masked window**, measured
  directly rather than inferred.

Armed with a 2 MB/cpu ring buffer in overwrite mode — **nothing is written to
disk**, which matters at 85 %. All four probes confirmed present and not
disabled in `/sys/kernel/debug/kprobes/list`.

☠️ **Not yet seen firing.** Five seconds of tracing produced only the header,
because nobody was touching the panel. A probe that has not fired has proved
nothing, and the buffer holds roughly two minutes at the observed rate — so it
has to be read while an episode is still recent.

☠️ **The observer effect, stated:** a kprobe costs a microsecond or two against
a handler that takes milliseconds, so roughly 0.1 %. It is on the path being
measured, which is unavoidable here, and small enough not to create the
lengthening it is looking for — but the durations it reports include it.

## ★★★ 2026-09-08 11:25 — the kprobes fired, and they refute BOTH driver mechanisms

Trace window: `hx-kprobe-window.txt.gz` (the 15 s around the outage, from a
234 s / 18 689-interrupt ring buffer). The outage: **18 consecutive `.`**,
x=102–111, all `explained=NO` — this time the *right* side vanished.

### Every read succeeded on the first attempt

| | |
|---|---|
| `himax_read_events` returns in the window | **455, every one `ret=0x0`** |
| `hx_rd` entries vs `hx_irq` entries | **454 / 454** — exactly one read per interrupt |
| `himax_irq_handler` returns | 455, all `0x1` = `IRQ_HANDLED` |

★ The `do/while` retry loop **never iterated once**. So the **silent retry is
refuted** for this outage, and so is the exhausted retry. Nothing in the driver's
read path misbehaved.

### And the masked window did not lengthen — the ONESHOT mechanism is refuted too

Handler entry→return, by second (95667–95671 **is** the outage):

| t | n | median | p90 | max |
|---|---:|---:|---:|---:|
| 95660 | 98 | 6.215 ms | 6.820 | 7.607 |
| 95665 | 45 | 6.010 | 6.572 | 7.336 |
| 95666 | 44 | 6.031 | 6.662 | 6.892 |
| **95667** | 53 | **6.206** | 6.688 | 7.310 |
| **95668** | 50 | **6.066** | 6.422 | 6.892 |
| **95669** | 55 | **6.110** | 6.446 | 6.976 |
| **95670** | 39 | **6.048** | 6.510 | 7.117 |
| **95671** | 59 | **6.158** | 6.805 | 7.831 |

**Flat at 6.0–6.2 ms throughout**, maximum 7.8 ms anywhere. The i2c read is
6.0 ms of that 6.2, so the handler *is* the read.

☠️ **That retires the hypothesis this instrument was armed to test** — the one
retracted into two sections above. The masked window is constant, so the ONESHOT
confound is now measured rather than argued, and with it excluded the earlier
observation stands after all: **the interrupt rate fell from ~98/s to ~50/s with
the handler unchanged, so the chip asserted less often.** The reduction is on the
controller's side.

★ Worth noting for its own sake: at 98 irq/s and 6 ms each, the line is masked
**59 % of the time** in ordinary two-finger tapping. The ceiling is ~166/s.

### ★★ The operator's prediction, made before the data was looked at

Unprompted, mid-analysis: *"két 3s alvás után visszatérve jön elő"* — it comes
out after two three-second sleeps, on returning. The trace has exactly that:

```
95654.846 -> 95659.601   4.76 s with no interrupt at all
95661.116 -> 95665.122   4.01 s with no interrupt at all
        outage 95667 - 95671, about 2 s after tapping resumed
```

and the bus tracked the pauses: `11:25:37 suspending → 11:25:41 resuming →
11:25:43 suspending → 11:25:46 resuming`, then the outage.

**All four outages of the day follow a bus resume:**

| outage | preceding resume | delay |
|---|---|---|
| 09:50:24.5 | 09:50:15 | 9.5 s |
| 10:22:26.3 | 10:22:18 | 8.3 s |
| 10:41:30.9 | 10:41:28 | 2.9 s |
| 11:25:49 | 11:25:46 | 3.0 s |

☠️ **Four events are not statistics, and the base rate is missing.** If the bus
resumes often and outages are rare, "every outage follows a resume" is close to
guaranteed. What that objection does *not* touch is that **the operator stated
the pattern before anyone looked** — it is a prediction that held, not a shape
found in the data afterwards.

☠️ **And two of those four rows were recovered from the preserved extract, not
from the phone** — the 09:50 and 10:22 bus lines were deleted by this session's
own `journalctl --vacuum-size` at 10:35. Exporting them first was the only
reason the pattern could be tested across four events instead of two. The rule
paid for itself within the hour.

### The A/B that settles it, and it needs one write

```sh
echo on > /sys/bus/platform/devices/78b7000.i2c/power/control
```

Runtime PM off, the bus never suspends, the operator taps as usual with the same
pauses. **Outages stop** ⇒ the transition is in the path. **They continue** ⇒ the
bus is not, and what idles is the controller itself. Reversible with `auto`, no
rebuild, no flash, and it does not need the operator to judge anything.

## 2026-09-08 11:33 — a fifth outage, the tightest correlation yet, and one lost to my own freeze

`1133-slice.txt`. Nineteen consecutive `.`, 11:33:41.885 → 11:33:44.861,
x=106–120, all `explained=NO` — nineteen high tones, which is what the operator
heard.

```
11:33:28  suspending      12 s of idle
11:33:40  resuming
11:33:41.885 - 11:33:44.861   the outage, 1.9 s after the resume
11:33:48  suspending
```

And the rate halves and recovers on the second the alternation returns:

| second | irq | contact |
|---|---:|---:|
| 11:33:41–44 (the outage) | **51–57** | 4–5 |
| **11:33:45** | **104** | 9 |
| 11:33:46 | 100 | 9 |

**Five of five outages follow a bus resume**, by 1.9 – 9.5 s.

☠️ **This one has no kprobe data, and that is my fault.** I froze tracing at
11:26 to read the buffer and never re-armed it. The freeze was not even
necessary: reading `/sys/kernel/tracing/trace` gives a consistent snapshot with
tracing still on. **An instrument switched off to be read is an instrument that
will be off for the next event** — re-arm in the same command that reads, or do
not stop it at all. Re-armed 11:39 with the buffer cleared.

## The A/B, armed 2026-09-08 11:40

```sh
echo on > /sys/bus/platform/devices/78b7000.i2c/power/control
```

Verified to bite before anything is claimed from it: `control` reads `on`,
`runtime_status` stayed `active` through 8 s of no touching where it had
previously suspended within a second or two, and the journal has logged **zero**
further `suspending` lines. Accumulated `runtime_suspended_time` before the
change was 91 926 757 ms, so the bus really had been spending its life asleep.

☠️ **This is a gated before/after, NOT an A-B-A′.** The lever changes the world:
once runtime PM is off there are no resumes to return to, so the third leg would
be a second B. The A leg is what today already measured — five outages across
roughly two hours of intermittent tapping with `control=auto` — and the gate on
it is satisfied by measurement rather than assumption: the bus demonstrably did
suspend, and every one of the five outages followed a resume.

☠️ **And the exposure cannot be counted in resumes**, because the B leg has
none. The trigger the operator identified is a *pause*, and pauses are their
behaviour, identical in both legs. So the comparison is **outages per idle gap
> 2 s**, counted from the tap log on both sides — not per hour, and not per
resume.

☠️ **Revert when done**: `echo auto > …/power/control`. Holding a QUP out of
runtime suspend costs power continuously, and this device's power figures are
the subject of half the captures in this directory. Leaving it on would quietly
poison the next idle-current measurement, and nothing about the file says so.
