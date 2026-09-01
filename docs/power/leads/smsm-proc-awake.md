# ★★★★★ We never tell the modem the AP is awake — `SMSM_PROC_AWAKE` is set on the oracle and permanently zero on mainline

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

**Pre-registered:** MPSS duty falls materially toward the oracle's ~6 % with the
bit set ⇒ the mechanism is found and it is a shippable fix. Duty unchanged
within the ~3-point repeatability ⇒ this firmware does not read the bit, and the
lead is dead — say so and move to the RPM sleep-set question below.

## Two neighbours, and one of them is already dead

**`msm_ipc_router_set_ws_allowed()` — dead for this SoC.** It looked like a
second missing interface (QRTR has no equivalent: grep for `wakeup_source` in
`net/qrtr/` returns nothing). But its only two callers are in
`smp2p_sleepstate.c`, and that driver never probes on msm8953 — the `sleepstate`
smp2p node exists in the vendor `msm8937-smp2p.dtsi` and `sdm845-smp2p.dtsi`
only. On the oracle this code does not run either, so it cannot be part of the
difference.

**RPM sleep-set votes — open, and deeper.** The vendor votes separately for the
active set and the sleep set (`rpm-smd.c`, and the whole `msm_bus` stack does
too). Mainline's `smd-rpm.c` knows the concept — its request carries
"active/sleep state flags" — but whether our drivers ever populate the sleep set
is a second question, and a failure there would change what the RPM lets the
system drop when everyone is idle. Lower prior for a *per-wake* cost of 125 ms,
which is why it is second.
