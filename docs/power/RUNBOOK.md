# Power investigation run-book

> ⚠️ **AI-generated.** Maintained by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

**This file is the resume point.** It is rewritten whenever the state changes, so
that a context compaction — or a new session — costs nothing. Read it first, do
what "Next step" says, then update it. Everything else on this page ages out;
the reasoning lives in [`bringup/`](bringup/README.md) and the findings in
[`README.md`](README.md).

## Where the question stands

The search moved three times on 2026-08-14 and landed outside this SoC:

1. *Does a suspend reach the RPM?* — wrong level.
2. *Does anything notify the RPM?* — nothing did; mainline msm8953 described no
   MPM. Added, and the notification demonstrably runs.
3. *Why does the governor never select the deepest cluster state?* — **answered**:
   `genpd_governor_data::cached_power_down_state_idx` is declared `bool`, so a
   cached state index of 2 comes back as 1 and the search, which only walks
   downwards, can never reach index 2 again. Six years old, not msm8953-specific.
   Fixed; `cluster-pc` 0 → 14516 per minute, `system-pc` 0 → 3531. Written up in
   [`README.md`](README.md) under "The real cause".
4. **Current: the RPM still records nothing.** `qcom_stats` `vlow`/`vmin` are 0
   and the APSS master record is all zeros, while the AP now completes a
   system-level power collapse ~47 times a second. The question is now the RPM
   handshake alone.

## Next step

**The regulator sleep-set theory is dead** (it pointed the wrong way — see
[`README.md`](README.md), "The regulator sleep-set theory was wrong"), and the one
real gap it uncovered, the **vMPM wakeup timer**, is now fixed and pushed
(`wip/7.1.3/power` `97951baf7a85`) — and did not move the RPM either.

Every AP-side precondition is now individually verified: the composed PSCI
parameter `0x41000353` really reaches firmware (traced), firmware accepts it 98 %
of the time, the mailbox write matches downstream byte for byte, the wakeup
deadline is programmed, and the master-stats reader is proven live by a 60 s
differential in which MPSS gains 150 and PRONTO 563 while APSS gains nothing.

**So the next step is a two-sided capture of shared memory, not another patch.**
The oracle runs the same TZ on the same silicon, so whatever makes the RPM record
an APSS shutdown there has to be visible in what the kernel leaves behind before
the PSCI call. Concretely:

1. Boot `slot_a`, and dump the **same vMPM region** (`/dev/mem`, `0x60000 + 0x1d4`,
   0x48 bytes — the script is `/home/fp3/vmpm_dump.py`, copy it across) while
   Ubuntu Touch is idle. Diff it word for word against ours. The enable/edge words
   should differ (different wakeup sets); anything *structural* that differs is
   the answer.
2. If that is inconclusive, widen to the RPM MSG RAM around it and diff the two
   dumps as a whole.
3. Only if both are inconclusive does it become a firmware question, and at that
   point the honest write-up is that mainline cannot reach RPM power collapse on
   this SoC without knowing what TZ expects.

**Still open, unchanged:** the GPIO wakeup map is deployed and provably inert
until the RPM takes over; the regulator sleep set is a real hazard the day it
does, so it must be built *before* the RPM ever collapses, not after; and
`_commit`/`pkgrel` still pin the tested `162f27abc328` rather than the current
`debug-int/7.1.3` tip.

## Device and tree state

* Phone on `slot_b`, running a hand-deployed `Image` from `debug-int/7.1.3`
  `6fd035d9501a` (md5 `2f64535335ff01c395db30000c056a13`, verified on both sides),
  not a package build. Backups in `/boot`: `vmlinuz.pre-mpmtimer`,
  `vmlinuz.genpdfix`, `vmlinuz.base-mpm`, `vmlinuz.pre-mpm`.
* The oracle is `slot_a` (Ubuntu Touch); `fastboot set_active a|b` switches, and
  `ut-ssh` reaches it.
* Kernel work is the `power` category: `wip/7.1.3/power` → `integration/7.1.3` →
  `debug-int/7.1.3`, all pushed to `fork`.
* **A package build has not been run for any of this**, so `_commit` in
  `linux-fp3/APKBUILD` still predates it. Do that before calling anything
  shipped.

## Instruments, with the paths that cost time to find

| question | command |
|---|---|
| did the SoC reach a low-power mode | `grep Count /sys/kernel/debug/qcom_stats/{vlow,vmin}` |
| which master never goes down | `cat /sys/kernel/debug/qcom_rpm_master_stats/APSS` — ☠️ one file per master, and the directory is `qcom_rpm_master_stats`, not `rpm_master_stats`; needs `modprobe rpm_master_stats` |
| how deep does idle actually get | `cat /sys/kernel/debug/pm_genpd/power-domain-cluster0/idle_states` |
| the same on the oracle | `ut-ssh 'cat /sys/kernel/debug/rpm_master_stats'` and `.../lpm_stats/stats` |
| what is waking the CPUs | two `/proc/interrupts` snapshots differenced — ☠️ stop the compositor first, or `msm_mdss` at 65/s makes the run meaningless |
