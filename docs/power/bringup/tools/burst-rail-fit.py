#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Split a burst-rail.sh capture by the current and report, per rail, how often it
# was up in the burst samples against the quiet ones.
#
# ☠️ THE OUTPUT IS A CORRELATION AND NEVER AN ATTRIBUTION. No per-rail current
# exists on this SoC (`requested_microamps` is what a consumer ASKED for, and it
# is 0 here). A rail at the top of this list is a candidate for a scope, not a
# number of milliamps. And a rail that never changes is not exonerated - it is
# only excluded from explaining the CHANGE.
#
# ☠️ EVERY READING CARRIES ITS OWN KEY, and this parser refuses to invent one.
# The first version of the capture format wrote a bare vector with a name list in
# the header; three regulators have no readable `state`, so the vector was 54 long
# against 57 names and every label after the first gap was wrong - and the tool
# printed a confident shortlist off it. Names are not unique either: this phone
# has two PMICs and therefore two `l1`, `l2` and `l3`. The `regulator.N` directory
# is the identity; the name is only a label, and is printed with it.
#
#   burst-rail-fit.py rails.txt
import sys, statistics

def load(path):
    text = open(path).read()
    names, start = {}, 0
    for line in text.splitlines():          # ☠️ two passes: window_from is at the END
        if line.startswith("# name "):
            _, _, key, label = line.split(None, 3)
            names[key] = label
        elif line.startswith("#") and "window_from=" in line:
            start = int(line.split("window_from=")[1].split()[0])
    rows = []
    for line in text.splitlines():
        if line.startswith("#"):
            continue
        f = line.split()
        if len(f) < 4:
            continue
        try:
            t, cur, v = int(f[0]), int(f[1]), int(f[2])
        except ValueError:
            continue
        if t < start:
            continue
        vals = {}
        for tok in f[3:]:
            if "=" in tok:
                k, _, val = tok.partition("=")
                vals[k] = val
        rows.append((t, cur, v, vals))
    return names, rows

def label(names, key):
    base = key.split("/")[0]
    field = key.split("/")[-1]
    return "%s %s (%s)" % (base, names.get(base, "?"), field)

for path in sys.argv[1:]:
    names, rows = load(path)
    if len(rows) < 10:
        print("%s: %d samples - too few" % (path, len(rows)))
        continue
    cur = sorted(r[1] for r in rows)
    floor = cur[len(cur) // 10]
    hi = [r for r in rows if r[1] >= 1.5 * floor]
    lo = [r for r in rows if r[1] < 1.5 * floor]
    keys = sorted(set().union(*(set(r[3]) for r in rows)))
    print("\n== %s" % path)
    print("   %d samples  %d readings/sample  floor=%d median=%d p90=%d max=%d mA"
          % (len(rows), len(keys), floor, statistics.median(r[1] for r in rows),
             cur[int(len(cur) * 0.9)], cur[-1]))
    print("   burst: %d   quiet: %d" % (len(hi), len(lo)))
    if not hi or not lo:
        print("   one side is empty - nothing to compare")
        continue
    # ☠️ A reading missing from a sample is not a value. Count only samples that
    # actually carried the key, or a rail that appeared late reads as "off early".
    moved, constant = [], 0
    for k in keys:
        h = [r[3][k] for r in hi if k in r[3]]
        q = [r[3][k] for r in lo if k in r[3]]
        if not h or not q:
            continue
        # "up" = enabled, or in a non-idle opmode: a rail need not switch OFF to
        # stop costing, it drops to LPM, and enabled/disabled alone would miss it.
        up = (lambda vs: sum(1 for x in vs if x in ("E", "f", "n")) / len(vs))
        a, b = up(h), up(q)
        if abs(a - b) > 0.05:
            moved.append((abs(a - b), k, a, b, len(h), len(q)))
        else:
            constant += 1
    if not moved:
        print("   -> NO RAIL MOVES with the current. All %d readings are in the same\n"
              "      state during the bursts as during the quiet samples. The power is\n"
              "      not a rail switching either - what is left is a rail whose LOAD\n"
              "      changes without its state changing, which sysfs cannot see.\n"
              "      Next step is hardware: a scope or a shunt, not another /sys file."
              % constant)
        continue
    moved.sort(reverse=True)
    print("   %d readings constant, %d move:" % (constant, len(moved)))
    print("   %-46s %7s %7s %8s %9s" % ("rail (field)", "burst", "quiet", "delta", "n hi/lo"))
    for d, k, a, b, nh, nq in moved[:25]:
        print("   %-46s %6.0f%% %6.0f%% %+7.0f%% %5d/%-4d"
              % (label(names, k), a * 100, b * 100, (a - b) * 100, nh, nq))
    print("   -> a shortlist for a scope, not a bill: no per-rail current exists here.")
