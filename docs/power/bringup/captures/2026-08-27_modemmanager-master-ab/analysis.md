# 2026-08-27 — the modem wakes itself, and the AP never hears about it

> ⚠️ **AI-generated.** Claude (Opus 5) under the direction of Lajosházi, László
> Gergely.

`burst-master-knob.sh modemmanager 'systemctl stop ModemManager' … 360`. Second
intervention on the same finding: if the AP's modem daemon is what keeps poking
the modem, stopping it must move the MSS core's duty cycle.

| leg | ModemManager | samples | MPSS core up | median with it up / down |
|---|---|---|---|---|
| A | active | 187 | 71/187 = **38 %** | 158 / 88 (+70) |
| **B** | **inactive** | 187 | 68/187 = **36 %** | 158 / 87 (+72) |
| A′ | active | 184 | 68/184 = **37 %** | 160 / 92 (+68) |

**Flat, like the radio was.** And the new column settles the other half of the
question: `modem_irq_per_s` — the modem's own SMD edge, hwirq 57 (IRQ 141 on this
boot) — is **0 in every sample of leg B** and effectively zero in A and A′
(r = −0.06 and +0.04 against the current; the one excursion to 50/s in A′ is
ModemManager restarting).

So the MSS core is up a third of the time **while sending the AP nothing**, and
**stopping every AP-side modem client changes neither its duty cycle nor the
current**. The two candidate stories from the previous capture are now one:

* ~~the AP pokes the modem~~ — ruled out twice, by the client and by the counter;
* **the modem firmware wakes on its own**, on a schedule Linux neither sets nor
  sees.

The general edge counter (`edge_irq_per_s`, everything SMD/smp2p/glink/ipa) moves
25–35/s and does not correlate either (r = ±0.04 to +0.14). This is dominated by
the RPM's own edge, which ticks half a million times a boot; it is background.

## What this closes, and what it leaves

Every lever reachable from Linux has now been pulled: the radio (`mmcli
--disable`), the modem daemon, and — from the day's earlier work — wlan, the CPU,
the panel and userspace work generally. **The one lever left on this side is
stopping the modem remoteproc, and that is barred**: it costs audio until the next
reboot and a mixer write afterwards oopses the kernel.

So the next question is not "how do we stop it" but **"does the oracle pay it
too"**. Ubuntu Touch runs the same modem, registered, on the same silicon. If its
MPSS duty is the same, this ~30 mA is what this modem costs and the pmOS/UT gap is
somewhere else entirely; if it is much lower, the difference is ours and it is
configuration. That measurement decides whether this whole front is worth another
hour, and it needs no remoteproc.

☠️ It is still a correlation. Nothing here proves the MSS core's wake *causes* the
current; a common third cause is not excluded, only made harder to imagine now
that the CPU, the panel, userspace and both radios are out.
