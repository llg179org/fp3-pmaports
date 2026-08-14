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

Two, in this order:

* **Finish the current A/B that is running.** `/usr/local/bin/dischg.sh` logs
  `current_now`/`voltage_now`/`charge_now` every 30 s to `/tmp/d-fix.txt` on the
  fixed kernel. Repeat the identical run on `/boot/vmlinuz.base-mpm` (the same
  tree minus the one-word fix) and compare. ☠️ With the battery at `Full` and
  VBUS at 0 the gauge reports `current_now = 0`; the usable signal is the
  `voltage_now` / `charge_now` slope, or a run started after it has fallen out of
  `Full`.
* **Why the RPM records nothing.** The AP side is now doing everything visible:
  MPM genpd powers off 3582 times a minute, which is the mailbox write. Next
  instruments: does the vMPM SRAM slice actually change (dump `0x1d4..0x21c` of
  the RPM MSG RAM before/after), and does the oracle's own vMPM look different at
  the same moment.

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
