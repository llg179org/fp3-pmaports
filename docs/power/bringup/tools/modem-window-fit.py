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
#
# ☠️☠️☠️ AND THAT ARITHMETIC INVERTS ON A MASTER THAT NEVER WAKES. Measured
# 2026-08-31 with a 120 s double-sample on the live device: the RPM updates
# `XO total duration` when the master EXITS XO shutdown, not while it is down.
# So a master that stays down for the whole window contributes a delta of ZERO
# and the line above reports it as `awake 100.0%` - the exact opposite of the
# truth. The control in the same sample: MPSS toggled 375 times in 120 s and
# accumulated 114.2 s (95.1% off), so the counter is not broken, it is
# edge-updated. LPASS had been down 1.68 h, cores 0x0, count frozen at 75, and
# read as 100% awake for three days of write-ups.
#
# The struct carries its own disambiguation and this script now reads it, which
# is what `leads/lpass-mclk-gate-state.md` had said in its header since
# 2026-08-21: `Last XO shutdown enter` > `Last XO shutdown exit` with
# `Active cores bitmask` 0x0 means DOWN and staying down. A zero delta is only
# `awake 100%` when the master is demonstrably up.
import re
import sys

TICK = 19.2e6
MASTERS = ("APSS", "MPSS", "PRONTO", "LPASS")
XO_KEYS = ("xo_accumulated_duration", "XO total duration")
# The fields that tell a saturated zero delta apart from a real one.
STATE_KEYS = {
    "enter": ("Last XO shutdown enter", "xo_last_entered_at"),
    "exit": ("Last XO shutdown exit", "xo_last_exited_at", "last_exit"),
    "cores": ("Active cores bitmask", "active_cores"),
}


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
    state = {}
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
        for name, keys in STATE_KEYS.items():
            for k in keys:
                if body.startswith(k):
                    raw = body.split(":", 1)[-1].strip().split("@")[-1].strip()
                    try:
                        state[(phase, master, name)] = int(raw, 16) if raw.startswith("0x") else int(raw)
                    except ValueError:
                        pass
    return t0, t1, vals, state, txt


def radio(txt):
    out = []
    for pat in ("access tech", "signal quality", "state:", "Technology", "Status", "Strength"):
        for line in txt.splitlines():
            if pat in line and line.lstrip().startswith("#"):
                out.append(line.strip("# ").strip())
                break
    return out


for path in sys.argv[1:]:
    t0, t1, vals, state, txt = parse(path)
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
        # ☠️ A zero delta is ambiguous: never slept, or never woke. Ask the
        # struct, do not assume.
        if b == a:
            en = state.get(("AFTER", m, "enter"))
            ex = state.get(("AFTER", m, "exit"))
            co = state.get(("AFTER", m, "cores"))
            if en is not None and ex is not None and en > ex and co == 0:
                print(f"   {m:<7} XO off {off:7.1f}s -> ASLEEP the whole window "
                      f"(enter>exit, cores 0x0; the counter updates on exit)")
                continue
            if en == 0 and ex == 0:
                print(f"   {m:<7} XO off {off:7.1f}s -> awake {100.0:5.1f}% "
                      f"(never entered XO shutdown at all)")
                continue
            print(f"   {m:<7} XO off {off:7.1f}s -> ☠️ zero delta, state unreadable "
                  f"(enter={en} exit={ex} cores={co}) - do not read a duty off this")
            continue
        print(f"   {m:<7} XO off {off:7.1f}s -> awake {100 * (1 - off / w):5.1f}%")
    for line in radio(txt):
        print(f"   | {line}")
