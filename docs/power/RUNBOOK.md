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

★★ **There is now a direct current instrument** - no cable to unplug, no voltage
fitting. `qcom_smbx` maps the charger supply's writable `POWER_SUPPLY_PROP_STATUS`
onto `USBIN_SUSPEND_BIT`:

```sh
echo Unknown  > /sys/class/power_supply/pmi632-charger/status   # off VBUS
echo Charging > /sys/class/power_supply/pmi632-charger/status   # restore
```

after which `pmi632-battery/current_now` reads real discharge current. The
protocol is `docs/power/idle-leg.sh` (host copy) / `/home/fp3/currleg.sh` (the
device-side one used for the legs so far).

**Baseline: an idle FP3 with the screen off draws about 155 mA.** That is the
number worth attacking; everything measured so far moves it by single digits.

**In flight:** an interleaved A/B of the genpd fix, fresh boot per leg.

```
FIX  -160.6  FIX2 -158.2  FIX3 -164.3          (genpd bool fix in)
CTL  -154.4  CTL2 -155.4  CTL3 running         (that one commit reverted)
```

The deep-idle kernel looks 4-9 mA *worse*, consistently. ☠️ But the per-sample
standard deviation is ~60 mA - the load is bursty - so a 100-sample mean has a
standard error near 6 mA. The groups separating is suggestive, not established;
keep alternating legs until the arms are clearly apart or clearly not. A coherent
reason for the sign exists: the AP pays ~143 domain entries a second while the
RPM never collapses, so the transitions buy nothing downstream.

**Withdrawn, do not re-cite:** every mV/h figure in this directory (voltage-slope
method, unusable at 99 % on a suspended port - it read *backwards* in a controlled
test), and the claim that the panel dominated the budget (it is ~10 mA of 150).

**The RPM question is parked, not open.** Every AP-side precondition is verified
and the two-sided vMPM dump is structurally identical; what remains is past the
PSCI call, in TZ or RPM firmware, where this kernel has no instrument. See
[`README.md`](README.md).

**Not submission-ready:** the vMPM timer commit (`wip/7.1.3/power`
`97951baf7a85`) is a real omission but changes nothing measurable yet. The two
LKML patches that *are* ready (genpd bool, cpuidle-psci ordering) are unaffected -
though if the A/B holds, the genpd cover letter should say plainly that on this
SoC the fix costs current until the platform's sleep handshake works.

**Also still open:** GPIO wakeup map inert until the RPM takes over; the regulator
sleep set must exist *before* the RPM ever collapses; `_commit`/`pkgrel` still pin
`162f27abc328`.

## Device and tree state

* Phone on `slot_b`, running a hand-deployed `Image` from `debug-int/7.1.3`
  `6fd035d9501a` (build #18, `/home/fp3/Image.fix`; the A/B control is
  `/home/fp3/Image.control`, the same tree with 162f27abc328 reverted),
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
