#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# THE NIGHT'S CHARGE BUDGET: does the outer OCV pair agree with the sum of its
# segments? Written BEFORE the data arrived, against the predictions in
# captures/2026-09-02_night-replication/PREREGISTERED.md.
#
# ☠️ THE WHOLE-NIGHT AVERAGE IS NOT A COMPARATOR. It is one side of a balance.
# The night is a MIXTURE - three reboots, two rests, three legs with 90 s alarms -
# so comparing its mean against an earlier IDLE ladder would be exactly the "two
# numbers measured two different ways" mistake this project retracted four times
# in one week. The only honest comparisons are:
#   * whole-night dQ(OCV pair)  vs  the sum of the segments  -> closes or not
#   * a LEG mean                vs  an earlier cheap-state leg  -> same instrument
# and never the night's mean against anything.
#
# ☠️ AND THE OUTER PAIR MAY NOT BRACKET A PURE DISCHARGE. night-run.sh restores
# the USB input before every reboot, on purpose: the suspend bit lives in the PMIC
# and would survive the warm reboot, bringing the phone back silently unable to
# charge. So on three segments the input is ON. If the cable is physically
# connected, the pack CHARGES there, the night's dQ is consumption MINUS charge,
# and no voltage reading can separate them. This script decides which happened
# from the charger status the run records at every step - it does not assume.
#
#   night-budget.py <night-log-dir>
import re
import sys

# Pack curve, 2026-08-28 discharge to shutdown: 2185 mAh over 17.94 h.
# ☠️ USE IT FOR LOCAL SLOPE (mAh/mV), NEVER FOR ABSOLUTE SoC. Every point of it
# sits ~16 mV below the true OCV because it was taken UNDER a ~110 mA load
# (R~0.15 ohm); that offset cancels in a difference and does not cancel in an
# absolute assignment.
PACK_MAH = 2185.0
PACK_HOURS = 17.94
PACK_MEAN_MA = PACK_MAH / PACK_HOURS          # 121.8 - the MEAN, because the mAh
# ☠️ axis is an INTEGRAL. The published bound used 110, which is the discharge's
# MEDIAN (108). That made the bound 1.57d where the correct scale gives 1.49d - so
# the published number was conservative rather than wrong, and it is corrected
# here rather than quietly kept.

PRED = {                                       # the pre-registered bands
    'leg_ma': (35.0, 46.0), 'leg_spread_ma': 5.0,
    'rest_ma': (25.0, 35.0), 'boot_ma': (150.0, 350.0),
    'dq_mah': (270.0, 330.0), 'closure_pct': 10.0,
}


def parse(path):
    """Read run.log into (segments, ocv_marks, charger_states)."""
    txt = open(path).read()
    segs, ocv, chg = [], [], []
    for line in txt.splitlines():
        m = re.match(r'(\S+ \S+) \[\+(\d+)s (\w+)\] (.*)', line)
        if not m:
            continue
        wall, up, boot, rest = m.group(1), int(m.group(2)), m.group(3), m.group(4)
        if rest.startswith('OCV '):
            ocv.append((wall, up, boot, rest))
        if rest.startswith('battery '):
            b = re.match(r'battery (\d+)% (\d+)uV (\S+)', rest)
            if b:
                chg.append((wall, up, boot, int(b.group(1)), int(b.group(2)), b.group(3)))
        if rest.startswith('--- leg') or rest.startswith('=== step') or 'NIGHT COMPLETE' in rest:
            segs.append((wall, up, boot, rest))
    return segs, ocv, chg


def main(d):
    segs, ocv, chg = parse(f'{d}/run.log')
    print(f'pack curve: {PACK_MAH:.0f} mAh / {PACK_HOURS:.2f} h = {PACK_MEAN_MA:.1f} mA mean')
    print()

    # ☠️ THE FIRST QUESTION IS NOT A NUMBER. Before any budget, decide whether the
    # night was a discharge at all.
    # ☠️ THIS DETECTOR MUST NOT OVER-CLAIM, and the first version did. The run
    # records the charger status at the TOP of each step - BEFORE the OCV routine
    # suspends the input - so a "Charging" there is expected by design and says
    # nothing about whether current flowed during a segment. Worse, the status
    # reads "Charging" whenever the input is merely ENABLED, cable or no cable.
    # So the log can rule the charging case IN as possible; it cannot rule it OUT,
    # and it cannot measure it. Report exactly that.
    active = [c for c in chg if c[5] not in ('Discharging', 'Unknown', 'Not charging')]
    print('== charger status at every step boundary (read BEFORE the OCV suspends it)')
    for c in chg:
        print(f'   {c[0]}  [+{c[1]}s {c[2]}]  {c[3]}%  {c[4]/1e6:.3f} V  {c[5]}')
    print()
    if active:
        print('☠️ THE INPUT WAS ENABLED AT ' + str(len(active)) + ' STEP BOUNDARIES.')
        print('   That is BY DESIGN - night-run.sh restores it before every reboot, because')
        print('   the suspend bit lives in the PMIC and would survive the warm reboot. What')
        print('   this log CANNOT tell you is whether current actually flowed, i.e. whether')
        print('   the cable was connected: the status reads "Charging" for an enabled input')
        print('   either way.')
        print('   ⇒ DECIDE IT FROM THE VOLTAGE INSTEAD: if capacity or voltage RISES across')
        print('     any reboot boundary, the pack took charge and the whole-night OCV bound')
        print('     is NOT available - the night is consumption MINUS charge and no voltage')
        print('     reading separates them. Say so; do not rescale the bound.')
        rises = [(a, b) for a, b in zip(chg, chg[1:]) if b[4] > a[4] + 5000]
        if rises:
            print(f'   ☠️☠️ {len(rises)} boundary/boundaries where the voltage ROSE by >5 mV:')
            for a, b in rises:
                print(f'        {a[0]} {a[4]/1e6:.3f} V  ->  {b[0]} {b[4]/1e6:.3f} V')
            print('        The whole-night bound is off the table. The per-leg means and')
            print('        their boot-to-boot spread survive - that is still the main result.')
        else:
            print('   ✅ no boundary shows a voltage rise: consistent with no charge taken,')
            print('      so the whole-night budget below is worth closing.')
    else:
        print('   the input was never enabled at a boundary - the night is a clean discharge.')
    print()

    print('== OCV marks')
    for o in ocv:
        print(f'   {o[0]}  [+{o[1]}s {o[2]}]  {o[3]}')
    print()
    print('== segment timeline')
    for s in segs:
        print(f'   {s[0]}  [+{s[1]}s {s[2]}]  {s[3]}')
    print()
    print('☠️ PRE-REGISTERED BANDS (captures/2026-09-02_night-replication/PREREGISTERED.md):')
    for k, v in PRED.items():
        print(f'   {k}: {v}')
    print('   Closure threshold: the two sides agree within '
          f"{PRED['closure_pct']:.0f} %. Do not loosen this after seeing the numbers.")


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '.')
