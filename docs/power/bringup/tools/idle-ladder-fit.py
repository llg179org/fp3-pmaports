#!/usr/bin/env python3
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
"""Fit an idle-ladder capture: median current per stage, and the marginal cost
of each step.

☠️ Median, never mean. One current_now read on this device scatters by about
138 mA, and a single outlier moves a mean of 60 samples by more than the terms
being resolved.

☠️ Stage R is the drift control, not a result. If R does not come back to S0,
the difference is the ladder's error bar and every marginal below it that is
smaller than that gap is noise, not a finding.
"""
import random
import sys
from statistics import median


def load(path):
    stages, order = {}, []
    for line in open(path):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        f = line.split()
        if len(f) != 5:
            continue
        tag, _up, cur, volt, _cap = f
        if tag not in stages:
            stages[tag] = []
            order.append(tag)
        # current_now is negative while discharging; report magnitude in mA
        stages[tag].append((abs(int(cur)) / 1000.0, int(volt) / 1e6))
    return stages, order


def pct(xs, q):
    xs = sorted(xs)
    i = (len(xs) - 1) * q
    lo, hi = int(i), min(int(i) + 1, len(xs) - 1)
    return xs[lo] + (xs[hi] - xs[lo]) * (i - lo)


def stat_se(xs, fn, rounds=2000, seed=11):
    """Bootstrap standard error of the median.

    ☠️ The drift control (R - S0) bounds systematic error but says nothing
    about the sampling error of any one stage. Measured on synthetic data with
    this device's scatter, 60 samples give a median SE around 6 mA, so a
    marginal - a difference of two medians - carries about 9 mA. Marginals
    below that are not findings no matter how clean the drift control looks.
    """
    rnd = random.Random(seed)
    n = len(xs)
    if n < 4:
        return float('nan')
    vals = []
    for _ in range(rounds):
        vals.append(fn([xs[rnd.randrange(n)] for _ in range(n)]))
    mu = sum(vals) / len(vals)
    var = sum((v - mu) ** 2 for v in vals) / (len(vals) - 1)
    return var ** 0.5


def median_se(xs, **kw):
    return stat_se(xs, median, **kw)


def floor_se(xs, **kw):
    return stat_se(xs, lambda v: pct(v, 0.10), **kw)


def quart(xs, q):
    xs = sorted(xs)
    i = (len(xs) - 1) * q
    lo, hi = int(i), min(int(i) + 1, len(xs) - 1)
    return xs[lo] + (xs[hi] - xs[lo]) * (i - lo)


LABEL = {
    'S0': 'baseline (session stopped, everything else as booted)',
    'S1': '- cups avahi bluetooth udisks2 tuned tuned-ppd',
    'S2': '- snsregd iio-sensor-proxy',
    'S3': '- spkwatch ringwatch fp3-voiced',
    'S4': '- ModemManager rmtfs tqftpserv',
    'S5': '- wifi radio',
    'R': 'RESTORED = drift control, compare to S0',
}


def main(path):
    stages, order = load(path)
    if not stages:
        print('no samples - the capture is empty')
        return 1

    med, se = {}, {}
    print(f'{path}\n')
    print(f'{"stage":5} {"n":>3} {"FLOOR p10":>10} {"+-SE":>6} {"median":>8} '
          f'{"+-SE":>6} {"IQR":>13} {"max":>7}  {"V":>6}')
    print('-' * 92)
    for tag in order:
        cur = [c for c, _ in stages[tag]]
        volt = [v for _, v in stages[tag]]
        med[tag] = pct(cur, 0.10)
        se[tag] = floor_se(cur)
        print(f'{tag:5} {len(cur):3d} {med[tag]:10.1f} {se[tag]:6.1f} '
              f'{median(cur):8.1f} {median_se(cur):6.1f} '
              f'{quart(cur, .25):6.1f}-{quart(cur, .75):<6.1f} '
              f'{max(cur):7.1f}  {median(volt):6.3f}')

    # ☠️ The marginals below are computed on the FLOOR (p10), not the median.
    # Measured on the 2026-08-18 ladder: the floor was stable to a few mA
    # across five stages (84.8, 83.9, 85.9, 85.3, then 88.5 on the restored
    # control) while the median wandered over 137-151 with a 10-18 mA standard
    # error. The distribution here is a quiet floor plus bursts, and the burst
    # rate is not what any of these stages was changing - so the floor is the
    # signal and everything above it is weather.

    print('\nmarginal cost of each step (previous stage - this stage):')
    prev = None
    for tag in order:
        if tag == 'R':
            continue
        if prev is not None:
            d = med[prev] - med[tag]
            u = (se[prev] ** 2 + se[tag] ** 2) ** 0.5
            mark = '' if abs(d) > 2 * u else '   <- inside the noise'
            print(f'  {prev} -> {tag}  {d:+7.1f} +-{u:4.1f} mA   '
                  f'{LABEL.get(tag, "")}{mark}')
        prev = tag

    if 'R' in med and 'S0' in med:
        drift = med['R'] - med['S0']
        du = (se['R'] ** 2 + se['S0'] ** 2) ** 0.5
        print(f'\nDRIFT CONTROL  R - S0 = {drift:+.1f} +-{du:.1f} mA '
              f'(R {med["R"]:.1f}, S0 {med["S0"]:.1f})')
        print(f'☠️  Any marginal above smaller than {abs(drift):.1f} mA is inside '
              f'the drift and is not a finding.')
        if 'S5' in med:
            print(f'\nTOTAL removed S0 -> S5: {med["S0"] - med["S5"]:+.1f} mA '
                  f'({med["S0"]:.1f} -> {med["S5"]:.1f} mA)')
    else:
        print('\n☠️  no R stage - the ladder has no drift control and the '
              'marginals cannot be trusted.')
    return 0


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
