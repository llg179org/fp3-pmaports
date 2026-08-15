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

☠️☠️ **The whole night's idle-current work was measured with the panel refreshing
at 65 Hz.** Stopping `greetd` is not enough - `fbcon` holds DRM DPMS on with no
userspace client, and `msm_mdss` keeps firing 65 times a second. The fix is

```sh
echo 4 > /sys/class/graphics/fb0/blank      # msm_mdss disappears from /proc/interrupts
```

after which total wakeups roughly halve. **Every mV/h figure in this directory
predates that discovery and has to be treated as measured under a load that
dwarfs the effect.** In particular, "the genpd fix did not move the current" is
not a safe conclusion yet.

**Do this first:** re-run the matched A/B (genpd-fixed kernel vs
`/boot/vmlinuz.base-mpm` control) with the panel blanked as part of the protocol,
same reboot → 600 s settle → 50 samples shape as before. A paired panel-on /
panel-off leg on one boot is running as of 2026-08-15 05:40 to size the display
term first; its output is `/home/fp3/leg-panel{off,on}.txt` on the device.

☠️ The measurement only works while the pack is actually discharging. With a USB
cable attached `pmi632-charger/online` reads 1 and the voltage sits flat, so
check it before trusting a slope.

**The RPM question is parked, not open.** Everything on the AP side is verified
(see [`README.md`](README.md), "What is now known for certain about the AP side"),
the two-sided vMPM dump is structurally identical, and both of the kernel-side
theories were measured false. What remains is on the far side of the PSCI call,
in TZ or RPM firmware, where this kernel has no instrument.

**Not submission-ready:** the vMPM timer commit (`wip/7.1.3/power`
`97951baf7a85`) is a real omission - the driver documents `TIMER0`/`TIMER1` and
never writes them - but it changes nothing measurable yet, so it stays on the
fork until it can be shown to fix something. The two LKML patches that *are*
ready (genpd bool, cpuidle-psci ordering) are unaffected.

**Also still open:** the GPIO wakeup map is deployed and provably inert until the
RPM takes over; the regulator sleep set must be built *before* the RPM ever
collapses, not after; and `_commit`/`pkgrel` still pin `162f27abc328`.

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
