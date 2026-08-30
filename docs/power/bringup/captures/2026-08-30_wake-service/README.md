# 2026-08-30 — what wakes the phone, named at the service layer

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed the measurement.

**Why the layer matters.** The radio-off control established that what ends every
suspend arrives *from the network* — but so does an incoming call, so naming the
**channel** (IPCRTR, which the 2026-08-22 census did) cannot separate them by
construction. This census names the **service**, which can.

Three sleeps, 600 s alarm, three probes; the script reports which armed
(`chan hdr` — `qrtr_port_lookup` was refused, presumably inlined, and that is an
answer rather than a silent gap).

## The result

Every QRTR packet seen across the three sleeps, with the ports resolved against
the name-service map captured in the same run:

| src | port | service | seen |
|---|---|---|---|
| node 0 (modem) | **52** | **Data System Determination** | 1 |
| node 0 (modem) | **40** | **Network Access Service** | 1 |
| node 5 | 10 | not the modem — the map lists node 0 only | 2 |

And from the same map, the port that matters on the other side:

| — | **39** | **Voice service** | *where a call would arrive* |

⇒ **The noise is NAS and DSD indications** — registration, signal strength, cell
and RAT state. **A call arrives on a different port.** So the two are separable at
the QRTR port layer, which is the criterion
[`leads/selective-smd-wakeup.md`](../../leads/selective-smd-wakeup.md) needed and
did not have. Its plan-B section — filter one layer up from SMD — is now the main
plan, not the fallback.

## ★ And the interrupt/packet ratio is what makes the design viable

Per sleep: **35–47 IPCRTR interrupts against 1–3 QRTR packets.** Most of the
edge's interrupts carry no message at all, which matches the 2026-08-22 finding
that the ring is signal-level. That is exactly the property the design needs: an
`IRQF_NO_SUSPEND` handler runs on every interrupt but would call
`pm_system_wakeup()` only when a packet worth waking for arrives — and most
interrupts produce no packet to judge.

## ☠️ Limits, stated because the result is small

- **Four packets across three sleeps.** Enough for a direction, not for a ratio.
  A longer census is owed before anything is built on the proportions.
- **The call port is from the map, not from an observed call.** The Voice service
  is listed at port 39; no call was placed during this run. A census taken across
  a real incoming call is what would confirm the separation, and that needs a
  person to dial.
- ☠️ **A misreading in the instrument's own output, corrected here.** The script
  labels its last few trace lines *"the tail is the wake itself"*. It is not: the
  trace keeps running after the resume, so the tail shows post-wake traffic —
  which is why it reads as all `rpm_requests`, the RPM's edge rather than the
  modem's. The witnesses that do hold are `pm_wakeup_irq=139` and the QRTR
  headers. The label is wrong and the next revision should remove it.

Instrument: `tools/wake-service.sh`.
