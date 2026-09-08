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

THE POSITION SPAN, added 2026-09-08
===================================
Each RELEASE now carries where the contact WENT, not only that it ended:

    RELEASE #n slot=s  x 271->268 span 4  y 1612->1620 span 9  pts 7  dur 63ms

It exists to separate three readings of one measured event. On 2026-09-08
09:50:24 a run of four same-side taps had every known explanation absent - no
boundary, no drift, no overlap, the i2c bus awake, no driver error - while the
SURVIVING contacts' down-time more than doubled, 61.6 ms before to 127.0 ms
during and 51.3 ms after. Three things predict that:

    the controller MERGED two fingers into one reported contact
    the RELEASE is reported late and the other finger lands in its shadow
    the operator simply held one finger longer

☠️ The third can never be excluded from a log - a touch that produces neither a
contact nor an interrupt leaves nothing behind - but the first is now decidable
WITHOUT asking the operator anything: a genuine long press stays near its own x,
while a merge wanders or jumps toward the other half. That is what `span` is.

☠️ These are DEVICE units, not the app's 360-px logical width, so the header
reads the panel's own range out of the driver (EVIOCGABS) rather than leaving a
reader to guess the scale. A number whose units are assumed is a number that
will be compared against the wrong thing.
"""
import fcntl
import os
import struct
import sys
import time

DEV, OUT = sys.argv[1], sys.argv[2]
EV_SYN, EV_ABS = 0x00, 0x03
SYN_REPORT, SYN_DROPPED = 0, 3
ABS_MT_SLOT, ABS_MT_TRACKING_ID = 0x2f, 0x39
ABS_MT_POSITION_X, ABS_MT_POSITION_Y = 0x35, 0x36
FMT = "qqHHi"                      # 64-bit: tv_sec, tv_usec, type, code, value
SZ = struct.calcsize(FMT)


def absinfo(fd, axis):
    """The driver's own range for one axis, via EVIOCGABS.

    struct input_absinfo is six int32: value, min, max, fuzz, flat, resolution.
    _IOR('E', 0x40 + axis, that) -> dir 2, size 24, type 0x45.
    """
    req = (2 << 30) | (24 << 16) | (0x45 << 8) | (0x40 + axis)
    buf = fcntl.ioctl(fd, req, b"\0" * 24)
    return struct.unpack("6i", buf)


f = open(DEV, "rb", buffering=0)
out = open(OUT, "a", buffering=1)
out.write("== kernel-contacts start %s on %s\n"
          % (time.strftime("%F %H:%M:%S"), DEV))
try:
    ax, ay = absinfo(f.fileno(), ABS_MT_POSITION_X), absinfo(f.fileno(), ABS_MT_POSITION_Y)
    out.write("   axes: x %d..%d (fuzz %d, res %d)   y %d..%d (fuzz %d, res %d)"
              "   <- DEVICE units, not the app's 360 px\n"
              % (ax[1], ax[2], ax[3], ax[5], ay[1], ay[2], ay[3], ay[5]))
except OSError as e:
    # ☠️ Say so rather than logging spans against an unknown scale.
    out.write("   axes: EVIOCGABS failed (%s) - spans below have NO known scale\n" % e)
slot = 0
n_contact = n_release = n_dropped = 0
live = {}                          # slot -> [x0, x1, xmin, xmax, y0, y1,
                                   #          ymin, ymax, points, t_begin]
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
    elif typ == EV_ABS and code in (ABS_MT_POSITION_X, ABS_MT_POSITION_Y):
        # ☠️ Only while a contact is live. A position for a slot with no open
        # contact would otherwise fold into the NEXT one and inflate its span -
        # the reading this column exists to make, manufactured by the reader.
        st = live.get(slot)
        if st is not None:
            i = 0 if code == ABS_MT_POSITION_X else 4
            if st[i] is None:
                st[i] = st[i + 1] = st[i + 2] = st[i + 3] = val
            else:
                st[i + 1] = val
                st[i + 2] = min(st[i + 2], val)
                st[i + 3] = max(st[i + 3], val)
            if i == 0:
                st[8] += 1
    elif typ == EV_ABS and code == ABS_MT_TRACKING_ID:
        if val >= 0:
            n_contact += 1
            live[slot] = [None, None, None, None,
                          None, None, None, None, 0, sec + usec / 1e6]
            out.write("%s  CONTACT #%d  slot=%d id=%d\n" % (ts, n_contact, slot, val))
        else:
            n_release += 1
            st = live.pop(slot, None)
            if st is None or (st[0] is None and st[4] is None):
                # A release with no position at all is itself worth seeing.
                out.write("%s  RELEASE #%d  slot=%d  (no position reported)\n"
                          % (ts, n_release, slot))
            else:
                # ☠️ EACH AXIS SEPARATELY. Guarding on X alone crashed the whole
                # reader on a contact that carried X and no Y - TypeError on
                # None - and it would have died on the device with the app still
                # running and nobody watching its stderr. Found by the synthetic
                # gate before deployment, not by losing a run.
                def axis(i):
                    if st[i] is None:
                        return "n/a"
                    return "%d->%d span %d" % (st[i], st[i + 1], st[i + 3] - st[i + 2])
                out.write("%s  RELEASE #%d  slot=%d  x %s  y %s  pts %d  dur %.0fms\n"
                          % (ts, n_release, slot, axis(0), axis(4), st[8],
                             (sec + usec / 1e6 - st[9]) * 1000.0))
