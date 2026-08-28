# Open leads

> ⚠️ **AI-generated.** Maintained by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

One page per question that is still open. A lead graduates out of here in one of
two directions: into [`../../README.md`](../../README.md) if it turns into a fix
that shipped, or into [`../disproven/`](../disproven/README.md) if it turns out to
be wrong. Neither has happened to any of these yet.

| lead | where it stands |
|---|---|
| [`modem-idle-lte.md`](modem-idle-lte.md) | ★★★★★ **the current lead, and it is the whole remaining idle gap.** The modem core is awake **34.8 %** on pmOS and **6.1 %** on the oracle — same hardware, same firmware, same operator and cell, both on LTE, measured with one instrument within half an hour. Every other candidate is dead. ☠️ And the cheaper system is the one doing *more*: it holds a live PDP context, we hold no bearer at all |
| [`lpass-never-sleeps.md`](lpass-never-sleeps.md) | ☠️ **two corrections since this page was written.** (1) "A master that never shuts down is a sufficient explanation for `vlow` reading 0" is **disproven** — LPASS was made to collapse for the whole of every suspend and `vlow` did not move; and the `vlow` hunt itself closed on 2026-08-24 when the oracle turned out never to reach it either. (2) The audio-clock fix shipped in r78 and **LPASS still records `XO total duration: 0` over a 600 s window**, against the oracle's 582.1 s. Priced at ~4 mA, so a correctness item today — but 7 % of what remains once the modem term goes |
| [`rpm-sleep-set.md`](rpm-sleep-set.md) | mainline's `qcom_smd-regulator.c` has exactly one `qcom_rpm_smd_write()`, hard-coded to the active state, where the vendor keeps `handle_active`/`handle_sleep` and a mandatory `qcom,set` bitmask. Fourteen LDOs vote active and never sleep. Both obvious patches are wrong, and the page says why |
| [`idle-ladder.md`](idle-ladder.md) | what the awake floor is made of: five userspace candidates, all zero, and the panel's 24.5 mA that was hiding in every level |
| [`de-compare.md`](de-compare.md) | phosh against another desktop environment. ☠️ Dropped by decision — the Sxmo install needed 264 MB net against 347 MB free |

☠️ **A lead is not a plan.** What to do next is in [`../../../TODO.md`](../../../TODO.md),
and it is deliberately the only page that says so.
