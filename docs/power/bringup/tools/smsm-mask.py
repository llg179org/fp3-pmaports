#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
"""Read the SMSM state vector and the per-remote subscription masks from SMEM.

    smsm-mask.py            (RUNS ON THE DEVICE, needs root)

WHY
===
The AP can tell the remotes it is awake by setting a bit in its own SMSM entry -
bit 12, SMSM_PROC_AWAKE downstream. mainline never sets it (see
leads/smsm-proc-awake.md).  Before spending a measurement window on a patch that
sets it, there is a cheaper question:

    DOES THE MODEM EVEN ASK TO BE TOLD?

`notify_other_smsm()` in the vendor kernel wakes a remote only for the bits that
remote SUBSCRIBED to, and the subscriptions live in shared memory next to the
state itself.  So bit 12 of the modem's mask over the APPS entry answers it:

    set   -> this firmware wants to hear about the AP's awake flag
    clear -> the bit cannot wake it, and the whole lead is dead for free

☠️ THIS IS A PASSIVE READ.  It maps shared memory and touches no register, no
QMI, no radio.  It is safe to run inside an undisturbed measurement window - the
only cost is the ssh login itself.

LAYOUT
======
mainline drivers/soc/qcom/smem.c and smsm.c:

    SMEM base on msm8953    0x86300000, 1 MiB (device tree `smem@86300000`)
    struct smem_header      proc_comm[4] (64B) + version[32] (128B)
                            + initialized/free_offset/available/reserved (16B)
                            = 0xD0, then toc[512] of 16 bytes each
    struct smem_global_entry  allocated, offset, size, aux_base

    item  85  SMEM_SMSM_SHARED_STATE     num_entries u32 states
    item 333  SMEM_SMSM_CPU_INTR_MASK    num_entries * num_hosts u32 masks
    item 419  SMEM_SMSM_SIZE_INFO        {num_entries, num_hosts}

☠️ Version 12 (SMEM_GLOBAL_PART_VERSION) moves item lookup into a partition and
this walk would read nonsense.  The version word is checked and printed, and the
script REFUSES rather than guessing.
"""
import mmap
import os
import struct
import sys

SMEM_BASE = 0x86300000
SMEM_LEN = 0x100000
TOC_OFF = 0xD0
TOC_ENTRY = 16
VERSION_OFF = 0x40
SBL_VERSION_INDEX = 7
GLOBAL_PART_VERSION = 12

SHARED_STATE = 85
CPU_INTR_MASK = 333
SIZE_INFO = 419

DEFAULT_ENTRIES = 8
DEFAULT_HOSTS = 3

# SMSM entry/host indices, from the downstream smsm.h ordering
NAMES = {0: "APPS", 1: "MODEM", 2: "Q6/ADSP", 3: "WCNSS", 4: "DSPS", 5: "RPM"}
PROC_AWAKE = 12


def main():
    try:
        fd = os.open("/dev/mem", os.O_RDONLY | getattr(os, "O_SYNC", 0))
    except PermissionError:
        print("need root", file=sys.stderr)
        return 1
    m = mmap.mmap(fd, SMEM_LEN, mmap.MAP_SHARED, mmap.PROT_READ, offset=SMEM_BASE)

    def u32(off):
        return struct.unpack_from("<I", m, off)[0]

    version = u32(VERSION_OFF + SBL_VERSION_INDEX * 4) >> 16
    print("SMEM master SBL version: %u" % version)
    if version >= GLOBAL_PART_VERSION:
        print("☠️ version %u uses the global partition; this legacy TOC walk would "
              "read nonsense. Refusing." % version, file=sys.stderr)
        return 2

    def item(n):
        """(offset, size) of SMEM item n, or None if not allocated."""
        base = TOC_OFF + n * TOC_ENTRY
        allocated, off, size, _aux = struct.unpack_from("<IIII", m, base)
        if not allocated or off == 0 or size == 0 or off + size > SMEM_LEN:
            return None
        return off, size

    si = item(SIZE_INFO)
    if si:
        num_entries, num_hosts = struct.unpack_from("<II", m, si[0])
        print("size info: num_entries=%u num_hosts=%u" % (num_entries, num_hosts))
    else:
        num_entries, num_hosts = DEFAULT_ENTRIES, DEFAULT_HOSTS
        print("size info absent; using defaults num_entries=%u num_hosts=%u"
              % (num_entries, num_hosts))

    st = item(SHARED_STATE)
    if not st:
        print("SMSM shared state not allocated", file=sys.stderr)
        return 3
    print("\nstate vector (one entry per host, the value that host publishes):")
    for i in range(num_entries):
        v = u32(st[0] + i * 4)
        flag = " <- PROC_AWAKE(12) SET" if v & (1 << PROC_AWAKE) else ""
        print("  entry %u %-8s = 0x%08x%s" % (i, NAMES.get(i, "?"), v, flag))

    im = item(CPU_INTR_MASK)
    if not im:
        print("\nSMSM interrupt mask not allocated", file=sys.stderr)
        return 4
    print("\nsubscription masks: mask[entry][host] = bits of <entry> that <host>"
          " wants to be interrupted for")
    hdr = "".join("%12s" % NAMES.get(h, str(h)) for h in range(num_hosts))
    print("  %-12s%s" % ("entry \\ host", hdr))
    for e in range(num_entries):
        row = ""
        for h in range(num_hosts):
            row += "  0x%08x" % u32(im[0] + (e * num_hosts + h) * 4)
        print("  %-12s%s" % (NAMES.get(e, str(e)), row))

    print("\n== THE ANSWER ==")
    for h in range(num_hosts):
        mask = u32(im[0] + (0 * num_hosts + h) * 4)   # entry 0 = APPS
        got = bool(mask & (1 << PROC_AWAKE))
        print("  %-8s subscribes to bit 12 of the APPS entry: %s"
              % (NAMES.get(h, str(h)), "YES" if got else "no"))
    print("\n☠️ A 'no' from MODEM kills leads/smsm-proc-awake.md without spending "
          "a measurement window. A 'YES' does not prove the firmware acts on it - "
          "it proves only that it asked to be told.")
    m.close()
    os.close(fd)
    return 0


if __name__ == "__main__":
    sys.exit(main())
