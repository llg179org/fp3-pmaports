#!/usr/bin/env python3
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Read de-compare legs and print the median current per leg, with the spread.
# ☠️ Median, not mean: a single current_now read on this device scatters by
# about 138 mA, so one outlier moves a mean and moves nothing else.
import sys, statistics, pathlib

def leg(path):
    cur, head = [], []
    for line in pathlib.Path(path).read_text().splitlines():
        if line.startswith('#'):
            head.append(line)
            continue
        f = line.split()
        if len(f) == 4:
            cur.append(abs(int(f[1])) / 1000.0)
    return head, cur

rows = []
for p in sys.argv[1:]:
    head, cur = leg(p)
    if not cur:
        print(f"{p}: no samples")
        continue
    cur.sort()
    med = statistics.median(cur)
    q1, q3 = cur[len(cur)//4], cur[3*len(cur)//4]
    rows.append((pathlib.Path(p).name, len(cur), med, q1, q3, min(cur), max(cur)))
    for h in head:
        if 'phosh=' in h or 'greetd_session' in h or 'backlight' in h or 'dpms' in h:
            print(f"  {h}")

print()
print(f"{'leg':<34}{'n':>4}{'median mA':>11}{'IQR':>16}{'min-max':>16}")
for name, n, med, q1, q3, lo, hi in rows:
    print(f"{name:<34}{n:>4}{med:>11.1f}{q1:>8.0f}-{q3:<7.0f}{lo:>7.0f}-{hi:<8.0f}")

if len(rows) == 2:
    a, b = rows
    d = b[2] - a[2]
    print()
    print(f"difference: {b[0]} - {a[0]} = {d:+.1f} mA  ({d/a[2]*100:+.1f}%)")
    print("☠️ compare only legs that share a screen state and a brightness.")
