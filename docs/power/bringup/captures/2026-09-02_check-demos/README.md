<!-- AI-generated: written by Claude Opus 5 as part of an AI-assisted port. -->

# Demonstrating both IMS checks on the device (2026-09-02)

A check nobody has ever seen fail is not a check, it is decoration. Both of these
were walked through both of their branches on the live phone.

## 56-ims-config-test.sh — configuration level

| state | result |
|---|---|
| IMS=off, timer running | `PASS` (rc=0) |
| IMS=on | `FAIL` (rc=1), with the exact error message |

☠️ **And the demonstration FOUND a defect in the check itself:** `enabled` and
`active` are two different questions. A timer stopped by hand still reports
`enabled`, so the check passed while the next reboot would have restored the
vector with nothing to put it back. Fixed: it asks both, and says in a separate
sentence which one is missing.

## 57-ims-duty-test.sh — behavioural level

Two 120 s windows on the same band and cell (`eutran-3` / `1470732`), so the band
is excluded as a confounder:

| state | duty | wakes/s | ms/wake | result |
|---|---|---|---|---|
| IMS=on  | 37.1 % | 2.41 | 154.1 | `FAIL` (rc=1) |
| IMS=off |  5.0 % | 3.13 |  16.0 | `PASS` (rc=0) |

3.13/s = 1/320 ms, the paging DRX cycle: in the cheap state the UE is camped and
holds no connection. 2.41/s is *below* the paging rate — those are not paging
occasions but connection housekeeping, which is why the check asks about the duty
and the wake rate separately.

## The reconciler, live, in the middle of it

Halfway through the demo, `fp3-ims-reconcile`'s own log:

```
fp3-ims-reconcile: ☠️ HAD DRIFTED, corrected on attempt 2  {'voice': False, 'vowifi': False, 'video': False, 'sms': False, 'ut': False}
```

So the drift was not simulated: the check demo itself set IMS back on, and the
reconciler noticed and corrected it, with a read-back.

Raw output: `57-ims-duty-test-both-ways.txt`.
