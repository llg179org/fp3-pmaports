#!/usr/bin/env python3
# read/write one 32-bit MMIO register via /dev/mem: pmem.py <addr> [value]
import mmap, os, sys
addr = int(sys.argv[1], 0)
page = addr & ~0xFFF
off = addr - page
fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
m = mmap.mmap(fd, 0x1000, offset=page)
def rd():
    return int.from_bytes(m[off:off+4], "little")
print(f"0x{addr:08x} = 0x{rd():08x}")
if len(sys.argv) > 2:
    val = int(sys.argv[2], 0)
    m[off:off+4] = val.to_bytes(4, "little")
    print(f"wrote 0x{val:08x}, reads back 0x{rd():08x}")
