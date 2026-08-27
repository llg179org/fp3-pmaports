#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Summarise a night-ladder run: how much the pack actually gave up over the whole
# ladder, in every unit the two systems have in common.
#
# ☠️ WHY THIS EXISTS SEPARATELY FROM idle-ab-fit.py. That tool answers "what does
# it cost to sit here" per window (floor and median). This one answers "what did
# the night cost", which is a different question and needs a different treatment
# of the gaps between rungs - the pack CHARGES for the ~20 s between two rungs,
# so summing the rungs is right and differencing the endpoints is not.
#
# ☠️ THE ASYMMETRY THIS IS BUILT AROUND. The oracle (4.9 downstream) exports
# /sys/class/power_supply/bms/cc_soc, a raw coulomb count; pmOS mainline exports
# no cc_soc and reports full_uAh=?. So the ONLY quantity both sides measure is
# current_now, sampled ~5 s apart, and trapezoidal integration of it is the common
# language. ☠️ On the UT side, where both exist, they disagree by a factor of two
# - and in the direction that rules out "the sampling misses bursts", because too
# few samples under-count. Measured 2026-08-26: integrated 1030.6 mAh against a
# coulomb 501.2 mAh over the same eight hours. Whatever the cause, a pmOS mAh
# figure from this tool is "integrated current, uncorrected" and is NOT
# comparable to a UT coulomb number; compare integrated to integrated.
#
#   ladder-summary.py <rung file> [...]        (files of one run, in rung order)
import sys, re

def load(path):
    hdr, rows = {}, []
    cols = None
    for ln in open(path):
        if ln.startswith("# t_s"):
            cols = ln[2:].split()
            continue
        if ln.startswith("#"):
            m = re.search(r"\bos=(\w+)", ln)
            if m: hdr["os"] = m.group(1)
            m = re.search(r"capacity=(\d+)", ln)
            if m and "cap0" not in hdr: hdr["cap0"] = int(m.group(1))
            continue
        f = ln.split()
        if not f or not f[0].lstrip("-").isdigit() or cols is None: continue
        r = dict(zip(cols, f))
        rows.append(r)
    return hdr, cols, rows

def summarise(path):
    hdr, cols, rows = load(path)
    if len(rows) < 2: return None
    t = [int(r["t_s"]) for r in rows]
    i = [abs(int(r["current_uA"])) / 1000.0 for r in rows]      # mA, sign is direction
    v = [int(r["voltage_uV"]) / 1e6 for r in rows]
    # trapezoid over the actual sample times: sampling is nominally 5 s but drifts
    mAs = sum((i[k] + i[k+1]) / 2 * (t[k+1] - t[k]) for k in range(len(t)-1))
    # ☠️ current_now is CURRENT, not power, and the two ladders did not run over
    # the same part of the pack: pmOS spanned 4.150 -> 3.708 V against UT's
    # 4.262 -> 3.967 V. At a lower pack voltage the SAME power draws MORE current,
    # so comparing mA to mA hands pmOS a penalty it did not earn. Integrate I*V
    # too and compare energy, which is the quantity that does not care where on
    # the discharge curve it was measured.
    mWs = sum((i[k]*v[k] + i[k+1]*v[k+1]) / 2 * (t[k+1] - t[k]) for k in range(len(t)-1))
    span = t[-1] - t[0]
    out = {"os": hdr.get("os", "?"), "n": len(rows), "span": span,
           "v0": v[0], "v1": v[-1], "mAh_i": mAs / 3600.0, "mean_i": mAs / span,
           "mWh": mWs / 3600.0, "mean_p": mWs / span}
    if "cc_soc" in cols:
        cc = [r["cc_soc"] for r in rows if r["cc_soc"] != "-"]
        if len(cc) >= 2:
            out["cc0"], out["cc1"] = int(cc[0]), int(cc[-1])
            out["cc_d"] = out["cc0"] - out["cc1"]
    return out

FULL_MAH = 3060.0	# 10000 cc_soc counts, from idle-ab-fit's own full_uAh on UT

runs = [(p, summarise(p)) for p in sys.argv[1:]]
runs = [(p, s) for p, s in runs if s]
if not runs: sys.exit("no usable rung files")

os_ = runs[0][1]["os"]
print(f"== {os_}: {len(runs)} rungs")
print("  rung   span     v start -> end      integrated I        power   cc_soc delta")
tot_mAh = tot_span = tot_cc = tot_mWh = 0
have_cc = False
for n, (p, s) in enumerate(runs, 1):
    cc = ""
    if "cc_d" in s:
        have_cc = True; tot_cc += s["cc_d"]
        cc = f"   {s['cc_d']:4d} counts = {s['cc_d']*FULL_MAH/10000:6.1f} mAh"
    print(f"  {n:>4}  {s['span']:5d}s   {s['v0']:.3f} -> {s['v1']:.3f} V   "
          f"{s['mAh_i']:6.1f} mAh ({s['mean_i']:5.1f} mA)  {s['mean_p']:5.1f} mW{cc}")
    tot_mAh += s["mAh_i"]; tot_span += s["span"]; tot_mWh += s["mWh"]

h = tot_span / 3600.0
print(f"\n  -- over {h:.2f} measured hours --")
print(f"  voltage      {runs[0][1]['v0']:.3f} -> {runs[-1][1]['v1']:.3f} V "
      f"= {(runs[0][1]['v0']-runs[-1][1]['v1'])*1000:.0f} mV "
      f"({(runs[0][1]['v0']-runs[-1][1]['v1'])*1000/h:.1f} mV/h)")
print(f"  energy       {tot_mWh:.0f} mWh = {tot_mWh/h:.1f} mW mean  "
      f"<- compare THIS across the two systems, not mA")
print(f"  integrated I {tot_mAh:.1f} mAh  = {tot_mAh/h:.1f} mA mean "
      f"= {tot_mAh/FULL_MAH*100:.1f} % of a {FULL_MAH:.0f} mAh pack "
      f"({tot_mAh/FULL_MAH*100/h:.2f} %/h)")
if have_cc:
    cc_mAh = tot_cc * FULL_MAH / 10000
    print(f"  coulomb      {tot_cc} counts = {cc_mAh:.1f} mAh = {cc_mAh/h:.1f} mA mean "
          f"= {tot_cc/100:.1f} % ({tot_cc/100/h:.2f} %/h)")
    print(f"  ☠️ integrated / coulomb = {tot_mAh/cc_mAh:.3f}")
    print("     This is NOT a sampling shortfall - too few samples would UNDER-count,")
    print("     not double. The likeliest reading is that THE SAMPLING ITSELF WAKES")
    print("     THE PHONE: every ~5 s a sysfs read brings it up, so current_now")
    print("     measures the awake-and-idle draw while the coulomb counter integrates")
    print("     in hardware, sleep included. ☠️ Do NOT carry this ratio over to pmOS")
    print("     to 'correct' its integrated figure: the ratio is a property of how")
    print("     often that system wakes, which is the very thing under comparison.")
else:
    print("  coulomb      NOT AVAILABLE on this system (no cc_soc, full_uAh=?) —"
          " the integrated figure above is uncorrected")
