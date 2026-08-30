# 2026-08-30 — the spread, and the first windows the modem did not end

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed every change and made or reviewed
> every measurement it rests on.

**What was asked.** Not an A/B. The morning had produced six consecutive
52–63 s sleeps and, on the same configuration, one of 601 s — so the question
was the *distribution*, which no two-armed comparison can answer. Twenty rounds
were queued; four completed before the run was stopped in favour of the QMI
census (`tools/wake-qmi.sh`), which had by then become the more informative use
of the phone.

**Command:** `wake-service.sh 600 20 logind`, started 10:56:25, ModemManager on
the distro default (`--test-quick-suspend-resume`), modem registered, all
drop-ins cleared.

## The result

| round | slept | ended by |
|---|---|---|
| 1 | 601 s of 600 | `pm_wakeup_irq=72` — the RTC |
| 2 | 601 s of 600 | 72 — the RTC |
| 3 | 600 s of 600 | 72 — the RTC |
| 4 | 601 s of 600 | 72 — the RTC |

Four of four filled the window, and **not one was ended by the modem**. Every
previous short sleep on this front ended on IRQ 139/141, the modem's SMD edge.
The host's USB log agrees independently, and it is the better witness because it
never touches the phone: 10:56:27→11:06:28, 11:06:53→11:16:55,
11:17:19→11:27:19, 11:27:44→11:37:45, and a fifth sleep from 11:38:10 that the
stop interrupted.

`terse` was applied in all four rounds (4 journal lines each).

## ☠️ What this capture does NOT show, and the instrument change it forced

The per-round QRTR header counts — NAS (port 40), DSD (52), WDS (45), UIM (44),
four of each, one per round — **cannot be read as "traffic that arrived while
asleep"**. Tracing stays on across the resume, so the buffer holds the sleep
*and* the first moments of the wake, and a resume alone produces hundreds of
`rpm_requests` inside a second. The counts are therefore "during the sleep or
just after it", which is not the question.

It is tempting, and would have been wrong, to conclude from this file that the
NAS/DSD indications arrive without ending a sleep. They may; this capture cannot
say. What it *does* establish is the RTC ending, which comes from
`pm_wakeup_irq` and is not affected.

`tools/wake-qmi.sh` now writes a `RESUMED` marker to `trace_marker` as the first
statement after the suspend call returns, and cuts the trace there — and says so
in the output, including when the marker is missing, because a split that
silently did not happen looks exactly like a clean one.

## Read with

- `leads/sleep-length-is-a-state.md` — the spread is the subject of that lead.
- `leads/selective-smd-wakeup.md` — the filter this was meant to inform. Four
  RTC-ended windows do not disprove the need for it, but they do mean the phone's
  behaviour in the quiet regime is not what the filter was designed against.
