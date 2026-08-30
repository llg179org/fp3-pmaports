# R1b — does this phone ask for a suspend by itself?

> ⚠️ AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.

**Window 2026-08-30 17:53 → 18:23**, `idle-suspend-window.sh 1800 60`, armed as
`systemd-run --unit=r1b` so no connection is held open. Baseline read before the
change: `suspend_stats success=13 fail=0`.

Configuration under test: a `/run` logind drop-in setting `IdleAction=suspend`
with `IdleActionSec=60`. `/run` is tmpfs on purpose — a reboot undoes the
experiment whether or not the script's trap ran. The modem edge is left armed, so
an incoming call still wakes the phone; a residency result bought by dropping
calls answers a question nobody asked.

## Two witnesses, and the second one needs no connection

1. **On the phone:** the `success` delta across the window, read from
   `/sys/power/suspend_stats` before *and* after (an absolute count afterwards
   cannot say what happened *in* the window).
2. **On the host:** the kernel log. When this phone suspends, the CDC-NCM link
   drops and `usb 1-5` disconnects; on resume it re-enumerates. This witness
   costs nothing and **cannot perturb what it watches**, which the first one can
   — every ssh is a wake, and an open ssh session is a sleep inhibitor
   (`/etc/sleep-inhibitor.conf`).

Host baseline for the window: the last enumeration before it was `17:52:40`
(the phone waking from the final step-0 round, which the stop trip caught).

## ☠️ Pre-registered, written BEFORE the result

A `success` delta of **0** has (at least) two readings, and they are not the same
finding:

* **the policy never fired** — `IdleAction` acts when logind considers the
  sessions idle, and a graphical session with the display on may never report
  idle at all. Then the window says nothing about whether the phone *can* stay
  asleep, only that this lever does not reach it;
* **the policy fired and something refused** — a held inhibitor, or a suspend
  that was requested and aborted.

The two are distinguished by the inhibitor list the script prints at both ends
and by the kernel's `PM: suspend entry/exit` pairs, both of which it captures.
☠️ **Do not report a bare "the phone never suspends by itself" from a zero
delta** without saying which of the two it was.

A delta **> 0** makes the *length* of those sleeps the next question, not the
count — sleep length on this phone has been measured to range 61–601 s with the
configuration unchanged.

## Result

(pending — window closes 18:23)
