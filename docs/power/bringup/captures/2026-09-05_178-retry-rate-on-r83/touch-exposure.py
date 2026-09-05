#!/usr/bin/env python3
"""Read an fp3-touch-sample TSV and report EXPOSURE, not interrupt count.

☠️ Why this exists. check 59 gates a clean result on ">= 500 touch interrupts
this boot", and that gate is too weak: on 2026-09-05 an r83 boot logged 2002
interrupts over 104 minutes and passed it, while 2000 of them fell inside a
single four-minute burst and the panel was untouched for the other 100. The
#142 fault is per first-access-after-idle, so a phone nobody touches has almost
no vulnerable moments and a clean log measures the operator's absence.

What counts is ACTIVE TIME - sampling intervals in which the interrupt counter
actually moved - and it is the only number this prints as the denominator.

☠️ Rows are grouped by boot_id first. /proc/interrupts resets at boot, so a
delta taken across a reboot is negative nonsense; that happened on the first
run of this analysis and the boot_id column is what caught it.
"""
import sys, collections, datetime

rows = [l.split() for l in open(sys.argv[1]) if l.strip()]
rows = [r for r in rows if len(r) >= 6]
by = collections.defaultdict(list)
for r in rows:
    by[r[-1]].append(r)

for bid, rs in by.items():
    rs.sort(key=lambda r: int(r[0]))
    span = int(rs[-1][0]) - int(rs[0][0])
    active = 0
    prev = None
    for r in rs:
        t, i = int(r[0]), int(r[1])
        if prev and t > prev[0] and i > prev[1]:
            active += t - prev[0]
        prev = (t, i)
    m = lambda c: max(int(r[c]) for r in rs)
    print(f"boot {bid[:8]}  {datetime.datetime.fromtimestamp(int(rs[0][0])):%H:%M}"
          f"-{datetime.datetime.fromtimestamp(int(rs[-1][0])):%H:%M}"
          f"  wall {span/60:6.0f} min   ACTIVE {active/60:6.0f} min"
          f"   irqs {int(rs[-1][1])-int(rs[0][1]):6d}")
    print(f"    -110={m(2)}  -6={m(3)}  -5={m(4)}"
          + (f"   qup: timeout={m(5)} cleared={m(6)} held={m(7)}" if len(rs[0]) >= 8 else ""))
    # what a clean run of this length is worth, from check 59's arithmetic
    if m(2) == 0 and m(4) == 0:
        if active < 36 * 60:
            print(f"    ☠️ {active/60:.0f} min active is BELOW the ~36 min floor "
                  f"(r82 stalls were up to 726 s apart). This says nothing.")
        elif active < 100 * 60:
            print(f"    clean, but only rules out 'worse than r82'.")
        else:
            print(f"    clean over {active/60:.0f} min active - by the rule of three, "
                  f"~{3/(active/200):.0f}x better than the r82 rate.")
