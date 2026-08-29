# The AP sends the RPM about fifteen requests a second while idle

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed every measurement it rests on.

## Why this page exists

It replaces a claim that was wrong. For two days the RPM's SMD edge was quoted as
*the modem's*, and the conclusion drawn from it — that the modem rings this phone
35 times a second and nothing on the AP side can move it — put the responsiveness
front out of reach. Measured by hardware IRQ, the modem's edge fires **0.07 times
a second**; the ring is the **RPM's**, and the traffic on it is the AP's own.

| edge | GIC hwirq | rate, idle |
|---|---|---|
| **RPM** (`rpm-proc`, SPI 168) | 200 | **13.29 /s** |
| ADSP (`lpass`, SPI 289) | 321 | 0.00 /s |
| WCNSS (`pronto`, SPI 142) | 174 | 0.39 /s |
| MPSS (the modem, SPI 25) | 57 | 0.07 /s |

## What the traffic is

`qcom_rpm_smd_write`, traced with `func_stack_trace` for 60 s on an idle phone:
**927 calls**, 15.5 per second, and the stacks are one story:

```
qcom_rpm_smd_write
qcom_icc_rpm_smd_send / qcom_icc_rpm_set / qcom_icc_rpm_set_bus_rate
qcom_icc_update_provider / qcom_icc_set
icc_set_bw
_set_opp_bw / _set_opp / dev_pm_opp_set_rate
apply_constraints
rpm_callback / __rpm_callback / rpm_resume / __pm_runtime_resume
mmc_runtime_resume                                        (408 of them)
```

Every runtime-PM resume of the eMMC host sets an OPP, every OPP carries an
interconnect bandwidth request, and every interconnect request is one or two RPM
messages. The host's `autosuspend_delay_ms` is **50**, so a write burst that takes
a few milliseconds is followed by a suspend 50 ms later and a resume on the next
one.

Measured beside it over the same 60 s: `mmcblk0` took **131 write operations**,
the host was runtime-active **3 %** of the time, and **no userspace process wrote
a single byte** — the writes are filesystem journal and writeback, plus whatever
the measuring session itself caused.

## The autosuspend delay is a dead knob — measured, three rounds

The first attempt drove all three legs over SSH and produced an effect the size of
its own drift. Redone properly — detached, 300 s legs, three rounds, counting with
the **function profiler** rather than the ring buffer so that reading the counter
costs no disk I/O of its own (`tools/rpm-write-ab.sh`):

| round | A: 50 ms | B: 2000 ms | A′: 50 ms |
|---|---|---|---|
| 1 | 3869 | 3450 | 3514 |
| 2 | 3517 | **3851** | 3593 |
| 3 | 3799 | 3220 | 3530 |

Medians 3799 / 3450 / 3530, and in round 2 **B is above both of its own controls**.
The ranges overlap completely. **Raising the eMMC host's autosuspend delay does not
change the RPM write rate**, and the obvious knob on this lead is closed.

★ Which is itself informative. If the traffic were bursts of writes each followed
by a 50 ms suspend, a 2 s delay would merge them and the rate would fall. It does
not, so the resumes are **spread out** — roughly two write operations a second,
each far enough from the next that no plausible delay bridges them. And
`mmc_runtime_resume` accounted for only **408 of the 927** stacks: less than half
the traffic is the eMMC at all, and the rest has not been attributed.

## Why it is worth another attempt

- It is **AP-side**, which nothing on the modem front has been for two days.
- It bears on **suspend residency** directly: 13 wakes a second is by itself enough
  to keep s2idle from holding, and this is our own traffic rather than a
  peripheral's.
- The knob is a plain sysfs value with an obvious cost model — a longer autosuspend
  delay trades a little idle current in the storage controller for far fewer
  bus-bandwidth votes.

☠️ It is **not** part of the consumption gap to the oracle. That is one term, the
modem core's awake duty on LTE, and this is not it — see
[`modem-idle-lte.md`](modem-idle-lte.md).
