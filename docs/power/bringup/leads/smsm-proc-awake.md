# ☠️ WITHDRAWN AS A MODEM LEAD, 2026-09-01 22:00 — the modem does not subscribe to the bit. It is now an ADSP lead

> **Read [`../captures/2026-09-01_smsm-subscription-mask/`](../captures/2026-09-01_smsm-subscription-mask/README.md)
> first.** The modem's subscription mask over the APPS entry is bit 23 alone, so
> bit 12 cannot wake it and cannot change its work per wakeup. The **ADSP**
> subscribes to bit 12 and to nothing else. Everything below is the source
> reading that led here and is still accurate; only the target changed. It cost
> one ssh login to find out instead of a flash and two windows.

# (original) We never tell the modem the AP is awake — `SMSM_PROC_AWAKE` is set on the oracle and permanently zero on mainline

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed the source reading it rests on.

2026-09-01, from source only — no measurement was taken for this page, and the
phone was inside an undisturbed overnight window while it was written.

## Why the search moved to source

Every mechanism this port could reach from the outside has now been eliminated
for the 30-point modem duty gap: the daemon, Wi-Fi, the cable, a modem power
cycle, uptime, a reboot, the RAT list, phantom-RAT acquisition scans, the band
(worth 17 points *inside* our stack, none of the cross-stack gap), RSRP, cpuidle,
rmtfs, the data bearer, and — decisively — **the AP's QMI traffic**: 14 messages
in 300 s against ~770 modem wakeups, so at most 2.3 % of the wakeups can have an
AP-modem message attached to them.

The shape that survives all of it is narrow: **the wake RATE is the oracle's
(3.15/s vs 2.46/s, ours slightly lower), and the wake LENGTH is 7× ours**
(20 ms vs 145 ms). Something makes the modem do more work per occasion, without
the AP saying anything to it over QMI.

That leaves the interfaces that are *not* QMI: the ones the AP kernel drives
directly. So: read the oracle's kernel, which is on disk
(`hadk22/kernel/fairphone/sdm632`, the vendor 4.9 tree), and diff its
modem-facing power signalling against ours.

## What the oracle does and we do not

`drivers/soc/qcom/msm_smd.c`, vendor tree:

```c
#define SMSM_PROC_AWAKE        0x00001000      /* include/soc/qcom/smsm.h */

static int smsm_pm_notifier(struct notifier_block *nb,
                            unsigned long event, void *unused)
{
        switch (event) {
        case PM_SUSPEND_PREPARE:
                smsm_change_state(SMSM_APPS_STATE, SMSM_PROC_AWAKE, 0);
                break;
        case PM_POST_SUSPEND:
                smsm_change_state(SMSM_APPS_STATE, 0, SMSM_PROC_AWAKE);
                break;
        }
        return NOTIFY_DONE;
}
```

and, at init (line 2450), **before** registering that notifier:

```c
        smsm_pm_notifier(&smsm_pm_nb, PM_POST_SUSPEND, NULL);
        i = register_pm_notifier(&smsm_pm_nb);
```

That first call is not a no-op: it takes the `PM_POST_SUSPEND` branch, so the
bit is **set to 1 at boot**. On the oracle, therefore, SMSM bit 12 of the APPS
entry reads *"the applications processor is awake"* continuously, and drops to 0
only for the duration of a system suspend.

The path is live on this SoC, not legacy: the vendor `msm8953.dtsi` instantiates
`qcom,smsm-modem` on edge 0 (`irq-bitmask 0x2000`, interrupt 26) right beside
`qcom,smd-modem`.

**Mainline never touches that bit.** `drivers/soc/qcom/smsm.c` in
`msm8953-mainline` contains no `PROC_AWAKE`, no PM notifier, no suspend hook —
grep finds zero hits for any of them. And no device tree in the tree, for any
SoC, consumes `<&apps_smsm 12>`: the consumers that exist are bit 1 and 11
(msm8916/8939) and bits 9 and 10 (`wcnss_wifi`, "tx-enable"/"tx-rings-empty"),
on ours too.

So on pmOS the APPS SMSM entry has bit 12 **permanently zero**. If the modem
reads it, we have been telling it, continuously and including right now, that
the applications processor is asleep.

## Why this candidate fits where the others did not

- **It is asymmetric while the AP is AWAKE.** Every suspend-tied mechanism has
  failed on the fact that the gap is measured in awake 600 s windows. This one
  is wrong in the awake state too, because we never set the bit at boot.
- **It costs no QMI.** It is shared memory plus a doorbell, invisible to the
  `qrtr_endpoint_post` probe that measured the AP out of the wakeups.
- **It plausibly changes work-per-wake rather than wake rate**, which is the
  measured shape.
- It is a thing our stack **does not do**, not a thing it does wrong — which is
  the category the outside review said the remaining causes would fall into.

## ☠️ What is NOT established

**Whether the modem firmware reads bit 12 at all.** That is closed firmware.
Everything above is a verified asymmetry in the AP-side source and a plausible
mechanism; it is not a demonstrated cause, and it must not be written up as one
until a paired window says so.

## The experiment

A faithful port of the vendor behaviour, category **power**: set
`<&apps_smsm 12>` at probe, clear it on `PM_SUSPEND_PREPARE`, set it again on
`PM_POST_SUSPEND`. The write path already exists on our side —
`smsm_update_bits()` is registered as a `qcom_smem_state` provider and the
`wcnss_wifi` node drives bits 9 and 10 through it today — so this needs a
consumer, not new plumbing.

Then one A/B: 600 s windows, band pinned, covariates sampled, bit off vs bit on,
same boot if the implementation allows toggling.

### Written, built, and not yet deployed (2026-09-01 21:42)

Two commits, driver and DT split the way the submission will want them, on
`wip/<base>/power` with cherry-pick twins on `integration/<base>` and
`debug-int/<base>`:

* `soc: qcom: smsm: tell the remotes whether this processor is awake` — a PM
  notifier driving the bit, set at probe. The bit number comes from a new
  `qcom,proc-awake-bit` property rather than being assumed, so every platform
  that does not name it behaves exactly as before.
* `arm64: dts: qcom: msm8953: name the SMSM processor-awake bit` — the property,
  set to 12.

`checkpatch --strict`: **0 errors** (its four warnings are all the
`Co-authored-by:` trailer, which is the fork convention and is replaced by
`Assisted-by:` when the submit series is regenerated). Both build clean —
`CC drivers/soc/qcom/smsm.o` with no warnings, and `DTC
sdm632-fairphone-fp3.dtb` — and the property is verified *in the built blob*,
not merely in the source: `qcom,proc-awake-bit = <0x0c>`.

**Nothing is deployed.** The package `_commit` is untouched and the phone is
still running the previous kernel; the commits are not pushed. The A/B waits for
the overnight decay window to close.

### ☠️ That paragraph half-decayed, measured 2026-09-03 08:1x

It is now wrong in one direction and right in the other, which is the shape of
claim that gets believed whole:

* **Wrong:** the `_commit` is *not* untouched. `linux-fp3/APKBUILD` pins
  `_commit=b8023520cddb…` at `pkgrel=80`, and that commit **is** the DT half of
  this patch — both commits sit at the tip of `debug-int/7.1.3` and on
  `wip/7.1.3/power`.
* **Right, and it is the half that matters:** the phone is **not running it**.
  `apk list -I linux-fp3` reads **r78**, and the running device tree has no
  `proc-awake` property at all (`grep -rl proc-awake /proc/device-tree` → empty).
  Built and pinned is not installed.

So the A/B still needs a build, a flash and a reboot — and that is exactly why it
cannot be run today. The 2026-09-03 night replication measures the boot-to-boot
band of a 40.3 mA figure taken on **this** kernel; installing a different one
first would put a new variable inside the series meant to isolate boot-to-boot
variation. The experiment is queued behind it.

☠️ **And a gap this exposed in our own captures:** neither
`2026-09-02_ims-ma3/README.md` nor the replication's `PREREGISTERED.md` records
the kernel `pkgrel` the measurement ran on. It had to be recovered from the
device afterwards. Every capture that compares across days needs the package
version in its header, the way band and cell already are.

☠️ Two bugs were found by reading the diff, both in the error path and both
introduced by me:

1. the block was first placed in the middle of `probe()`, where any later
   failure would leave a **registered PM notifier pointing at a freed object**;
2. moving it to the end fixed that and created a second one — its `goto out_put`
   then **skipped `unwind_interfaces`**, leaking the IRQ domains and the
   registered smem state on failure.

Neither would have been caught by the compiler, by checkpatch, or by a boot that
works.

**Pre-registered:** MPSS duty falls materially toward the oracle's ~6 % with the
bit set ⇒ the mechanism is found and it is a shippable fix. Duty unchanged
within the ~3-point repeatability ⇒ this firmware does not read the bit, and the
lead is dead — say so and move to the RPM sleep-set question below.

## ☠️ This is NOT the smp2p `sleepstate` hypothesis, which is already withdrawn

[`smp2p-sleepstate-missing.md`](smp2p-sleepstate-missing.md), opened 2026-08-31,
looked at `smp2p_sleepstate.c` — the *same* semantic bit, number 12, "the AP is
awake" — and **withdrew** it as a modem candidate, correctly: that entry's
`qcom,remote-pid` is **2**, which our own `msm8953.dtsi` says is the **ADSP**.
Downstream does not tell the modem over smp2p either. A second reason turned up
tonight and points the same way: msm8953 has **no `sleepstate` node at all**, in
any tree — the entry exists only in `msm8937-smp2p.dtsi` and
`sdm845-smp2p.dtsi`, so that driver never probes on this SoC.

**SMSM is a different transport, and it does reach the modem.** The shared state
vector is per-host, every remote can subscribe to any bit of the APPS entry, and
the vendor's `notify_other_smsm()` explicitly wakes the modem when a subscribed
bit of `SMSM_APPS_STATE` changes:

```c
if (smsm_info.intr_mask &&
    (__raw_readl(SMSM_INTR_MASK_ADDR(smsm_entry, SMSM_MODEM)) & notify_mask))
        notify_modem_smsm();
```

The vendor `msm8953.dtsi` instantiates `qcom,smsm-modem` on edge 0 beside
`qcom,smd-modem`, so the edge is live. So the withdrawal in that lead does not
carry over to this one — but the two must be read together, and anyone who
remembers "the sleepstate hypothesis died" should note that this is a different
mechanism, not a resurrection.

## ★ The subscription mask turns the unknown into a measurement

The paragraph above also names a way to test the *firmware* side without
flashing anything. `notify_other_smsm()` only wakes the modem for bits the modem
**subscribed to**, and those subscriptions live in the same shared memory as the
state itself — `SMEM_SMSM_CPU_INTR_MASK`, which mainline's `smsm.c` already maps
(`smsm->subscription = intr_mask + smsm->local_host * smsm->num_hosts`).

So: **read the modem's interrupt mask for the APPS entry and look at bit 12.**

* set ⇒ this firmware asked to be told when the AP's awake flag changes, which is
  strong evidence it acts on it, and the patch below is worth measuring;
* clear ⇒ the modem never asked, the bit cannot wake it, and this lead is dead
  before a single window is spent on it.

Neither answer needs a reboot, a flash, or a slot switch. It does need a reader:
mainline exposes none of this to userspace, so it is either a debugfs file in the
debug layer or a `/dev/mem` + SMEM table walk of the kind
[`../tools/rpmstats_raw.py`](../tools/rpmstats_raw.py) already does for the RPM
records. **Do this before the A/B.**

## One neighbour that is dead outright

**`msm_ipc_router_set_ws_allowed()`.** It looked like a second missing interface
(QRTR has no equivalent: grep for `wakeup_source` in `net/qrtr/` returns
nothing). But its only two callers are in `smp2p_sleepstate.c`, which — as above
— never probes on msm8953. On the oracle this code does not run either, so it
cannot be part of the difference.

**RPM sleep-set votes — open, and deeper.** The vendor votes separately for the
active set and the sleep set (`rpm-smd.c`, and the whole `msm_bus` stack does
too). Mainline's `smd-rpm.c` knows the concept — its request carries
"active/sleep state flags" — but whether our drivers ever populate the sleep set
is a second question, and a failure there would change what the RPM lets the
system drop when everyone is idle. Lower prior for a *per-wake* cost of 125 ms,
which is why it is second.
