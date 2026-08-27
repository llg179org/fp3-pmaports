# 2026-08-27 — the intervention: disabling the modem RF does nothing to the MSS core

> ⚠️ **AI-generated.** Claude (Opus 5) under the direction of Lajosházi, László
> Gergely.

`burst-master-knob.sh modem 'mmcli -m 0 --disable' … 360` — A-B-A′ where the
outcome compared is **MPSS's duty cycle**, not the current, because the
current-only version of this experiment was flat (2 mA against a 3 mA baseline
spread) and that told us nothing about whether the MSS core kept waking.

| leg | modem state | samples | median mA | MPSS core up | median with MPSS up / down |
|---|---|---|---|---|---|
| A | registered | 189 | 98 | 68/189 = **36 %** | 152 / 76 (+76) |
| **B** | **disabled** | 189 | **99** | 65/189 = **34 %** | 168 / 84 (+84) |
| A′ | registered | 187 | 105 | 63/187 = **34 %** | 161 / 89 (+72) |

**Nothing moves.** The duty cycle is 36 / 34 / 34 %, the median current 98 / 99 /
105 mA, and the MPSS separation is present in all three legs. `mmcli --disable`
puts the radio off the air and the MSS core goes on waking exactly as often.

So the +91 mA is **not the radio being enabled**, and it is not something the
Linux-side modem interface controls through that switch. What remains:

1. the AP pokes the modem — `ModemManager`, `rmtfs`, `tqftpserv` and the QMI/QRTR
   plumbing are all running, and `rmtfs` in particular serves the modem's own
   storage, so a modem-initiated write lands as an AP-visible message;
2. the modem firmware wakes on its own and the AP never hears about it.

These have opposite fixes, and the way to tell them apart is on the AP side: the
modem's SMD edge — **hwirq 57 on an `smd-edge` row**, IRQ 141 on this boot, the
same line that terminates every suspend — has ticked **1 694 times in 5.7 h**,
about one message every 12 s. If each message keeps the MSS core up for ~4 s that
is a third of the wall clock on its own. `burst-master.sh` now samples that
counter per row, so the next capture answers it directly.

☠️ **The Linux IRQ number is an allocation and it moves.** The instrument
identifies the edge by hwirq 57, not by 141, which is what it happened to be on
the boot where it was first named.

One more thing found while taking the inventory, not yet chased: **`pd-mapper` is
in `failed`** (`status=1/FAILURE`, 29 ms of CPU). It serves the protection-domain
registry that QMI clients look services up in, and a failed registry is the shape
of a thing that gets retried. It is also a candidate for the separate finding that
**LPASS never releases the crystal**.
