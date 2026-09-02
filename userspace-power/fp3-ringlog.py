#!/usr/bin/env python3
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Log every incoming call the modem sees, so measuring reachability costs the
# owner nothing but the call itself.
#
# The question this serves: with the IMS loop switched off, does an incoming call
# still reach a phone that has been asleep for a long time? Four calls minutes
# apart proved the call PATH works; they said nothing about the delivery RATE,
# whose 95 % lower bound from 4/4 is only 0.473. Answering that needs many calls
# spread over hours - so the phone has to record them without anybody watching.
#
# ☠️ NO RuntimeMaxSec, NO TIMER, NO CAP. This failure class has already cost this
# investigation two measurements in one day: a recorder capped at 1800 s watching
# a nine-hour window (everything after the first half hour was lost, silently),
# and a 76 s accumulator window read across a 60 s sleep. An instrument that must
# outlive an open-ended measurement gets Restart=always and nothing else.
#
# ☠️ AND IT MUST NOT KEEP THE PHONE AWAKE, because an awake phone is not the
# phone under test. It follows the journal, which is passive: no polling, no
# timer, no wakeup source of its own.
import re
import subprocess
import sys
import time

OUT = "/var/log/fp3/ringlog.tsv"
if "--stdin" in sys.argv:
    OUT = "/dev/stdout"
# ModemManager announces the call before the shell does anything with it; the
# ringtone line is the user-visible moment. The gap between them is the only part
# of the delay this device controls.
RE_RING_IN = re.compile(r"call state changed: \w+ -> ringing-in")
RE_RINGING = re.compile(r"Setting ring state to 'ringing'")
RE_END = re.compile(r"ringing-in -> (\w+)")
RE_TS = re.compile(r"^(\w{3} \d{2} \d{2}:\d{2}:\d{2}\.\d+)")


def ts(line):
    m = RE_TS.match(line)
    if not m:
        return None
    # short-precise omits the year, so supply the current one explicitly - parsing
    # without it is deprecated and mis-handles a leap day.
    stamp, frac = m.group(1).split(".")
    y = time.localtime().tm_year
    t = time.strptime("%d %s" % (y, stamp), "%Y %b %d %H:%M:%S")
    return time.mktime(t) + float("0." + frac)


def field(cmd, pat):
    try:
        out = subprocess.run(cmd, shell=True, capture_output=True, text=True,
                             timeout=20).stdout
        m = re.search(pat, out)
        return m.group(1) if m else "?"
    except Exception:
        return "?"


def context():
    # ☠️ Read this AFTER the ring, never on a schedule: every one of these calls
    # wakes the AP, and a poller would make the phone unreachable-to-sleep, i.e.
    # would destroy the very state being measured.
    band = field("qmicli -d qrtr://0 --nas-get-rf-band-info 2>/dev/null",
                 r"Active Band Class: *'([^']*)'")
    cell = field("qmicli -d qrtr://0 --nas-get-cell-location-info 2>/dev/null",
                 r"Global Cell ID: *'([^']*)'")
    with open("/proc/uptime") as f:
        up = f.read().split()[0]
    return band, cell, up


def main():
    # ☠️ THE WALL CLOCK ON THIS DEVICE CANNOT BE TRUSTED ALONE. Its RTC starts at
    # 1970 and stays wrong until NTP lands, so a call logged in the first minutes
    # after a boot carries a timestamp from another decade. That matters here more
    # than anywhere else, because a MISSED call leaves no line at all: delivery is
    # measured as the difference between the SCHEDULE and this log, and matching a
    # fixed hh:mm slot against a wrong clock loses real calls and invents missed
    # ones. So every row also carries monotonic uptime and the boot id - those two
    # are correct from the first second, and a run can be re-aligned afterwards.
    boot = "?"
    try:
        with open("/proc/sys/kernel/random/boot_id") as f:
            boot = f.read().strip()[:8]
    except OSError:
        pass
    line_out = open(OUT, "a", buffering=1)
    try:
        empty = line_out.tell() == 0
    except OSError:                # /dev/stdout under --stdin is not seekable
        empty = True
    if empty:
        line_out.write("# wall\tdev_ms\tband\tcell\tuptime_s\toutcome\tboot\tmono\n")
    # ☠️ A LOGGER NOBODY HAS SEEN FIRE IS DECORATION. `--stdin` replays a saved
    # journal through exactly the same parser, so the extraction can be checked
    # against calls that really happened instead of being trusted.
    # ☠️ IN REPLAY THE band/cell COLUMNS ARE MEANINGLESS. They are read from the
    # modem when the row is written, so a replayed journal stamps TODAY's band on
    # calls from this morning - measured: the four 08:41-08:54 calls came back
    # labelled eutran-20/1470722, while they really happened on eutran-1/1470762.
    # Replay validates the TIMING extraction, nothing else.
    if "--stdin" in sys.argv:
        stream = sys.stdin
        p = None
    else:
        p = subprocess.Popen(
            ["journalctl", "-f", "-o", "short-precise", "--since", "now"],
            stdout=subprocess.PIPE, text=True)
        stream = p.stdout
    ring_in = None
    ring_at = None
    for line in stream:
        if RE_RING_IN.search(line):
            ring_in, ring_at = ts(line), None
        elif ring_in is not None and RE_RINGING.search(line):
            ring_at = ts(line)
        elif ring_in is not None and RE_END.search(line):
            band, cell, up = context()
            dev = "%.0f" % ((ring_at - ring_in) * 1000) if ring_at else "NO_RING"
            # ☠️ The wall time is the CALL's, not the moment this line is written -
            # otherwise a replayed or delayed log times every call at the instant
            # it was processed, which is what the first version did.
            line_out.write("%s\t%s\t%s\t%s\t%s\t%s\t%s\t%.1f\n" % (
                time.strftime("%F %T", time.localtime(ring_in)), dev, band, cell, up,
                RE_END.search(line).group(1), boot, time.monotonic()))
            ring_in = ring_at = None
    return 1                      # journalctl ended: let systemd restart us


if __name__ == "__main__":
    sys.exit(main())
