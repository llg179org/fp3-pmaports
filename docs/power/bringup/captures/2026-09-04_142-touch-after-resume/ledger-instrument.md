# The touch ledger, and its validation

`142-touchlog.sh`, run as `fp3-142-ledger`. Samples three counters at 1 Hz and
writes **only on change**, so an idle phone costs a few bytes an hour:

```
irq       sum of the per-CPU counts on the hx83112b line of /proc/interrupts
err110    dmesg | grep -c -e "Failed to read input event: -110"
suspends  /sys/power/suspend_stats/success
```

marking `<<< -110` and `<<< RESUMED` on the transitions. It exists because the
`-110` only arises when a human touches the panel, which made every trial cost a
round trip through the operator. With the ledger the operator touches whenever
they like and the record is read afterwards.

## Why it is not an evtest log

`evtest` would answer "did an event reach userspace". The ledger answers the two
questions that decide #142 — *did the controller raise interrupts* and *did the
driver's i2c read fail* — and it does so without holding the input device or
depending on evtest's output buffering when piped.

## Validation, 2026-09-04 12:25 — a known positive, not a clean run

☠️ The first 40 minutes produced **no ledger lines at all**: no touch, no
suspend, nothing. A quiet log from an instrument that has never been seen
firing is indistinguishable from a broken one, so the quiet was not accepted as
evidence of anything. A suspend was forced to make it speak:

```
lines before: 2
rtcwake -m mem -s 20   ->  rc=0
2026-09-04 12:25:57 irq=2922 err110=0 suspends=2  <<< RESUMED
```

The loop runs, reads, compares, writes, and stamps the correct wall time. The
`irq` extractor was proven separately against `/proc/interrupts` (2922, matching
a direct read) and the `err110` pattern was self-tested on a synthetic line
(returns 1). So two of the three fields are proven end to end and the third is
proven at the pattern.

☠️ What is still NOT proven: that `err110` fires **in situ**. The synthetic test
proves the pattern matches; only a real `-110` while the ledger runs proves the
whole path. Until that happens, a ledger with `err110=0` across a touch means
"no -110 was seen", not "the ledger would have seen one".

## Incidental

The phone did not suspend once in 40 minutes of idle with an ssh session held
open, which is consistent with the session inhibiting it. The three suspends on
this boot were all forced with `rtcwake`.
