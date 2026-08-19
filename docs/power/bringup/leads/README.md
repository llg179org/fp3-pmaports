# Open leads

> ⚠️ **AI-generated.** Maintained by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

One page per question that is still open. A lead graduates out of here in one of
two directions: into [`../../README.md`](../../README.md) if it turns into a fix
that shipped, or into [`../disproven/`](../disproven/README.md) if it turns out to
be wrong. Neither has happened to any of these yet.

| lead | where it stands |
|---|---|
| [`lpass-never-sleeps.md`](lpass-never-sleeps.md) | ★ **the current lead.** The audio DSP has shut down twice since boot, 0.12 s in total, against 4344 shutdowns on the vendor stack on the same hardware. A master that never shuts down is a sufficient explanation for `vlow` reading 0 in every capture ever taken here |
| [`rpm-sleep-set.md`](rpm-sleep-set.md) | mainline's `qcom_smd-regulator.c` has exactly one `qcom_rpm_smd_write()`, hard-coded to the active state, where the vendor keeps `handle_active`/`handle_sleep` and a mandatory `qcom,set` bitmask. Fourteen LDOs vote active and never sleep. Both obvious patches are wrong, and the page says why |
| [`idle-ladder.md`](idle-ladder.md) | what the awake floor is made of: five userspace candidates, all zero, and the panel's 24.5 mA that was hiding in every level |
| [`de-compare.md`](de-compare.md) | phosh against another desktop environment. ☠️ Dropped by decision — the Sxmo install needed 264 MB net against 347 MB free |

☠️ **A lead is not a plan.** What to do next is in [`../RUNBOOK.md`](../RUNBOOK.md),
and it is deliberately the only page that says so.
