#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Read a pll-vs-voltage.sh log and answer the one question it was run to
# answer: does the little cluster's PLL fail more often as the pack empties?
#
# The RUNBOOK asked for "a fixed sweep at high and low battery". Two points
# answer that only if the effect is large; pll-vs-voltage.sh instead sweeps
# repeatedly all the way down, so what arrives here is a series and the honest
# summary of a series is a fit with an interval, not a pair of numbers.
#
# ☠️ The rate is failures per *transition*, never per round. A write to
# scaling_setspeed that the governor coalesces away exercises nothing, so
# pll-sweep.sh reports the kernel's own total_trans delta and that is the
# denominator used here.
#
# ☠️ A ratio of small counts is noisy in a way that invites over-reading. With
# ~17 failures in ~13500 transitions per point, a single point's rate carries
# roughly +/-25% just from counting statistics. That is why this fits the whole
# series rather than comparing the first point to the last, and why it prints a
# Poisson-based interval next to every rate.
#
#   pll-ramp-fit.py <log> [...]

import math
import re
import sys

POINT = re.compile(r"^#+ point (\d+)\s+(\S+)\s+V=(\d+)\s+cap=(\d+)")
TRANS = re.compile(r"^transitions \(kernel's own count\):\s+(\d+)")
FAILS = re.compile(r"^PLL enable failures:\s+(\d+)")


def parse(paths):
    """-> [(point, clock, volts, cap, transitions, failures), ...]"""
    out, cur = [], None
    for path in paths:
        with open(path) as f:
            for line in f:
                m = POINT.match(line)
                if m:
                    if cur and cur[4] is not None:
                        out.append(tuple(cur))
                    n, clock, v, cap = m.groups()
                    cur = [int(n), clock, int(v) / 1e6, int(cap), None, None]
                    continue
                if cur is None:
                    continue
                m = TRANS.match(line)
                if m:
                    cur[4] = int(m.group(1))
                    continue
                m = FAILS.match(line)
                if m:
                    cur[5] = int(m.group(1))
    if cur and cur[4] is not None and cur[5] is not None:
        out.append(tuple(cur))
    return [r for r in out if r[4] and r[5] is not None]


def poisson_ci(k, n):
    """Rough 95% interval on k/n, per 10 000. Normal approximation on sqrt(k),
    which is good enough above about ten counts and is labelled, not hidden."""
    if n == 0:
        return (float("nan"), float("nan"))
    lo = max(0.0, k - 1.96 * math.sqrt(k))
    hi = k + 1.96 * math.sqrt(k)
    return (lo / n * 1e4, hi / n * 1e4)


def fit(xs, ys):
    """Least squares slope/intercept, and Pearson r. No numpy on the device."""
    n = len(xs)
    if n < 3:
        return None
    mx, my = sum(xs) / n, sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    sxy = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    syy = sum((y - my) ** 2 for y in ys)
    if sxx == 0 or syy == 0:
        return None
    b = sxy / sxx
    return b, my - b * mx, sxy / math.sqrt(sxx * syy)


def main(paths):
    rows = parse(paths)
    if not rows:
        sys.exit("no complete points in the log - a point needs both its "
                 "transition count and its failure count")

    print(f"{'pt':>3} {'clock':>9} {'V':>7} {'cap':>5} "
          f"{'trans':>8} {'fails':>6} {'per10k':>8}  95% interval")
    xs, ys, tot_t, tot_f = [], [], 0, 0
    for n, clock, v, cap, t, f in rows:
        rate = f / t * 1e4
        lo, hi = poisson_ci(f, t)
        print(f"{n:>3} {clock:>9} {v:>7.3f} {cap:>4}% "
              f"{t:>8} {f:>6} {rate:>8.1f}  [{lo:.1f}, {hi:.1f}]")
        xs.append(v)
        ys.append(rate)
        tot_t += t
        tot_f += f

    print()
    span = max(xs) - min(xs)
    print(f"points: {len(rows)}   voltage span: {max(xs):.3f} -> {min(xs):.3f} V "
          f"({span * 1000:.0f} mV)")
    print(f"pooled: {tot_f} failures in {tot_t} transitions = "
          f"{tot_f / tot_t * 1e4:.1f} per 10 000")

    if span < 0.15:
        print("\n⚠️  Under 150 mV of span. That is not a ramp yet - the fit "
              "below is reported, but a trend over this little range is not "
              "evidence either way.")

    r = fit(xs, ys)
    if r is None:
        print("\nnot enough points to fit")
        return
    b, a, corr = r
    print(f"\nfit: rate = {a:.1f} + {b:.1f} x V   (per 10 000 per volt)")
    print(f"     r = {corr:+.3f}")

    # ☠️ Do NOT read the verdict off r. Pearson r is scale-free, so a trend of
    # 13 -> 12 per 10 000 across the whole ramp - which is noise - fits with
    # r = +0.83 and would otherwise be announced as a direction. Caught by a
    # deliberately flat fixture; the verdict has to turn on effect SIZE.
    #
    # The yardstick is the counting noise the points actually carry: the mean
    # 95% half-width of the per-point rates. A fitted change smaller than twice
    # that, or smaller than half the pooled rate, is not something this run can
    # distinguish from Poisson scatter.
    span_v = max(xs) - min(xs)
    delta = abs(b) * span_v
    pooled = tot_f / tot_t * 1e4

    # The yardstick is the uncertainty of the FIT, not of one point. A first
    # version compared the fitted change against the mean per-point 95%
    # half-width and threw away a real 12 -> 25 doubling that was monotone over
    # twelve points, because a twelve-point fit is far better determined than
    # any single point in it. Take the slope's own standard error from the
    # residuals instead - that way the data's actual scatter sets the bar.
    n = len(xs)
    mx = sum(xs) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    resid = [y - (a + b * x) for x, y in zip(xs, ys)]
    s2 = sum(r * r for r in resid) / (n - 2) if n > 2 else float("inf")
    se_b = math.sqrt(s2 / sxx) if sxx else float("inf")
    unc = 1.96 * se_b * span_v
    print(f"     change across the ramp: {delta:.1f} per 10 000 "
          f"(95% uncertainty on it: {unc:.1f}; pooled rate {pooled:.1f})")

    # Two gates, and both have to pass: statistically distinguishable from a
    # flat line, and big enough to matter for scheduling a power leg.
    if delta < unc or delta < 0.5 * pooled:
        print("     => NO usable voltage dependence: the fitted change is "
              "within what counting noise alone produces.")
        print("        That is itself the answer the RUNBOOK needs. The storm "
              "is not voltage-gated, so a power leg cannot be protected by "
              "scheduling it at high battery, and every leg must carry its own "
              "failure count instead.")
    elif corr <= -0.5:
        print("     => failures rise as the pack empties: consistent with the "
              "supply-sag hypothesis. Schedule power legs above the voltage "
              "where the rate leaves the noise.")
    elif corr >= 0.5:
        print("     => failures FALL as the pack empties: opposite to the "
              "supply-sag hypothesis, and worth a second run before it is "
              "believed.")
    else:
        print("     => a change this size with no monotone trend means "
              "something other than voltage is moving. Look at what else "
              "differs between points before fitting anything else.")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__ or "usage: pll-ramp-fit.py <log> [...]")
    main(sys.argv[1:])
