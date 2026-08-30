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

- ~~The filter criterion does not exist.~~ **Resolved above — measured on both
  sides.** What remains of this point: **SMS and other must-wake events have not
  been enumerated**, and each needs its port on the wake list or it is lost the
  same way a call would have been. "A channel that matters" is undefined
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

## ★★★★ 2026-08-30: the filter criterion now exists, and plan B became plan A

The page below was written with a hole in it — *"the filter criterion does not
exist"* — and the service-level census filled it
(`captures/2026-08-30_wake-service/`). Every QRTR packet arriving across three
sleeps, with the ports resolved against the name-service map captured in the same
run:

| src | port | service |
|---|---|---|
| node 0 (modem) | **52** | Data System Determination |
| node 0 (modem) | **40** | Network Access Service |

and from the same map, **port 39 is the Voice service** — a different port from
either.

⇒ **The noise is NAS/DSD indication traffic and a call arrives elsewhere, so the
two are separable at the QRTR port layer.** The channel layer cannot do it (both
ride IPCRTR), which is why the census had to name the service. **Plan B below —
filter one layer up, in `qrtr_endpoint_post()` — is therefore the main plan, and
the SMD-layer version is the fallback.**

★ **And the ratio is what makes the design viable at all**: 35–47 IPCRTR
interrupts per sleep against **1–3 QRTR packets**. Most of the edge's interrupts
carry no message, so a handler that only calls `pm_system_wakeup()` for a packet
worth waking for has little to judge and a great deal to ignore.

★★★★★ **And the call's own port is now measured too** (2026-08-30 10:39): the
round a call landed in carried `4 x src_node=0 src_port=39` — the **Voice
service** — and that source appears in **no other round**, including the one that
slept its full 600 s. So the filter has both halves from measurement:

```
wake on:    src_node=0 src_port=39          (Voice)
ignore:     src_port 40 (NAS), 52 (DSD), 45 (WDS), 44 (UIM), node 5 port 10
```

☠️ **Still not established, and load-bearing:** four packets across three sleeps
is a direction, not a ratio; the call's port comes from the service map rather
than from an observed call, so a census taken across a real incoming call is what
would confirm the separation; and ☠️ **that census ran over `rtcwake`, which
bypasses logind, so ModemManager was never told to go terse** — the NAS/DSD
traffic it saw is the *unquieted* state. If terse removes those indications, the
kernel filter may be unnecessary and the question becomes why terse bought no
residency. That re-run is in flight.

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

## ☠️ Before building any of this: the cheaper fork in the road

Measured 2026-08-30, the noise is NAS (QRTR port 40) and DSD (52) indications
while a call is Voice (39). Naming the *service* was enough to show the two are
separable — and **not** enough to justify a kernel patch, because two causes
produce that same census and they need opposite fixes:

| cause | fix |
|---|---|
| the modem sends the indication unsolicited | kernel-side filter — this lead |
| **ModemManager subscribed to it** (NAS `0x0003` Register Indications, WMS `0x0047` Indication Register) | **unregister it in userspace** — no kernel patch, reversible over ssh, upstreamable as a ModemManager change |

The second is strictly cheaper and it has never been ruled out. It is also
plausible on its face: `NAS 0x0051 Signal Info` and `NAS 0x0002 Event Report`
are exactly the kind of thing a modem manager asks to be told about, and a
signal-strength indication arriving every minute is a subscription, not weather.

**The message id is what separates them**, and the service-layer census does not
capture it. `tools/wake-qmi.sh` does: it reads the QMI `service_header` at
`+0x20` of the QRTR v1 payload and names the message from `qmi-msgids.txt`
(generated from libqmi's own definitions). Run it before writing a line of
kernel code — and if the answer is "subscription", **this lead is not the fix
and should not be built**.

☠️ Note the asymmetry that makes this worth doing first: a kernel filter that
turns out to have been unnecessary is invisible once merged — it works, so
nothing ever says it was the wrong layer.

## Pre-registered reading of the QMI census

Written **before** the run, so the result is read off a table rather than
rationalised afterwards. The port→service map is not assumed: `qrtr-lookup` on
the device gives it, and both `wake-service.sh` and `wake-qmi.sh` capture it at
the top of every run because QRTR ports are dynamic. Measured 2026-08-30:
**39 = Voice, 40 = Network Access, 44 = UIM, 45 = Wireless Data,
51 = Wireless Messaging, 52 = Data System Determination.**

| what the noise turns out to be | what it means | what to do |
|---|---|---|
| NAS `0x0024` Serving System, `0x004e` System Info, `0x0068` Network Reject, or the DSD `0x0026` System Status | terse asks the modem to unregister exactly these and the modem kept sending them | **not a kernel problem** — the unregister failed or is not honoured. Chase it in ModemManager; the journal cannot tell you, by construction |
| NAS `0x0051` Signal Info or `0x0002` Event Report | signal-strength reporting MM subscribed to via its signal-info config | **userspace** — stop subscribing, or widen the terse step to cover it |
| something MM never registered for | genuinely unsolicited | **this lead** — build the kernel filter |
| ids absent from `qmi-msgids.txt` | libqmi has no definition; the id is still data | identify before deciding; do not assume unsolicited from a missing name |

And the half that decides whether a filter is *allowed* to exist at all:

| the SMS | consequence |
|---|---|
| arrives on port 51 with a WMS indication id | that id joins the wake list next to Voice, and the filter stays viable |
| arrives on a port or service not predicted here | the wake list was incomplete in a way we could not have reasoned our way to — which is the whole reason this run exists |
| does not wake the phone at all | ☠️ **stop**: the current system already loses SMS in suspend, and that is a bug to report before optimising anything |

Note the last row: it is the only outcome that would make the *present* state,
not the proposed one, the problem — and no measurement so far would have caught
it, because nobody has ever sent this phone an SMS while it was asleep.

## 2026-08-30 12:11 — the SMS half of the wake list, measured

`captures/2026-08-30_wake-qmi-sms/`. Three rounds of a 600 s alarm; the SMS was
sent during the third.

| round | slept | ended by | port 51 |
|---|---|---|---|
| 1 | 601 s | RTC (72) | — |
| 2 | 601 s | RTC (72) | — |
| 3 | **321 s** | **modem edge (139)** | **WMS Event Report + 2× Send Ack** |

**An SMS wakes the phone, and it does so on the Wireless Messaging Service's own
port.** The pre-registered table above named three possible outcomes; this is the
first, and it is the one that keeps the filter viable. The third — *"the SMS does
not wake the phone at all"* — is ruled out, which matters because that outcome
would have made the **present** system the bug rather than the proposed one.

**The wake list is therefore:**

| service | port | measured |
|---|---|---|
| Voice | 39 | 2026-08-30 10:39, an incoming call out of a 280 s sleep |
| Wireless Messaging | 51 | 2026-08-30 12:11, an SMS out of a 321 s sleep |

☠️ **It is still a list of two, and the argument that produced it applies to
itself.** The reason to run this measurement was that a filter built on the call
alone would have swallowed SMS. Nothing about today's run rules out a third
thing that also deserves a wake and has never been sent to this phone while it
slept — a voicemail notification, an operator/cell-broadcast message, an MMS
push, a network-initiated detach. **Before the filter ships, the list has to be
argued from the service map rather than from what we happened to test**, and
each entry it names has to be either measured or explicitly accepted as a risk.
An unmeasured service on a *deny* list is a silent failure by construction.

### And a genuinely new fact about the noise

Rounds 1 and 2 slept their **full** windows while NAS (40), DSD (52), WDS (45)
and UIM (44) traffic arrived. Until this capture that could not be said: the
trace ran across the resume, so "during the sleep" and "just after it" were the
same buffer. With the `RESUMED` marker the split is explicit — 3742 of 3743
lines in round 1 are from the sleep — so **the noise demonstrably arrives
without ending a suspend.**

That does not make the noise harmless: what changed between the morning's 52–63 s
sleeps and these full windows is still unnamed, and the same traffic was present
in both. It does mean the design question moves. "The modem sends packets, so we
wake" is now known to be false as stated; the filter's job is narrower than it
looked, and possibly unnecessary in this regime.

## Pre-registered: what the corrected census must show, and what would falsify the filter

Written before the run, because the reasoning is short enough to commit to and
the outcome is decisive either way.

**The mechanism forces a prediction.** The modem SMD edge is armed as a system
wakeup source. `irq_pm_handle_wakeup()` turns any interrupt on a wake-armed IRQ
into a system wakeup **before the handler runs**, so during s2idle *every* SMD
interrupt ends the suspend. A QRTR packet cannot be delivered without that
interrupt. Therefore, in the window bounded by `SUSPENDING` and `RESUMED`:

| round | prediction |
|---|---|
| ended by the RTC (`pm_wakeup_irq=72`) | **zero** QMI messages. Nothing arrived, or the sleep would have ended |
| ended by the modem edge (139/141) | exactly the packet(s) that ended it, and nothing else |

**What each outcome means:**

- **Prediction holds.** Then in this regime the modem is *genuinely quiet* — it
  does not send indications that we absorb, it does not send them at all — and
  the filter's premise ("much arrives, little deserves a wake") is **false
  here**. There would be nothing for a filter to filter, and the lead should be
  parked rather than built. The short-sleep regime becomes the only place the
  design could still matter, and it has to be re-measured there.
- **Packets appear in an RTC-ended round.** Then something is wrong in the
  reasoning above — most likely the edge is not armed the way we believe, or a
  packet path exists that does not raise that interrupt. Either would be a more
  important finding than the filter, and would have to be chased before anything
  is written.

☠️ Note which way this cuts. The comfortable outcome for a design already
sketched, argued and half-documented is the second one. **The first outcome
retires it**, and the first is what the mechanism predicts. Record that here so
the reading afterwards is not free to prefer the other.

## ✅ ANSWERED 2026-08-30 14:23 — the prediction held, so this lead is PARKED

The census was re-run with the window bounded by
`/usr/lib/systemd/system-sleep/zz-fp3-trace-marker`, which runs after every
inhibitor including ModemManager's terse path — the third boundary attempt, and
the first one that is actually the sleep.
Full capture: [`../captures/2026-08-30_wake-qmi-sleephook/`](../captures/2026-08-30_wake-qmi-sleephook/).

| round | slept | ended by | QMI messages inside the window |
|---|---|---|---|
| 1 | 46 s of 600 | `141 smd-edge` | **1** |
| 2 | **600 s of 600** | `56 pm8xxx_rtc_alarm` | **0** |

Both IRQ names resolved from that boot's own `/proc/interrupts`.

**The prediction above held exactly**, and by this page's own pre-registration
that is the outcome which **retires the filter**:

> *"Then in this regime the modem is genuinely quiet … the filter's premise
> ('much arrives, little deserves a wake') is **false here**. There would be
> nothing for a filter to filter, and the lead should be parked rather than
> built."*

One packet in 646 s of sleep is not a filtering problem. **Parked.**

### What would reopen it

Only one thing, and it is named in the pre-registration too: **the short-sleep
regime.** This morning's sleeps were 52–63 s and every one of them ended on the
modem edge; the two rounds above were taken in the long regime, where the phone
fills a 600 s alarm. If a census run *inside* the short regime shows many packets
per sleep, the premise is true there and the design comes back. Until that
measurement exists, this page is closed.

☠️ **A note on how this was read, because it went wrong first.** Within an hour
of the result the capture's own write-up concluded that the census *justified*
the filter — the exact reading this section's pre-registration was written to
prevent, by a page that says in bold which way the reading would be tempted to
cut. Pre-registration only works if it is re-read **at reading time**, not only
at writing time. Corrected in `fdaf2a4`.
