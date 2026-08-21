#!/usr/bin/env python3
# watch TLMM cfg of gpio22/23 + amp liveness; log every transition. Runs until <secs> arg.
import mmap, os, sys, time, fcntl
fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
maps = {}
def cfg(pin):
    a = 0x1000000 + 0x1000*pin
    page = a & ~0xFFF
    if page not in maps:
        maps[page] = mmap.mmap(fd, 0x1000, offset=page)
    m = maps[page]
    return int.from_bytes(m[a-page:a-page+4], "little")
def up():
    return float(open("/proc/uptime").read().split()[0])
dur = float(sys.argv[1]) if len(sys.argv) > 1 else 120
last = None
t0 = up()
while up() - t0 < dur:
    st = (cfg(22), cfg(23), cfg(14), cfg(15))
    if st != last:
        print(f"{up():9.2f} gpio22=0x{st[0]:03x} gpio23=0x{st[1]:03x} gpio14=0x{st[2]:03x} gpio15=0x{st[3]:03x}", flush=True)
        last = st
    time.sleep(0.05)
