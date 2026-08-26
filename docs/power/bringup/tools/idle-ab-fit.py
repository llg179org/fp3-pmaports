#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Fable 5) under the direction of Lajosházi, László Gergely.
#
# Read one or more idle-ab.sh outputs and print the comparison.
#
# ☠️ It reports the FLOOR (p10) and the median of current_now, never the mean:
# the distribution on this device is a quiet floor with bursts, one read scatters
# by ±138 mA, and a mean is dragged by the bursts in a way that answers a
# different question ("what did it cost over this window" rather than "what does
# it cost to sit here"). Where a coulomb counter is present its integrated value
# is printed beside them, because that IS the over-the-window answer, and the two
# disagreeing is information rather than an error.
#
#   idle-ab-fit.py <file> [file ...]
import sys
import statistics as st


def read(path):
    os_name, kernel, window, full_uah = "?", "?", None, None
    t, i, v, cc = [], [], [], []
    lit = []          # sample times at which the panel was NOT off
    for line in open(path):
        line = line.rstrip("\n")
        if line.startswith("#"):
            if line.startswith("# idle-ab "):
                for tok in line.split():
                    if tok.startswith("os="):
                        os_name = tok[3:]
                    if tok.startswith("window="):
                        window = tok[7:]
            elif line.startswith("# kernel="):
                kernel = line[len("# kernel="):].split()[0]
            elif "full_uAh=" in line:
                try:
                    full_uah = int(line.split("full_uAh=")[1].split()[0])
                except ValueError:
                    pass
            continue
        f = line.split()
        if len(f) < 3:
            continue
        try:
            t.append(int(f[0]))
            i.append(-int(f[1]) / 1000.0)   # discharge is negative; report positive mA
            v.append(int(f[2]) / 1e6)
        except ValueError:
            continue
        if len(f) > 3 and f[3] != "-":
            cc.append((int(f[0]), int(f[3])))
        # ☠️ The panel token, carried in every sample since 2026-08-26. Before
        # that the panel was proven dark once, at the door, and a window it
        # relit inside was indistinguishable from the phone drawing more - on
        # the very question this comparison exists to answer. A file without
        # the column is an OLD run, which is not the same as a clean one.
        if len(f) > 4:
            tok = f[4]
            if "ppo=1" in tok or "=enabled" in tok:
                lit.append(int(f[0]))
    return dict(path=path, os=os_name, kernel=kernel, window=window,
                full=full_uah, t=t, i=i, v=v, cc=cc, lit=lit,
                has_panel_col=any(len(l.split()) > 4 for l in open(path)
                                  if l[:1].isdigit()))


def report(d):
    i, t, v, cc = d["i"], d["t"], d["v"], d["cc"]
    if not i:
        print(f"{d['path']}: no samples")
        return
    p10 = sorted(i)[max(0, len(i) // 10 - 1)]
    print(f"== {d['path']}")
    if d["lit"]:
        print(f"   ☠️ INVALID: the panel was ON for {len(d['lit'])} of {len(i)} samples"
              f" (first at t={d['lit'][0]}s). A lit panel was worth +24.5 mA on every")
        print("      floor measured before 2026-08-19. Do not quote a number from this run.")
    elif not d["has_panel_col"]:
        print("   ☠️ no panel column: this predates 2026-08-26, so the panel was proven")
        print("      dark once at the door and never rechecked. Absence of evidence.")
    print(f"   os={d['os']} kernel={d['kernel']} n={len(i)} span={t[-1] - t[0]}s "
          f"v {v[0]:.3f} -> {v[-1]:.3f} V")
    # ☠️ An invalidated run keeps its numbers, but not in a shape anyone can
    # lift out of context. Several retracted figures in this investigation got
    # their second life from being printed in the same format as a good one.
    tag = "NOT QUOTABLE " if d["lit"] else "current_now  "
    print(f"   {tag}floor(p10) {p10:6.1f} mA   median {st.median(i):6.1f} mA"
          f"   (mean {sum(i) / len(i):6.1f}, reported only to show the burst pull)")
    if cc and d["full"]:
        dt = cc[-1][0] - cc[0][0]
        dq = (cc[0][1] - cc[-1][1]) / 10000.0 * d["full"] / 1000.0   # mAh
        if dt:
            print(f"   cc_soc       integrated {dq * 3600 / dt:6.1f} mA over {dt}s "
                  f"(d={cc[0][1] - cc[-1][1]} counts = {dq:.2f} mAh)")
    elif cc:
        print("   cc_soc present but charge_full was not recorded - rerun with the header intact")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    ds = [read(p) for p in sys.argv[1:]]
    for d in ds:
        report(d)
    # ☠️ Only clean runs enter the gap line. A comparison is exactly as good as
    # its worse half, and quietly averaging an invalidated run into it is how a
    # retracted number gets a second life.
    withfloor = [(d, sorted(d["i"])[max(0, len(d["i"]) // 10 - 1)])
                 for d in ds if d["i"] and not d["lit"]]
    dropped = [d for d in ds if d["i"] and d["lit"]]
    for d in dropped:
        print(f"\n-- {d['os']} ({d['path']}) excluded from the gap: panel was on --")
    if len(withfloor) > 1:
        print("\n-- gap (floor to floor) --")
        base = withfloor[0]
        for d, f in withfloor[1:]:
            print(f"   {d['os']} {f:.1f} mA  vs  {base[0]['os']} {base[1]:.1f} mA"
                  f"   -> {f - base[1]:+.1f} mA")
    return 0


if __name__ == "__main__":
    sys.exit(main())
