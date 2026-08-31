# The modem does not refuse the terse unregister — measured with an instrument that can say no

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed the measurement it rests on.

2026-08-31. ModemManager built from upstream `5e91dd2` plus the three local
patches (`qmi-report-failed-unregister`), cross-built for aarch64 in the
pmbootstrap chroot and installed on the device; the packaged binary is kept as
`/usr/sbin/ModemManager.pkg.bak`. Raw: [`terse2.txt`](terse2.txt).

**Why the patched build was needed:** the stock daemon prints
`terse state 3GPP (n/3): … done` **on the statement after dispatching** the
asynchronous operation, and suppresses the error message entirely on the disable
path. Both were fixed locally, so the lines below are written from the
completion callback and a refusal would appear as `<wrn>`.

## The run

`rtcwake -m no -s 120` then `systemctl suspend`, fired from a transient unit that
waits 45 s first so the ssh session that launched it is gone. ModemManager
running, modem `registered / LTE / vodafone HU / attached`.

```
11:15:05  terse state 3GPP (1/3): disable unsolicited registration events done
11:15:05  terse state 3GPP (2/3): disable unsolicited events done
11:15:05  setting terse state (2/2): all done
11:15:06  kernel: PM: suspend entry (s2idle)
11:17:07  kernel: PM: suspend exit
```

**No `<wrn>` line.** ⇒ **The modem accepts both unregisters.** The failure is not
in terse's execution. What still arrives during a sleep is therefore a *different
message set that terse never asks about*, and the question moves from "why is the
unregister refused" to "what arrives that terse does not cover".

☠️ **The strength of this negative is bounded.** The warning branch has never been
observed firing, and a checking tool proves nothing until it has been shown
failing on a known positive. Until that is done, this reads "no refusal was
reported", not "no refusal happened".

## ☠️ It slept the full alarm, with ModemManager running

121 s of a 120 s alarm, by the kernel's own `PM: suspend entry/exit` pair. That
contradicts the pattern `sleep-night.sh`'s header records — *"with the daemon
running every suspend dies within 16-53 s on the modem's SMD edge, 5 of 5"*.

n=1, and the repository already documents that sleep length here is a regime that
varies 61–601 s with no configuration change
([`leads/sleep-length-is-a-state.md`](../../leads/sleep-length-is-a-state.md)), so
this is not yet a contradiction of that finding — but it is the first long sleep
recorded with the daemon running, and it was not predicted.

`pm_wakeup_irq=141`, and on this boot `/proc/interrupts` names 141 `smd-edge` —
the modem — while 56 is `pm8xxx_rtc_alarm`. So the wake is attributed to the
modem edge even though the sleep ran to the alarm's length. The two cannot be
separated from one sample.

For contrast, on the same boot with the daemon **stopped**
([`../2026-08-31_mpss-across-suspend-nomm/`](../2026-08-31_mpss-across-suspend-nomm/README.md)):
602 s slept, woken by IRQ 56, the RTC.

## ☠️ A measurement bug in this capture's own script, found and corrected

The script printed `suspend_stats before: 74` and `after: 74`, which read as a
completed suspend cycle that the counter never counted — a contradiction against
the kernel log in the same file.

It was neither. The heredoc was unquoted and the command substitutions were
escaped as `\$(…)` inside an outer double-quoted `sh -c`, so both `$(cat …)` calls
were expanded **when the script was written**, not when it ran. The two numbers
were one measurement printed twice. Read live afterwards, the counter is 75,
consistent with the kernel log.

The general form, worth carrying: **two readings that are identical by
construction look exactly like a quantity that did not change.** A before/after
pair inside a generated script has to be proven to be two separate reads.
