#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Read one or more modem-window.sh captures and print the per-master awake duty
# beside the radio state the window was taken in.
#
#   modem-window-fit.py capture.txt [capture2.txt ...]
#
# ☠️ The duty is 1 - (XO accumulated delta) / (window x 19.2e6). The tick is the
# 19.2 MHz XO on both systems, and the field is named differently on each -
# `xo_accumulated_duration` downstream, `XO total duration` on mainline - which is
# why this parses both rather than assuming one.
import re
import sys

TICK = 19.2e6
MASTERS = ("APSS", "MPSS", "PRONTO", "LPASS")
XO_KEYS = ("xo_accumulated_duration", "XO total duration")


def parse(path):
    txt = open(path, errors="ignore").read()
    t0 = t1 = None
    for line in txt.splitlines():
        m = re.match(r"#\s*t0=(\d+)", line)
        if m:
            t0 = int(m.group(1))
        m = re.match(r"#\s*t1=(\d+)", line)
        if m:
            t1 = int(m.group(1))

    # Counters, keyed by (phase, master). A section header names the master on
    # mainline; downstream the master name is a bare line inside the dump.
    vals = {}
    phase = None
    master = None
    for line in txt.splitlines():
        if line.startswith("BEFORE"):
            phase, body = "BEFORE", line[6:].strip()
        elif line.startswith("AFTER"):
            phase, body = "AFTER", line[5:].strip()
        else:
            continue
        body = body.strip("[]")
        if body in MASTERS:
            master = body
            continue
        if master is None:
            continue
        for k in XO_KEYS:
            if body.startswith(k):
                raw = body.split(":", 1)[1].strip()
                vals[(phase, master)] = int(raw, 16) if raw.startswith("0x") else int(raw)
    return t0, t1, vals, txt


def radio(txt):
    out = []
    for pat in ("access tech", "signal quality", "state:", "Technology", "Status", "Strength"):
        for line in txt.splitlines():
            if pat in line and line.lstrip().startswith("#"):
                out.append(line.strip("# ").strip())
                break
    return out


for path in sys.argv[1:]:
    t0, t1, vals, txt = parse(path)
    print(f"== {path}")
    if t0 is None or t1 is None or t1 <= t0:
        print("   ☠️ no usable t0/t1 - the window never closed")
        continue
    w = t1 - t0
    print(f"   window {w}s")
    for m in MASTERS:
        a, b = vals.get(("BEFORE", m)), vals.get(("AFTER", m))
        if a is None or b is None:
            print(f"   {m:<7} (absent)")
            continue
        off = (b - a) / TICK
        print(f"   {m:<7} XO off {off:7.1f}s -> awake {100 * (1 - off / w):5.1f}%")
    for line in radio(txt):
        print(f"   | {line}")
