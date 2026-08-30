# 2026-08-30 — the first correctly-bounded census, and it answers the question

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

**Command:** `run-wake-qmi.sh start 600 2` at 14:01, `post` at 14:23, on
`7.1.3-postmarketos-qcom-msm8953`, slot_b, fresh boot.
**Compared against:** the two earlier attempts the same day
(`2026-08-30_wake-qmi-sms/`, `2026-08-30_wake-qmi-2marker/`), whose windows were
bounded one hop too early and one hop too late and whose counts were withdrawn.

The window is now bounded by `/usr/lib/systemd/system-sleep/zz-fp3-trace-marker`,
which runs **after every inhibitor and delay handler**, ModemManager's terse path
included — so `FP3_FREEZE` is the last userspace instant before the kernel
freezes and `FP3_THAW` the first after the thaw.

## The reading

| round | slept | ended by | **QMI messages inside the true sleep window** |
|---|---|---|---|
| 1 | 46 s of 600 | **141 `smd-edge`** — the modem | **1** (`src_port=68 REQ msg=3`) |
| 2 | **600 s of 600** | **56 `pm8xxx_rtc_alarm`** — the alarm | **0** |

Both IRQ numbers were resolved from `/proc/interrupts` **on this boot** (see the
trap below). The terse handshake, which filled the window in both earlier
attempts, is now outside it: 4 terse lines per round, none of them inside.

## What it establishes

**A sleep that runs to its alarm contains no QMI traffic at all**, and the sleep
the modem ended contains exactly one packet. That is the mechanism the selective
filter was designed around, stated as a prediction in
`leads/selective-smd-wakeup.md` before this ran:

> *"ended by the RTC — **zero** QMI messages. Nothing arrived, or the sleep would
> have ended."*

⇒ **Every QMI packet that arrives during s2idle ends the sleep.** There is no
"noise that arrives without waking us" — that reading was withdrawn earlier today
on instrument grounds, and the correctly-bounded window now says the opposite.

⇒ **R1c, the selective wake filter, is justified rather than speculative.** The
thing it would filter is real and is the only thing that ends a sleep.

## ☠️ What this does not say

- **n = 2.** One round each way. The direction is clean and the mechanism
  predicts it, but two rounds are two rounds.
- **The single packet is not identified.** Port 68 was not among the 32 ports the
  run's own `qrtr-lookup` resolved, so `msg=3` decodes to four candidate services
  (NAS `Register Indications`, PBM, VOICE, WDS `Indication Register`) and the
  tool prints all four rather than choosing. Naming it needs a run whose port map
  covers 68.
- Round 1's window is 46 s long, so "1 message" is one message in 46 s, not in
  ten minutes.

## ☠️☠️ The trap this run exposed: wake-IRQ numbers move between boots

On **this** boot:

```
 56: pm8xxx_rtc_alarm          <- the RTC
141: smd-edge                  <- the modem
 72: 1b00020.camss_msm_csid1   <- a CAMERA interrupt
```

Every capture written earlier today reads `pm_wakeup_irq=72` as "the RTC". On
those boots it may well have been; on this one **72 is the camera**. The number
alone is not a name, and `pm_wakeup_irq` is only interpretable against the
`/proc/interrupts` of the boot that produced it. `sleep-night.sh` already
resolves the name inline; `wake-qmi.sh` prints the bare number, and the labelling
was being done by hand in prose — which is exactly where a boot-local number gets
promoted to a permanent fact.
