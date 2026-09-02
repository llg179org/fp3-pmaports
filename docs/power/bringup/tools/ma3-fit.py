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

def leg_stats(rows, boots=4000):
    gaps = [(rows[i + 1][0] - rows[i][0]).total_seconds() for i in range(len(rows) - 1)]
    med = st.median(gaps)
    thr = SAMPLES_PER_S * med
    kept = [(v, c) for _, v, c in rows if c < thr]
    if not kept:
        return None
    point = ma(kept)
    bs = sorted(ma([random.choice(kept) for _ in kept]) for _ in range(boots))
    lo, hi = bs[int(0.025 * boots)], bs[int(0.975 * boots) - 1]
    return dict(med=med, thr=thr, kept=len(kept), n=len(rows), ma=point, lo=lo, hi=hi)

d = pathlib.Path(sys.argv[1])
d = d / 'raw' if (d / 'raw').is_dir() else d
legs = sys.argv[2:] or [p.name[8:-4] for p in sorted(d.glob('samples-*.txt'))]
print(f"{'leg':<4} {'sleep':>7} {'gate':>7} {'kept':>8} {'current':>10}   95% CI (bootstrap on sum/sum)")
for leg in legs:
    r = leg_stats(load(d, leg))
    if not r:
        print(f'{leg:<4} no sample survives the gate')
        continue
    print(f"{leg:<4} {r['med']:>6.0f}s {r['thr']:>7.0f} {r['kept']:>4}/{r['n']:<3} "
          f"{r['ma']:>8.1f} mA   [{r['lo']:.1f}, {r['hi']:.1f}]  +-{(r['hi']-r['lo'])/2:.1f}")
print()
print('☠️ The CI is the SPREAD OF THIS ONE LEG ONLY. It says nothing about the')
print('   PMI632 offset the whole project shares, and nothing about boot-to-boot')
print('   variation - the A vs A2 pair is the honest witness for the latter.')
