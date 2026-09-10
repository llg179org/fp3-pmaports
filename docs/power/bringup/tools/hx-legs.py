#!/usr/bin/env python3
"""hx-legs.py ANCHOR_HHMMSS  NAME:START:END [NAME:START:END ...]
Per-leg tap statistics from taptest.log + kernel-contacts.log.
☠️ Both logs carry HH:MM:SS only and accumulate across days, so a plain time
window matches yesterday too (measured 2026-09-11: "leg 2" came back with 15406
contacts and a 132 s maximum). ANCHOR is the time of TODAY's taptest restart
("evdev watch: open" / "started on"); only lines after the LAST such line count.
"""
import re, statistics, sys
anchor=sys.argv[1]; legs=[a.split(":",1) for a in sys.argv[2:]]
def today(path, pred):
    lines=open(path,errors="replace").read().splitlines()
    idx=[i for i,l in enumerate(lines) if pred(l)]
    return lines[idx[-1]:] if idx else []
# taptest: its own restart line carries only HH:MM:SS; kernel-contacts writes a
# DATED "== kernel-contacts start YYYY-MM-DD HH:MM:SS" line - anchor on that.
tt=today("/home/fp3/taptest.log", lambda l: l.startswith(anchor[:5]) and "evdev watch: open" in l)
kc=today("/var/log/kernel-contacts.log", lambda l: l.startswith("== kernel-contacts start") and (" "+anchor[:5]) in l)
print(f"today: taptest {len(tt)} lines, kcontacts {len(kc)} lines (anchor {anchor})")
for name,win in legs:
    a,b=win.split(":")[0]+":"+win.split(":")[1]+":"+win.split(":")[2], ":".join(win.split(":")[3:])
    T=[l for l in tt if a<=l[:8]<b]; K=[l for l in kc if a<=l[:8]<b and "RELEASE" in l]
    s="\n".join(T); taps=len(re.findall(r"  (o|\.)  #",s)); no=len(re.findall(r"explained=NO",s)); ov=len(re.findall(r"OVERLAP #",s))
    durs=[int(m) for l in K for m in re.findall(r"dur (\d+)ms",l)]; lg=[d for d in durs if d>=100]
    print(f"{name:22s} {a}-{b}: taps {taps:4d} unexplained {no:2d} ({100*no/max(taps,1):.2f}%) overlaps {ov:2d} | contacts {len(durs):4d} median {statistics.median(durs) if durs else 0:.0f}ms >=100ms {len(lg)} ({100*len(lg)/max(len(durs),1):.1f}%) max {max(durs) if durs else 0}")
