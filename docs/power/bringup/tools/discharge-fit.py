#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Reduce a discharge-run.sh capture to the three numbers it was run for:
#
#   1. the pack's REAL capacity - the integral of current_now from a full pack to
#      the phone switching itself off, against the 3 060 000 uAh nameplate that
#      every "points -> mAh" figure on both systems is computed from;
#   2. the OCV -> SoC curve, i.e. what a resting voltage actually means;
#   3. what `capacity` claimed at each point, so the gauge's error can be plotted
#      instead of assumed. The pmOS gauge has read ~30 points optimistic against
#      the oracle, and that is a user-facing bug, not a measurement nuisance.
#
# ☠️ IT REPORTS THE INTEGRAL, NOT A MEAN CURRENT. A bursty discharge has a mean
# that hides both ends; the integral is the only honest summary of a pack.
#
# ☠️ ROWS WITH A LIT PANEL ARE DROPPED FROM THE CURVE AND COUNTED SEPARATELY.
# The compositor re-enables the panel on any input and a lit screen is ~24.5 mA -
# most of the floor. discharge-run.sh records bl_power on every row precisely so
# this can be done; averaging them in would quietly bias the whole curve.
#
#   discharge-fit.py discharge.txt
import sys, statistics

COLS = ["uptime_s", "cap_pct", "v_uV", "cur_uA", "temp_dC", "bl_power", "status"]
NAMEPLATE_UAH = 3060000

def load(path):
    rows, lit, bad = [], 0, 0
    for line in open(path):
        if line.startswith("#"):
            continue
        p = line.split()
        if len(p) < len(COLS):
            bad += 1
            continue
        try:
            r = dict(zip(COLS, [float(p[0])] + [int(x) for x in p[1:5]] + p[5:7]))
        except ValueError:
            bad += 1
            continue
        if r["bl_power"] != "4":       # 4 = off; anything else is a lit panel
            lit += 1
            continue
        rows.append(r)
    return rows, lit, bad

for path in sys.argv[1:]:
    rows, lit, bad = load(path)
    if len(rows) < 10:
        print("%s: %d usable rows - nothing to fit" % (path, len(rows)))
        continue
    rows.sort(key=lambda r: r["uptime_s"])
    # trapezoid on |current| over real elapsed time; a dropped row leaves a gap and
    # the trapezoid spans it, which is right - the pack kept discharging through it
    uah = 0.0
    for a, b in zip(rows, rows[1:]):
        dt = b["uptime_s"] - a["uptime_s"]
        if dt <= 0 or dt > 600:        # a gap over 10 min is a suspend or a stall
            continue
        uah += (abs(a["cur_uA"]) + abs(b["cur_uA"])) / 2.0 * dt / 3600.0
    hours = (rows[-1]["uptime_s"] - rows[0]["uptime_s"]) / 3600.0
    print("\n== %s" % path)
    print("   %d rows over %.2f h  (%d dropped for a lit panel, %d unparsable)"
          % (len(rows), hours, lit, bad))
    print("   capacity claimed: %d%% -> %d%%" % (rows[0]["cap_pct"], rows[-1]["cap_pct"]))
    print("   voltage:          %.3f V -> %.3f V" % (rows[0]["v_uV"] / 1e6, rows[-1]["v_uV"] / 1e6))
    print("   integrated draw:  %.0f uAh = %.0f mAh" % (uah, uah / 1000.0))
    print("   nameplate:        %d uAh -> the pack delivered %.0f%% of it"
          % (NAMEPLATE_UAH, 100.0 * uah / NAMEPLATE_UAH))
    pts = rows[0]["cap_pct"] - rows[-1]["cap_pct"]
    if pts > 0:
        print("   the gauge spent %d points for that: %.1f mAh per point, against a"
              % (pts, uah / 1000.0 / pts))
        print("   nameplate point of %.1f mAh" % (NAMEPLATE_UAH / 1000.0 / 100.0))
    cur = [abs(r["cur_uA"]) / 1000.0 for r in rows]
    print("   current mA: p10=%.0f median=%.0f p90=%.0f  (mean %.0f, and the mean is"
          " not the number)" % (sorted(cur)[len(cur)//10], statistics.median(cur),
                                sorted(cur)[9*len(cur)//10], statistics.mean(cur)))
    print("\n   claimed % -> measured, in tenths of the run:")
    print("   %8s %8s %10s %10s" % ("cap_pct", "V", "mAh so far", "mA median"))
    n = max(1, len(rows) // 10)
    acc = 0.0
    for i in range(0, len(rows) - 1, n):
        chunk = rows[i:i + n]
        for a, b in zip(chunk, chunk[1:]):
            dt = b["uptime_s"] - a["uptime_s"]
            if 0 < dt <= 600:
                acc += (abs(a["cur_uA"]) + abs(b["cur_uA"])) / 2.0 * dt / 3600.0
        c = [abs(r["cur_uA"]) / 1000.0 for r in chunk]
        # ☠️ Report the END of the chunk, not its start. The accumulator has
        # already absorbed the whole chunk by this point, so printing the first
        # row's percentage beside it puts a claimed SoC next to charge that was
        # drawn after it - which on the 2026-08-27 run made the last decile look
        # like 7 gauge points spent on 3 mAh. The capture had no gap; the table did.
        print("   %8d %8.3f %10.0f %10.0f"
              % (chunk[-1]["cap_pct"], chunk[-1]["v_uV"] / 1e6, acc / 1000.0,
                 statistics.median(c)))
