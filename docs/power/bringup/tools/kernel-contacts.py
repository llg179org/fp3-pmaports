#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
"""Count what the KERNEL delivered, so it can be diffed against what the app got.

    kernel-contacts.py /dev/input/eventN OUT.log     (ON THE DEVICE, as root)

WHY
===
fp3-taptest can only see what the compositor hands it. When the operator reports
a tap that produced nothing and the app's log has no raw touch AT ALL, two very
different things look identical:

    the finger never landed          -> nothing to find
    the panel/driver never reported  -> the fault this port has been chasing

This reads the evdev device directly and logs the START of every contact - an
ABS_MT_TRACKING_ID going from -1 to a real id - with the KERNEL's own timestamp.
Run it while the app runs, then diff the two logs: a kernel contact with no
`RAW touch-begin` within a few ms is a touch lost between evdev and the client.

☠️ Counting BTN_TOUCH instead would undercount: it is single-touch emulation and
does not toggle for a second finger landing while the first is down - which is
exactly the case under investigation here.

☠️ A second reader is safe: evdev gives every open file its own ring buffer, so
this does not take events away from libinput. It DOES get its own SYN_DROPPED if
it ever falls behind, which is logged rather than passed over.
"""
import os
import struct
import sys
import time

DEV, OUT = sys.argv[1], sys.argv[2]
EV_SYN, EV_ABS = 0x00, 0x03
SYN_REPORT, SYN_DROPPED = 0, 3
ABS_MT_SLOT, ABS_MT_TRACKING_ID = 0x2f, 0x39
FMT = "qqHHi"                      # 64-bit: tv_sec, tv_usec, type, code, value
SZ = struct.calcsize(FMT)

f = open(DEV, "rb", buffering=0)
out = open(OUT, "a", buffering=1)
out.write("== kernel-contacts start %s on %s\n"
          % (time.strftime("%F %H:%M:%S"), DEV))
slot = 0
n_contact = n_release = n_dropped = 0
while True:
    data = f.read(SZ)
    if not data or len(data) < SZ:
        break
    sec, usec, typ, code, val = struct.unpack(FMT, data)
    ts = time.strftime("%H:%M:%S", time.localtime(sec)) + ".%03d" % (usec // 1000)
    if typ == EV_SYN and code == SYN_DROPPED:
        n_dropped += 1
        out.write("%s  SYN_DROPPED #%d  <- the kernel ring overflowed for THIS "
                  "reader; counts after it are incomplete\n" % (ts, n_dropped))
    elif typ == EV_ABS and code == ABS_MT_SLOT:
        slot = val
    elif typ == EV_ABS and code == ABS_MT_TRACKING_ID:
        if val >= 0:
            n_contact += 1
            out.write("%s  CONTACT #%d  slot=%d id=%d\n" % (ts, n_contact, slot, val))
        else:
            n_release += 1
            out.write("%s  RELEASE #%d  slot=%d\n" % (ts, n_release, slot))
