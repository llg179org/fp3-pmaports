#!/usr/bin/env python3
# Raw reader for the RPM sleep-stats records in message RAM (msm8953).
# Mirrors mainline drivers/soc/qcom/qcom_stats.c "qcom,rpm-stats":
#   phys base 0x290000; u32 at +0x14 & 0xFFFF = dynamic offset of records;
#   2 records of: u32 stat_type(FourCC) u32 count u64 last_entered
#                 u64 last_exited u64 accumulated, then 0x10 appended
#                 (u32 client_votes + 3 reserved).
# mmap-based so it works where read(2) on /dev/mem EFAULTs.
import mmap, os, struct, sys

BASE = 0x290000
PAGE = 4096

fd = os.open("/dev/mem", os.O_RDONLY | getattr(os, "O_SYNC", 0))
m = mmap.mmap(fd, 0x10000, mmap.MAP_SHARED, mmap.PROT_READ, offset=BASE)

def u32(off): return struct.unpack_from("<I", m, off)[0]
def u64(off): return struct.unpack_from("<Q", m, off)[0]

dyn = u32(0x14)
off = dyn & 0xFFFF
print("word@+0x14 = 0x%08x -> records offset 0x%x" % (dyn, off))
for i in range(2):
    r = off + i * 0x30
    t = u32(r)
    name = struct.pack("<I", t).decode("ascii", "replace")
    print("record %d @0x%x: type=0x%08x (%r) count=%u last_entered=%u "
          "last_exited=%u accumulated=%u client_votes=0x%x"
          % (i, r, t, name, u32(r+4), u64(r+8), u64(r+0x10), u64(r+0x18),
             u32(r+0x20)))
m.close(); os.close(fd)
