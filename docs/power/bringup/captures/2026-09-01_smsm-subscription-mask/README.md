# ★★★★★ The modem does not subscribe to the AP-awake bit — the ADSP does. My own lead, killed in 30 seconds without a measurement window

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed the measurement it rests on.

2026-09-01 22:00, `tools/smsm-mask.py`, a **passive** read of shared memory —
no register write, no QMI, no radio. It ran *inside* the undisturbed overnight
window because it cannot disturb anything.

## The question it settles

[`../leads/smsm-proc-awake.md`](../leads/smsm-proc-awake.md), written two hours
earlier, found a real asymmetry in the AP-side source: the vendor kernel sets
SMSM bit 12 (`SMSM_PROC_AWAKE`) at boot and clears it across suspend, and
mainline never touches it. The page named the gap honestly — *"whether the modem
firmware reads bit 12 at all is closed firmware"* — and proposed a flashed A/B.

It did not need one. `notify_other_smsm()` wakes a remote **only for the bits
that remote subscribed to**, and the subscriptions are in shared memory beside
the state.

## What the hardware says

```
SMEM master SBL version: 11        (legacy TOC; the walk is valid)
size info: num_entries=5 num_hosts=8

state vector
  entry 0 APPS     = 0x00000600      bits 9,10 - our own wcnss tx state
  entry 1 MODEM    = 0x08000009
  entry 2 Q6/ADSP  = 0x08000001
  entry 3 WCNSS    = 0x08000001

subscription masks over the APPS entry
  APPS     0x00000000
  MODEM    0x00800000      bit 23 only
  Q6/ADSP  0x00001000      ☚ bit 12, and nothing else
  WCNSS    0x00000640      bits 6, 9, 10
```

**The modem's mask over the APPS entry is bit 23 alone.** It never asked to hear
about bit 12, so setting the bit cannot wake it and cannot change what it does
per wakeup. As a modem-duty candidate this lead is **dead**, and it died for the
price of one ssh login instead of a flash, a reboot and two 600 s windows.

Bit 12 of the APPS entry is also confirmed **clear** in the live state vector
(`0x00000600`), exactly as the source reading predicted — so that half of the
lead was right.

## ★ And the same table hands the bit to its real owner

**The ADSP subscribes to bit 12 and to nothing else at all.** A single-purpose
subscription is not an accident: the audio DSP is waiting to be told when the
applications processor is awake, and on mainline it never is.

That converges, from a different transport, with what
[`../leads/smp2p-sleepstate-missing.md`](../leads/smp2p-sleepstate-missing.md)
concluded on 2026-08-31 — that the downstream `sleepstate` smp2p entry is aimed
at `remote-pid = 2`, the ADSP. Two independent readings, two different
mechanisms, one conclusion: **the thing we never tell is aimed at the ADSP.**

And there is a standing, unexplained ADSP problem to point it at: the daemon's
effect on LPASS exists **only across suspend** (2026-09-01 A/B: awake, the ADSP
never power-collapses whether ModemManager runs or not), and `lpass-never-sleeps`
has been open for weeks.

## What this does to the work already done

The two commits and the r80 package built tonight are **not wasted, and not
withdrawn** — they are simply an ADSP experiment now, not a modem one. The patch
is correct, minimal, device-tree-gated and already built; only the pre-registered
reading changes:

> **was:** MPSS duty falls toward ~6 % ⇒ mechanism found.
> **is:** the LPASS counter across suspend changes when the bit is driven ⇒ the
> ADSP was waiting for a signal we never sent.

☠️ And a caution the table itself demands: a subscription proves the remote
*asked to be told*. It does not prove the firmware does anything useful with the
answer. The A/B still has to be run; what changed is which counter it reads.

## Reproduce

```sh
sudo python3 tools/smsm-mask.py     # on the device; passive, safe mid-window
```
