#!/usr/bin/env python3
"""Gate for the Beeper's pre-emption. Runs the class EXTRACTED FROM THE
DEPLOYED FILE, not a retyped copy."""
import re, sys, time, math, os, queue, struct, subprocess, threading, wave
src = open("/home/fp3/armb/fp3-taptest.py").read()
consts = re.search(r"^TONE_EDGE_HZ.*?^BEEP_ENABLED = True$", src, re.S | re.M).group(0)
rend   = re.search(r"^def _render_tone.*?^    return path$", src, re.S | re.M).group(0)
which  = re.search(r"^def _which.*?^    return None$", src, re.S | re.M).group(0)
# ☠️ Anchor on the NEXT top-level definition, not on a line of the body. The
# first version ended the class at the first 12-space "return False", which is
# the guard on fire()'s very first line - so fire() was extracted truncated,
# queued nothing, and the gate reported "pre-emption does not work" while
# testing nothing at all. A stand-in that is not the thing.
klass  = re.search(r"^class Beeper:.*?(?=^\S)", src, re.S | re.M).group(0)
_need = ("def fire", "put_nowait", "terminate", "def _run")
_missing = [k for k in _need if k not in klass]
if _missing:
    print("EXTRACTION INCOMPLETE, missing:", _missing); sys.exit(2)
print("extracted Beeper: %d lines, %d chars" % (klass.count(chr(10)), len(klass)))
ns = dict(math=math, os=os, queue=queue, struct=struct, subprocess=subprocess,
          threading=threading, time=time, wave=wave)
exec(compile(consts + "\n" + rend + "\n" + which + "\n" + klass, "beeper", "exec"), ns)
log = lambda m: print("   log:", m.strip())
os.makedirs("/tmp/gate", exist_ok=True)
b = ns["Beeper"](log, dirpath="/tmp/gate")
if not b.ok:
    print("BEEPER NOT OK"); sys.exit(1)
time.sleep(1.2)                      # let the primer finish

def run(label, seq):
    p0, d0, c0 = b.played, b.dropped, b.cut
    t0 = time.time()
    for name, gap_after in seq:
        b.fire(name, 0.0)
        time.sleep(gap_after)
    time.sleep(1.0)
    print("  %-34s played +%d  dropped +%d  CUT +%d  wall %.2f s"
          % (label, b.played - p0, b.dropped - d0, b.cut - c0, time.time() - t0))

print("\nKNOWN NEGATIVE - one tone alone must NOT be cut:")
run("single miss (150 ms)", [("miss", 0.0)])
print("\nKNOWN POSITIVE - three tones 50 ms apart, newest must win:")
run("edge -> miss -> over, 50 ms apart", [("edge", 0.05), ("miss", 0.05), ("over", 0.0)])
print("\nThe real case: MISS then OVER 47 ms later (the measured pair):")
run("miss -> over, 47 ms apart", [("miss", 0.047), ("over", 0.0)])
