# Power investigation run-book

> ⚠️ **AI-generated.** Maintained by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

**This file is the resume point.** It is rewritten whenever the state changes, so
that a context compaction — or a new session — costs nothing. Read it first, do
what "Next step" says, then update it. Everything else on this page ages out;
the reasoning lives in [`bringup/`](bringup/README.md) and the findings in
[`README.md`](README.md).

## Where the question stands

The search moved twice on 2026-08-14 and is now one level shallower than it
started:

1. *Does a suspend reach the RPM?* — wrong level.
2. *Does anything notify the RPM?* — answered: nothing did, because mainline
   msm8953 described no MPM. Added; the notification now demonstrably runs.
3. **Current: why does the CPU domain governor almost never select the deepest
   cluster state?** With the display off, `cluster-gdhs` is entered 7628 times a
   minute for a 7.3 ms mean, `cluster-pc` zero times, `Rejected` zero — and the
   governor books 62 % of its own entries as "Below". The oracle enters a system
   power collapse ~30 times a second in 4–16 ms bursts.

## Next step

Measure the governor's next-wakeup estimate rather than its outcome:
`drivers/pmdomain/governor.c`, `cpu_power_down_ok()` — what `idle_duration_ns`
does it compute, against `cluster-pc`'s 270 + 430 µs latencies and 2500 µs
residency. An ftrace or a temporary `trace_printk` in that function answers it in
one boot.

Two cheaper A/Bs that can run first, either of which is a real result:

* drop `system_pc`'s `min-residency-us` from 13000 toward the oracle's measured
  4–16 ms window — the 13000 came from summing downstream latencies, not from a
  histogram, so it is a candidate cause rather than a transcription;
* `pinctrl-msm8953.c` has no `wakeirq_map` while five sibling RPM-generation SoCs
  do; the table is downstream's `mpm_msm8953_gpio_chip_data[]`, in `{gpio,
  mpm-pin}` order. ☠️ Pin 53 is claimed twice downstream — GIC `mdss_irq` and
  GPIO 62 — and mainline's driver accepts only the first, so decide which one
  before sending it.

## Device and tree state

* Phone on `slot_b`, running a hand-deployed `Image` + DTB (not a package build).
  Backups in `/boot`: `vmlinuz.pre-mpm`, `sdm632-fairphone-fp3.dtb.pre-mpm`,
  `sdm632-fairphone-fp3.dtb.mpm-only`.
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
