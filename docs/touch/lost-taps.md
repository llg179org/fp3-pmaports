# The other touch fault: taps that vanish without a trace

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
