#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
"""Read a `modem-decay-watch.sh` night and apply its PRE-REGISTERED readings.

    modem-decay-fit.py <capture-dir> [bucket_minutes]      default 10

The tool it reads dumps the four RPM masters verbatim every 10 s for a whole
night, touching nothing. The question is whether the expensive modem state
DECAYS on its own, and on what schedule - the leading explanation is a retry
with exponential backoff inside the modem, which predicts steps whose spacing
GROWS.

The readings were written down before the night ran, and this script applies
them mechanically. It does not get to pick the one that suits the hypothesis:

    decay >= 10 points, no cell change        -> BACKOFF SURVIVES
    flat within +-3 points for >= 8 h, same cell -> BACKOFF DEAD
    the change coincides with a cell/band move   -> VOID
    sawtooth                                     -> RECURRING TRIGGER, and then
                                                    the reset times are checked
                                                    against the covariate reads,
                                                    because the probe may BE the
                                                    trigger

☠️ The parse is done by `rpm_master_stats.py`, never by hand. That module owns
the inversion trap (a zero delta is not a duty) and the two file formats.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rpm_master_stats as R          # noqa: E402

BLOCK = re.compile(r"^== t=([0-9.]+) wall=(\d+) i=(\d+)\s*$", re.MULTILINE)


def read_samples(path):
    """[(mono, wall, {master: Record})] in file order."""
    text = open(path, encoding="utf-8", errors="replace").read()
    marks = list(BLOCK.finditer(text))
    out = []
    for i, m in enumerate(marks):
        end = marks[i + 1].start() if i + 1 < len(marks) else len(text)
        recs = R.parse(text[m.end():end])
        if recs:
            out.append((float(m.group(1)), int(m.group(2)), recs))
    return out


COV = re.compile(r"^== cov t=([0-9.]+) wall=(\d+)\s*$", re.MULTILINE)
CELL = re.compile(r"3GPP cell ID:\s*'(\d+)'")
BAND = re.compile(r"Active Band Class:\s*'([^']+)'")
RSRP = re.compile(r"RSRP:\s*'(-?\d+)")


def read_cov(path):
    if not os.path.exists(path):
        return []
    text = open(path, encoding="utf-8", errors="replace").read()
    marks = list(COV.finditer(text))
    out = []
    for i, m in enumerate(marks):
        end = marks[i + 1].start() if i + 1 < len(marks) else len(text)
        blk = text[m.end():end]
        c, b, r = CELL.search(blk), BAND.search(blk), RSRP.search(blk)
        out.append({"mono": float(m.group(1)), "wall": int(m.group(2)),
                    "cell": c.group(1) if c else None,
                    "band": b.group(1) if b else None,
                    "rsrp": r.group(1) if r else None})
    return out


def buckets(samples, master, minutes):
    """[(t_start_mono, wall, seconds, Window)] - one window per bucket.

    Each bucket is measured from its FIRST to its LAST sample, so a bucket the
    sampler missed seconds of is priced on the span it actually covers.
    """
    if not samples:
        return []
    span = minutes * 60.0
    out = []
    cur = []
    t0 = samples[0][0]
    for s in samples:
        if s[0] - t0 >= span and len(cur) >= 2:
            out.append(cur)
            cur = [s]
            t0 = s[0]
        else:
            cur.append(s)
    if len(cur) >= 2:
        out.append(cur)
    res = []
    for b in out:
        first, last = b[0], b[-1]
        if master not in first[2] or master not in last[2]:
            continue
        secs = last[0] - first[0]
        if secs <= 0:
            continue
        res.append((first[0], first[1], secs,
                    R.Window(first[2][master], last[2][master], secs)))
    return res


def main(argv):
    if len(argv) < 2:
        print(__doc__.strip()); return 2
    d = argv[1]
    minutes = float(argv[2]) if len(argv) > 2 else 10.0
    samples = read_samples(os.path.join(d, "samples.txt"))
    cov = read_cov(os.path.join(d, "covariates.txt"))
    if not samples:
        print("no samples parsed - is this a modem-decay-watch capture?")
        return 1

    hours = (samples[-1][0] - samples[0][0]) / 3600.0
    print("# modem-decay-fit  %s" % d)
    print("#   %d samples, %.2f h, bucket %g min" % (len(samples), hours, minutes))

    cells = sorted({c["cell"] for c in cov if c["cell"]})
    bands = sorted({c["band"] for c in cov if c["band"]})
    print("#   cells seen: %s" % (", ".join(cells) or "-"))
    print("#   bands seen: %s" % (", ".join(bands) or "-"))
    moved = len(cells) > 1 or len(bands) > 1

    for m in R.MASTERS:
        bs = buckets(samples, m, minutes)
        if not bs:
            continue
        print("\n-- %s" % m)
        duties = []
        for t, wall, secs, w in bs:
            hh = (t - samples[0][0]) / 3600.0
            if w.duty is None:
                print("  +%5.2f h  %s" % (hh, w.verdict.upper()))
                continue
            # ☠️ Print the VERDICT, not just the percentage. "0.0 %" reads the
            # same whether it was measured or inferred from a frozen counter,
            # and those are different claims.
            note = "" if w.verdict == "measured" else "  (%s)" % w.verdict
            if w.overflow:
                note += ("  ☠️ delta exceeds the bucket (%.0f s off in %.0f s)"
                         " - lower bound" % (w.d_ticks / R.TICK_HZ, secs))
            duties.append((hh, 100.0 * w.duty))
            print("  +%5.2f h  %5.1f %%  %6.2f wakes/s  %s%s"
                  % (hh, 100.0 * w.duty, w.wakes_per_s,
                     ("%.1f ms" % w.ms_per_wake) if w.ms_per_wake else "-", note))
        if m != "MPSS" or len(duties) < 3:
            continue

        # the pre-registered readings, applied mechanically
        first, last = duties[0][1], duties[-1][1]
        lo = min(d for _, d in duties)
        hi = max(d for _, d in duties)
        drop = first - last
        print("\n  first %.1f %%, last %.1f %%, range %.1f-%.1f pts, span %.2f h"
              % (first, last, lo, hi, hours))
        # a sawtooth is a series that goes down and comes back up more than once
        ups = sum(1 for i in range(1, len(duties))
                  if duties[i][1] - duties[i - 1][1] > 5.0)
        if moved:
            print("  => VOID: the cell or band moved during the night "
                  "(cells=%s bands=%s). No reading is licensed." % (cells, bands))
        elif ups >= 2:
            print("  => SAWTOOTH: %d upward jumps > 5 pts. A recurring trigger."
                  % ups)
            print("     ☠️ Now check whether the resets line up with the "
                  "covariate reads - if they do, THE PROBE IS THE TRIGGER and "
                  "the night must be re-run with covariates at start/end only.")
        elif drop >= 10.0:
            print("  => BACKOFF SURVIVES: %.1f pts of decay, no cell change. "
                  "The step TIMESTAMPS are the prize; geometric spacing is the "
                  "retry schedule itself." % drop)
        elif hi - lo <= 6.0 and hours >= 8.0:
            print("  => BACKOFF DEAD: flat within %.1f pts over %.2f h on one "
                  "cell." % (hi - lo, hours))
        else:
            print("  => NO READING: %.1f pts of change over %.2f h fits none of "
                  "the four pre-registered patterns. Say so; do not invent a "
                  "fifth." % (drop, hours))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
