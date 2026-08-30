# Making the modem edge wake the phone for a call and not for a heartbeat

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely. ☠️ **This page is a DESIGN, not a result.** Nothing
> in it has been built or measured; the kernel mechanics are quoted from the tree
> and the documentation, and every one of them is checkable. The measurement it
> depends on has not been taken yet.

## The trade this would break

Today the modem's SMD edge is armed as a system wakeup source, so an incoming
call raises the phone from s2idle and it rings — and every other thing the modem
signals ends the suspend too. Disarm it and the suspends hold but calls do not
arrive. **The halving half of the goal needs residency, and this is the wall it
hits — with no oracle to copy, since the vendor stack does not sleep either**
(120 attempts, 2 completed suspends, aborted by its own IPC router; see
`captures/2026-08-24_ut-coulomb-and-sleep-attempt.txt`).

## Why the current code cannot be tuned

Ours (`rpmsg: qcom_smd: allow edge interrupts to wake the system from suspend`)
arms the whole edge:

```c
device_set_wakeup_capable(dev, true);
ret = dev_pm_set_wake_irq(dev, irq);
```

That is all-or-nothing by construction, and the reason is in `kernel/irq/pm.c`:

```c
void irq_pm_handle_wakeup(struct irq_desc *desc)
{
	irqd_clear(&desc->irq_data, IRQD_WAKEUP_ARMED);
	desc->istate |= IRQS_SUSPENDED | IRQS_PENDING;
	desc->depth++;
	irq_disable(desc);
	pm_system_irq_wakeup(irq_desc_get_irq(desc));
}
```

**A wake-armed IRQ becomes a system wakeup before the handler runs**, and the IRQ
is disabled on the way. So no amount of cleverness inside
`qcom_smd_edge_intr()` can filter anything: by the time it could look at which
channel signalled, the suspend is already over. This is why every "quiet that
channel" idea died — the granularity does not exist at that layer.

## The mechanism that does exist

`suspend_device_irq()` in the same file:

```c
if (!desc->action || irq_desc_is_chained(desc) ||
    desc->no_suspend_depth)
	return false;          /* IRQF_NO_SUSPEND: never armed, never suspended */
```

and `Documentation/power/suspend-and-interrupts.rst` on suspend-to-idle:

> *"all of the interrupts with the IRQF_NO_SUSPEND flag set will bring CPUs out
> of idle while in that state, but they will not cause the IRQ subsystem to
> trigger a system wakeup"*

⇒ With `IRQF_NO_SUSPEND` the handler **runs** during s2idle — the channel is
serviced, the data is consumed, nothing is lost — and the system goes back to
idle **unless the handler calls `pm_system_wakeup()` itself**. That is exactly
the missing knob: the driver decides, per interrupt, whether this one was worth
waking for.

## The shape of the change

1. request the modem edge's IRQ with `IRQF_NO_SUSPEND` instead of arming it via
   `dev_pm_set_wake_irq()`;
2. in `qcom_smd_edge_intr()`, after walking the channels, call
   `pm_system_wakeup()` **only** when a channel that matters signalled;
3. keep the existing per-edge sysfs control as the policy switch, so the
   behaviour is opt-in per edge exactly as it is now.

## ☠️ What is not known yet, and what would make this wrong

- **The filter criterion does not exist.** "A channel that matters" is undefined
  until it is measured which channel carries a call and which carry the traffic
  that currently ends every suspend. The 2026-08-22 per-channel census answered
  *IPCRTR, and the ring is signal-level rather than messages* — but it ran
  entirely on back-to-back short sleeps, i.e. inside the disturbed regime
  (`sleep-length-is-a-state.md`), so it may describe only what a freshly woken
  phone does. `tools/wakesrc-rested.sh` re-takes it on a rested phone. **If the
  call and the heartbeat arrive on the same channel, this design does not work
  and the filter has to move up to the QRTR port**, which is a different and
  larger change.
- **`IRQF_NO_SUSPEND` costs the full-suspend wake path.** Such an IRQ does not
  wake the system from a platform suspend at all — only from s2idle. This device
  is `s2idle`-only (`/sys/power/mem_sleep` reads `[s2idle]`), so it is free
  *here*, and it is a real limitation for anything sent upstream.
- **The documentation warns against mixing.** *"There are very few valid reasons
  to use both enable_irq_wake() and the IRQF_NO_SUSPEND flag on the same IRQ, and
  it is never valid to use both for the same device."* The design above uses
  `IRQF_NO_SUSPEND` **instead of**, not alongside, the wake arming.
  `IRQF_COND_SUSPEND` exists for the shared-IRQ case and is *not* what this is.
- **The handler would run with devices suspended.** SMD reads shared memory, which
  survives s2idle, but that is an argument, not a measurement.

## Plan B, if the call and the noise share a channel

Checked in the tree, not assumed: `qrtr_endpoint_post()` in `net/qrtr/af_qrtr.c`
parses the header before delivery and has `cb->src_node`, `cb->src_port`,
`cb->dst_port` and `cb->type` in hand, then resolves the destination with
`qrtr_port_lookup(cb->dst_port)`. **So one layer up from SMD the identity is not
a channel but a local socket** — i.e. the service — which is a strictly better
place to decide whether this packet was worth waking for.

That makes the design robust to the measurement going the wrong way: if
`wakesrc-rested.sh` finds the call and the heartbeat arriving on the same SMD
channel, the filter moves here instead of dying. ☠️ Two things would have to be
established first, and neither is: that this path runs in a context where
`pm_system_wakeup()` may be called, and that the port carrying a call is stable
enough to recognise (a QRTR port is dynamic; the *service* behind it is what is
stable, and mapping one to the other at interrupt time is the part that may not
be cheap). Do not write code against this section until the channel-layer
measurement says it is needed.

## Order of work

1. `wakesrc-rested.sh` — name what ends a **rested** phone's sleep (running after
   the recovery curve);
2. only if the call and the noise are separable at the channel layer, build the
   filter;
3. measure with a real incoming call during a long sleep, exactly as
   `captures/2026-08-30_terse-call/` did — the responsiveness half is not
   negotiable, and a design that buys residency by dropping calls is disqualified
   whatever it saves.
