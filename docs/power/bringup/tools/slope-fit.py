#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Reduce a suspend-slope.sh run to a suspend current.
#
#   slope-fit.py suspend-slope.txt [curlog.txt]
#
# The method, and why it is not the obvious one: on this platform capacity,
# charge_now and voltage_ocv are a single number maintained by a 30 s poll
# worker that does not run while userspace is frozen, so none of them can cross
# a suspend boundary. Only voltage_now and current_now are sampled on read. See
# README.md, "The second instrument was wrong too".
#
# So: fit compensated voltage against time separately for the asleep phase and
# the awake control phase, and take the ratio. A slope cancels any constant
# offset, which is what every bias found here turns out to be. The awake phase
# also carries a directly measured current, so the ratio converts to milliamps
# without the OCV table entering at all:
#
#   I_sleep = I_awake * (slope_A / slope_B)
#
# ☠️ Read the phase B block of the output first. It is the control: if its mean
# current is not near the independently known awake figure, or its fit is not a
# straight line, the method is broken and the phase A number means nothing.
# Three instruments have already failed this question; the control window is
# what caught every one of them.
#
# Self-test: slope-fit.py --selftest  (a checker that has never been shown
# failing has proved nothing).

import re
import sys

R_MOHM = 120  # factory-internal-resistance-micro-ohms / 1000, from the DT

LINE = re.compile(r"phase=(\w+)\s+n=(\d+)\s+t=(\d+)\s+v=(-?\d+)\s+i=(-?\d+)")


def parse(path):
    """-> {phase: [(t_s, v_comp_uv, i_ua), ...]}"""
    phases = {}
    with open(path) as f:
        for line in f:
            m = LINE.search(line)
            if not m:
                continue
            ph, _, t, v, i = m.group(1), *(int(x) for x in m.groups()[1:])
            # Discharging current is negative; compensating for the IR drop
            # means adding it back to get the unloaded terminal voltage.
            phases.setdefault(ph, []).append((t, v - i * R_MOHM // 1000, i))
    return phases


def fit(pts):
    """Least-squares slope of v against t. -> (slope_uv_per_s, r2)"""
    n = len(pts)
    if n < 3:
        return None, None
    sx = sum(p[0] for p in pts)
    sy = sum(p[1] for p in pts)
    mx, my = sx / n, sy / n
    sxy = sum((p[0] - mx) * (p[1] - my) for p in pts)
    sxx = sum((p[0] - mx) ** 2 for p in pts)
    syy = sum((p[1] - my) ** 2 for p in pts)
    if sxx == 0 or syy == 0:
        return None, None
    slope = sxy / sxx
    return slope, (sxy * sxy) / (sxx * syy)


def dense_mean(path, t0, t1):
    """Mean |current| from the companion logger, over [t0, t1]."""
    vals = []
    try:
        with open(path) as f:
            for line in f:
                parts = line.split()
                if len(parts) < 2:
                    continue
                try:
                    t, i = int(parts[0]), int(parts[1])
                except ValueError:
                    continue
                if t0 <= t <= t1:
                    vals.append(abs(i))
    except OSError:
        return None, 0
    return (sum(vals) / len(vals) if vals else None), len(vals)


def report(path, curlog=None):
    phases = parse(path)
    for ph in ("settle", "A", "B"):
        if ph not in phases:
            continue
        pts = phases[ph]
        slope, r2 = fit(pts)
        span = (pts[-1][0] - pts[0][0]) / 3600
        print(f"phase {ph}: {len(pts)} samples over {span:.2f} h")
        print(f"  compensated V: {pts[0][1]/1e6:.4f} -> {pts[-1][1]/1e6:.4f}")
        if slope is None:
            print("  too few points to fit")
        else:
            print(f"  slope {slope*3600/1000:+.2f} mV/h   r2={r2:.4f}"
                  + ("   ☠️ not a straight line" if r2 < 0.90 else ""))
        sampled = [abs(p[2]) for p in pts]
        print(f"  current_now over these samples: mean {sum(sampled)/len(sampled)/1000:.1f} mA,"
              f" min {min(sampled)/1000:.1f}, max {max(sampled)/1000:.1f}")
        if curlog and ph in ("A", "B"):
            m, n = dense_mean(curlog, pts[0][0], pts[-1][0])
            if m:
                print(f"  dense logger: mean {m/1000:.1f} mA over {n} samples")
        print()

    a, b = phases.get("A"), phases.get("B")
    if not a or not b:
        print("need both phases to convert")
        return
    sa, _ = fit(a)
    sb, ra2 = fit(b)
    if not sa or not sb:
        print("cannot fit both phases")
        return

    # The control's current: prefer the dense logger, since the load varies a
    # lot and 8 widely spaced samples estimate its mean badly.
    i_awake = None
    if curlog:
        i_awake, _ = dense_mean(curlog, b[0][0], b[-1][0])
    if i_awake is None:
        i_awake = sum(abs(p[2]) for p in b) / len(b)

    print("=" * 60)
    print(f"CONTROL   phase B awake: {i_awake/1000:.1f} mA measured directly,"
          f" slope {sb*3600/1000:+.2f} mV/h")
    print("          ☠️ if that current is not the awake figure you already"
          " know, stop here.")
    print(f"RESULT    phase A asleep: {i_awake/1000 * sa/sb:.1f} mA"
          f"   (= {i_awake/1000:.1f} x {sa/sb:.3f})")
    print("=" * 60)


def selftest():
    """Prove the fit against inputs whose answer is known, including a
    negative - a checker not yet shown failing has proved nothing."""
    import tempfile, os
    ok = True

    # Phase B falls 100 mV/h at 100 mA; phase A falls 25 mV/h => 25 mA.
    lines = []
    for n in range(8):
        t = 1000 + n * 900
        lines.append(f"X phase=A n={n} t={t} v={4200000 - 25000*(t-1000)//3600} i=0")
    for n in range(8):
        t = 10000 + n * 900
        lines.append(f"X phase=B n={n} t={t} v={4100000 - 100000*(t-10000)//3600} i=-100000")
    fd, p = tempfile.mkstemp(text=True)
    os.write(fd, ("\n".join(lines) + "\n").encode())
    os.close(fd)

    ph = parse(p)
    sa, _ = fit(ph["A"])
    sb, r2 = fit(ph["B"])
    got = (sum(abs(x[2]) for x in ph["B"]) / len(ph["B"])) / 1000 * sa / sb
    if abs(got - 25.0) > 0.5:
        print(f"FAIL: expected 25.0 mA, got {got:.2f}")
        ok = False
    if r2 < 0.999:
        print(f"FAIL: clean line should fit, r2={r2:.4f}")
        ok = False

    # Negative control: scatter must not pass the straight-line check.
    noisy = [(t, v, 0) for t, v in
             zip(range(0, 8000, 1000), [10, 900, 20, 880, 30, 870, 40, 860])]
    _, r2n = fit(noisy)
    if r2n >= 0.90:
        print(f"FAIL: scatter passed the r2 gate, r2={r2n:.4f}")
        ok = False

    os.unlink(p)
    print("selftest: PASS" if ok else "selftest: FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--selftest":
        sys.exit(selftest())
    if len(sys.argv) < 2:
        sys.exit(__doc__ or "usage: slope-fit.py suspend-slope.txt [curlog.txt]")
    report(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
