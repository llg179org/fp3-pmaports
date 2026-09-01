#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Read a modem-night.sh run and put the modem's duty NEXT TO what reached it.
#
#   modem-night-fit.py <modem-night-DIR>
#
# One row per round: which suspend path, how long it actually slept, what woke
# it, each RPM master's awake share, and the QMI census split by direction. The
# whole point is the correlation - a duty number on its own has been available
# for days and has not named anything.
#
# ☠️ A ZERO XO DELTA IS AMBIGUOUS and this is where it bites hardest. The RPM
# updates `XO total duration` on EXIT from XO shutdown, so a master that stays
# down for the whole round contributes zero and reads as "awake 100%" unless the
# shutdown COUNT is consulted too. Measured 2026-08-31; it produced a ★★★★★
# finding that was exactly backwards. Here: delta 0 AND count unchanged = asleep
# throughout; delta 0 AND count moved = genuinely awake.
import os
import re
from datetime import datetime
import sys

TICK = 19.2e6
MASTERS = ("APSS", "MPSS", "LPASS", "PRONTO")


def masters(path):
    """{phase: {master: (xo_total, xo_shutdowns)}} plus the header fields."""
    out, meta, phase = {}, {}, None
    for line in open(path, errors="ignore"):
        if line.startswith("=== BEFORE"):
            phase = "BEFORE"; out[phase] = {}; continue
        if line.startswith("=== AFTER"):
            phase = "AFTER"; out[phase] = {}; continue
        m = re.match(r"#\s*round=(\d+)\s+path=(\w+)\s+t=(\S+ \S+)\s+cap=(\d+)%\s+v=(\d+)uV", line)
        if m:
            meta.update(round=int(m.group(1)), path=m.group(2), t=m.group(3),
                        cap=int(m.group(4)), v=int(m.group(5)))
        elif re.match(r"#\s*round=", line):
            # Older captures carry no t= field. Keep reading them rather than
            # dropping the round: the elapsed column simply stays blank.
            m2 = re.match(r"#\s*round=(\d+)\s+path=(\w+).*cap=(\d+)%\s+v=(\d+)uV", line)
            if m2:
                meta.update(round=int(m2.group(1)), path=m2.group(2),
                            cap=int(m2.group(3)), v=int(m2.group(4)))
        m = re.match(r"#\s*after: cap=(\d+)%\s+v=(\d+)uV", line)
        if m:
            meta.update(cap_after=int(m.group(1)), v_after=int(m.group(2)))
        m = re.match(r"#\s*wakeup_irq=(\S+)", line)
        if m:
            meta["irq"] = m.group(1)
        # ☠️ The network is a named covariate, not a constant: band, cell and
        # RSRP are all assigned by it and all survive every device-side arm.
        # Captures written before 2026-09-01 carry no `# radio:` line at all;
        # the columns then read `-`, which is the honest answer for them. Two
        # lines are emitted per round and the LAST one wins, because the radio
        # state a round ENDED in is the one that priced it.
        m = re.match(r"#\s*radio: (.*)", line)
        if m:
            kv = dict(p.split("=", 1) for p in m.group(1).split() if "=" in p)
            first = meta.get("radio_first")
            meta["radio"] = kv
            if first is None:
                meta["radio_first"] = dict(kv)
        m = re.match(r"(\w+)\s+xo_total=(\d+)\s+xo_shutdowns=(\d+)", line)
        if m and phase:
            out[phase][m.group(1)] = (int(m.group(2)), int(m.group(3)))
    return out, meta


def census(path):
    """(slept_s, {REQ/RSP/IND: n}, [top service lines])"""
    slept, kinds, svc, irq = None, {"REQ": 0, "RSP": 0, "IND": 0}, [], None
    if not os.path.exists(path):
        return slept, kinds, svc, True, irq
    nowindow = False
    for line in open(path, errors="ignore"):
        m = re.search(r"round \d+: slept (\S+)s", line)
        if m and m.group(1) != "?":
            slept = float(m.group(1))
        # ☠️ Take the waking IRQ from the census, because only there does it carry
        # its NAME. The numbers are assigned in probe order and move between
        # boots - captures written on 2026-08-30 read IRQ 72 as "the RTC" while
        # on that evening's boot 72 was a camss interrupt.
        m = re.search(r"pm_wakeup_irq=(\d+) \(([^)]*)\)", line)
        if m:
            irq = f"{m.group(1)}:{m.group(2)}"
        if "SLEEP-HOOK MARKERS DID NOT FIRE" in line:
            nowindow = True
        m = re.match(r"\s+(\d+)\s+src_port=(\S+)\s+(REQ|RSP|IND)\s+msg=(\d+)\s+(.*)", line)
        if m:
            n, port, kind, msg, name = int(m.group(1)), m.group(2), m.group(3), m.group(4), m.group(5).strip()
            kinds[kind] += n
            svc.append((n, port, kind, msg, name))
    svc.sort(reverse=True)
    return slept, kinds, svc, nowindow, irq


def radio_cells(meta):
    """(band/chan, cell, rsrp) for the table. `-` for a capture that predates the
    columns. A `\u2620\ufe0f` prefix means that field CHANGED across the sleep: the round
    priced two radio configurations and belongs in neither average."""
    r = meta.get("radio")
    if not r:
        return "-", "-", "-"
    f = meta.get("radio_first") or {}

    def cell(key, shown):
        mark = "\u2620\ufe0f" if f.get(key) and f[key] != r.get(key) else ""
        return mark + shown

    band = cell("band", f"{r.get('band','?')}/{r.get('chan','?')}")
    return band, cell("cell", r.get("cell") or "?"), r.get("rsrp") or "?"


def main(root):
    rounds = sorted(d for d in os.listdir(root) if d.startswith("round-"))
    if not rounds:
        print(f"no round-* directories under {root}"); return 2
    # ☠️ The elapsed column exists because the duty turned out to be a function
    # of how long the phone had been up, not of any configuration. A ladder is
    # unreadable without it, and every round already carries its wall clock.
    t0 = None
    for d in rounds:
        _, mt = masters(os.path.join(root, d, "masters.txt"))
        if mt.get("t"):
            t0 = datetime.strptime(mt["t"], "%Y-%m-%d %H:%M:%S"); break
    print(f"{'rnd':>4} {'t_h':>6} {'path':<8} {'slept':>6} {'waking irq':>18} "
          f"{'MPSS':>7} {'LPASS':>7} {'PRONTO':>7} {'REQ':>5} {'RSP':>5} {'IND':>5}  {'v_uV':>8}"
          f"  {'band':>11} {'cell':>10} {'rsrp':>6}")
    agg = {}
    for d in rounds:
        ms, meta = masters(os.path.join(root, d, "masters.txt"))
        slept, kinds, svc, nowin, irq = census(os.path.join(root, d, "qmi.log"))
        w = slept if slept else None
        cells = {}
        for m in MASTERS:
            b, a = ms.get("BEFORE", {}).get(m), ms.get("AFTER", {}).get(m)
            if not b or not a or not w:
                cells[m] = "  —  "; continue
            dt, dc = a[0] - b[0], a[1] - b[1]
            if dt == 0:
                cells[m] = "asleep" if dc == 0 else " 100.0"
            else:
                awake = 100 * (1 - (dt / TICK) / w)
                # ☠️ A delta implying MORE XO-off time than the window itself is a
                # contradiction, not a small number: the counter reset, the round
                # boundaries are wrong, or the sleep length was misread. Printing
                # it as a negative percentage makes a broken round look like a
                # very good one, so say so and keep it out of every average.
                cells[m] = f"{awake:6.1f}" if -2 <= awake <= 102 else "☠️IMPOS"
        p = meta.get("path", "?")
        qmi = (f"{kinds['REQ']:>5} {kinds['RSP']:>5} {kinds['IND']:>5}" if not nowin
               else f"{'?':>5} {'?':>5} {'?':>5}")
        th = "     ?"
        if t0 and meta.get("t"):
            th = f"{(datetime.strptime(meta['t'], '%Y-%m-%d %H:%M:%S') - t0).total_seconds()/3600:6.2f}"
        print(f"{meta.get('round','?'):>4} {th:>6} {p:<8} {slept if slept else '?':>6} "
              f"{(irq or meta.get('irq','?')):>18} {cells['MPSS']:>7} {cells['LPASS']:>7} "
              f"{cells['PRONTO']:>7} {qmi}"
              f"  {meta.get('v_after', meta.get('v','?')):>8}"
              f"  %11s %10s %6s" % radio_cells(meta)
              + ("   \u2620\ufe0f no sleep window" if nowin else ""))
        a = agg.setdefault(p, {"n": 0, "slept": 0.0, "REQ": 0, "RSP": 0, "IND": 0,
                               "duty": [], "nowin": 0})
        a["n"] += 1
        if slept:
            a["slept"] += slept
        # ☠️ A round whose sleep window never opened has UNKNOWN traffic, not zero
        # traffic. Adding its zeros to the totals is how an unmeasured round makes
        # the night look quiet - the exact shape of "a clean log proves nothing
        # until the channel is shown to report that event class at all".
        if nowin:
            a["nowin"] += 1
        else:
            for k in ("REQ", "RSP", "IND"):
                a[k] += kinds[k]
        try:
            a["duty"].append(float(cells["MPSS"]))
        except ValueError:
            pass

    print("\n=== the internal A/B: the two suspend paths, same night, same cell")
    for p, a in sorted(agg.items()):
        duty = f"{sum(a['duty'])/len(a['duty']):.1f}%" if a["duty"] else "—"
        mean = f"{a['slept']/a['n']:.0f}s" if a["n"] else "—"
        print(f"  {p:<8} rounds={a['n']:<4} mean sleep={mean:<8} "
              f"mean MPSS awake={duty:<8} (n={len(a['duty'])})  "
              f"QMI REQ={a['REQ']} RSP={a['RSP']} IND={a['IND']}"
              + (f"   ☠️ {a['nowin']} round(s) had NO sleep window and are excluded"
                 if a["nowin"] else ""))
    print("\n☠️ Read the difference between the two rows as the sleep handshake's share,")
    print("   and a round with a HIGH MPSS duty and ZERO QMI as evidence for candidate (c):")
    print("   the modem is not being kept awake by anyone, it simply does not go down.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]) if len(sys.argv) > 1 else print(__doc__) or 2)
