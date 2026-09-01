#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Fit the sleeping phone's current against MPSS duty, from whole-night points.
#
#   duty-ma-line.py points.txt [--only tag[,tag...]] [--predict DUTY[,DUTY...]]
#
# points.txt: one point per line, '#' comments ignored
#   <label> <duty_fraction> <mA> <sigma_mA> [tag,tag,...]
#
# Why a file and not arithmetic in a commit message: with n=2 the line IS the
# conclusion, so every later point has to be able to move it in public. Tags let
# a subset be refitted - the two nights that founded this line differed in Wi-Fi
# state as well as in duty, and a fit that cannot be restricted to one Wi-Fi
# regime cannot show whether that confound matters.
#
# ☠️ n=2 fits exactly, with zero residual and no error bars. A perfect fit
# through two points is not agreement, it is arithmetic; the printed residuals
# only start meaning something at n>=3.
import sys


def read_points(path):
    pts = []
    for ln in open(path):
        ln = ln.split("#", 1)[0].strip()
        if not ln:
            continue
        f = ln.split()
        if len(f) < 4:
            sys.exit(f"malformed point: {ln}")
        tags = set(f[4].split(",")) if len(f) > 4 else set()
        pts.append((f[0], float(f[1]), float(f[2]), float(f[3]), tags))
    return pts


def fit(pts):
    # Weighted least squares, weight 1/sigma^2. Returns (slope, intercept).
    w = [1.0 / (s * s) if s > 0 else 1.0 for (_, _, _, s, _) in pts]
    sw = sum(w)
    sx = sum(wi * p[1] for wi, p in zip(w, pts))
    sy = sum(wi * p[2] for wi, p in zip(w, pts))
    sxx = sum(wi * p[1] * p[1] for wi, p in zip(w, pts))
    sxy = sum(wi * p[1] * p[2] for wi, p in zip(w, pts))
    den = sw * sxx - sx * sx
    if abs(den) < 1e-12:
        sys.exit("all points share one duty - the line is not determined")
    slope = (sw * sxy - sx * sy) / den
    return slope, (sy - slope * sx) / sw


def main(argv):
    path, only, predict = argv[0], None, [0.061]
    i = 1
    while i < len(argv):
        if argv[i] == "--only":
            only = set(argv[i + 1].split(","))
            i += 2
        elif argv[i] == "--predict":
            predict = [float(x) for x in argv[i + 1].split(",")]
            i += 2
        else:
            sys.exit(f"unknown argument: {argv[i]}")

    pts = read_points(path)
    if only:
        pts = [p for p in pts if only & p[4]]
        if len(pts) < 2:
            sys.exit(f"--only {','.join(sorted(only))} leaves {len(pts)} point(s)")
    slope, icept = fit(pts)

    print(f"n = {len(pts)}" + (f"   (--only {','.join(sorted(only))})" if only else ""))
    print(f"mA = {icept:.1f} + {slope:.0f} x duty")
    if len(pts) == 2:
        print("☠️  n=2: the fit is exact by construction, the residuals below are zero")
    print()
    print(f"{'point':<28}{'duty':>8}{'mA':>9}{'fit':>8}{'resid':>8}")
    for lbl, d, ma, sg, _ in pts:
        f = icept + slope * d
        print(f"{lbl:<28}{d*100:7.1f}%{ma:8.1f}±{sg:.0f}{f:8.1f}{ma-f:+8.1f}")
    print()
    for d in predict:
        print(f"at duty {d*100:.1f}%  ->  {icept + slope*d:.1f} mA")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__ or "usage: duty-ma-line.py points.txt [--only tags] [--predict duty]")
    main(sys.argv[1:])
