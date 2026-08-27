#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Characterise the BURSTS in an idle-ab window, not the level. The ladders showed
# our floor is below the oracle's and our median above it, so what separates the
# two systems is what happens between the quiet samples - and this asks what that
# looks like: how often, how big, and whether it is periodic.
#
# ☠️ THE SAMPLING LIMIT IS THE FIRST THING TO READ. idle-ab.sh samples every ~5 s,
# so anything with a period under ~10 s is aliased and anything shorter than a
# sample is invisible unless it happens to be caught. A burst seen here is real; a
# burst NOT seen here is not absent. This tool can say "there is a 30 s period" and
# can never say "there is nothing faster than 10 s".
#
# ☠️ AND A HIGH SAMPLE IS NOT A WAKE COUNT. current_now is what the pack delivered
# at that instant; several wakeups inside one interval read as one sample.
#
#   burst-profile.py <rung file> [...]
import sys, statistics as st

def load(path):
    cols, rows = None, []
    for ln in open(path):
        if ln.startswith("# t_s"): cols = ln[2:].split(); continue
        if ln.startswith("#"): continue
        f = ln.split()
        if cols and f and f[0].lstrip("-").isdigit(): rows.append(dict(zip(cols, f)))
    t = [int(r["t_s"]) for r in rows]
    i = [abs(int(r["current_uA"]))/1000.0 for r in rows]
    return t, i

def autocorr_peak(x, lo, hi):
    """Strongest autocorrelation lag in [lo,hi] samples, and its value."""
    n = len(x); m = sum(x)/n
    d = [v - m for v in x]
    den = sum(v*v for v in d) or 1.0
    best = (0, 0.0)
    for lag in range(lo, min(hi, n//3)):
        num = sum(d[k]*d[k+lag] for k in range(n-lag))
        r = num/den
        if r > best[1]: best = (lag, r)
    return best

for path in sys.argv[1:]:
    t, i = load(path)
    if len(i) < 30: print(f"== {path}: too few samples"); continue
    s = sorted(i)
    p10, p50, p90, p99 = (s[int(len(s)*q)] for q in (0.10, 0.50, 0.90, 0.99))
    dt = (t[-1]-t[0])/(len(t)-1)
    # "burst" = a sample at least 1.5x the floor. Arbitrary, but applied identically
    # to both systems, which is what a comparison needs.
    thr = p10*1.5
    burst = [v for v in i if v >= thr]
    # excess energy: how much of the mean is bursts sitting above the floor
    excess = sum(v - p10 for v in i if v > p10)/len(i)
    lag, r = autocorr_peak(i, 2, 40)
    print(f"== {path}")
    print(f"   n={len(i)} dt={dt:.1f}s   floor(p10) {p10:6.1f}   median {p50:6.1f}"
          f"   p90 {p90:6.1f}   p99 {p99:6.1f}   max {max(i):6.1f} mA")
    print(f"   above {thr:.0f} mA (1.5x floor): {len(burst)*100.0/len(i):5.1f} % of samples"
          f"   mean burst {st.mean(burst) if burst else 0:6.1f} mA")
    print(f"   excess over floor: {excess:6.1f} mA of the {st.mean(i):.1f} mA mean"
          f"  ({excess*100/st.mean(i):.0f} % of the draw is above the floor)")
    print(f"   strongest autocorrelation lag {lag} samples = {lag*dt:5.1f}s  r={r:+.3f}"
          + ("   <- periodic" if r > 0.2 else "   (no periodicity found)"))
