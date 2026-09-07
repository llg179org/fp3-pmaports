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

**Hypothesis, labelled as such and untested:** the affinity change is not the
fault but the **enabler**. Its own commit message says the RPM previously held the
AP's active vote for the whole of every boot (`Shutdown count 0`); raising the
level is what makes the system actually reach collapse — and a system that really
collapses is one where the unheld panel rail really goes away. The revert cures
the symptom by never getting deep enough to expose it.

☠️ **If that is right, what Bert needs is `cd2745d8d321` + `c508e99b9fa9`, not a
revert — and the affinity patch is sendable.** If it is wrong, the affinity
commit has a fault of its own and `#149` must keep holding it back.

### ☠️ The one fact that decides between them is not ours to look up

**Which of the five commits above Bert's tree carried is unknown.** His report
says he reverted `1ac2e21fbf3a` and the touchscreen recovered; it does not say
whether the 09-04/05 touch fixes were present when he did. Both readings fit what
he wrote:

- tree **without** them → the hypothesis stands and is nearly proven by the dates;
- tree **with** them → the fixes do **not** mask it, the hypothesis is dead, and
  the affinity commit has a real fault.

It is one `git log` on his side. It belongs in the next mail (`#154`), and until
it is answered no amount of measuring here can distinguish the two.

## What our own phone can and cannot say

☠️ **The passive evidence is empty, and #179 could never have supplied it.**

- `himax_resume()` calls `enable_irq()` and **nothing else** — it does no i2c. So
  a `-110`/`-6` cannot appear at resume on its own; it takes a real touch to fire
  the interrupt. **This test cannot be run unattended.**
- The boot of 2026-09-07 (8 h 53) shows `Failed to read input event` **0 times**
  — with **70** touch interrupts in total. Check 59's floor is 500: that reads
  "nobody touched it", not "clean".
- #179's 184 clean active minutes carry **no suspend/resume information at all**
  — its sampler has no such column — so they say nothing about a post-resume
  failure whatever they say about the cascade.

So the r88 evidence that #142 was written to lean on does not reach the question,
and the measurement still has to be made.

## The measurement, and why it is cheap right now

The phone is in the configuration `#182` left behind — `IdleAction=suspend`,
`IdleActionSec=2min` — so it suspends on its own within minutes of being put
down. That is the regime this test needs and it will not be cheaper later.

`touch-resume-probe.sh` (beside this page) prints one snapshot; the **difference**
between a snapshot taken before the suspend and one taken after the tapping is
the measurement. The criterion is the one a finger can answer:

> After a real suspend, does the panel respond to touch at all — and do `-110`,
> `-6` or `Disabling IRQ` appear while it is being used?

☠️ **The ambiguity to keep in view**: `HIMAX_READ_RETRIES` is 3, so a transient
failure now leaves *no log line* — "zero errors" is ambiguous between "no faults"
and "faults absorbed", exactly as `#178` states. It does not weaken this test,
because Bert's failure is a **persistent loss** (`-6` = the device is gone), which
no three-attempt retry absorbs.
