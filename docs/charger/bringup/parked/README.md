# Parked work — written, measured, deliberately not shipped

> ⚠️ **AI-generated.** This page — and the code, device tree and tooling it
> describes — was written by Claude (Opus 5) working under the direction of
> Lajosházi, László Gergely, who reviewed every change and made or reviewed
> every measurement it rests on. Kernel commits carry `Co-authored-by: Claude`;
> anything prepared for the LKML carries `Assisted-by:` instead and never a
> `Signed-off-by` from the assistant, since only a human can certify the DCO.

Code that works but is not on any branch, because shipping it would be solving
the wrong problem. Kept as a patch so the work is not lost and the reasoning is
not repeated.

## `resume-early-rest-anchor.patch`

Adds `.resume_early` to `qcom_smbx` via `LATE_SYSTEM_SLEEP_PM_OPS`: on the way
out of a suspend, before userspace is unfrozen, it reads the voltage/current
pair and — if the sample is quiet — re-anchors the state of charge on it as a
true open-circuit voltage. 88 insertions, no deletions.

| | |
|---|---|
| applies to | `wip/7.1.3/charger`, verified against `f5da2bfd25e2` |
| apply with | `git apply docs/charger/bringup/parked/resume-early-rest-anchor.patch` |
| builds | yes, `W=1` silent |
| measured working | yes — see below |

**It is not untested code.** `../../../power/2026-08-14_pmos_resume-early-rest-anchor.txt`
records it firing on a 300 s `rtcwake` suspend and moving the reported capacity
from 93.87 % to 91.00 % off a genuine rested OCV of 4 275 748 µV.

### Why it is parked anyway

It is scaffolding for a board that cannot rest, and the correct fix is to make
the board rest. Two measurements, both from 2026-08-14, decided it:

* **The hardware path it substitutes for is already implemented and merely
  starved.** `qcom_smbx` reads `S3_GOOD_OCV` at `QG_S3_GOOD_OCV_V_DATA0`,
  de-duplicates an unchanged capture against `chip->fg_good_ocv_uv`, and
  re-anchors from it. That code has never run only because the register reads
  `0x8000` — the PMIC has not entered S3 once, because S3 entry wants **10.4 mA**
  and this board idles at 139–143 mA. Nothing needs writing for that path; it
  needs a quieter board.
* **The hardware path is also strictly better.** `S3_GOOD_OCV` is captured
  *during* sleep, when the machine really is quiet. This patch samples at
  *wake* — and a user wake is never quiet. Measured: on a power-button resume
  the sample was **150 mA** against the patch's own 50 mA gate, so the anchor
  correctly declined to fire. It would only ever work on non-user wakes such as
  `rtcwake`.

### What would bring it back

A **partial** win on idle current. The two gates differ by five times: the
hardware needs 10.4 mA, this patch needs 50 mA. If the idle floor comes down far
enough to matter but not to 10 mA — say to 30 — then S3 still never fires and
this patch does. It is insurance against landing between the two thresholds.

☠️ **If the idle floor reaches S3, delete this patch rather than applying it.**
Two mechanisms correcting the same integral, on different schedules and
different gates, is worse than one that works.
