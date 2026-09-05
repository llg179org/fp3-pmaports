# #157 — the i2c-qup timeout fix, measured against its own known-positive

Date: 2026-09-05 19:05–19:07. Kernel r83 (`_commit=9af3de4d21f2`, `uname -v`
`#84-fp3`), phone on WiFi, operator present.

## What was compared against what

The same script, unchanged: `../2026-09-04_142-touch-after-resume/142-trigger.sh`.
It unbinds the touch driver, blanks or unblanks the screen, and times **one**
i2c transaction to an unused address on the touch bus. Its r82 result is on
record in `../2026-09-04_142-touch-after-resume/TRIGGER-screen-gates-it.md`,
which is what makes this a differential measurement rather than a reading.

| arm | r82, 2026-09-04 | r83, 2026-09-05 |
|---|---|---|
| screen OFF | 15.0704 15.0692 15.0899 15.0465 15.1061 s — **5/5 stalled** | 2.0173 2.0353 2.0305 s — **3/3 stalled** |
| screen ON | 0.0004–0.0006 s, errno 6 — 0/5 | 0.0006–0.0008 s, errno 6 — 0/3 |

Command, run as root on the device:

```sh
PER=3 BLANK=12 sh /tmp/142-trigger.sh
```

## What it says

**15.076 s → 2.028 s, a factor of 7.4**, on the one path the change touches.

The predicted value was exact before the run: r83 computes
`TOUT_MIN * HZ + usecs_to_jiffies(len * one_byte_t)` = `2 s + 1 × 99 µs`
= 2.0001 s for this one-byte probe. The measured 2.03 s carries the ~30 ms of
surrounding ioctl and scheduling, which is the resolution this instrument has.

The screen-ON arm is **unchanged** (sub-millisecond, errno 6, 0/3 like 0/5
before). That is the control that says the change is confined to the timeout
path and did not slow or alter a healthy transaction.

## ☠️ What it does NOT say

* **The stall still happens.** 3/3 with the screen off. This fixes what a stall
  *costs*, not that the touch chip holds the bus. The chip-side cause is still
  open and still lives in the #142 material.
* **The himax retry is not measured here.** This probe is a raw i2c read to an
  unused address, not the driver's event read, so the second half of #157 —
  three retries plus `dev_err_ratelimited` — is untouched by this experiment.
  It can only be measured in ordinary use, against the r82 rate recorded in
  `../2026-09-05_157-fault-rate-on-r82/`.
* **2 s is still a long freeze.** The remaining floor is upstream's `TOUT_MIN`
  (2 s), which this change deliberately left alone: it is a shared constant for
  every i2c-qup user, and the downstream `i2c-msm-v2` reaching 0.504 s is not on
  its own an argument for lowering it here. That is a separate question, not a
  loose end of this one.
* **The reproducer needs the driver unbound**, which never happens in real use —
  the caveat is stated in full in `TRIGGER-screen-gates-it.md` and has not
  changed. What it establishes is the QUP timeout constant, which is exactly
  what was modified.

## What code this measurement judged

`e79375c44e2f` — *i2c: qup: size the transfer timeout from the transfer, not from
the maximum*, shipped in linux-fp3 r83 (`_commit=9af3de4d21f2`). This page is the
only measurement of that commit's effect, and it judges the **cost** of a stall,
not whether one happens. Verify the hash resolves before trusting it.

☠️ It does **not** judge `c3111d25d687` (the himax retry), and it cannot: the
probe is a raw i2c transaction to an unused address, not the driver's event read.
