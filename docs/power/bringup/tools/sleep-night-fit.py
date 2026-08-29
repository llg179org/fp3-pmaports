#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Price suspend residency in mA from a sleep-night.sh log.
#
#   sleep-night-fit.py <rounds.txt> [reference-discharge.txt] [skip_hours]
#
# `skip_hours` drops the leading part of the run before fitting. A run that had to
# start high spends its first hours on the flat top of the curve, where the travel
# is inside the sample spread; including those rounds does not average out, it
# drags the slope toward zero. Fit the part of the run that is on a readable
# stretch and say which part that was.
#
# ☠️ WHY THIS CANNOT JUST READ THE CAPACITY COLUMN. `capacity`, `charge_now` and
# `current_now` are three sysfs names for ONE software integrator in qcom_smbx.c,
# and its suspend-gap branch counts nothing by design ("a suspend draws too little
# to have moved the charge"). Across the very window this measures, that column is
# pinned by the driver. The only number in the log the suspend does not freeze is
# `v_uV`, sampled by hardware right after each wake.
#
# So: turn volts into charge with a curve measured on this pack, then fit charge
# against time.
#
# The reference curve is a full discharge with its own current column
# (`captures/2026-08-28_discharge-to-shutdown/discharge.txt`): integrate the
# current to get charge spent, and pair it with the voltage at that moment. That
# gives V -> mAh-spent, which inverts to mAh-remaining.
#
# ☠️ THE REFERENCE IS TAKEN UNDER LOAD AND SO IS EACH SAMPLE, AND THE TWO LOADS
# ARE NOT THE SAME. The reference ran at ~150 mA; a sleep-night sample is taken in
# the first seconds after a resume. The IR offset between them does not cancel,
# because the curve is not a straight line - so the absolute mAh is not the claim
# here. The SLOPE is, and a fit is only quoted with the residual beside it.
#
# ☠️ AND A RUN STARTED HIGH IS WORTH LITTLE. Above ~90 % the curve is flat enough
# that a whole night sits inside the ~20 mV sample spread; the printout says so
# rather than letting the reader take a number off a flat stretch.
import sys, statistics

def read_reference(path):
    """(voltage_uV, charge_spent_mAh) from a discharge with a current column."""
    pts, prev_t, spent = [], None, 0.0
    for line in open(path):
        if line.startswith('#') or not line.strip():
            continue
        f = line.split()
        try:
            t, v, i = float(f[0]), int(f[2]), int(f[3])
        except (ValueError, IndexError):
            continue
        if prev_t is not None:
            # uA over seconds -> mAh
            spent += abs(i) * (t - prev_t) / 3.6e6
        prev_t = t
        pts.append((v, spent))
    # the pack only falls, so make the mapping monotone in voltage before use
    pts.sort(key=lambda p: -p[0])
    mono, last = [], -1.0
    for v, s in pts:
        last = max(last, s)
        mono.append((v, last))
    return mono

def spent_at(curve, v):
    """linear interpolation into the reference, clamped at both ends"""
    if v >= curve[0][0]:
        return curve[0][1]
    if v <= curve[-1][0]:
        return curve[-1][1]
    for k in range(1, len(curve)):
        v1, s1 = curve[k - 1]
        v2, s2 = curve[k]
        if v2 <= v <= v1:
            if v1 == v2:
                return s1
            return s1 + (s2 - s1) * (v1 - v) / (v1 - v2)
    return curve[-1][1]

def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__ or "usage: sleep-night-fit.py <rounds.txt> [reference]")
    rounds = sys.argv[1]
    ref = sys.argv[2] if len(sys.argv) > 2 else \
        "../captures/2026-08-28_discharge-to-shutdown/discharge.txt"
    skip_h = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
    curve = read_reference(ref)
    print(f"# reference: {ref}  {len(curve)} points, "
          f"{curve[0][0]/1e6:.3f} V .. {curve[-1][0]/1e6:.3f} V, "
          f"{curve[-1][1]:.0f} mAh spanned")

    xs, ys, slept, total = [], [], 0, 0
    for line in open(rounds):
        if line.startswith('#') or not line.strip():
            continue
        f = line.split()
        try:
            wall, sl, v = float(f[1]), float(f[3]), int(f[5])
        except (ValueError, IndexError):
            continue
        total = wall
        slept += sl          # ☠️ over the WHOLE run: it is a property of the
                             # phone, not of the window chosen for the fit
        if wall / 3600.0 < skip_h:
            continue
        xs.append(wall / 3600.0)
        ys.append(spent_at(curve, v))
    n = len(xs)
    if n < 3:
        sys.exit(f"only {n} rounds - not enough to fit a slope")

    mx, my = statistics.fmean(xs), statistics.fmean(ys)
    sxx = sum((x - mx) ** 2 for x in xs)
    if sxx == 0:
        sys.exit("all rounds at the same time - nothing to fit")
    slope = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sxx
    inter = my - slope * mx
    resid = [y - (inter + slope * x) for x, y in zip(xs, ys)]
    rms = (sum(r * r for r in resid) / n) ** 0.5

    vs = [int(l.split()[5]) for l in open(rounds)
          if not l.startswith('#') and len(l.split()) > 5
          and float(l.split()[1]) / 3600.0 >= skip_h]
    fitted = max(xs) - min(xs)
    print(f"# rounds={n} of a {total/3600:.2f} h run, fitted over {fitted:.2f} h "
          f"from t={skip_h:.2f} h  slept={slept/total*100:.1f} % of the whole run")
    print(f"# voltage {min(vs)/1e6:.3f} .. {max(vs)/1e6:.3f} V, "
          f"sample spread {statistics.pstdev(vs)/1000:.1f} mV")
    print(f"average draw = {slope:.1f} mA   (rms residual {rms:.1f} mAh)")
    # ☠️ Say when the answer is not supported rather than printing it plainly.
    if rms > abs(slope) * fitted * 0.25:
        print("☠️ residual is a large fraction of the total travel - this fit is "
              "noise-dominated, run longer or start lower on the curve")
    if max(vs) > 4_150_000:
        print("☠️ the run sits on the flat top of the curve (>4.15 V); a night's "
              "drain there is inside the sample spread")

main()
