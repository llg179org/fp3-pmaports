#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
"""Classify an xo-series.sh capture: is the awake time SMOOTH or BURSTY?

The whole point of the series is a question the mean cannot answer. Two
mechanisms produce the same 38% duty and want opposite fixes:

  smooth  ~150 ms of work every paging cycle, so almost every second looks alike
  bursty  quiet for tens of seconds, then SECONDS at a time scanning for a
          system that is not there

The discriminator is the COEFFICIENT OF VARIATION of the per-second awake time,
backed by RUN MASS - the share of all awake time that arrives inside runs of
three or more consecutive busy seconds, which is what "a multi-second scan"
means physically.

☠️ THE FIRST VERSION OF THIS FILE USED THE TOP-DECILE SHARE AND WAS WRONG, and
it was wrong in the direction that matters: a synthetic textbook burst - 15 s
scans every 40 s, 37.5% of seconds saturated, 62.5% of seconds idle - came back
UNDECIDED. The metric is ALGEBRAICALLY CAPPED at 0.10/f, where f is the fraction
of busy seconds: the top decile can only ever hold a tenth of the busy seconds,
so at f=0.375 nothing above 0.27 is reachable and a 0.35 threshold can never
fire. The measured ceiling, by busy fraction: 0.20 -> 0.50, 0.375 -> 0.27,
0.60 -> 0.17. A scale-free-looking statistic is not scale-free. It is still
printed, as context, and never as the verdict.

☠️ AND THE VERDICT IS VOID IF THE LEG CHANGED REGIME. A leg that runs 5% for
five minutes and 35% for five more has a bimodal distribution for reasons that
have nothing to do with bursts, so the step test runs FIRST and suppresses the
classification when it fires. The mean of two regimes is a property of neither.

  xo-series-fit.py <capture.txt> [...]
"""
import sys

SATURATED_MS = 900.0   # a second this busy is a stretch of work, not an occasion
BUSY_MS = 500.0        # more than half a second awake is not per-occasion work
QUIET_MS = 50.0
RUN_MIN = 3            # consecutive busy seconds that constitute a "stretch"
CV_BURSTY = 0.80       # coefficient of variation above this: bursty
CV_SMOOTH = 0.35       # ...below this: smooth. Between: say undecided, do not guess
STEP_PP = 15.0         # per-minute duty step worth naming


def load(path):
    rows = []
    for ln in open(path, encoding="utf-8", errors="replace"):
        if ln.startswith("#") or not ln.strip():
            continue
        f = ln.split()
        if len(f) < 4:
            continue
        try:
            rows.append((float(f[0]), float(f[1]), float(f[3])))  # t, awake_ms, dt
        except ValueError:
            continue
    return rows


def per_minute(rows):
    mins, cur, curwin, m0 = [], 0.0, 0.0, rows[0][0]
    for t, a, dt in rows:
        if t - m0 >= 60.0:
            mins.append(100.0 * (cur / 1000.0) / curwin if curwin else 0.0)
            cur, curwin, m0 = 0.0, 0.0, t
        cur += a
        curwin += dt
    if curwin >= 30.0:
        mins.append(100.0 * (cur / 1000.0) / curwin)
    return mins


def run_mass(aw):
    """Share of all awake time inside runs of >= RUN_MIN consecutive busy seconds."""
    busy = [x >= BUSY_MS for x in aw]
    inruns, i, n = 0.0, 0, len(aw)
    while i < n:
        if not busy[i]:
            i += 1
            continue
        j = i
        while j < n and busy[j]:
            j += 1
        if j - i >= RUN_MIN:
            inruns += sum(aw[i:j])
        i = j
    tot = sum(aw)
    return (inruns / tot if tot else 0.0), busy


def report(path):
    rows = load(path)
    print(f"=== {path}")
    if len(rows) < 30:
        print(f"  \u2620\ufe0f only {len(rows)} samples - too few to classify. NOT a smooth series.")
        return
    aw = [r[1] for r in rows]
    win = sum(r[2] for r in rows)
    n = len(aw)
    mean = sum(aw) / n
    var = sum((x - mean) ** 2 for x in aw) / n
    sd = var ** 0.5
    cv = sd / mean if mean else 0.0
    duty = 100.0 * (sum(aw) / 1000.0) / win if win else 0.0

    s = sorted(aw)
    p = lambda q: s[min(n - 1, int(q * n))]
    top10 = s[int(0.9 * n):]
    share = sum(top10) / sum(aw) if sum(aw) else 0.0
    rm, busy = run_mass(aw)
    f_busy = sum(busy) / n
    ceiling = min(1.0, 0.10 / f_busy) if f_busy else 1.0

    sat = [x >= SATURATED_MS for x in aw]
    run = best = 0
    for b in sat:
        run = run + 1 if b else 0
        best = max(best, run)

    print(f"  n={n} window={win:.0f}s  duty={duty:.1f}%  mean_awake={mean:.0f} ms/s  sd={sd:.0f}")
    print(f"  p10={p(.1):.0f}  p50={p(.5):.0f}  p90={p(.9):.0f} ms/s")
    print(f"  saturated (>={SATURATED_MS:.0f} ms): {100.0*sum(sat)/n:.1f}% of seconds, "
          f"longest run {best} s")
    print(f"  quiet (<{QUIET_MS:.0f} ms): {100.0*sum(1 for x in aw if x < QUIET_MS)/n:.1f}%")
    print(f"  CV = {cv:.2f}   run mass (>={RUN_MIN} s stretches) = {rm:.2f}")
    print(f"  top-decile share = {share:.2f}  \u2620\ufe0f capped at {ceiling:.2f} here "
          f"(busy fraction {f_busy:.2f}) - context only, never the verdict")

    mins = per_minute(rows)
    stepped = False
    if len(mins) >= 2:
        print("  per-minute duty: " + " ".join(f"{m:.0f}" for m in mins))
        d, i = max((abs(mins[k + 1] - mins[k]), k) for k in range(len(mins) - 1))
        # \u2620\ufe0f A STEP IS ONE-WAY; AN ALTERNATION IS NOT A STEP. The first version
        # called any large adjacent move a regime change, and a synthetic burst
        # with a 40 s period - which aliases against the 60 s bucket into 51/26/
        # 51/26 - was reported as a regime step and had its verdict suppressed.
        # The very pattern the tool exists to detect was hidden by its own guard.
        # A real transition SEPARATES the two halves: everything before it sits
        # on one side of everything after it. An alternation does not.
        # \u2620\ufe0f AND A ONE-MINUTE HALF PROVES NOTHING. With a single minute on
        # one side, "the halves do not overlap" is satisfied by noise: the
        # alternating series above passed it because its first minute happened
        # to be 0.2 pp above the largest of the rest. Demand at least two
        # minutes on each side, and a real GAP - half the step threshold -
        # between them. A transition inside the last minute of a leg is simply
        # not decidable from this leg, and saying so beats guessing.
        before, after = mins[:i + 1], mins[i + 1:]
        gap = STEP_PP / 2.0
        separated = (len(before) >= 2 and len(after) >= 2 and
                     (max(before) + gap < min(after) or min(before) > max(after) + gap))
        if d >= STEP_PP and separated:
            stepped = True
            print(f"  \u2620\ufe0f REGIME STEP: minute {i} -> {i+1} moves {mins[i]:.0f}% -> "
                  f"{mins[i+1]:.0f}% ({d:.0f} pp), and the two halves do not overlap. This "
                  "leg averages two regimes; its mean is a property of neither, and the "
                  "smooth/bursty verdict is VOID for it - split the series at the step and "
                  "classify each side.")
        elif d >= STEP_PP:
            print(f"  per-minute duty swings {d:.0f} pp but the level RETURNS (the halves "
                  "overlap): periodic, not a regime change. That is burst structure "
                  "aliasing against the 60 s bucket - read it in the CV and run mass below.")
        else:
            print(f"  no regime step (largest adjacent move {d:.0f} pp)")

    if stepped:
        return
    if cv >= CV_BURSTY:
        print(f"  => BURSTY. CV {cv:.2f}, and {100*rm:.0f}% of the awake time arrives in "
              f"stretches of >={RUN_MIN} s (longest {best} s). Consistent with "
              "acquisition/scan work, NOT with per-occasion work.")
    elif cv <= CV_SMOOTH:
        print(f"  => SMOOTH. CV {cv:.2f}: nearly every second carries the same load. "
              "Consistent with per-occasion work or a fixed per-wake overhead; NOT with "
              "periodic scans.")
    else:
        print(f"  => UNDECIDED ({CV_SMOOTH} < CV {cv:.2f} < {CV_BURSTY}). Say so; do not "
              "pick the reading that suits the hypothesis.")
    # ☠️ SAY THE RESOLUTION LIMIT OUT LOUD. A 1 Hz series cannot see structure
    # below a second, so "SMOOTH" means "no bursts of about a second or more" and
    # NOT "the wakes are uniform" - a sentence that will otherwise be quoted back
    # as if this instrument had measured it.
    print(f"  resolution: 1 Hz. This can only exclude bursts of ~1-2 s and longer; it says "
          f"nothing about structure inside a second. Longest saturated run here: {best} s, "
          f"share of awake time in runs of >={RUN_MIN} s: {rm:.2f}, quiet seconds: "
          f"{100.0*sum(1 for x in aw if x < QUIET_MS)/n:.1f}%.")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    for a in sys.argv[1:]:
        report(a)
