# The AP never tells the ADSP it is suspending — mainline has no `sleepstate`

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed every measurement it rests on.

**Opened 2026-08-31**, from a search for ways to lower the MPSS duty. What it
found is real, is missing on mainline, and — read carefully — **is not about the
modem at all.** The correction is the most useful part of this page.

## What downstream has

`drivers/soc/qcom/smp2p_sleepstate.c` in the vendor 4.9 tree for this device
(`hadk22/kernel/fairphone/sdm632`). It is 90 lines and does one thing:

```c
#define PROC_AWAKE_ID 12 /* 12th bit */

case PM_SUSPEND_PREPARE:
        gpio_set_value(slst_gpio_base_id + PROC_AWAKE_ID, 0);
        usleep_range(10000, 10500); /* Tuned based on SMP2P latencies */
        msm_ipc_router_set_ws_allowed(true);
        break;

case PM_POST_SUSPEND:
        gpio_set_value(slst_gpio_base_id + PROC_AWAKE_ID, 1);
        msm_ipc_router_set_ws_allowed(false);
        break;
```

* a PM notifier at `priority = INT_MAX`, so it runs before everything else;
* **bit 12** of an SMP2P entry named `sleepstate`: **1 = the AP is awake**,
  **0 = the AP is going down**. `probe()` sets it to 1;
* a deliberate **10 ms** wait after clearing it, commented *"Tuned based on SMP2P
  latencies"* — the remote is given time to see the bit before the freeze;
* `msm_ipc_router_set_ws_allowed()` flips whether the IPC router (the downstream
  ancestor of QRTR, which carries QMI) may take wakesources. Allowed while the AP
  is suspended, forbidden while it is awake.

## ☠️☠️ Which remote it talks to — the correction

The obvious reading is "the AP tells the modem it is asleep, and mainline never
does, which is why our modem behaves the same asleep and awake." **That reading is
wrong**, and one grep of the device tree settles it.

`msm8937-smp2p.dtsi` (this SoC family) contains **exactly one** sleepstate entry:

```
smp2pgpio_sleepstate_2_out: qcom,smp2pgpio-sleepstate-gpio-2-out {
        qcom,entry-name = "sleepstate";
        qcom,remote-pid = <2>;
};
```

and our own mainline `msm8953.dtsi` fixes what those pids mean:

| node | `qcom,remote-pid` |
|---|---|
| `smp2p-modem` | **1** |
| `smp2p-adsp` | **2** |
| `smp2p-wcnss` | 4 |

⇒ **The sleepstate bit goes to the ADSP, not the modem.** The vendor tree's own
comment agrees from the other direction: its inbound SSR entry, labelled
*"ssr - inbound entry from mss"*, uses `remote-pid = <1>`.

**So downstream does not tell the modem either.** This mechanism therefore
**cannot** explain any pmOS-versus-oracle difference on the modem side, and it is
not a candidate for the 34.8 % → 6.1 % duty gap. That hypothesis is withdrawn
here rather than published.

## What is actually missing, and why it may still matter

Measured in our tree (`fp3-power-wt`, base 7.1.3):

```sh
ls drivers/soc/qcom/ | grep smp2p        # smp2p.c, trace-smp2p.h — no smp2p_sleepstate.c
grep -rn "sleepstate" drivers/soc/qcom/ arch/arm64/boot/dts/qcom/   # nothing
grep -n "PM_SUSPEND_PREPARE" drivers/soc/qcom/smp2p.c               # nothing
```

Mainline's `smp2p.c` has **no PM notifier at all**, and no board DT in the tree
declares a `sleepstate` entry. So on pmOS the ADSP is never told that the
application processor is going down, and is never told when it comes back.

Why that is worth testing, stated as hypotheses rather than as findings:

* the ADSP is a documented consumer of this bit downstream, and this project has
  an unexplained ADSP-side history (`lpass-*` tools and captures exist because the
  audio DSP would not power-collapse);
* R1a measured that **every QMI packet arriving during s2idle ends the sleep**.
  The `msm_ipc_router_set_ws_allowed()` half of the downstream driver is exactly
  a policy about which side may hold a wakesource across suspend — the same
  question, approached from the source rather than by filtering on the AP;
* it is a small, self-contained, upstreamable change if it works.

☠️ **It is also entirely possible that this changes nothing measurable.** The bit
is an *advisory* signal; whether this firmware acts on it is unknown, and nothing
in the vendor driver proves that it does. Treat a null result as the expected
outcome and the instrument as the thing that has to be trusted.

## Pre-registered experiment

Not "port it and see". The measurement has to be able to fail:

1. **Before anything**, one `modem-window.sh` and one LPASS-side reading, so the
   baseline exists in the same boot as the change.
2. Port: a small platform driver mirroring the vendor one, plus a `sleepstate`
   entry on `smp2p-adsp` in the FP3 DT, taking a `qcom,smem-state` rather than
   the downstream `gpio` idiom (mainline's `smp2p.c` exposes `#qcom,smem-state-cells`,
   which is the same bit through the API this tree actually has).
3. Re-measure the same two things.

Readings, fixed in advance:

| observation | conclusion |
|---|---|
| LPASS XO/power-collapse counters move, current unchanged | the bit is acted on but is not worth mA here |
| suspends survive longer / fewer QMI-ended sleeps | the interesting case — the wakesource half is what mattered |
| nothing moves at all | the firmware ignores an advisory bit; **park it and say so** |
| MPSS duty changes | ☠️ **suspect the instrument first** — nothing in this mechanism talks to the modem |

The last row is the trap: a change that appears to move a number it has no path
to touch is a measurement error until proven otherwise.

## Sources

* vendor driver: `hadk22/kernel/fairphone/sdm632/drivers/soc/qcom/smp2p_sleepstate.c`
  (Copyright 2014-2018 The Linux Foundation, GPL-2.0-only)
* vendor DT: `.../arch/arm64/boot/dts/qcom/msm8937-smp2p.dtsi` lines 161-174
* mainline for comparison:
  [`drivers/soc/qcom/smp2p.c`](https://github.com/torvalds/linux/blob/master/drivers/soc/qcom/smp2p.c)
* a public copy of the same downstream driver, for readers without the vendor tree:
  [android.googlesource.com](https://android.googlesource.com/kernel/msm/+/android-wear-8.0.0_r0.21/drivers/soc/qcom/smp2p_sleepstate.c)

## ☠️ What the search did NOT find

There is **no published recipe for lowering the MPSS duty** on mainline
Qualcomm. The postmarketOS [Power saving](https://wiki.postmarketos.org/wiki/Power_saving)
page attributes mainline's idle penalty to runtime PM, not the modem; the
[msm8953 remoteproc series](https://lore.kernel.org/lkml/CJXVR1WTNWBR.2YTXMB8GZU84K@skynet-linux/T/)
is bring-up only; and the ModemManager/libqmi material on unsolicited indications
discusses correctness, never current. That absence is itself a reason to keep D2
(name what the modem is doing) ahead of any speculative switch-flipping.
