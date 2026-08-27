#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Split a burst-attrib.sh capture by the thing it is trying to explain - the
# current - and print every other column on both sides of that split.
#
# ☠️ THIS IS THE WHOLE POINT OF THE TOOL, not a convenience. Ranking a capture
# describes the background; splitting it by burst/quiet tests it. burst-source.sh
# was ranked first and psi_avgs_work looked like the answer at over half of all
# workqueue work - until the split showed 313 events per bin in the bursts against
# 316 in the quiet, i.e. no difference at all.
#
#   burst-attrib-fit.py attrib.txt [...]
import sys, statistics

COLS = ["t_s","cur_mA","v_mV","busy_pct","pc_res_pct","wfi_per_s","pc_per_s",
        "f0_kHz","f4_kHz","wlan_pps"]

def load(path):
    """Rows after the window mark. ☠️ The mark is not cosmetic: burst-attrib's
    sampler starts before idle-ab has the panel down, and a lit panel is ~24.5 mA
    - most of the floor. Samples before `# window_from=` are not measurements."""
    # ☠️ TWO PASSES, AND THAT IS NOT TIDINESS. burst-attrib appends the
    # `# window_from=` line at the END of the file, because it only learns the
    # panel wait when idle-ab returns. A single sequential pass sets `start`
    # after every data row has already been kept, so the filter silently does
    # nothing - measured 2026-08-27, an Ap leg with a 30 s panel wait came back
    # with all 195 samples instead of 179, the first sixteen of them lit.
    text = open(path).read()
    start = 0
    for line in text.splitlines():
        if line.startswith("#") and "window_from=" in line:
            start = int(line.split("window_from=")[1].split()[0])
    rows = []
    for line in text.splitlines():
        if line.startswith("#"):
            continue
        p = line.split()
        if len(p) < len(COLS):
            continue
        try:
            r = [int(x) for x in p[:len(COLS)]]
        except ValueError:
            continue
        if r[0] >= start:
            rows.append(r)
    return rows

def q(v, f):
    v = sorted(v)
    return v[min(len(v) - 1, int(len(v) * f))]

for path in sys.argv[1:]:
    rows = load(path)
    if len(rows) < 10:
        print("%s: %d samples - too few to split" % (path, len(rows)))
        continue
    cur = [r[1] for r in rows]
    floor = q(cur, 0.10)
    hi = [r for r in rows if r[1] >= 1.5 * floor]
    lo = [r for r in rows if r[1] < 1.5 * floor]
    print("\n== %s" % path)
    print("   %d samples  floor(p10)=%d  median=%d  p90=%d  max=%d mA"
          % (len(rows), floor, statistics.median(cur), q(cur, 0.90), max(cur)))
    print("   burst (>=1.5x floor): %d   quiet: %d" % (len(hi), len(lo)))
    if not hi or not lo:
        print("   one side is empty - nothing to compare")
        continue
    print("   %-12s %10s %10s %10s" % ("column", "burst", "quiet", "ratio"))
    for i, name in enumerate(COLS):
        if i in (0, 1):
            continue
        a = statistics.median([r[i] for r in hi])
        b = statistics.median([r[i] for r in lo])
        rat = ("%.2fx" % (a / b)) if b else "-"
        print("   %-12s %10.1f %10.1f %10s" % (name, a, b, rat))
    # the verdict the tool exists to give
    ba = statistics.median([r[3] for r in hi]); bb = statistics.median([r[3] for r in lo])
    ra = statistics.median([r[4] for r in hi]); rb = statistics.median([r[4] for r in lo])
    print("   ->", end=" ")
    if ba > bb + 5 or (bb and ba / max(bb, 1) > 1.5):
        print("the burst carries CPU-busy time: it is code running.")
    elif rb - ra > 5:
        print("no extra CPU-busy, but the cluster stops collapsing: an idle-depth burst.")
    else:
        print("no CPU-busy and no residency signature - the power is NOT a running\n"
              "      instruction. Next instrument is a rail, not a profiler.")
