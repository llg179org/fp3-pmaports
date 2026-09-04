#!/usr/bin/env python3
"""#142 - inter-stall INTERVALS at a constant probe rate.

Why this exists rather than reusing 142-i2cprobe.py: the 23..726 s interval
spread quoted so far came from a session of HUMAN tapping, whose density varied
with what the operator happened to be doing. Long gaps in that record may simply
be periods with no touch at all, so those numbers describe the operator, not the
fault. At a constant machine rate the gaps mean something.

Two differences from the shared probe:
  * it runs for a WALL-CLOCK duration, not a trial count - a stall costs ~15 s,
    so a fixed trial count silently makes the arms different lengths;
  * it prints each stall's start time at ms resolution and the interval list,
    which is the actual measurement.

usage: 142-intervals.py <platform> <addr-hex> <idle-seconds> <duration-seconds> <label>
"""
import sys, time, fcntl, os, errno, glob

def bus_of(platform):
    for a in glob.glob("/sys/bus/i2c/devices/i2c-*"):
        if platform in os.path.realpath(a):
            return int(os.path.basename(a).split("-")[1])
    raise SystemExit("no i2c bus found for %s - refusing to guess" % platform)

I2C_SLAVE_FORCE = 0x0706
plat, addr = sys.argv[1], int(sys.argv[2], 16)
idle, dur, label = float(sys.argv[3]), float(sys.argv[4]), sys.argv[5]
dev = "/dev/i2c-%d" % bus_of(plat)

print("== ARM %s: %s addr=0x%02x idle=%.2fs for %.0fs  (start %s)"
      % (label, dev, addr, idle, dur, time.strftime("%H:%M:%S")), flush=True)

t_arm = time.monotonic()
stalls, n, durs = [], 0, []
while time.monotonic() - t_arm < dur:
    time.sleep(idle)
    f = os.open(dev, os.O_RDWR)
    try:
        fcntl.ioctl(f, I2C_SLAVE_FORCE, addr)
        t0 = time.monotonic()
        try:
            os.read(f, 1); e = 0
        except OSError as ex:
            e = ex.errno
        d = time.monotonic() - t0
    finally:
        os.close(f)
    n += 1; durs.append(d)
    if d >= 1.0:
        # the stall's START, in seconds since the arm began - that is what the
        # intervals must be computed from, not its end (the 15 s is dead time).
        off = t0 - t_arm
        stalls.append(off)
        print("   %s  stall #%-3d at t+%8.3f s  (trial %d)  held %.3f s  errno %d (%s)"
              % (time.strftime("%H:%M:%S"), len(stalls), off, n, d, e,
                 errno.errorcode.get(e, "ok")), flush=True)

elapsed = time.monotonic() - t_arm
ds = sorted(durs)
print("-- ARM %s done: %d probes in %.0f s (%.2f/s), %d stalls"
      % (label, n, elapsed, n / elapsed, len(stalls)), flush=True)
print("   probe duration  min %.4f  median %.4f  max %.4f s"
      % (ds[0], ds[len(ds) // 2], ds[-1]), flush=True)
if len(stalls) >= 2:
    iv = [round(stalls[i + 1] - stalls[i], 2) for i in range(len(stalls) - 1)]
    s = sorted(iv)
    print("   INTERVALS (%d) %s" % (len(iv), s), flush=True)
    print("   min %.2f   median %.2f   max %.2f s" % (s[0], s[len(s) // 2], s[-1]), flush=True)
elif len(stalls) == 1:
    print("   INTERVALS: only 1 stall - no interval measurable", flush=True)
else:
    # ☠️ say what a null is worth rather than letting it read as "clean"
    print("   INTERVALS: NO stalls in %.0f s of probing at %.2f/s." % (elapsed, n / elapsed), flush=True)
    print("   95%% upper bound on the rate (rule of three): 1 per %.0f s" % (elapsed / 3), flush=True)
