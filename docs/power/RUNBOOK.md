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

**Device state right now (2026-08-15 01:29):** back on `slot_b`, running a hand
deployed `Image` + DTB from `debug-int/7.1.3` `6cbf488a28f0` (md5-verified against
the build tree on both files). `/boot` backups: `vmlinuz.genpdfix`,
`vmlinuz.base-mpm` (the control), `vmlinuz.pre-mpm`,
`sdm632-fairphone-fp3.dtb.pre-gpiowake`.

**Immediately in progress: does the GPIO wakeup map actually work?** First look
after the deploy is *not yet convincing* and needs finishing:

* `dmesg` shows only the known, expected `failed to map pin 58 as GIC hwirq 136
  is already mapped` — no new errors, and notably **no pin-53 collision message**,
  which needs explaining rather than celebrating.
* `/proc/interrupts` has exactly one `qcom_mpm` line (`GIC-0 203`, the MPM's own
  IRQ) and no GPIO line has moved to an MPM parent.

That is consistent with "nothing has requested a GPIO wakeup yet" — `pinctrl-msm`
only hands a line over on `enable_irq_wake`. So the test is not "is it in
`/proc/interrupts`" but: arm a wakeup on a GPIO that is in the map, and see it
survive a system power collapse. Candidates already wake-armed on this board are
in `/proc/interrupts` with `wakeup` in `/sys/.../power/wakeup`; the volume keys
and the touchscreen are the obvious ones. Check
`cat /sys/kernel/debug/irq/irqs/<n>` for the parent domain after arming.

**Then:**

1. **The RPM sleep half** — the remaining structural gap. Mainline's
   `smd-rpm.c` has no suspend hook at all; downstream flushes the RPM sleep set
   via `msm_rpm_enter_sleep()` before the PSCI call. See "What is still missing"
   in [`README.md`](README.md).
2. Bump `_commit`/`pkgrel` to `6cbf488a28f0` and rebuild the package **once the
   GPIO work is tested** — r54 deliberately pins the earlier, tested
   `162f27abc328`.

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
