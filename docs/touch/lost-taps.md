# The other touch fault: taps that vanish without a trace

**Status 2026-09-10.** A fix is on the device and **not yet measured against
the fault** — see [the trail at the end](#2026-09-10-the-fix-under-test-idle-mode-off-charger-mode-on).
Earlier text below is kept as written on 2026-09-06.

**Status 2026-09-06.** A *second*, distinct fault, separated from the i2c stall
of [`142-i2c-stall.md`](142-i2c-stall.md) on this date. Taps go missing while
the panel is otherwise healthy and the kernel logs **nothing at all**: no i2c
timeout, no checksum error, no failed read. r88 carries a diagnostic for the
leading mechanism and is on the device; **it has not fired yet**, and until it
does or is shown not to, the mechanism below is a hypothesis with a code path,
not a measurement.

## Why it is a different fault

The i2c stall has a loud signature — `transfer to 0x48 timed out`, `SDA 1
SCL 0`, `I2C_STATUS 0x0411a700` — and since r86 it recovers in 2.1 ms. This one
has no signature at all. Between 10:30 and 11:13 on 2026-09-06 there was not a
single i2c error, and taps still went missing.

## The two code facts that make it invisible

**1. The input core swallows an empty frame.** `himax_process_event()` always
calls `input_mt_sync_frame()` and `input_sync()`, but the input core drops a
`SYN_REPORT` when nothing changed since the last one. An event carrying zero
touch points therefore produces **no frame and no log line** — nothing reaches
`/dev/input/eventN` for any observer to see.

**2. ☠️ An all-zero event passes the checksum.**

```c
u16 checksum = 0;
for (i = 0; i < sizeof(*event); i++)
        checksum += data[i];
if ((checksum & 0x00ff) != 0)
        return false;
```

A buffer of zeroes sums to zero and is accepted. And zeroes are *not* what this
controller reports: its idle frame is `0xff`
(`himax_event_get_num_points()` special-cases `num_points == 0xff`, and an
unused slot is `HIMAX_INVALID_COORD` = `0xffff`). So a read that comes back
empty — noise, a NAK, a truncated transfer — is read by the driver as **"nobody
is touching the panel"**, silently.

Together: a corrupted read becomes a lost tap with no evidence anywhere.

## What was actually measured

Two moments, both marked by the operator with the power button (a separate
input device, `pm8941_pwrkey`, which the touch path cannot swallow; `logind`
timestamps it as `Power key pressed short`).

**10:35:26.** Cadence 147 ms (press-to-press: 192 123 127 157 159 140 143 133);
`#236 → #237` took **316 ms, 2.15x**. One tap's worth of time with nothing
recorded, marker 430 ms later.

**11:12:21–23**, operator tapping a keypad continuously and confirming it:

```
11:12:21.007  LIFT 965.7 ms (median 83)  irqs=+2 frames=0  -> CHIP REPORTED, NO PRESS
11:12:22.262  LIFT 555.8 ms (median 83)  irqs=+1 frames=0  -> CHIP REPORTED, NO PRESS
11:12:23.136  LIFT 797.8 ms (median 83)  irqs=+3 frames=0  -> CHIP REPORTED, NO PRESS
11:12:23.336  GAP  199.5 ms  down=True
        <- 11:12:23  Power key pressed short   (the marker)
```

Three consecutive lifts at 7-12x the cadence, each carrying interrupts and
delivering no frame, with a finger on the glass throughout.

## ☠️ How nearly this was reported wrong — three times

The instrument was rebuilt three times in an hour, and each version produced
confident output that was wrong:

| version | what it claimed | why it was wrong |
|---|---|---|
| v6 | `CHIP NEVER REPORTED` on 17 of its first 30 presses | it gated on the **lift**, where no finger means no interrupts — a known *negative* dressed as a known positive. The gate refused the instrument, correctly |
| v6 | `frames=1` on every lift | `frames_at_release` was taken before the release's own `SYN_REPORT`, making the frame half a constant |
| v7 | seven `CHIP REPORTED, NO PRESS` around a charger plug | `/proc/interrupts` counts the **hard** IRQ, which fires before `BTN_TOUCH` reaches userspace, so a window ending at the press contained **the press's own interrupt**. Quiet lifts alternated +0/+1 on sampling phase alone; five of the seven were this artefact |

v8 ends the window 40 ms before the press and gates twice: on the **hold**
(a known positive — interrupts must rise while a finger is down: 30/30, +3 to
+23) and on the first 30 **lifts** (short ones must read +0: **18/18**). Only
after both passed was anything above quoted.

The general shape is the one already in `fp3-kernel-test`: *an instrument that
is plausible is more dangerous than one that is obviously broken*, and a gate
belongs **inside** the tool, not beside it.

## What r88 does, and what it deliberately does not

```c
if (!memchr_inv(&event, 0, sizeof(event)))
        dev_warn_ratelimited(&ts->client->dev,
                             "all-zero event accepted by the checksum\n");
else if (!himax_event_get_num_points(&event))
        dev_dbg(&ts->client->dev, "empty event: %*ph\n", ...);
```

Behaviour is **unchanged** — the event is still processed exactly as before — so
the next occurrence measures whether reads really do come back as zeroes without
a fix confounding it. The `dev_dbg` arm is silent by default and shows the
*legitimate* point-less reports for comparison when dynamic debug is on.

☠️ **A silent r88 is a result too**, and the opposite one: if hours of ordinary
use produce dropouts but no `all-zero event` line, the read is not returning
zeroes and this whole page is wrong.

## Why no more keypad marathons are needed

Every earlier instrument was tap-driven — lift cadence, a missing `PRESS` — which
is why catching this cost the operator a tired hand. r88's check runs on **every
interrupt**, and the chip interrupts without a finger (an i2c timeout landed
38 s into a boot with one touch interrupt in the whole boot; `SWALLOWED` lines
appear with nobody near the panel). Ordinary use is enough.

## If r88 stays silent: automating the stimulus

☠️ **`uinput` and `adb shell input tap` are not options** and never were: they
inject into the input layer, bypassing the sensor, the controller and the bus —
the three things under test — so they would pass unconditionally. `pytest` has
nothing for this either; it runs Python functions, it cannot touch glass.

What does work is a **capacitive finger**: conductive tape on the panel, switched
to ground through a relay or MOSFET driven from the host. No moving parts, a few
euros, and it exercises the real sensing front end. A servo or solenoid tapper is
the same idea with more hardware. Neither is worth building before r88 answers.

## Reading the instruments

```sh
fp3-ssh 'sudo -n dmesg | grep -E "all-zero event|Wrong event checksum"'
fp3-ssh 'sudo -n journalctl -b | grep "Power key pressed short"'   # the markers
fp3-ssh 'tail -40 /home/fp3/142-gaps.txt'                          # lifts, gaps, gates
fp3-ssh 'systemctl is-active fp3-touch-gaps fp3-screen-mark fp3-i2c-qup-dyndbg'
```

☠️ The gap logger writes to a **file**, not the journal: `journalctl -u
fp3-touch-gaps` shows only systemd's own lines and looks like a dead instrument.

☠️ Its process is not what `pgrep -f` finds — that matched the wrong pid three
times in one day. Use `systemctl show -p MainPID --value fp3-touch-gaps`.

## 2026-09-06, closed for now: the kernel is exonerated, the loss is above it

Three runs with both ends of the chain logged on one clock — the kernel's
`/dev/input/eventN` (`142-gaps.txt`, contacts counted by `ABS_MT_TRACKING_ID`)
and a GTK client after the compositor (`taptest.log`).

**The finding that holds across all three, and is the reason to stop here:**

```
alternation breaks with a kernel CONTACT in the gap:   53/53 · 7/7 · 33/33
```

Every single time the client's record shows a repeat where the operator was
alternating, the kernel had delivered a touch in between. **The touch reaches
`/dev/input` and does not reach the application.** Nothing below that line is
implicated: not the controller, not the i2c bus, not the himax driver.

That closes the question the morning could not: the i2c stall of
[`142-i2c-stall.md`](142-i2c-stall.md) was real and was fixed, and it is **not**
the fault the operator has been feeling.

### What is NOT established, and was nearly reported as if it were

| run | phoc scheduling | swallowed |
|---|---|---|
| 1 | `SCHED_OTHER` 0 | 13.7 % |
| 2 | `SCHED_RR` 5 | 1.0 % |
| 3 (control) | `SCHED_OTHER` 0 | **2.6 %** |

A 14x improvement from raising the compositor's priority looked decisive. The
A-B-A control refused it: restoring `SCHED_OTHER` did **not** bring 13.7 % back.

☠️ **Run 1's number is contaminated.** It ran 475 s at 0.86 taps/s with long
pauses, and every stray contact in a pause — the phone being held, a palm —
counted as "swallowed" because no tap followed it. Runs 2 and 3 were dense
(3.7 and 5.5 taps/s) and short. The honest magnitude is **2-4 %**, and the
scheduling question is **open**, not answered.

The break-anchored count is the one to trust: it sits between two real client
taps, so a stray contact cannot inflate it.

Two-finger use is not the mechanism either: of 24 swallowed contacts in run 3,
**2** fell in a tight (<60 ms) pair.

### The remaining segment, and the instrument that will split it

"Between `/dev/input` and the application" is still two places, because the
client-side probe used `Gtk.GestureClick` — which is itself a gesture
recogniser and can reject a touch it reads as the start of a drag.

```
/dev/input → libinput → phoc → Wayland → GDK → GTK gesture → app
             └─────────── measured as one ───────────┘
```

`fp3-taptest.py` now carries a second, raw counter on
`Gtk.EventControllerLegacy`, which sees the `GdkEvent` before any gesture
arbitration:

* kernel `CONTACT` present, **`RAW touch-begin` absent** → lost in libinput or phoc
* `RAW` present, **tap absent** → lost in GTK's gesture recognition

One session with the new build answers it. Nothing else here needs a kernel.

### Where the sources are

`docs/power/bringup/tools/` — `fp3-taptest.py` (client side, with the raw
counter), `fp3-touch-gaps.py` (kernel side), `fp3-screen-mark`. That page also
lists the six ways these instruments produced confident, wrong output before
they were trusted; that list is the transferable part of this investigation.


## 2026-09-10 — the fix under test: idle mode off, charger mode on

The four lines `/fp3-kernel-test` rule 6 asks for, written while the capture is
open. The fourth is the one that is still empty.

**Symptom.** Taps go missing in runs; the operator reports them as following a
pause of a few seconds (*"két 3 s-os alvás után visszatérve jön elő"*, and on
2026-09-10, that it is the touch controller that sleeps, not the display). At the
kernel the shape is one finger's contacts arriving while the other finger's are
absent from the event stream, no interrupt raised for them — the controller
reported nothing (2026-09-10 14:09:38–39, four left contacts x 333/344/323/321
device units, no right contact for 698 ms, `himax_irq_handler` entries only for
the left ones). The driver was exonerated three layers deep on 2026-09-10 and the
fault placed at or below the controller.

**How to provoke it.** Alternate-tap in the `.O` app, pause 3 s or more without
touching, resume. Hit rate: **not established** — the 2026-09-10 14:09 session
contained no demonstrable loss, and the instrument cannot tell "finger not down"
from "controller silent" (see `findings-log.md`, 2026-09-10).

**The change** — `wip/7.1.3/touch` c03ea86b360b, 42b5f155c825, 519519bf9517; twins on
`integration/7.1.3` and `debug-int/7.1.3`; module hot-swapped 19:10:

1. `let the supplies settle before the reset` — 20 ms after enabling the rails;
   measured: with the panel off, probe's ID read NACKed 3/3 without it.
2. `keep the controller out of idle mode` — clears bit 3 of the firmware word at
   `0x10007088` (the vendor's `himax_idle_mode()` writes `0x17`/`0x1f`). Three
   things it had to learn, each measured before it was written in:
   - the AHB *command* registers are one byte wide and adjacent; the regmap's
     32-bit `regmap_write(0x13, 0x31)` puts three zero bytes into `0x14–0x16`,
     after which a firmware-word read returns its first byte repeated
     (`5a 5a 5a 5a` for `5a a5 5a a5`). The firmware words are reached with
     one-byte SMBus command writes, the vendor's form;
   - the firmware **reloads its configuration from flash after a reset** and
     overwrites the idle word with the stored default: a value written 1 ms after
     the reset was still there 10 ms after probe returned and gone by 50 ms, so
     nothing is written for 100 ms after a reset (`HIMAX_FW_RELOAD_MS`) and the
     first interrupt re-reads the words;
   - the bit is a **configuration switch, not a state flag**: cleared from
     userspace it stayed cleared for 30 touch-free seconds (0 interrupts).
3. `tell the controller when a charger is present` — writes `a55aa55a` /
   `77887788` to `0x10007f38` from a power-supply notifier via the interrupt
   thread; the vendor does the same from its touch path. Proven by setting the
   word to `77887788` from userspace and rebinding: the driver put `a55aa55a` back.

**The effect.** On the *registers*, measured: idle byte0 `0x3f` → **`0x37`** at
+1 s and +5 s after probe, charger word **`a55aa55a`**, no `Failed to …` line.

On the *fault*: **no effect — measured as a 2×2 within one session,
2026-09-11 00:27–00:53, same operator, same rhythm, the two firmware words
toggled from userspace between legs** (`tools/hx-legs.py`, anchored on the
day's restart):

| idle mode | charger mode | taps | unexplained breaks | contacts ≥100 ms |
|---|---|---|---|---|
| off | on  | 943  | 11 (1.17 %) | 14 (1.5 %) |
| off | off | 800  | 24 (3.00 %) | 14 (1.7 %) |
| on  | off | 1001 |  6 (0.60 %) |  8 (0.8 %) |
| **on** | **on** (shipped) | **1053** | **7 (0.66 %)** | 8 (0.8 %) |

Neither switch lowers the rate; the idle-off legs were the worse ones, and they
were also the first twelve minutes of the session, so rhythm is confounded with
the setting. A short leg (123 taps) in the shipped state read 8.9 % and its
repeat over 1053 taps read 0.66 % — sample size, not signal. The kernel-level
signature is flat across all four legs: the surviving finger's contact stretches
to 130–200 ms while the other finger's is absent and `hx_irq` entries dip to
1–4 per 100 ms for ~300 ms (00:28:56, idle bit clear the whole time).

☠️ **So the idle-mode switch and the charger-mode word are not the mechanism**,
and queue 184 is closed as refuted. **Dropped on 2026-09-11 at the operator's
decision** ("dobd el aminek nem volt hatása"): the idle-mode, charger-mode and
panel-follower commits and the DT `panel` link — correct code with no measured
effect. `wip/7.1.3/touch`, `integration/7.1.3` and `debug-int/7.1.3` were reset
to the supply-settle commit and force-pushed **after** tagging the old tips
`archive/{wip-7.1.3-touch,integration-7.1.3,debug-int-7.1.3}-fwwords-2026-09-11`,
which also keep `965404d95138` (the `r89` pin) reachable. Commit 1 (supply
settle) fixes a measured probe failure and stays; `r90` is built from it.
What the dropped commits taught (the command-register write width, the
firmware reload window, the panel reset) stays in `findings-log.md` and would
be needed again by anyone who writes to those words.

The fault is still at or below the controller — three layers agree, and the
knobs the vendor driver touches do not move it. Two things come next, in
this order. **An automated stimulus** (queue 186): the rate is operator-
and rhythm-dependent enough that a 2×2 needed four hand-tapped legs of ~1000
taps to separate signal from sample size; the section "If r88 stays silent:
automating the stimulus" above sketches it, and it is now required rather than
optional. Then **the oracle**: the same alternating run on Ubuntu Touch with
an evdev logger. If
the loss is there too, it is firmware or hardware and no kernel change on our
side will reach it; if it is not, something the vendor stack does *other* than
these two words is missing here.

☠️ Two things learned the expensive way while getting there, kept in
`docs/power/bringup/findings-log.md` (2026-09-10): unbinding this driver with the
display off kills the panel (the driver held the last reference to `iovcc`),
and reloading the module with kprobes armed on its functions fires
`WARNING kernel/trace/ftrace.c ftrace_bug` — `tools/hx-swap.sh` guards both.
