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

    med = {}
    print(f'{path}\n')
    print(f'{"stage":5} {"n":>3} {"median mA":>10} {"IQR":>13} {"min-max":>15}  {"V":>6}')
    print('-' * 78)
    for tag in order:
        cur = [c for c, _ in stages[tag]]
        volt = [v for _, v in stages[tag]]
        m = median(cur)
        med[tag] = m
        print(f'{tag:5} {len(cur):3d} {m:10.1f} '
              f'{quart(cur, .25):6.1f}-{quart(cur, .75):<6.1f} '
              f'{min(cur):6.1f}-{max(cur):<7.1f}  {median(volt):6.3f}')

    print('\nmarginal cost of each step (previous stage - this stage):')
    prev = None
    for tag in order:
        if tag == 'R':
            continue
        if prev is not None:
            d = med[prev] - med[tag]
            print(f'  {prev} -> {tag}  {d:+7.1f} mA   {LABEL.get(tag, "")}')
        prev = tag

    if 'R' in med and 'S0' in med:
        drift = med['R'] - med['S0']
        print(f'\nDRIFT CONTROL  R - S0 = {drift:+.1f} mA '
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
