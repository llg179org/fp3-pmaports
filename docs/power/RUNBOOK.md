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

**In flight right now (2026-08-14, ~23:10):**

* An idle-current A/B is running. `systemd-run --unit=dischg` runs
  `/usr/local/bin/dischg.sh /tmp/d-fix.txt` (30 s samples of
  `current_now`/`voltage_now`/`charge_now`), display off, `greetd` stopped.
  ☠️ The battery is `Full` and VBUS reads 0, so `current_now` is a constant 0 —
  **the usable signal is the `voltage_now` slope**, about 42 mV/h in the first
  five minutes. Design: 25 min on the fixed kernel (`/boot/vmlinuz`), 25 min on
  `/boot/vmlinuz.base-mpm` (identical tree minus the one-word fix), then 25 min
  on the fixed one again — the third leg controls for post-charge voltage
  relaxation, which decays with time and would otherwise be read as a difference
  between the kernels.
* `pmb build --arch aarch64 --force linux-fp3` is building r54, pinned to
  `debug-int/7.1.3` `162f27abc328`, with `CONFIG_QCOM_MPM=y` now in
  `config-fp3.aarch64`.

**Also in progress (uncommitted, in `fp3-power-wt`):** the GPIO wakeup map.
`pinctrl-msm8953.c` now carries `msm8953_mpm_map[]`, inverted from downstream
`mpm-8953.c`'s `mpm_msm8953_gpio_chip_data[]` (which is `{mpm-pin, gpio}`;
mainline wants `{gpio, mpm-pin}`), plus `.wakeirq_map`/`.nwakeirq_map`. Still to
do: `wakeup-parent = <&mpm>;` on the `tlmm` node in `msm8953.dtsi` — a **separate
commit**, driver and DTS never mixed. ☠️ MPM pin 53 is claimed twice downstream,
by GIC `mdss_irq` (SPI 72) and by GPIO 62; mainline has one MPM pin space and the
DT `qcom,mpm-pin-map` claims it first, so GPIO 62 will log a mapping error and
never arm. Left in the table because it is SoC data; say so in the commit.

**Then: why the RPM still records nothing.** The likely answer is already in
view and needs confirming rather than searching for. On the oracle, APSS
`xo_count` is 0 too — only `numshutdowns` moves — so what the RPM counts for the
AP is the AP telling it, not an XO vote. Downstream that telling is
`msm_rpm_enter_sleep()`, which flushes the RPM **sleep set** over SMD before the
PSCI call; mainline's `qcom_smd_rpm` has no sleep-set/active-set split at all and
sends everything to the active set. If that is right, mainline msm8953 can power
collapse the AP as deeply as it likes and the RPM will never drop the SoC rails
on its behalf, and the MPM mailbox — which is about programming the wakeup
controller, not about sleep votes — cannot substitute for it. Check by reading
`drivers/soc/qcom/smd-rpm.c` for a sleep-set path and the downstream
`rpm-smd.c` for what it sends.

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
