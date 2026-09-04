#!/usr/bin/env python3
"""#142 automated stall probe - no finger required.

The -110 arises when a transaction on the touchscreen's i2c bus hangs. A
transaction can be issued from userspace, so the fault can be sampled at machine
rate instead of one trial per human tap.

The probe reads one byte from an address with NO device on it. That makes the
two outcomes unmistakable BY DURATION, so the result does not depend on trusting
an errno:

    healthy    -> the address NACKs, ~1 ms, errno ENXIO (-6)
    hung       -> the QUP xfer_timeout expires, ~15 s, errno ETIMEDOUT (-110)

Sweeping the idle time before each probe tests the standing hypothesis: the
controller autosuspends after 1 s, and the suspect is the first transaction
after a runtime resume.

    idle < 1 s  -> controller never suspends -> should never hang
    idle > 1 s  -> every probe forces a resume

☠️ What it does NOT test: this exercises the CONTROLLER and the bus, not the
touch chip's own state machine. If the hang originates inside the hx83112b
rather than in the QUP controller, an unused-address probe will not reproduce it
and a clean run does not exonerate the touch path. Read a null here as "the
controller resume path is clean", never as "the bug is gone".

usage: 142-i2cprobe.py <bus> <addr-hex> <idle-seconds> <trials>
"""
import sys, time, fcntl, os, errno

I2C_SLAVE_FORCE = 0x0706
bus, addr, idle, n = int(sys.argv[1]), int(sys.argv[2], 16), float(sys.argv[3]), int(sys.argv[4])
dev = "/dev/i2c-%d" % bus
print("probe: %s addr=0x%02x idle=%.1fs trials=%d  (started %s)"
      % (dev, addr, idle, n, time.strftime("%H:%M:%S")), flush=True)

slow, results = 0, []
for i in range(n):
    time.sleep(idle)
    f = os.open(dev, os.O_RDWR)
    try:
        fcntl.ioctl(f, I2C_SLAVE_FORCE, addr)
        t0 = time.monotonic()
        try:
            os.read(f, 1)
            e = 0
        except OSError as ex:
            e = ex.errno
        d = time.monotonic() - t0
    finally:
        os.close(f)
    results.append((d, e))
    if d >= 1.0:
        slow += 1
        print("  %s  trial %4d  %8.3f s  errno %d (%s)   <<< SLOW"
              % (time.strftime("%H:%M:%S"), i, d, e, errno.errorcode.get(e, "ok")), flush=True)

ds = sorted(d for d, _ in results)
codes = {}
for _, e in results:
    codes[errno.errorcode.get(e, "ok")] = codes.get(errno.errorcode.get(e, "ok"), 0) + 1
print("\nsummary: %d trials, idle %.1fs" % (n, idle))
print("  duration  min %.4f  median %.4f  max %.4f s" % (ds[0], ds[len(ds)//2], ds[-1]))
print("  errno     %s" % codes)
print("  >= 1 s    %d of %d  (%.1f %%)" % (slow, n, 100.0*slow/n))
