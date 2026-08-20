#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Fit an alternating-arms leg: one slope per SUSPEND, compared arm against arm.
#
# ☠️ The obvious analysis is wrong, and a synthetic test caught it before any
# device time was spent. Regressing all of one arm's samples against time looks
# natural and is contaminated: between two CUT suspends the FULL arm ran and
# discharged the pack, so that discharge lands inside the CUT fit's gaps. On data
# built with a true 11.6 mV/h difference the whole-arm regression reported 2.1.
#
# The uncontaminated measurement is each suspend on its own - v1-v0 over t1-t0,
# which spans only that arm's own state - and the comparison is between the two
# arms' distributions of those. That is also why the leg alternates: consecutive
# suspends sit at nearly the same voltage and temperature, so the pairing is
# tight.
#
# It reports a DIFFERENCE OF SLOPES, not a current. Converting needs an awake
# control and this leg deliberately does not spend time on one: the question is
# which arm is cheaper and by how much.
import re, sys, statistics

per = {}
for line in open(sys.argv[1] if len(sys.argv) > 1 else '/dev/stdin'):
    m = re.search(r'ARM (\w+) t0=(\d+) v0=(\d+) t1=(\d+) v1=(\d+) slept=(\d+)s of (\d+)s', line)
    if not m:
        continue
    label = m.group(1)
    t0, v0, t1, v1, slept, asked = (int(x) for x in m.groups()[1:])
    if slept < asked * 0.95:
        print(f'☠️  a {label} suspend ended early: {slept}s of {asked}s - excluded')
        continue
    if t1 > t0:
        per.setdefault(label, []).append((v1 - v0) * 3600 / (t1 - t0) / 1000.0)

if len(per) < 2:
    sys.exit('need both arms; found: ' + ', '.join(per) or 'none')

print(f'{"arm":6} {"n":>3} {"median mV/h":>12} {"mean":>9} {"sd":>7}   samples')
stat = {}
for label, xs in sorted(per.items()):
    sd = statistics.pstdev(xs) if len(xs) > 1 else float('nan')
    stat[label] = (statistics.median(xs), statistics.mean(xs), sd, len(xs))
    print(f'{label:6} {len(xs):>3} {statistics.median(xs):>12.2f} {statistics.mean(xs):>9.2f} {sd:>7.2f}   '
          + ' '.join(f'{x:.1f}' for x in xs))

(la, a), (lb, b) = sorted(stat.items())
d = a[0] - b[0]
# pool the WITHIN-arm scatter; pooling across arms would hide the very
# difference being tested inside its own error bar.
within = []
for label, xs in per.items():
    m = statistics.median(xs)
    within += [x - m for x in xs]
pooled = statistics.pstdev(within) if len(within) > 1 else float('nan')
se = pooled * (1 / len(per[la]) + 1 / len(per[lb])) ** 0.5

print()
print(f'{la} median − {lb} median = {d:+.2f} mV/h   ({abs(d)/abs(b[0])*100:.1f}% of {lb})')
print(f'within-arm scatter {pooled:.2f} mV/h → standard error of the difference {se:.2f}')

# ☠️ Guards, both found by feeding this deliberately bad input rather than by
# reading it. With one usable suspend per arm the within-arm scatter is exactly
# zero, and dividing by it crashed. And a scatter that small is not a licence to
# believe a small difference: three suspends per arm is the minimum at which the
# spread means anything at all.
nmin = min(len(per[la]), len(per[lb]))
if nmin < 3:
    print(f'☠️  only {nmin} usable suspend(s) in the smaller arm - no verdict. Need at least 3.')
elif se == 0:
    print('☠️  zero within-arm scatter with n≥3 is not credible - check the samples above.')
elif abs(d) < 2 * se:
    print('☠️  inside 2 standard errors - not a result. More cycles, or the effect is small.')
else:
    print(f'outside 2 standard errors ({abs(d)/se:.1f}σ)')
    if abs(d) < 1.0:
        print('☠️  ...but the difference is under 1 mV/h. This instrument has never')
        print('    reproduced a baseline better than 1.4%, so treat that as the floor')
        print('    of what it can honestly resolve, whatever the arithmetic says.')
print()
print('☠️  A difference of slopes, not a current. And a null here means "no')
print('    fast-acting difference": an effect that needs minutes of quiet to')
print('    appear cannot show up in an alternation this tight.')
