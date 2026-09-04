# What else happens when the touch stalls? Nothing. 2026-09-04, 15 events.

A negative result, with the controls that make it worth something. The question
was whether the `-110/-6` correlates with anything else on the system — dhcp,
wifi, the modem, the charger, the display, a timer.

## The kernel log: silent

**Not one kernel message of any kind within ±20 s of any of the 15 events**,
other than the `-110`/`-6` pair itself. The boot's kernel log is 806 lines and
~700 of them are one thing (below), none near a stall.

## The charger storm, excluded with a control

The log is dominated by `qcom-smbx-charger evt input-current-limiting`, ~700
lines alternating `rt=00/a0/…` and `rt=00/80/…`. Tempting, and wrong:

```
nearest charger event before a -110     median 1877 s
nearest charger event before a random point   median 1621 s
```

The charger burst belongs to a charging phase early in the boot and had ended
(`chg=terminate`) long before any stall. Excluded.

*(Separately worth someone's attention: ~700 PMIC interrupts in one charging
session, flapping between two states, is a lot. It is not this bug, and it is
not written up here beyond this note.)*

## Userspace: three candidates, all killed by the right control

Within ±20 s of the 15 events, against **random** times in the same window:

| candidate | near -110 | near random | first read |
|---|---|---|---|
| `fp3-usbnet-watchdog` ("Heal a jammed USB-NCM link") | 100 % | 100 % | no signal |
| `phoc` `DSI-1: Atomic commit failed: Resource busy` | 80 % | 36 % | **enriched?** |
| ModemManager RSSI update | 67 % | 65 % | no signal |
| sshd session opened (my own polling) | 40 % | 40 % | no signal |

☠️ **The `phoc` enrichment is an artifact of the wrong control.** A `-110` only
happens while the operator is touching, and the compositor only commits frames
while something is on screen — both are markers of *activity*, so a control drawn
from the whole window compares "busy" against "mostly idle".

Re-run against an **activity-matched** control — 400 seconds drawn only from
seconds in which the touch interrupt counter actually advanced:

| candidate | near -110 | near an active-touch second |
|---|---|---|
| `phoc` Atomic commit failed | 80 % | **92 %** |
| `fp3-usbnet-watchdog` | 100 % | 100 % |
| ModemManager RSSI | 67 % | 76 % |

The display message is *less* common around a stall than around an average
active second. Nothing survives.

☠️ And note what the first table would have produced on its own: "9 of 15 stalls
have the USB-NCM watchdog within 20 s" is a true sentence about a service that
runs so often it is within 20 s of everything, including 100 % of random points.
A base rate is not a finding.

## Not periodic either

Intervals between consecutive events: 47, 618, 62, 243, 43, 726, 62, 23, 57, 46,
472, 104, 38, 161 s — 23 s to 726 s, no cluster and no clean modulus at 15, 20,
30, 47, 60, 62 or 120 s. A timer-driven cause would show one; this is shaped like
a load-driven event, consistent with everything else: it happens when the panel
is touched, and only then.

## What this excludes, and what it leaves

Excluded: another subsystem disturbing the i2c bus at the moment of the stall,
in any form that reaches a log. Also excluded, from earlier: system suspend, the
charger, and our own i2c-qup pinctrl fix being absent (it is present).

Left standing, and still unexplained: **the transaction hangs for reasons that
leave no trace anywhere except its own errno.** The next test is the runtime-PM
one in `RESUME-at-the-weekend.md` — the controller autosuspends after 1 s idle,
and the first transaction after a resume is the remaining suspect.
