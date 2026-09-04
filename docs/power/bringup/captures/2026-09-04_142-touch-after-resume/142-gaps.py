#!/usr/bin/env python3
"""#142 frame-gap logger, millisecond resolution, no polling.

Reads /dev/input/event4 and uses the KERNEL's own timestamp on every event, so
the resolution is the input layer's, not a sampler's. Logs the interval between
consecutive SYN_REPORT frames, but only while a finger is actually down
(BTN_TOUCH == 1) - a gap with no finger on the glass is the operator pausing,
not the panel stalling, and conflating the two is what the 1 Hz ledger could not
avoid.
"""
import struct, time, sys

DEV = "/dev/input/event4"
OUT = "/home/fp3/142-gaps.txt"
FMT = "llHHi"                        # timeval sec, usec + type + code + value
SZ = struct.calcsize(FMT)
EV_SYN, EV_KEY = 0x00, 0x01
SYN_REPORT, BTN_TOUCH = 0x00, 0x14a
GAP_MS = 100.0                       # normal inter-frame is 12-50 ms at 20-80/s

def wall(ts):
    return time.strftime("%H:%M:%S", time.localtime(ts)) + ".%03d" % ((ts % 1) * 1000)

out = open(OUT, "a", buffering=1)
out.write("== gap logger start %s  (threshold %.0f ms, only while BTN_TOUCH=1)\n"
          % (time.strftime("%F %H:%M:%S"), GAP_MS))

down = False
last_syn = None          # kernel timestamp of the previous frame
frames = 0
gaps = 0
last_beat = time.time()

with open(DEV, "rb", buffering=0) as f:
    while True:
        b = f.read(SZ)
        if not b or len(b) != SZ:
            break
        sec, usec, typ, code, val = struct.unpack(FMT, b)
        ts = sec + usec / 1e6

        if typ == EV_KEY and code == BTN_TOUCH:
            down = (val == 1)
            if down:
                last_syn = ts        # a fresh press does not count as a gap
            continue

        if typ == EV_SYN and code == SYN_REPORT:
            frames += 1
            if down and last_syn is not None:
                d = (ts - last_syn) * 1000.0
                if d >= GAP_MS:
                    gaps += 1
                    out.write("%s  GAP %8.1f ms   (finger down, frame %d)\n"
                              % (wall(ts), d, frames))
            last_syn = ts

        now = time.time()
        if now - last_beat >= 60:
            out.write("%s  heartbeat: frames=%d gaps>=%.0fms=%d down=%s\n"
                      % (wall(now), frames, GAP_MS, gaps, down))
            last_beat = now
