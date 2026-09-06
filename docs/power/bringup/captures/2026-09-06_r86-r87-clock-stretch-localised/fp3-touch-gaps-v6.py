#!/usr/bin/env python3
"""#142 touch logger, millisecond resolution, no polling.

v5, 2026-09-06: correlate the INTERRUPT count against the frames delivered.

The decisive comparison for a lost tap needs no application at all. The chip
raising its interrupt means "there is touch data"; a SYN_REPORT means the driver
delivered it. A window in which interrupts advanced and NO frame came out is a
tap the kernel swallowed - and unlike the operator watching a calculator, this
sees it without anyone looking. ☠️ It is NOT one interrupt per tap: a press,
its moves and its release are many. So the flag is the ASYMMETRY (interrupts up,
frames flat), never a ratio.

v4, 2026-09-06: also log every BTN_TOUCH transition, and count presses. The
operator's symptom is not lag, it is LOST TAPS - four presses on a calculator
produced one digit, with no kernel error of any kind. A gap logger cannot see
that: a tap that never reaches the input layer leaves no gap, it leaves nothing.
Counting presses against a KNOWN typed string is what separates "the panel or
the driver lost it" from "userspace dropped it".

Reads /dev/input/event4 and uses the KERNEL's own timestamp on every event, so
the resolution is the input layer's, not a sampler's. Logs the interval between
consecutive SYN_REPORT frames, but annotating each with whether a finger
was down at the time.

v2, 2026-09-04: v1 logged a gap ONLY while BTN_TOUCH==1, and was therefore blind
to the fault it was built for. A 15 s i2c stall delivers no frames at all, so the
BTN_TOUCH=1 of the press that triggered it never reaches the input layer either -
`down` stays False and the gap is never logged. Three 15 s stalls passed through
v1 unrecorded. Never filter at capture time; annotate and filter at analysis.
"""
import struct
import collections
import threading, time, sys, select, re

# ☠️ NEVER hardcode the event node. It is handed out in probe order and moved
# from event4 to event7 to event14 on this device inside two days, and every
# driver rebind moves it again - a logger pointed at a stale node reads another
# device, or blocks forever, and looks exactly like "no stalls found".
# v3, 2026-09-06: locate it by the input device NAME instead.
def find_dev(name="Himax Touchscreen"):
    import os
    for d in sorted(os.listdir("/sys/class/input")):
        if not d.startswith("event"):
            continue
        try:
            with open("/sys/class/input/%s/device/name" % d) as fh:
                if fh.read().strip() == name:
                    return "/dev/input/" + d
        except OSError:
            continue
    raise SystemExit("no input device named %r - refusing to guess" % name)

DEV = find_dev()
OUT = "/home/fp3/142-gaps.txt"
FMT = "llHHi"                        # timeval sec, usec + type + code + value
SZ = struct.calcsize(FMT)
EV_SYN, EV_KEY = 0x00, 0x01
SYN_REPORT, BTN_TOUCH = 0x00, 0x14a
GAP_MS = 100.0                       # normal inter-frame is 12-50 ms at 20-80/s

SAMPLE_MS = 20.0
IDLE_MS = 500.0
LIFT_MIN_MS = 150.0      # never report below this, whatever the cadence
LIFT_FACTOR = 1.8        # ... and only if it is this much above the median lift
RING_SECONDS = 8.0
# ☠️ The gate, built into the instrument: a NEW measuring tool reports nothing
# until it has answered a question whose answer is already known. Here that is
# "an ordinary delivered tap must show interrupts > 0 AND frames > 0", so the
# first VALIDATE_FIRST presses print their LIFT line unconditionally. If those
# lines say +0 interrupts, the sampler or the /proc/interrupts parser is broken
# and NOTHING below may be quoted. Only after they pass do the thresholds apply.
VALIDATE_FIRST = 30


def wall(ts):
    return time.strftime("%H:%M:%S", time.localtime(ts)) + ".%03d" % ((ts % 1) * 1000)

out = open(OUT, "a", buffering=1)
out.write("== gap logger start %s  (v6: per-lift IRQ evidence at %.0f ms; first 30 presses are GATE lines; v5 detectors unchanged)\n"
          % (time.strftime("%F %H:%M:%S"), SAMPLE_MS))

def irq_count(name="hx83112b"):
    """Total interrupts for a named handler, across all CPUs.

    ☠️ Located BY NAME, and parsed by TAKING THE LEADING NUMERIC FIELDS rather
    than by counting the trailing ones. The real line on this device is

        138:  4768  0 0 0 0 0 0 0  msmgpio  65 Level  hx83112b

    - three fields between the counts and the name, not two. A regex written for
    two silently swallowed "msmgpio" into the numbers and would have crashed on
    int(). Tested against that exact line before use.
    """
    try:
        with open("/proc/interrupts") as fh:
            for line in fh:
                if not line.rstrip().endswith(name):
                    continue
                fields = line.split()[1:]          # drop the "138:" label
                total = 0
                for f in fields:
                    if not f.isdigit():
                        break                      # first non-number ends the counts
                    total += int(f)
                return total
    except OSError:
        pass
    return None

# ── v6: per-lift IRQ evidence ────────────────────────────────────────────────
#
# v5 could only say "interrupts rose and no frame arrived" over a ONE SECOND
# window, and a burst of tapping puts six or seven taps in each second - so a
# single tap that raised an interrupt without producing a frame hid among its
# neighbours. That is exactly the case being hunted: on 2026-09-06 at 10:35:26
# the operator felt a lost tap and marked it with the power button, and the
# only trace was a 209 ms lift where the burst's cadence was 147 ms. Whether
# the chip had interrupted at all was UNANSWERABLE at one-second resolution.
#
# So sample the counter into a ring at SAMPLE_MS and, when the lift before a
# press is long enough to hold a whole missing tap, print what the counter did
# INSIDE that lift. Then:
#   interrupts > 0, frames == 0  -> the chip reported, the frame never came
#   interrupts == 0              -> the chip never reported at all
# which are different faults in different places.
#
# ☠️ It costs 0.40 ms per read (measured on this device, 18 681-byte
# /proc/interrupts), so 20 ms sampling is ~2 % of one core WHILE TAPPING and
# idles at IDLE_MS otherwise. It reads only; it cannot change what it measures.
ring = collections.deque(maxlen=int(RING_SECONDS * 1000 / SAMPLE_MS))
ring_lock = threading.Lock()
last_frame_wall = [0.0]  # list so the sampler thread can read it without a lock

def sampler():
    """Keep (wall_time, irq_count) for the last RING_SECONDS."""
    while True:
        now = time.time()
        c = irq_count()
        if c is not None:
            with ring_lock:
                ring.append((now, c))
        busy = now - last_frame_wall[0] < 3.0
        time.sleep((SAMPLE_MS if busy else IDLE_MS) / 1000.0)

threading.Thread(target=sampler, daemon=True).start()

def lift_evidence(t0, t1):
    """IRQ samples in [t0, t1]: (count of samples, irq delta, first, last)."""
    with ring_lock:
        sel = [(t, c) for (t, c) in ring if t0 <= t <= t1]
    if len(sel) < 2:
        return len(sel), None, None, None
    return len(sel), sel[-1][1] - sel[0][1], sel[0][1], sel[-1][1]

lifts = collections.deque(maxlen=20)
release_ts = None
frames_at_release = 0

down = False
last_syn = None          # kernel timestamp of the previous frame
frames = 0
gaps = 0
presses = 0
press_ts = None
last_beat = time.time()

irq_prev = irq_count()
irq_mark = time.time()
last_frame_ts = None
frames_at_mark = 0
if irq_prev is None:
    out.write("== ☠️ no hx83112b line in /proc/interrupts - the IRQ half is BLIND\n")

with open(DEV, "rb", buffering=0) as f:
    while True:
        # ☠️ Wake even with no events, or a window in which the driver delivered
        # NOTHING - the very case being hunted - would never be examined.
        ready, _, _ = select.select([f], [], [], 0.25)
        if not ready:
            now = time.time()
            if now - irq_mark >= 1.0 and irq_prev is not None:
                cur = irq_count()
                # ☠️ Only while the panel is IN USE. A chip that raises periodic
                # interrupts with the screen off would otherwise flag every
                # window forever, and a detector that always fires detects
                # nothing. "In use" = a frame was delivered in the last 10 s.
                in_use = last_frame_ts is not None and now - last_frame_ts < 10.0
                if (cur is not None and cur > irq_prev
                        and frames == frames_at_mark and in_use):
                    out.write("%s  SWALLOWED: +%d interrupts, 0 frames in %.1f s\n"
                              % (wall(now), cur - irq_prev, now - irq_mark))
                if cur is not None:
                    irq_prev = cur
                irq_mark, frames_at_mark = now, frames
            continue
        b = f.read(SZ)
        if not b or len(b) != SZ:
            break
        sec, usec, typ, code, val = struct.unpack(FMT, b)
        ts = sec + usec / 1e6

        if typ == EV_KEY and code == BTN_TOUCH:
            down = (val == 1)
            if down:
                presses += 1
                out.write("%s  PRESS   #%d\n" % (wall(ts), presses))
                # ── v6: was this lift long enough to hide a whole tap?
                if release_ts is not None:
                    lift = (ts - release_ts) * 1000.0
                    med = (sorted(lifts)[len(lifts) // 2] if lifts else 0.0)
                    validating = presses <= VALIDATE_FIRST
                    if validating or (lift >= LIFT_MIN_MS and lifts
                                      and lift >= LIFT_FACTOR * max(med, 1.0)):
                        n, d, a, b = lift_evidence(release_ts, ts)
                        fr = frames - frames_at_release
                        if d is None:
                            verdict = "no IRQ samples in the window"
                        elif d > 0 and fr == 0:
                            verdict = "CHIP REPORTED, NO FRAME"
                        elif d == 0:
                            verdict = "CHIP NEVER REPORTED"
                        else:
                            verdict = "frames delivered, not a lost tap"
                        out.write("%s  %s %8.1f ms (median %.0f)  irqs=%s frames=%d"
                                  "  samples=%d  -> %s\n"
                                  % (wall(ts), "GATE" if validating else "LIFT",
                                     lift, med,
                                     "?" if d is None else "+%d" % d,
                                     fr, n, verdict))
                    lifts.append(lift)
                last_syn = ts        # a fresh press does not count as a gap
            else:
                out.write("%s  RELEASE #%d  held %.0f ms\n"
                          % (wall(ts), presses,
                             (ts - press_ts) * 1000.0 if press_ts else 0.0))
            if down:
                press_ts = ts
            else:
                release_ts = ts
                frames_at_release = frames
            continue

        if typ == EV_SYN and code == SYN_REPORT:
            frames += 1
            last_frame_ts = time.time()
            last_frame_wall[0] = last_frame_ts
            if last_syn is not None:
                d = (ts - last_syn) * 1000.0
                if d >= GAP_MS:
                    gaps += 1
                    out.write("%s  GAP %9.1f ms   down=%-5s frame=%d\n"
                              % (wall(ts), d, down, frames))
            last_syn = ts

        now = time.time()
        if now - last_beat >= 60:
            out.write("%s  heartbeat: frames=%d presses=%d irqs=%s gaps>=%.0fms=%d down=%s\n"
                      % (wall(now), frames, presses, irq_count(), GAP_MS, gaps, down))
            last_beat = now
