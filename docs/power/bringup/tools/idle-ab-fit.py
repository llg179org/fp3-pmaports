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
    return dict(path=path, os=os_name, kernel=kernel, window=window,
                full=full_uah, t=t, i=i, v=v, cc=cc)


def report(d):
    i, t, v, cc = d["i"], d["t"], d["v"], d["cc"]
    if not i:
        print(f"{d['path']}: no samples")
        return
    p10 = sorted(i)[max(0, len(i) // 10 - 1)]
    print(f"== {d['path']}")
    print(f"   os={d['os']} kernel={d['kernel']} n={len(i)} span={t[-1] - t[0]}s "
          f"v {v[0]:.3f} -> {v[-1]:.3f} V")
    print(f"   current_now  floor(p10) {p10:6.1f} mA   median {st.median(i):6.1f} mA"
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
    withfloor = [(d, sorted(d["i"])[max(0, len(d["i"]) // 10 - 1)]) for d in ds if d["i"]]
    if len(withfloor) > 1:
        print("\n-- gap (floor to floor) --")
        base = withfloor[0]
        for d, f in withfloor[1:]:
            print(f"   {d['os']} {f:.1f} mA  vs  {base[0]['os']} {base[1]:.1f} mA"
                  f"   -> {f - base[1]:+.1f} mA")
    return 0


if __name__ == "__main__":
    sys.exit(main())
