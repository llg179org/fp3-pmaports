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

## What has been tried, and what it did not settle

**Raising the autosuspend delay is not yet demonstrated.** A-B-A′ inside one boot,
60 s legs, counting `qcom_rpm_smd_write`:

| leg | `autosuspend_delay_ms` | calls / 60 s |
|---|---|---|
| A | 50 | 945 |
| B | 2000 | 649 |
| A′ | 50 | 726 |

The effect (−22 % against the mean of the controls) is the same size as the drift
between the two controls (−23 %), so this measures nothing. ☠️ **And the confound
is the instrument:** every leg was driven over SSH, and an SSH session is exactly
the idle filesystem write this is trying to count. The next attempt has to run
detached, with the host quiet, and with several repeats — the same discipline the
duty windows already have.

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
