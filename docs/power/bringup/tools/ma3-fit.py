#!/usr/bin/env python3
# Aggregate an ims-ma3 census and state its error band.
#
# ☠️ THE GATE IS PER LEG, AND ITS SCALE IS THE LEG'S OWN SLEEP - NOT THE ALARM.
# The accumulator wraps at ACCUM_CNT = 255 at ~3.35-3.4 samples/s, so a sample
# whose cnt implies a window longer than the leg actually slept began BEFORE the
# sleep and carries the previous wake's awake current, always upward. On a leg
# that sleeps the full alarm the two scales coincide; on a leg that does not
# sleep - which is exactly what the expensive state does - they differ by 4x, and
# reading the gate as "3.35 x alarm" silently keeps 39 contaminated samples
# instead of 7 and pulls that leg from 91.0 mA down to 84.2 mA. Measured on the
# 2026-09-02 census while trying to reproduce its own published table.
#
# ☠️ AND AGGREGATE sum(accum)/sum(cnt), NOT a mean of per-sample means: each
# sample is an integral over a different number of ticks, so a plain mean weights
# a short window like a long one.
#
# usage: ma3-fit.py <capture-dir> [leg ...]
import sys, re, statistics as st, random, datetime as dt, pathlib

I_RAW_TO_UA = 152588 / 1000          # per the QG datasheet units, /1000 -> uA
SAMPLES_PER_S = 3.35                 # measured: 140 samples over 41 s of sleep
MIN_CNT = 20                         # ~6 s; below that the resume transient dominates

def load(d, leg):
    out = []
    for line in open(d / f'samples-{leg}.txt'):
        m = re.search(r't=(\S+ \S+) acc=0x([0-9a-f]+) cnt=0x([0-9a-f]+)', line)
        if not m:
            continue
        t = dt.datetime.strptime(m.group(1), '%Y-%m-%d %H:%M:%S')
        v = int(m.group(2), 16)
        if v >= 1 << 23:             # 24-bit signed, little endian
            v -= 1 << 24
        out.append((t, v, int(m.group(3), 16)))
    return out

def ma(kept):
    return sum(v for v, c in kept) * I_RAW_TO_UA / sum(c for v, c in kept) / 1000

# ☠️ TWO WRONG ANSWERS BEFORE THIS ONE, AND THE SECOND WAS A REVIEWER'S.
#
# First a bootstrap at every n. Resampling 7 values estimates its own tail, so it
# printed +-8.4 mA off 7 samples and looked exactly as authoritative as the +-1.1
# off 22.
#
# Then, on review, a t interval below n=15. That was worse, and the same reviewer
# retracted it a round later: the POINT estimate is the cnt-weighted sum/sum, in
# which a short noisy window carries little weight, while a t interval runs on the
# UNWEIGHTED per-window means, where those same windows dominate the spread. The
# two do not describe the same quantity - which is how leg A' went from +-8.4 to
# +-43.3 without any new data.
#
# The estimator that matches the point estimate is the weighted variance of the
# weighted mean: Var(mu) = sum(w_i^2 (x_i - mu)^2) / (sum w_i)^2, with w = cnt.
# It neither flatters short windows nor lets them dominate, and it needs no
# resampling at any n.
T975 = {1: 12.706, 2: 4.303, 3: 3.182, 4: 2.776, 5: 2.571, 6: 2.447, 7: 2.365,
        8: 2.306, 9: 2.262, 10: 2.228, 11: 2.201, 12: 2.179, 13: 2.160,
        14: 2.145, 15: 2.131, 20: 2.086, 21: 2.080, 30: 2.042}

def t975(df):
    if df in T975:
        return T975[df]
    return next(v for k, v in sorted(T975.items()) if k >= df) if df < 30 else 1.96

def leg_stats(rows, boots=0):
    gaps = [(rows[i + 1][0] - rows[i][0]).total_seconds() for i in range(len(rows) - 1)]
    med = st.median(gaps)
    thr = SAMPLES_PER_S * med
    # ☠️ THE GATE NEEDS A FLOOR AS WELL AS A CEILING, and it took an outlier
    # detector to notice. Leg A' held a window with cnt = 1 - a single accumulator
    # tick, i.e. an instantaneous reading with no averaging at all - which came out
    # as 303.7 mA and, by itself, produced most of that leg's spread. Below roughly
    # six seconds the window is shorter than the resume transient sitting inside
    # it, so it measures the wake rather than the sleep. Dropping those is not
    # trimming inconvenient data: cnt is how many samples the hardware averaged,
    # and a one-sample average is not the quantity this script claims to report.
    kept = [(v, c) for _, v, c in rows if MIN_CNT <= c < thr]
    if not kept:
        return None
    point = ma(kept)
    n = len(kept)
    per = [v * I_RAW_TO_UA / c / 1000 for v, c in kept]
    if n < 2:
        return dict(med=med, thr=thr, kept=n, n=len(rows), ma=point,
                    lo=point, hi=point, how='n=1, no spread', out=[])
    w = [c for _, c in kept]
    sw = sum(w)
    var = sum((wi ** 2) * ((xi - point) ** 2) for wi, xi in zip(w, per)) / (sw ** 2)
    half = t975(n - 1) * var ** 0.5
    # ☠️ NAME THE OUTLIERS INSTEAD OF LETTING THEM BE A NUMBER. A leg whose spread
    # comes from one or two windows is not a noisy leg, it is a leg with something
    # in it that needs looking at - a window that caught the screen, a boot
    # remnant, a wake that never slept. The band alone hides that.
    med_x = st.median(per)
    out = [(round(x, 1), c) for x, (_, c) in zip(per, kept) if abs(x - med_x) > 3 * (st.median(
        [abs(y - med_x) for y in per]) or 1)]
    return dict(med=med, thr=thr, kept=n, n=len(rows), ma=point,
                lo=point - half, hi=point + half,
                how=f'weighted, df={n - 1}', out=out)


# ☠️ A LEG THAT DID NOT SLEEP ITS ALARM WAS DISTURBED, AND THE GATE HIDES IT.
# The gate scales with the leg's OWN median sleep, which is right - but it means a
# leg woken every 9 s against a 90 s alarm still produces a number, computed over
# a threshold of 30 and one surviving sample, and nothing in the output says the
# leg was interfered with. Measured: a rehearsal leg came back at 9 s median
# because this session ssh'd and pinged the phone in the middle of it to answer a
# question - the same interference this project had warned the owner about that
# morning. An ssh login is an AP wake. So the fit says it out loud.
def disturbed(med, alarm):
    return alarm and med < 0.6 * alarm

# ☠️ THE TABLE IN THE REPORT IS GENERATED BY THIS, NOT RETYPED. Copying numbers
# by hand is how a published table drifts from the data it claims to summarise -
# and this file exists because reproducing one such table took a sixth review
# round to explain. `--md` prints the markdown rows; paste those, nothing else.
MD = '--md' in sys.argv
# --alarm <s> lets the fit compare the sleep it sees with the sleep that was asked for
ALARM = 0
if '--alarm' in sys.argv:
    ALARM = float(sys.argv[sys.argv.index('--alarm') + 1])
argv = [a for a in sys.argv if a != '--md']
if '--alarm' in argv:
    i = argv.index('--alarm'); del argv[i:i + 2]
d = pathlib.Path(argv[1])
d = d / 'raw' if (d / 'raw').is_dir() else d
legs = argv[2:] or [p.name[8:-4] for p in sorted(d.glob('samples-*.txt'))]
if MD:
    print('| leg | slept | kept | **current** | 95 % CI (within-leg only) |')
    print('|---|---:|---:|---:|---|')
else:
    print(f"{'leg':<4} {'sleep':>7} {'gate':>7} {'kept':>8} {'current':>10}   95% CI (within-leg only)"
          f"   [gate: {MIN_CNT} <= cnt < 3.35 x the leg's own median sleep]")
for leg in legs:
    r = leg_stats(load(d, leg))
    if not r:
        print(f'{leg:<4} no sample survives the gate')
        continue
    if MD:
        print(f"| {leg} | {r['med']:.0f} s | {r['kept']}/{r['n']} | {r['ma']:.1f} mA | "
              f"±{(r['hi']-r['lo'])/2:.1f} ({r['how']}) |"
              + (f"  <!-- outliers: {r['out']} -->" if r['out'] else ''))
        continue
    print(f"{leg:<4} {r['med']:>6.0f}s {r['thr']:>7.0f} {r['kept']:>4}/{r['n']:<3} "
          f"{r['ma']:>8.1f} mA   [{r['lo']:.1f}, {r['hi']:.1f}]  +-{(r['hi']-r['lo'])/2:.1f}  ({r['how']})")
    if ALARM and disturbed(r['med'], ALARM):
        print(f"       ☠️☠️ THIS LEG WAS DISTURBED: median sleep {r['med']:.0f} s against a "
              f"{ALARM:.0f} s alarm. Something woke the AP - an ssh login, a ping, a poller. "
              f"The number above is not the sleeping floor of anything.")
    if r['out']:
        print(f"       ☠️ look at these windows before calling this statistics: "
              f"{', '.join(f'{x} mA (cnt {c})' for x, c in r['out'])}")
if MD:
    sys.exit(0)
# ☠️ THE GAP IS COMPUTED HERE TOO, because the last time it was typed into prose
# it went stale the moment the estimator changed: the report said +-12.3 for weeks
# after the band it was built from had become +-10.4. A number a human retypes is
# a number that drifts from its own fit.
res = {leg: leg_stats(load(d, leg)) for leg in legs}
cheap = min((r for r in res.values() if r), key=lambda r: r['ma'], default=None)
if cheap:
    for leg, r in res.items():
        if not r or r is cheap:
            continue
        gap = r['ma'] - cheap['ma']
        half = ((r['hi'] - r['lo']) ** 2 / 4 + (cheap['hi'] - cheap['lo']) ** 2 / 4) ** 0.5
        print(f"gap {leg} - cheapest: {gap:.1f} mA  +-{half:.1f}  (quadrature of the two within-leg bands)")
print()
print('☠️ THE CI IS WITHIN-LEG ONLY - the sampling noise of one leg of one boot.')
print('   It says nothing about the PMI632 offset the whole project shares, and')
print('   nothing about the DOMINANT unknown, which is boot-to-boot variation: no')
print('   single leg can see that, however many windows it holds. Label every')
print('   number from here "+-X (within-leg; boot-to-boot unknown)", and once')
print('   several boots exist take the boot-to-boot spread from the SPREAD OF THE')
print('   LEG MEANS - never from the pooled windows, which would hide it.')
