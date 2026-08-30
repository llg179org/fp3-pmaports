# 2026-08-30 — an SMS wakes the phone, and it does so on its own port

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed every change and made or reviewed
> every measurement it rests on.

**Command:** `tools/run-wake-qmi.sh start 600 3`, started 11:50:30, ModemManager
on the distro default (`--test-quick-suspend-resume`), modem registered.
The SMS was sent by the experimenter during the run and reported at 12:17.

## The result

| round | slept | ended by | port 51 (Wireless Messaging) traffic |
|---|---|---|---|
| 1 | 601 s of 600 | `pm_wakeup_irq=72` — the RTC | none |
| 2 | 601 s of 600 | 72 — the RTC | none |
| 3 | **321 s of 600** | **139 — the modem SMD edge** | **yes** |

Round 3 is the only round with any traffic on port 51, and it is the only round
the modem ended. What it carries is exactly the shape of an inbound message:

```
1  src_port=51  IND  msg=1   →  WMS: Event Report   (the modem announcing it)
2  src_port=51  RSP  msg=55  →  WMS: Send Ack       (ModemManager acknowledging)
```

The host's USB log agrees without touching the phone: 12:11:29 → 12:16:49.

## What this settles

- ☠️ **The outcome nobody had tested for does not happen.** An SMS *does* wake
  this phone out of s2idle. The pre-registered table
  (`leads/selective-smd-wakeup.md`) listed "the SMS does not wake the phone at
  all" as the one result that would make the **present** system the bug; it is
  ruled out.
- **The wake list now has two measured entries, not one:** Voice (port 39, from
  the 10:39 call) and Wireless Messaging (port 51). A filter built yesterday
  would have swallowed SMS exactly as the low-power arm swallowed the call.
- **The noise arrives without ending the sleep.** Rounds 1 and 2 slept their full
  windows and still show NAS (40), DSD (52), WDS (45) and UIM (44) traffic. This
  is the first time that can be said at all: the trace is cut at the `RESUMED`
  marker, so these are packets from *inside* the sleep (3742 of 3743 lines in
  round 1), not the resume storm the earlier captures could not separate.

## ☠️ What is solid here, and what is provisional

**Solid — the port level.** The QRTR v1 header offsets are read from
`net/qrtr/af_qrtr.c:39` and the port→service map from `qrtr-lookup` on the
device. "Port 51 appears only in round 3" needs nothing else.

**Provisional — the message-id level.** The decode is new. It names round 3's
port-51 pair as `WMS: Event Report` + `WMS: Send Ack`, which is a **known
positive**: an SMS was deliberately sent, and that is what an inbound SMS looks
like. That is real validation. But two things in the same output do not sit
comfortably and are **not** claimed here:

- most lines decode as `RSP` (a response), and userspace is frozen during the
  sleep, so it is not obvious who asked;
- the same handful of ids recurs in every round with the same counts, which is
  regular enough to be a decode artefact rather than traffic.

Neither affects the port-level result. Before any message id from this capture
is used to justify a change, decode a second known positive — the cleanest being
a placed call, whose Voice-port ids can be checked the same way.

---

## ☠️ WITHDRAWN the same afternoon: "the noise arrives without ending the sleep"

Written above, and wrong. The `RESUMED` marker separates the sleep from the
resume — and **nothing separated the sleep from what came before it**. Tracing is
switched on, and only *then* does `systemctl suspend` run: logind calls
ModemManager, ModemManager runs its terse path, and that path sends
**NAS Register Indications** and **DSD System Status Change** and gets answers.
All of it lands in the buffer while the phone is still awake.

The decode says so plainly once read with MM's source beside it:

```
5  src_port=40  RSP  msg=3   →  NAS: Register Indications   (0x0003)
2  src_port=52  RSP  msg=37  →  DSD: System Status Change   (0x0025)
```

Those are **exactly the two calls the terse path makes** — sourced from
`mm-broadband-modem-qmi.c:4334` and `:4369`, read hours before this capture
existed. Identical counts in all three rounds, which is what a fixed handshake
looks like and not what network traffic looks like.

**So the claim inverts.** What the capture shows on NAS and DSD is not modem
noise that failed to wake us; it is **ModemManager's own suspend handshake**, and
whether any modem-initiated indication arrives during the sleep is **not
answered by this capture at all**.

Two things survive, and they are the two that never depended on the boundary:

- **the SMS result** — port 51 appears in round 3 only, and round 3 is the only
  round the modem ended. A wake is an event at a point in time, not a count over
  a window;
- **the message-id decode is now validated twice.** The SMS pair was one known
  positive; the terse handshake is a second, and a better one, because its
  identity comes from reading ModemManager's source rather than from what the
  answer was expected to be. The `RSP` labels that looked wrong ("who is asking,
  with userspace frozen?") were right all along — **the question was wrong, not
  the decode**: userspace was not yet frozen.

`tools/wake-qmi.sh` now writes a `SUSPENDING` marker before the suspend call and
decodes only what falls **between** the two, refusing to report at all if either
marker is missing. Validated on a synthetic trace: of three messages, only the
one between the markers survives.
