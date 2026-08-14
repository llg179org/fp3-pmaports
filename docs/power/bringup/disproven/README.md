# Disproven: the missing system-level PSCI state

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed the change and the measurement.

Kept so it is not re-derived. The patch here **does what it claims and does not
fix what it was aimed at**, which is the only reason it is worth a page.

## The hypothesis

The RPM's per-master records show the application processor has never told the
RPM it is going down, while the modem and the WLAN subsystem do so constantly.
The downstream msm8953 tree describes the sleep hierarchy in **three** levels,
not two, and composes the PSCI suspend parameter from all three:

| level | `qcom,psci-mode-shift` | deepest mode |
|---|---|---|
| `system` | **8** | `system-pc`, mode 3, carrying **`qcom,notify-rpm`** |
| cluster (`pwr`, `perf`) | 4 | `l2-pc`, mode 5 |
| CPU | 0 | `pc`, mode 3 |

Mainline's `msm8953.dtsi` matches downstream exactly on the cluster and CPU
nibbles — retention 3, GDHS 4, power-collapse 5; CPU power-collapse 3 — and
leaves **bits 8–11 zero in every parameter**. Since downstream attaches
`qcom,notify-rpm` to precisely the level mainline never asks for, the obvious
reading is that the RPM is never notified because the system level is never
requested.

## The change

`system-level-psci-domain.patch`: a `power-domain-system` genpd above the two
cluster domains, with one `domain-idle-state` whose
`arm,psci-suspend-param` is `0x41000353` — system 3, cluster 5, CPU 3, composed
the way downstream composes it. Latencies taken from the downstream level's own
`qcom,latency-us` (11027) and `qcom,time-overhead` (1495).

It builds clean, `dtc` says nothing, and the domain registers and is used.

## Why it is disproven

Two `rtcwake` suspends of 120 and 300 s, with the domain in place:

| | result |
|---|---|
| `power-domain-system` usage | **2** (both suspends), `Rejected 0`, `S2idle 2` |
| `qcom_stats/vlow` Count | **0** |
| `qcom_stats/vmin` Count | **0** |
| APSS `Shutdown count` | **0** |
| MPSS / PRONTO in the same window | 1430 / 1092 |

**The state is requested, the firmware accepts it, and the RPM still records
nothing.** So the missing APSS sleep vote is not a missing PSCI parameter, and
composing the downstream parameter is not sufficient.

## What it narrows the search to

☠️ **Do not re-test this by adding the system nibble again.** It was accepted and
it changed nothing.

The lead that survives is one line from the boot log, which predates this
experiment and is not caused by it:

```
psci: [Firmware Bug]: failed to set PC mode: -1
```

The firmware refuses OS-initiated mode, which is why the device tree carries
`force-psci-domains` at all. In platform-coordinated mode the platform — not
Linux — decides the composite state, so a parameter Linux composes may never be
the one acted on. The next question is therefore what, on this firmware, is
supposed to produce the APSS shutdown, and whether it is a PSCI path at all
rather than the RPM sleep-set votes.
