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

**The question is answered; what remains is building it.** Mainline's
`drivers/regulator/qcom_smd-regulator.c` votes **only** the active set
(`rpm_reg_write_active()`, hard-coded `QCOM_SMD_RPM_ACTIVE_STATE`), so the RPM
holds permanent active votes and can never power-collapse — which is why
`vlow`/`vmin` are 0 and APSS `numshutdowns` never moves while the AP collapses 47
times a second. Downstream keeps a second per-regulator request
(`rpm_vreg->handle_sleep`, `RPM_SET_SLEEP`). Full write-up in
[`README.md`](README.md), "The RPM answer".

**Build it in this order:**

1. **Cheapest possible probe first, before writing a driver.** Pick one rail that
   is definitely idle — a camera or display regulator with no consumer — and send
   it a sleep-set vote of 0 by hand, then watch whether `vlow`'s `Client Votes`
   (`/sys/kernel/debug/qcom_stats/vlow`) loses a bit. There is no sysfs for this,
   so it needs a throwaway kernel patch calling `qcom_rpm_smd_write(...,
   QCOM_SMD_RPM_SLEEP_STATE, ...)` for that one id. **This is the measurement
   that decides whether the whole theory is right**, and it is one boot.
2. If the bit moves: add a real sleep-set path to `qcom_smd-regulator.c`.
   The shape to copy is `icc-rpm.c`, which already aggregates and sends both
   states. Upstream-bound, and it is a feature rather than a fix, so it needs a
   maintainer conversation before a v1 — `qcom_smd-regulator.c` serves many
   boards and a wrong sleep vote browns out a rail mid-sleep.
3. Only then re-run the idle-current A/B. Until the RPM collapses, no AP-side
   change is expected to move the milliamps — that is what the matched A/B
   already measured.

**Also still open:** the GPIO wakeup map is deployed and provably inert (see
README) — it cannot be tested until the RPM actually takes over. And bump
`_commit`/`pkgrel` to `6cbf488a28f0` once that happens; r54 deliberately pins the
tested `162f27abc328`.

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
