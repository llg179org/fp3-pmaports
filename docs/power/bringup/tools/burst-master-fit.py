#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Split a burst-master.sh capture by the current and print each RPM master's
# behaviour on both sides, so the burst can be attributed to one of them.
#
# ☠️ The column that carries the answer is `*_xopct`: the percentage of the
# interval that master had the 19.2 MHz crystal shut down. A master that is off
# the XO through the burst is not paying for it; one that holds it through the
# burst and releases it through the quiet stretch is the owner - regardless of
# its shutdown count, which counts events and not time. Packets are not power and
# neither are transitions.
#
#   burst-master-fit.py master.txt [...]
import sys, statistics

MASTERS = ["APSS", "LPASS", "MPSS", "PRONTO"]
FIELDS = ["sd", "xosd", "xopct", "cores"]

def header_cols(text):
    for line in text.splitlines():
        if line.startswith("# t_s"):
            return line[1:].split()
    return ["t_s", "cur_mA", "v_mV"] + [
        "%s_%s" % (m, f) for m in MASTERS for f in FIELDS]

def load(path):
    """Rows after the window mark.

    ☠️ TWO PASSES, DELIBERATELY. burst-master appends `# window_from=` at the END
    of the file - it only learns the panel wait when idle-ab returns. A single
    sequential pass sets the cutoff after every row has already been kept, so the
    filter silently does nothing and the file merely LOOKS filtered. That bug was
    measured in burst-attrib-fit.py on 2026-08-27; this is the fixed shape."""
    text = open(path).read()
    cols = header_cols(text)
    start = 0
    for line in text.splitlines():
        if line.startswith("#") and "window_from=" in line:
            start = int(line.split("window_from=")[1].split()[0])
    rows = []
    for line in text.splitlines():
        if line.startswith("#"):
            continue
        p = line.split()
        if len(p) < len(cols):
            continue
        # `cores` is a hex bitmask, everything else is decimal; a field that will
        # not parse is a hole, not a zero
        r = []
        ok = True
        for name, v in zip(cols, p):
            try:
                r.append(int(v, 16) if name.endswith("_cores") else int(v))
            except ValueError:
                ok = False
                break
        if ok and r[0] >= start:
            rows.append(r)
    return cols, rows

def q(v, f):
    v = sorted(v)
    return v[min(len(v) - 1, int(len(v) * f))]

for path in sys.argv[1:]:
    cols, rows = load(path)
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
    print("   %-14s %10s %10s %10s" % ("column", "burst", "quiet", "delta"))
    med = {}
    for i, name in enumerate(cols):
        if i < 2:
            continue
        a = statistics.median([r[i] for r in hi])
        b = statistics.median([r[i] for r in lo])
        med[name] = (a, b)
        print("   %-14s %10.1f %10.1f %+10.1f" % (name, a, b, a - b))
    # ☠️ THE SPLIT ABOVE IS BY THE EFFECT, AND ON THIS CAPTURE IT ANSWERED "NO
    # MASTER" WHILE THE ANSWER WAS SITTING IN THE SAME FILE. Splitting by current
    # and taking the median of a master column washes out a master that is up a
    # THIRD of the time: its median is 0 on both sides of the split. Split the
    # other way - by the candidate cause, and report the current - and MPSS
    # separates 166 mA from 74 mA. Both directions are needed: split by the effect
    # to test a story, split by the cause to find one.
    # a correlation table, because it is what was computed by hand on the first
    # capture and it is what pointed at MPSS_cores before any split did
    def corr(a, b):
        ma, mb = statistics.mean(a), statistics.mean(b)
        num = sum((x - ma) * (y - mb) for x, y in zip(a, b))
        da = sum((x - ma) ** 2 for x in a) ** 0.5
        db = sum((y - mb) ** 2 for y in b) ** 0.5
        return num / (da * db) if da and db else None
    print("\n   correlation with the current (r), and the range of each column:")
    for i, name in enumerate(cols):
        if i < 2:
            continue
        v = [r[i] for r in rows]
        if len(set(v)) < 2:
            print("   %-16s constant = %s" % (name, v[0]))
            continue
        print("   %-16s r=%+.2f   min=%-6s max=%s" % (name, corr(cur, v), min(v), max(v)))

    print("\n   conditioned on each master being up (the split by cause):")
    print("   %-16s %5s %8s %8s %8s" % ("condition", "n", "p10", "median", "p90"))
    conds = []
    for m in MASTERS:
        ck, xk = "%s_cores" % m, "%s_xopct" % m
        if ck in cols:
            conds.append(("%s cores up" % m, cols.index(ck), lambda v: v != 0))
        if xk in cols:
            # "awake" = it gave up less than 70 % of the interval to the crystal
            conds.append(("%s off-XO <70%%" % m, cols.index(xk), lambda v: v < 70))
    for name, i, pred in conds:
        up = [r[1] for r in rows if pred(r[i])]
        dn = [r[1] for r in rows if not pred(r[i])]
        if not up or not dn:
            print("   %-16s %5d  (never changes - no contrast)" % (name, len(up)))
            continue
        print("   %-16s %5d %8d %8.0f %8d" % (name, len(up), q(up, .10),
                                              statistics.median(up), q(up, .90)))
        print("   %-16s %5d %8d %8.0f %8d   <- and when it is not"
              % ("", len(dn), q(dn, .10), statistics.median(dn), q(dn, .90)))

    # the verdict comes from the split by CAUSE, because that is the one that
    # separated on this capture; the split by effect is kept above as the check
    best = None
    for m in MASTERS:
        ck = "%s_cores" % m
        if ck not in cols:
            continue
        i = cols.index(ck)
        up = [r[1] for r in rows if r[i] != 0]
        dn = [r[1] for r in rows if r[i] == 0]
        if len(up) < 5 or len(dn) < 5:
            continue
        d = statistics.median(up) - statistics.median(dn)
        if best is None or d > best[0]:
            best = (d, m, len(up), len(rows), statistics.median(up), statistics.median(dn))
    if best and best[0] > 20:
        d, m, nup, ntot, mu, md = best
        print("\n   -> %s is up in %d of %d samples (%.0f%%), and the current with it up is\n"
              "      %.0f mA against %.0f mA with it down (+%.0f). ☠️ That is a correlation on\n"
              "      one window, not an intervention - and a duty cycle read by point sampling.\n"
              "      Repeat it before it is a number." % (m, nup, ntot, 100.0 * nup / ntot, mu, md, d))

    print("   ->", end=" ")
    drops = []
    for m in MASTERS:
        k = "%s_xopct" % m
        if k in med:
            drops.append((med[k][1] - med[k][0], m, med[k]))
    drops.sort(reverse=True)
    if not drops:
        print("no master columns parsed - the capture is unusable.")
    elif drops[0][0] < 5:
        print("no master changes its XO duty by more than 5 points across the burst.\n"
              "      Whatever holds the rails up is not visible to the RPM at this\n"
              "      granularity - do not name a master on this evidence.")
    else:
        d, m, (a, b) = drops[0]
        print("%s holds the XO through the burst: %.0f%% off-XO in the burst against\n"
              "      %.0f%% in the quiet (%.0f points). That is the master to chase." % (m, a, b, d))
