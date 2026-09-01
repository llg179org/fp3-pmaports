# ★★★★★ The oracle is still at 6.9 % — and it is cheap on the band that costs us the most

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed the measurement it rests on.

2026-09-01, both slots inside 27 minutes, the same instrument
([`../../tools/modem-window.sh`](../../tools/modem-window.sh), md5-verified
identical on both), one 600 s window each, same operator (216-70), same
neighbourhood of cells.

The run exists because a plan review pointed out that **the 6.1 % oracle figure
was days old**, and the entire "persistent device state" hunt rests on it still
being true. Pre-registered: oracle still ~6 % ⇒ a real stack difference; oracle
now 30 %+ ⇒ the reference is stale and the hunt stops.

## Result: the reference is alive, and the band is not the explanation

| | pmOS (slot b) | oracle / Ubuntu Touch (slot a) |
|---|---:|---:|
| window | 17:00:30 → 17:10:31 | 17:15:33 → 17:25:33 |
| kernel | 7.1.3 mainline `#80-fp3` | 4.9.218 `-perf-ubuntutouch+` |
| **MPSS awake** | **37.4 %** | **6.9 %** |
| MPSS XO shutdowns | 1431 (**2.38 /s**) | 1886 (**3.14 /s**) |
| **mean awake time per wake** | **157 ms** | **22 ms** |
| LPASS awake | 100 % | **3.1 %** (14.19 shutdowns/s) |
| PRONTO awake | 27.5 % | 22.5 % |
| serving cell | 1470722 | 1470722 → 1470762 |
| band | eutran-20 (6200), RSRP −85.6 dBm | *(not readable — see below)* |

**6.9 % against 6.1 % measured on 2026-08-28.** The reference is not stale; the
oracle runs a registered, attached LTE modem at that duty today, on this network,
on this hardware.

☠️ **And the band does not explain the stack gap.** Today's
[band ladder](../2026-09-01_band-ladder/README.md) priced cell 1470722 (eutran-20)
at 34 % and cell 1470762 (eutran-1) at 50 % *on pmOS*. The oracle window **spans
both of those cells** — it started on 1470722, the cheap one pmOS was also on,
and ended on 1470762, the expensive one — and read 6.9 % across them. So the
band is a real 17-point effect **within** our stack and explains nothing about
the 30-point gap **between** the stacks.

## ★★ The sharpest statement of the problem so far

The two stacks wake the modem at the **same rate** — 2.4 and 3.1 XO exits per
second, the oracle slightly *more* often. What differs is how long it stays up:
**22 ms per wake on the oracle, 157 ms on ours, a factor of seven.** Every
earlier arm that found "the rate is flat, the length changes" was seeing one side
of this; here it is measured across the stacks in one afternoon.

★ **And the ADSP splits the same way**: 3.1 % awake on the oracle at 14 XO
shutdowns per second, against 100 % awake and zero shutdowns on pmOS with
ModemManager running — the other side of
[`../../leads/lpass-never-sleeps.md`](../../leads/lpass-never-sleeps.md),
measured on the vendor stack for the first time in this form.

## ☠️ What this run does not say

- **No current comparison.** The oracle charges normally with the cable in
  (4.048 → 4.110 V, capacity 68 → 71 % across the window) while the pmOS side
  runs with `USBIN_SUSPEND_BIT` set. The two sides' currents are not comparable
  and none is quoted.
- **The oracle's band was not read.** Ubuntu Touch has no `qmicli` and no
  `qrtr` — only `/dev/smdcntl0` — so the QMI block reported `☠️ NO QMI TRANSPORT
  ANSWERED` and fell back to ofono, which gives the cell but not the band or
  RSRP. The band above is inferred from the cell IDs measured on the pmOS side
  the same afternoon, not read on the oracle.
- **Both are awake windows.** Neither side was suspended, so these are duty
  figures for an awake AP, which is what makes them comparable to each other and
  to the band ladder — not to the overnight sleep census.

## Where the search goes now

The reference holds and the network is eliminated as *the* explanation, so the
30-point gap is a **stack** difference, and it has a shape: **our wakes are
seven times too long at the same wake rate.** That is what the remaining
candidates have to explain — the carrier/PDC configuration the vendor stack
applies, the RAT list that makes the UE run inter-RAT measurements inside every
DRX cycle, or an IMS registration our side never performs.
