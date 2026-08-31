#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Turn a modem-night.sh run into the row format sleep-night-fit.py reads, so the
# same validated voltage->mAh->slope fit prices it. Writing an adapter rather
# than a second fitter is deliberate: a parallel implementation of the curve
# lookup would rot on its own schedule and disagree quietly.
#
#   modem-night-to-rounds.py <modem-night-DIR> [--path logind|rtcwake|all]
#
# Emits: <round> <wall_s> <path> <slept_s> <cap> <v_uV>
# sleep-night-fit.py reads fields 1, 3 and 5 (wall, slept, v_uV).
#
# ☠️ THE VOLTAGE IS THE ONE SAMPLED AFTER THE SLEEP, not before it. That is the
# rest OCV right after a wake, which is the only number in the file the suspend
# does not freeze - `capacity` and `charge_now` are the same frozen software
# integrator, and this emits `cap` only so a reader can see it standing still.
#
# ☠️ --path matters. The two suspend paths in one run are not one population:
# logind rounds sleep the full alarm and rtcwake rounds die in seconds, so their
# duty cycles differ by an order of magnitude and a combined fit prices neither.
# Default is `logind`, the arm that actually slept.
import os
import re
import sys
from datetime import datetime


def main(root, want):
    rows, t0 = [], None
    for d in sorted(os.listdir(root)):
        m = re.match(r"round-(\d+)-(\w+)$", d)
        if not m:
            continue
        rnd, path = int(m.group(1)), m.group(2)
        mp = os.path.join(root, d, "masters.txt")
        qp = os.path.join(root, d, "qmi.log")
        if not os.path.exists(mp):
            continue
        txt = open(mp, errors="ignore").read()
        h = re.search(r"# round=\d+ path=\w+ t=(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)", txt)
        a = re.search(r"# after: cap=(\d+)% v=(\d+)uV", txt)
        if not h or not a:
            continue
        ts = datetime.strptime(h.group(1), "%Y-%m-%d %H:%M:%S")
        if t0 is None:
            t0 = ts
        slept = 0.0
        if os.path.exists(qp):
            s = re.search(r"round \d+: slept (\d+(?:\.\d+)?)s", open(qp, errors="ignore").read())
            if s:
                slept = float(s.group(1))
        if want != "all" and path != want:
            continue
        rows.append((rnd, (ts - t0).total_seconds(), path, slept, int(a.group(1)), int(a.group(2))))

    if not rows:
        sys.exit(f"no rounds matching --path {want} under {root}")
    print(f"# from {root}  path={want}  {len(rows)} rounds")
    print("# round wall_s path slept_s cap v_uV")
    for r in rows:
        print(f"{r[0]} {r[1]:.0f} {r[2]} {r[3]:.0f} {r[4]} {r[5]}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    want = "logind"
    if "--path" in sys.argv:
        want = sys.argv[sys.argv.index("--path") + 1]
    sys.exit(main(sys.argv[1], want))
