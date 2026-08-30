# 2026-08-30 — the oracle's APSS never parks the crystal either

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

**Command:** `cat /sys/kernel/debug/rpm_master_stats` on slot_a (Ubuntu Touch,
`4.9.218-perf-ubuntutouch+`), read twice, at 120 s and 394 s of uptime.
**Compared against:** the pmOS reading of the same counter taken this morning
across a real 601 s suspend (`captures/2026-08-30_xo-across-suspend/`).

## The reading

| | oracle (UT, slot_a) | pmOS (slot_b) |
|---|---|---|
| `APSS xo_count` | **0x0** | **0** |
| `APSS xo_accumulated_duration` | **0x0** | **0** |
| `APSS xo_last_entered_at` | **0x0** | **0** |
| `APSS numshutdowns` | 0xc28 → 0x4aed (3 112 → 19 181) | 485 401 |
| MPSS `xo_count` | 0x116 (278) | large, non-zero |
| PRONTO `xo_count` | 0x1ff (511) | large, non-zero |
| LPASS `xo_count` | 0x234 (564) | large, non-zero |

The counter works — every other master reports non-zero XO shutdowns on both
systems. It is **APSS specifically** that reads zero, and it reads zero on
**both** sides.

## What this closes

This morning's write-up called the pmOS zero *"the sub-50 mA row of the goal's
arithmetic"* — the application processor never letting the crystal go, on a
system that had finally stayed asleep for 600 s at a time. That reading is
**withdrawn**: the system we are trying to beat, at 6.1 % modem duty and ~63 mA,
does exactly the same thing.

⇒ **The X-track closes.** Getting APSS to park the XO vote, or getting the RPM
to a deeper corner, cannot be what separates the two systems, because the
cheaper system does not do it. Whatever the oracle's 63 mA is made of, it is not
made of this.

## ☠️ And the `vlow` question cannot be settled against an oracle at all

`leads/rpm-sleep-set.md` named this trip's purpose as *"the one control still
unrun, the oracle with USB detached: whether a working system ever reaches
`vlow` on this SoC at all."* It cannot answer that, for a reason that is a
property of the oracle rather than of the experiment:

```
# ls /sys/kernel/debug/rpm_stats
ls: cannot access '/sys/kernel/debug/rpm_stats': No such file or directory
```

The downstream 4.9 kernel does not build `rpm_stats.c`, so **the oracle has no
`vlow`/`vmin` counter**. There is no same-instrument comparison to make, and the
rule this project keeps re-learning — ask both sides the same question with the
same instrument — forbids substituting a different counter and calling it an
answer.

What the oracle does expose is `lpm_stats`, and its deepest system state is
reached often:

```
[system] system-pc:
  success count:     674
  total success time: 6.633389980
  failed count:      31
```

674 entries totalling **6.63 s** in roughly 300 s of uptime — about **2 %**
residency, in entries averaging ~10 ms. That is a cpuidle system power-collapse
counter, **not** the RPM voltage-corner counter our `vlow` reads, and it is
recorded here as context, not as the differential.

## Method note

The write-up above is the second attempt. The first read `system-pc: 674` and
started to conclude that "a working system does reach the deepest state here,
so our zero is a defect" — across two different counters on two different
kernels. The thing that stopped it was checking whether the oracle had the file
at all before comparing against it.
