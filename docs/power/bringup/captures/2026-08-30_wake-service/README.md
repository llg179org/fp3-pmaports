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


## ★★★★★ The call's own port, measured — the filter is now fully specified

The round the call landed in carries a packet source that appears in **no other
round**:

```
round 1 (the call, 10:39:15):   4 x type=1 src_node=0 src_port=39 -> dst_port=16408
round 3 (601 s, no call):       src_port=39 does not appear at all
```

**Port 39 is the Voice service**, per the name-service map captured in the same
run — so the call's arrival is now **observed**, not inferred from the map. And
its absence from the quiet round is the control that makes it meaningful.

The criterion is therefore complete and measured on both sides:

| decision | source | service |
|---|---|---|
| **WAKE** | `src_port=39` | **Voice** — the call |
| ignore | `src_port=40` | Network Access Service |
| ignore | `src_port=52` | Data System Determination |
| ignore | `src_port=45` | Wireless Data Service |
| ignore | `src_port=44` | User Identity Module |
| ignore | node 5, `src_port=10` | not the modem |

⇒ [`leads/selective-smd-wakeup.md`](../../leads/selective-smd-wakeup.md) has
everything it was missing. `qrtr_endpoint_post()` already parses `src_port` before
delivery, so the filter is a comparison, and the remaining unknowns are the ones
that page names: whether `pm_system_wakeup()` may be called from that context,
and whether SMS and other must-wake events need ports of their own on the list.

☠️ **Sample size, stated plainly:** four packets from one call, against one quiet
round. The presence/absence contrast is clean, but a filter built on this list
must be validated by *the same measurement after the change* — a call that still
rings, and a quiet night that is no longer interrupted — not by the list looking
right.
