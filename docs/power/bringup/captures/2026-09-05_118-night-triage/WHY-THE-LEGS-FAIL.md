# Why the legs fail — and the three legs were not the same experiment

Follow-up to `README.md`, same evening (2026-09-05 04:00), from the journal of
the 2026-09-03 night. It corrects that page on one point and adds two findings
it did not have.

## The correction

`README.md` says *"neither night can name what woke the AP"*. That is too
strong. The **2026-09-02** night did name it, and `night-run.sh` carries the
fix and its measurement in a comment:

> with no DHCP server answering, NM retried a lease on wlan0 **197 times inside a
> 77-minute leg** — one every ~23 s — and the AP's median sleep was 11 s against
> a 90 s alarm

`nmcli device set wlan0 managed no` was added for the leg. On 2026-09-03 it
**worked**: the run log carries no "could not unmanage", and leg 1's window
contains zero NetworkManager or DHCP lines. The leg failed anyway.

So the accurate statement is narrower and worse: **the known wake source was
identified, mitigated, and the night still failed.**

## Finding 1 — leg 1 failed with a completely silent userspace

Journal lines strictly inside each leg's own window:

```
leg1  20:43:43-21:59:32    NM/DHCP = 0     TOTAL JOURNAL LINES = 1
leg2  22:00:16-23:16:10    NM/DHCP = 71    total = 12387
leg3  23:17:04-00:32:46    NM/DHCP = 26    total = 10419
```

**One line in seventy-six minutes**, and the AP's median sleep was still 13 s
against a 90 s alarm. Nothing in userspace was logging, and nothing needed to be:
whatever ends these sleeps is below the journal. That eliminates NetworkManager,
and with it every userspace daemon that would have left a trace.

## Finding 2 — legs 2 and 3 ran with ModemManager in DEBUG

Those 12 387 and 10 419 lines are QMI traffic, `<dbg> [qrtr://0] received
message` and friends, at ~2.7 lines per second. The source is a persistent
drop-in:

```
/etc/systemd/system/ModemManager.service.d/zz-fp3-debug.conf   created 2026-09-02 06:41
  ExecStart=/usr/sbin/ModemManager --log-level=DEBUG
```

It was **still active when this page was written**. A daemon logging thousands
of QMI messages is both a plausible wake source and a contaminant in a
sleeping-current measurement, and it was present for two of the three legs.

## ☠️ Finding 3 — the three legs were not comparable

ModemManager **started at 22:00:11**, at the boot for leg 2. During leg 1 it was
not running at all, which is why that window is silent.

So the night's three legs differed in whether the modem daemon existed:

| leg | ModemManager | journal | median sleep |
|---|---|---|---|
| 1 | **not running** | 1 line | 13 s |
| 2 | running, DEBUG | 12 387 | 18 s |
| 3 | running, DEBUG | 10 419 | 9 s |

The whole design of the replication is that **the three legs differ only by the
boot** — that is what makes the spread of their means a boot-to-boot term. These
differ by the largest userspace variable on the device. Even if every leg had
slept its full alarm, their spread would not have been the boot-to-boot spread.

This is a second, independent reason the night cannot answer its question, and it
would not have been fixed by the legs sleeping properly.

## What this changes for the next attempt

The instrument change queued as #158 stands, and gains two requirements:

1. **Record the wake source per leg** — the original point, and now sharper:
   leg 1 proves the cause is not in the journal, so a `wakeup_sources` (or
   wake-reason) snapshot is the only thing that can name it.
2. **Assert the leg's userspace configuration, and log it** — at minimum whether
   ModemManager is running and at what log level. A leg that cannot state this
   is not comparable to another leg.
3. **Take the debug drop-in off before any sleeping measurement.** It is
   persistent, it survives reboots, and queue item #75 ("who writes it back")
   suggests it has reappeared before.
