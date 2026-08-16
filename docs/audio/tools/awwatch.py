#!/usr/bin/env python3
"""Watch the aw8898 across the window in which it stops acknowledging.

The death is anchored to boot at roughly 25 s, which is earlier than sshd, so
this has to run on the device.  Two modes make an A/B pair on identical boots:

  control - poll only, and record the uptime of the last successful read
  pdn     - the same, but first put the amplifier back into power-down
            (SYSCTRL bit 0 = 1), which is the state the vendor kernel leaves it
            in while idle.  Ours leaves it ACTIVE with no I2S clock.

Reads go straight to the bus, never through the driver's cached regmap.
"""
import fcntl, os, sys, time

I2C_SLAVE_FORCE, ADDR, SYSCTRL = 0x0706, 0x34, 0x04
mode = sys.argv[1] if len(sys.argv) > 1 else "control"
log = open(f"/var/log/awwatch-{mode}.log", "w", buffering=1)


def up():
    return float(open("/proc/uptime").read().split()[0])


def say(msg):
    log.write(f"{up():8.2f} {msg}\n")


def bus():
    for d in sorted(os.listdir("/sys/bus/i2c/devices")):
        if d.endswith("-0034"):
            return int(d.split("-")[0])
    return None


say(f"mode={mode} start")
n = bus()
while n is None and up() < 60:
    time.sleep(0.2)
    n = bus()
if n is None:
    say("the amp was never instantiated - nothing to watch")
    raise SystemExit(1)
say(f"amp on i2c-{n}")

fd = os.open(f"/dev/i2c-{n}", os.O_RDWR)
fcntl.ioctl(fd, I2C_SLAVE_FORCE, ADDR)


def rd(reg):
    os.write(fd, bytes([reg]))
    b = os.read(fd, 2)
    return (b[0] << 8) | b[1]


# What each arm writes into SYSCTRL, or None to only watch.  0x0045 is the
# value the vendor kernel sits at while idle: charge pump ACTIVE (bit 1 = 0)
# and I2S enabled (bit 6), where ours idles at 0x0007 with both powered down.
ARMS = {"control": None, "pdn": 0x0007, "vendor": 0x0045, "cp": None}

target = ARMS.get(mode, None)
if mode == "cp":
    try:
        target = rd(SYSCTRL) & ~0x0002          # clear CP_PDN only
    except OSError as e:
        say(f"could not read SYSCTRL to clear CP_PDN: errno={e.errno}")
if target is not None:
    try:
        v = rd(SYSCTRL)
        os.write(fd, bytes([SYSCTRL, (target >> 8) & 0xFF, target & 0xFF]))
        back = rd(SYSCTRL)
        say(f"SYSCTRL 0x{v:04x} -> wrote 0x{target:04x}, reads 0x{back:04x}")
    except OSError as e:
        say(f"could not write SYSCTRL: errno={e.errno}")

last_ok, deaths, alive = None, 0, True
while up() < 150:
    try:
        v = rd(SYSCTRL)
        c = rd(0x00)
        if not alive:
            say(f"ALIVE AGAIN chipid=0x{c:04x} sysctrl=0x{v:04x}")
            alive = True
        last_ok = up()
    except OSError as e:
        if alive:
            deaths += 1
            say(f"DIED errno={e.errno} (last good read at {last_ok})")
            alive = False
    time.sleep(0.25)

say(f"end: alive={alive} last_ok={last_ok} death_transitions={deaths}")
