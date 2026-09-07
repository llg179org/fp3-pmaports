# #142 — the affinity commit, Bert's touchscreen, and what the dates already settle

**2026-09-07**, pmOS `linux-fp3-7.1.3-r88`, source `6113869dcc3d`, branch
`debug-int/7.1.3`.

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, whose finger is the measurement this task needs.

## ★ First: the phone already runs the commit under suspicion

`git merge-base --is-ancestor 0314fee3ce35 debug-int/7.1.3` says **no** — and
that is the twin structure, not an absence. The value is there:

```
$ git show debug-int/7.1.3:arch/arm64/boot/dts/qcom/msm8953.dtsi | grep -A1 system-pc
    idle-state-name = "system-pc";
    arm,psci-suspend-param = <0x42000353>;
```

| branch | commit carrying `0x42000353` |
|---|---|
| `wip/7.1.3/power` | `0314fee3ce35` (the original) |
| `integration/7.1.3` | `1ac2e21fbf3a` |
| `debug-int/7.1.3` | `0740bfb33b77` ← **what the phone runs** |

☠️ **`1ac2e21fbf3a`, the hash Bert bisected to, is OUR `integration/7.1.3` twin**
— not a commit in some tree of his own. He is testing this port's branch. Any
measurement we take is therefore already on the *after* side of his revert; there
is no "before" on this phone unless one is built.

## ★★ The dates, which reframe the question

| commit | date | what it does |
|---|---:|---|
| `1ac2e21fbf3a` | **2026-08-17** | system-pc affinity 1 → 2 (the bisect result) |
| `cd2745d8d321` | **2026-09-04** | `Input: himax — hold the rails the touch half runs on` |
| `c508e99b9fa9` | **2026-09-04** | `dts: fp3 — give the touchscreen its supplies` |
| `fb68b1bd764f` | **2026-09-05** | `Input: himax — retry a failed event read` |
| `58f135a76e46` | **2026-09-05** | `Input: himax — do not let a failing read disable the interrupt` |

**Every protection on the touch path postdates the bisect point by 18–19 days.**

### The candidate mechanism, in the rail fix's own words

`cd2745d8d321` exists because of a signature measured on this phone, and its
commit comment describes Bert's failure line for line:

> *"with the display off, the panel drops the rail, the controller stops driving
> the bus, and the next transfer holds both lines low until the QUP transfer
> timeout expires — 15 s on that board — after which the driver reports
> `-ETIMEDOUT` and drops the touch."*

`-ETIMEDOUT` **is** `-110`, his first line; `-ENXIO` is `-6`, his second. These
are TDDI parts — one die drives display and touch, both halves on the panel's
rails — and before `c508e99b9fa9` the board DT declared no supply at all, so the
driver took the dummy regulator and the panel driver's vote was the only one.

## ☠️☠️ WITHDRAWN before it was ever measured: "the affinity change is the enabler"

The paragraph that stood here proposed that the affinity change is not the fault
but the **enabler** — that raising the level is what makes the system actually
reach collapse, so the unheld panel rail really goes away. It was written from
the commit dates alone, without reading this port's own prior capture, and that
capture had already answered it **by measurement** three days earlier.

★ **The rule this breaks is the one this session put into `/msm8953-mainline-pr`
that same morning**: search for existing work before writing, and search again
when done. It was applied to the outside world (ModemManager, `#182`) and not to
this repository, which is where the answer was. Half a rule is what produced a
plausible hypothesis in a question that was already settled.

## What [`../2026-09-04_142-touch-after-resume/`](../2026-09-04_142-touch-after-resume/) already measured

On `#80-fp3`, **before** any of the four touch fixes existed:

| gate | measurement | strength |
|---|---|---|
| **screen OFF** | 5/5 stalls against 0/5 with it on, interleaved, identical 12 s idle | p ≈ 0.004; 7/7 v 0/7 with reruns |
| **idle ≥ ~10 s** | threshold between 3 s and 10 s; 0/52 688 at 0.02 s spacing, 1/3 at 45 s | the strongest effect of the day |
| not a fresh boot | one observation each way | the weak leg |

and the root cause, read straight out of `regulator_summary`:

> `l6` has **exactly one consumer**, the panel's `iovcc`, and it drops its vote
> when the display is powered down. `touchscreen@48` declared no supply at all,
> because `trivial-touch.yaml` cannot carry one.

☠️ **And the affinity commit was explicitly excluded there, by measurement**:

> *"the first failure came 324 s after the resume … the second 47.6 s after the
> first, with no sleep of any kind. A resume cannot explain an event that happens
> twice, minutes apart, without one. `0314fee3ce35` is therefore not the cause of
> what we measured here."*

Stronger still, `armB-clean-boot-trial2.txt` is a clean boot **on the suspect
`0x42000353`**, with a real suspend/resume and ~513 post-resume touch interrupts,
and **no `-110` at all**.

So on this device the fault is **screen-gated and idle-gated, not
suspend-gated**, and a suspend is merely a reliable way to turn the display off.
The hold on the commit stays for the reason that capture already gave — *"it is
no longer 'we suspect this commit', it is 'we cannot yet explain his
observation'"* — and the dates section above is what makes his observation
explicable at last, since none of the three rail commits existed when he bisected.

## ★ The measurement that is actually outstanding, and it needs no finger

`ROOTCAUSE-the-panel-owns-the-rail.md` closes with the one thing it could not do:

> ☠️ **NOT yet verified: that it actually fixes the phone.** The confirming run is
> `142-trigger.sh` on a kernel carrying these commits, and that needs a build and
> a flash.

**That flash has happened.** The phone runs r88, which carries all three, so the
pre-registered run is available now — and it is **pre-registered**, which is what
makes it worth more than a fresh instrument: *screen-off must go from 5/5 to 0/5
over five interleaved rounds.*

★ It also satisfies the new-instrument gate on its own terms: `142-trigger.sh`
has already answered a question whose answer is on record (5/5 v 0/5 on
`#80-fp3`), so a null from it now means the fix worked, not that the instrument
was pointed the wrong way.

☠️ **Correction to this page's own earlier claim that the test "cannot be run
unattended".** That is true of the *driver-bound* question — real touches after a
real resume — because `himax_resume()` does no i2c and no touch means no event.
It is **not** true of the pre-registered run: `142-trigger.sh` drives the screen
over phosh's `org.gnome.ScreenSaver` D-Bus interface and probes an unused i2c
address with the driver unbound. It needs the phone awake and phosh alive, and
nothing else.

Two different measurements, and only the second needs a person:

| | instrument | driver | needs | settles |
|---|---|---|---|---|
| **A** | `142-trigger.sh` | unbound | phone awake | whether the rail fix removed the stall |
| **B** | tapping after a real suspend | bound | a finger, minutes of it | whether ordinary use is now clean |

☠️ **Before running A: disarm the idle-suspend drop-in.** `#182` left
`IdleActionSec=2min` in place, and A blanks the screen for 12 s per round over
~7 minutes — logind would suspend the phone in the middle of it.

☠️ **The risk A carries** is in its own header: rebinding the Himax with the
screen off returns `-5` and leaves the phone without a touchscreen — five reboots
in one day on 2026-09-04. The script now always rebinds screen-on and arms a
reboot after three failed tries.

---

# ARM A, run 2026-09-07 08:52–08:56 on `#89-fp3` (r88), clean boot

```
round 1 OFF screen=Off  first transaction after unbind:  2.0485 s errno 5  >>> STALL
round 1 ON  screen=On   first transaction after unbind:  0.0007 s errno 6  ok
round 2 OFF                                              2.0467 s errno 5  >>> STALL
round 2 ON                                               0.0007 s errno 6  ok
round 3 OFF                                              2.0526 s errno 5  >>> STALL
round 3 ON                                               0.0007 s errno 6  ok
round 4 OFF                                              2.0487 s errno 5  >>> STALL
round 4 ON                                               0.0007 s errno 6  ok
round 5 OFF                                              2.0499 s errno 5  >>> STALL
round 5 ON                                               0.0008 s errno 6  ok

screen OFF: 5/5      screen ON: 0/5
```

## ☠️☠️ The pre-registered criterion CANNOT be met by this instrument — measured, not argued

The registration said *screen-off must go from 5/5 to 0/5*. It stayed 5/5, and
that is **not** a verdict on the fix: `142-trigger.sh` **unbinds the touch
driver as its first action**, and the rail fix *is* the driver's
`devm_regulator_bulk_get_enable()` vote. devm releases it on unbind. Read
straight out of the same `regulator_summary` that found the root cause:

| state | `l6` | consumers |
|---|---|---|
| driver **bound** | `use=2 open=2` | `2-0048-iovcc` **and** `1a94000.dsi.0-iovcc` |
| driver **unbound** | `use=1 open=1` | only `1a94000.dsi.0-iovcc` — **the touch vote is gone** |
| after rebind | `open=2` | `2-0048-iovcc` back |

**The instrument's first move removes the thing it was registered to test.** The
registration was written on 2026-09-04, before the fix existed, so this could not
have been foreseen then — but it means arm A can never answer that question, and
no number of repetitions will change it.

★ It is worth being precise about what a 5/5 here does and does not mean. It is
**not** "the fix failed". It is "with no voter for the rail and the display down,
the bus still stalls" — which is the root cause **re-confirmed on r88 by a second
independent route**, since the vote structure was this time read out directly
rather than inferred.

## ★ What arm A DID measure, and it is a number #179 could not produce

| | 2026-09-04, `#80-fp3` | 2026-09-07, `#89-fp3` (r88) |
|---|---|---|
| screen-off arm | **5/5** stalled | **5/5** stalled |
| stall duration | **15.07 s** | **2.05 s** |
| errno | **110** (`-ETIMEDOUT`) | **5** (`-EIO`) |
| screen-on arm | 0/5 | 0/5 |

Five rounds spanning 2.0467–2.0526 s — a spread of **6 ms**, so this is a
*constant*, i.e. a timeout being hit, not a variable fault. `MECHANISM-qup-timeout.md`
decomposes the old one as 2 s + 131072 × 99 µs = 14.98 s; **the 2 s base survives
and the long tail is gone.** That is the i2c-qup bus-clear recovery firing where
the driver previously waited out the whole transfer timeout.

So the worst case for a dead bus on this board went from **15 s to 2 s**, and the
error the driver sees changed from `-110` to `-5`. #179 established that the
cascade was gone but explicitly could not measure a rate or a duration; this is
the duration, from a deterministic trigger rather than from ordinary use.

☠️ It is measured **with the driver unbound**, which is not a state ordinary use
reaches. It bounds the bus's behaviour, not the driver's.

## What is still outstanding — and it does need a finger after all

☠️ **Correction to this page's own earlier correction.** It said the outstanding
measurement needs no person. That is now wrong for a deeper reason than the first
version was: the rail fix can only be exercised **with the driver bound**, and a
bound driver only touches the bus when a finger fires its interrupt.

Arm B stands as the only test of the fix:

> after a real suspend, with the driver bound, does the panel respond to touch —
> and do `-110`, `-6` or `Disabling IRQ` appear during **minutes** of tapping?

The `#178` exposure floor applies: fewer than 500 touch interrupts means nobody
touched it, and the 09-04 rate was roughly one `-110` per minute of active
tapping. Seconds of tapping prove nothing.
