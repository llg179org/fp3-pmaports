#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, Laszlo Gergely.
#
# Read (and optionally set) the Qualcomm A/B boot-control attribute bits that
# live in the GPT partition entries of the boot device.
#
# Why this exists: on this eMMC device `qbootctl -s <slot>` aborts in its UFS
# bLun step, and the `-i` flag its own help advertises is not implemented in the
# packaged build (0.2.2-r1) -- getopt answers "unrecognized option: i". The
# attribute write is the whole mechanism on eMMC, so it is done here instead.
#
# The bit layout is Qualcomm's, NOT the generic AOSP one:
#     48..49  priority        50  active        51..53  tries remaining
#     54      successful      55  unbootable
# ☠️ It is not taken on faith: `dump` prints the raw 64-bit attribute of every
# slotted partition, and the currently-inactive slot must differ from the active
# one exactly in the bits this layout calls active/priority. If it does not,
# stop -- the layout is wrong and writing would brick the slot table.
import struct, sys, zlib

DEV = "/dev/mmcblk0"
LBA = 512
PRIORITY_SHIFT, PRIORITY_MASK = 48, 0x3 << 48
ACTIVE_BIT = 1 << 50
RETRY_SHIFT, RETRY_MASK = 51, 0x7 << 51
SUCCESSFUL_BIT = 1 << 54
UNBOOTABLE_BIT = 1 << 55


def read_header(f, lba):
    f.seek(lba * LBA)
    hdr = f.read(LBA)
    sig, rev, hsize, hcrc, _res = struct.unpack_from("<8sIIII", hdr, 0)
    if sig != b"EFI PART":
        raise SystemExit(f"no GPT signature at LBA {lba}")
    (my_lba, alt_lba, first_usable, last_usable) = struct.unpack_from("<QQQQ", hdr, 24)
    entries_lba, num_entries, entry_size, entries_crc = struct.unpack_from("<QIII", hdr, 72)
    return dict(raw=hdr, hsize=hsize, my_lba=my_lba, alt_lba=alt_lba,
                entries_lba=entries_lba, num=num_entries, esize=entry_size,
                ecrc=entries_crc)


def read_entries(f, h):
    f.seek(h["entries_lba"] * LBA)
    return bytearray(f.read(h["num"] * h["esize"]))


def parts(h, ents):
    out = []
    for i in range(h["num"]):
        e = ents[i * h["esize"]:(i + 1) * h["esize"]]
        if e[0:16] == b"\0" * 16:
            continue
        attr = struct.unpack_from("<Q", e, 48)[0]
        name = e[56:128].decode("utf-16-le").rstrip("\0")
        out.append((i, name, attr))
    return out


def describe(attr):
    return (f"raw=0x{attr:016x} prio={(attr & PRIORITY_MASK) >> PRIORITY_SHIFT} "
            f"active={1 if attr & ACTIVE_BIT else 0} "
            f"tries={(attr & RETRY_MASK) >> RETRY_SHIFT} "
            f"ok={1 if attr & SUCCESSFUL_BIT else 0} "
            f"unbootable={1 if attr & UNBOOTABLE_BIT else 0}")


def dump(f):
    h = read_header(f, 1)
    ents = read_entries(f, h)
    print(f"# GPT: {h['num']} entries of {h['esize']} B at LBA {h['entries_lba']}, "
          f"alt header LBA {h['alt_lba']}")
    slotted = [(i, n, a) for i, n, a in parts(h, ents) if n.endswith("_a") or n.endswith("_b")]
    for i, n, a in slotted:
        print(f"  [{i:3d}] {n:16s} {describe(a)}")
    # ☠️ The self-check: the two slots must differ, or the layout is not this one.
    by = {}
    for i, n, a in slotted:
        by.setdefault(n[:-2], {})[n[-1]] = a
    diffs = {k: v["a"] ^ v["b"] for k, v in by.items() if "a" in v and "b" in v}
    union = 0
    for d in diffs.values():
        union |= d
    print(f"# XOR of a-vs-b attributes across all slotted pairs: 0x{union:016x}")
    print(f"#   priority bits differ:   {bool(union & PRIORITY_MASK)}")
    print(f"#   active bit differs:     {bool(union & ACTIVE_BIT)}")
    print(f"#   tries bits differ:      {bool(union & RETRY_MASK)}")
    print(f"#   successful bit differs: {bool(union & SUCCESSFUL_BIT)}")
    if union & ~(PRIORITY_MASK | ACTIVE_BIT | RETRY_MASK | SUCCESSFUL_BIT | UNBOOTABLE_BIT):
        print("# ☠️ bits outside the assumed layout differ - DO NOT WRITE")


def set_active_only(f, target):
    """Flip ONLY bit 50 (active), the one bit that actually differs between the
    two slots on this device.

    ☠️ Deliberately narrower than a bootctl HAL's set_active, which would also
    rewrite priority, tries, successful and unbootable. On this phone `modem_a`
    reads unbootable=1 prio=0 tries=0 while every other _a partition reads
    prio=3 tries=7 ok=1 -- a leftover we did not create and whose reason is
    unknown. A full set_active would silently clear it. Reproducing the observed
    difference and nothing else keeps the change reversible and keeps us from
    inventing state we cannot justify.
    """
    h = read_header(f, 1)
    ents = read_entries(f, h)
    changed = []
    for i in range(h["num"]):
        off = i * h["esize"]
        e = ents[off:off + h["esize"]]
        if e[0:16] == b"\0" * 16:
            continue
        name = e[56:128].decode("utf-16-le").rstrip("\0")
        if not (name.endswith("_a") or name.endswith("_b")):
            continue
        attr = struct.unpack_from("<Q", e, 48)[0]
        new = attr | ACTIVE_BIT if name.endswith("_" + target) else attr & ~ACTIVE_BIT
        if new != attr:
            struct.pack_into("<Q", ents, off + 48, new)
            changed.append((name, attr, new))
    if not changed:
        print("# nothing to change")
        return
    for n, a, b in changed:
        print(f"  {n:16s} 0x{a:016x} -> 0x{b:016x}")
    write_back(f, h, ents)


def backup(f, path):
    """Both GPT copies to a file, so any mistake here is undoable."""
    h = read_header(f, 1)
    with open(path, "wb") as o:
        f.seek(0); o.write(f.read(34 * LBA))
        f.seek(h["alt_lba"] * LBA - 32 * LBA); o.write(f.read(33 * LBA))
    print(f"# backed up primary (LBA 0-33) and backup (LBA {h['alt_lba']-32}-{h['alt_lba']}) to {path}")


def write_back(f, h, ents):
    ecrc = zlib.crc32(bytes(ents)) & 0xFFFFFFFF
    for lba in (1, h["alt_lba"]):
        hh = read_header(f, lba)
        raw = bytearray(hh["raw"])
        struct.pack_into("<I", raw, 88, ecrc)
        struct.pack_into("<I", raw, 16, 0)
        crc = zlib.crc32(bytes(raw[:hh["hsize"]])) & 0xFFFFFFFF
        struct.pack_into("<I", raw, 16, crc)
        f.seek(hh["entries_lba"] * LBA)
        f.write(bytes(ents))
        f.seek(lba * LBA)
        f.write(bytes(raw[:LBA]))
        print(f"# wrote entries at LBA {hh['entries_lba']} and header at LBA {lba} "
              f"(entries crc 0x{ecrc:08x}, header crc 0x{crc:08x})")
    f.flush()


def set_slot(f, target):
    other = "b" if target == "a" else "a"
    h = read_header(f, 1)
    ents = read_entries(f, h)
    changed = []
    for i in range(h["num"]):
        off = i * h["esize"]
        e = ents[off:off + h["esize"]]
        if e[0:16] == b"\0" * 16:
            continue
        name = e[56:128].decode("utf-16-le").rstrip("\0")
        if not (name.endswith("_a") or name.endswith("_b")):
            continue
        attr = struct.unpack_from("<Q", e, 48)[0]
        new = attr
        if name.endswith("_" + target):
            new = (new & ~PRIORITY_MASK) | (0x3 << PRIORITY_SHIFT)
            new |= ACTIVE_BIT
            new = (new & ~RETRY_MASK) | (0x7 << RETRY_SHIFT)
            new &= ~UNBOOTABLE_BIT
            new |= SUCCESSFUL_BIT
        else:
            new = (new & ~PRIORITY_MASK) | (0x1 << PRIORITY_SHIFT)
            new &= ~ACTIVE_BIT
        if new != attr:
            struct.pack_into("<Q", ents, off + 48, new)
            changed.append((name, attr, new))
    if not changed:
        print("# nothing to change")
        return
    for n, a, b in changed:
        print(f"  {n:16s} 0x{a:016x} -> 0x{b:016x}")

    ecrc = zlib.crc32(bytes(ents)) & 0xFFFFFFFF
    # Primary header at LBA 1, backup where it says.
    for lba in (1, h["alt_lba"]):
        hh = read_header(f, lba)
        raw = bytearray(hh["raw"])
        struct.pack_into("<I", raw, 88, ecrc)
        struct.pack_into("<I", raw, 16, 0)             # zero CRC before computing
        crc = zlib.crc32(bytes(raw[:hh["hsize"]])) & 0xFFFFFFFF
        struct.pack_into("<I", raw, 16, crc)
        f.seek(hh["entries_lba"] * LBA)
        f.write(bytes(ents))
        f.seek(lba * LBA)
        f.write(bytes(raw[:LBA]))
        print(f"# wrote entries at LBA {hh['entries_lba']} and header at LBA {lba} "
              f"(entries crc 0x{ecrc:08x}, header crc 0x{crc:08x})")
    f.flush()


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "dump"
    if mode == "dump":
        with open(DEV, "rb") as f:
            dump(f)
    elif mode == "backup":
        with open(DEV, "rb") as f:
            backup(f, sys.argv[2])
    elif mode == "active":
        tgt = sys.argv[2]
        assert tgt in ("a", "b")
        with open(DEV, "r+b") as f:
            set_active_only(f, tgt)
            import os
            os.fsync(f.fileno())
        with open(DEV, "rb") as f:
            dump(f)
    elif mode == "set":
        tgt = sys.argv[2]
        assert tgt in ("a", "b")
        with open(DEV, "r+b") as f:
            set_slot(f, tgt)
            import os
            os.fsync(f.fileno())
        with open(DEV, "rb") as f:
            dump(f)
    else:
        raise SystemExit("usage: gptattr.py [dump | backup FILE | active a|b | set a|b]")
