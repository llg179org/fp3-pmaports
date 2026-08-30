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


# The logind re-run — and it breaks the morning's conclusion

☠️ The census above ran over `rtcwake`, which bypasses logind, so ModemManager
was never told to go terse: it described the *unquieted* modem. Re-run down the
logind path, terse confirmed applied (4 journal lines every round),
`wake-service-logind.log`:

| round | slept | ended by |
|---|---|---|
| 1 | **280 s** of 600 | modem edge — **the operator's call**, 10:39:15 `ringing-in` |
| 2 | 64 s of 600 | modem edge |
| 3 | **601 s of 600** | **`pm_wakeup_irq=72` — the RTC alarm** |

**Two results, and the second is a retraction.**

**1. A call woke a phone that had been asleep 280 s, and it rang.** Third
independent confirmation that terse does not cost the call path — this time with
the sleep duration measured around it.

**2. ☠️ "The modem edge terminates every suspend" is false.** Round 3 slept its
entire alarm with the radio up and registered, ended by the clock. It is the
first full sleep with a live radio in this project.

## ☠️ What must NOT be concluded from it

The obvious reading — *"so terse works after all"* — is contradicted by our own
data. The morning's `terse-ab-clean` legs used the **same** configuration, logind
path with terse applied and its four journal lines, and gave **52–63 s in six legs
out of six**. Same knob, same path, same day: 61 s six times, then 280 / 64 /
601 s.

So the honest statement is narrower than either conclusion:

> **Sleep length under an unchanged configuration varies by an order of
> magnitude** (61 s to 601 s), and six consistent samples in the morning
> concealed that. What drives the variance — time of day, network activity, cell
> state — **is not known and is not guessed here.**

That also re-frames the morning's terse verdict: it was not "terse does not
help", it was **six samples from a distribution wide enough that six was not
enough**. Any future A/B on this front needs a sample size chosen against this
spread, not against a hoped-for effect.
