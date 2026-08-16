#!/usr/bin/env python3
"""Read/write aw8898 registers straight on the i2c bus, bypassing the driver's
regmap cache.  The cache is why a cget can report a plausible value for a chip
that is not acknowledging at all, so every number here comes from a real
transfer and a failed transfer is reported as a failure, not as a stale value.

  awpoke.py dump              - read the registers the golden trace covers
  awpoke.py get <reg>         - one register
  awpoke.py set <reg> <val>   - one 16-bit write, then read back
"""
import fcntl, os, sys, time

I2C_SLAVE_FORCE = 0x0706
BUS_GLOB, ADDR = "/sys/bus/i2c/devices", 0x34


def bus_number():
    # the adapter number moves between boots; resolve it from the device name
    for d in sorted(os.listdir(BUS_GLOB)):
        if d.endswith("-0034"):
            return int(d.split("-")[0])
    raise SystemExit("no *-0034 device: the amp is not even instantiated")


def open_bus():
    fd = os.open(f"/dev/i2c-{bus_number()}", os.O_RDWR)
    fcntl.ioctl(fd, I2C_SLAVE_FORCE, ADDR)
    return fd


def rd(fd, reg):
    os.write(fd, bytes([reg]))
    b = os.read(fd, 2)
    return (b[0] << 8) | b[1]


def wr(fd, reg, val):
    os.write(fd, bytes([reg, (val >> 8) & 0xFF, val & 0xFF]))


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "dump"
    fd = open_bus()
    up = open("/proc/uptime").read().split()[0]
    if cmd == "dump":
        ok = fail = 0
        out = []
        for reg in list(range(0x00, 0x11)) + list(range(0x20, 0x24)):
            try:
                out.append(f"reg:0x{reg:02x}=0x{rd(fd, reg):04x}")
                ok += 1
            except OSError as e:
                out.append(f"reg:0x{reg:02x}=ERR({e.errno})")
                fail += 1
        print(f"uptime={up} ok={ok} fail={fail}")
        print(" ".join(out))
        sys.exit(0 if fail == 0 else 1)
    if cmd == "get":
        reg = int(sys.argv[2], 0)
        try:
            print(f"uptime={up} reg:0x{reg:02x}=0x{rd(fd, reg):04x}")
        except OSError as e:
            print(f"uptime={up} reg:0x{reg:02x}=ERR({e.errno})")
            sys.exit(1)
        return
    if cmd == "set":
        reg, val = int(sys.argv[2], 0), int(sys.argv[3], 0)
        try:
            wr(fd, reg, val)
        except OSError as e:
            print(f"uptime={up} write 0x{reg:02x}=0x{val:04x} FAILED errno={e.errno}")
            sys.exit(1)
        time.sleep(0.01)
        try:
            print(f"uptime={up} wrote 0x{reg:02x}=0x{val:04x}, reads back 0x{rd(fd, reg):04x}")
        except OSError as e:
            print(f"uptime={up} wrote 0x{reg:02x} but read back FAILED errno={e.errno}")
            sys.exit(1)
        return
    raise SystemExit(__doc__)


main()
