#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Read the IMS-voice-over-PS bit out of a raw DIAG capture.

vops-scan.py wanted a pcap (it was written for QCSuper); diag-log-capture.py
writes raw DIAG log entries. This joins the two: entry framing from
diag-ota-decode.py, IE walk from vops-scan.py.

The bit: TS 24.301 9.9.3.12A "EPS network feature support", IEI 0x64,
octet 3 bit 1 = IMS voice over PS session indicator (0 = NOT supported).

☠️ Walks the optional IEs by their own lengths and requires them to close on
the message boundary. leads/imei-tac-gating.md warns in as many words not to
byte-scan for 0x64: this repo has already published one wrong conclusion from a
scanner that searched too widely and only looked right.

☠️ Prints no NAS bytes. An ATTACH ACCEPT carries a GUTI and the TAI list.
"""
import struct, sys

def entries(path):
    b = open(path, "rb").read()
    i, out = 0, []
    while i + 14 <= len(b):
        if b[i] == 0x10 and i + 4 <= len(b):
            ln, = struct.unpack_from("<H", b, i + 2)
            if 12 <= ln <= 4096 and i + 4 + ln <= len(b):
                ln2, code = struct.unpack_from("<HH", b, i + 4)
                if ln2 == ln:
                    out.append((code, b[i + 16 : i + 4 + ln]))
                    i += 4 + ln
                    continue
        i += 1
    return out

EMM = {0x41: "ATTACH REQUEST", 0x42: "ATTACH ACCEPT", 0x43: "ATTACH COMPLETE",
       0x44: "ATTACH REJECT", 0x45: "DETACH REQUEST", 0x48: "TAU REQUEST",
       0x49: "TAU ACCEPT", 0x4a: "TAU COMPLETE", 0x4b: "TAU REJECT",
       0x4e: "SERVICE REJECT", 0x50: "GUTI REALLOC CMD", 0x52: "AUTH REQUEST",
       0x53: "AUTH RESPONSE", 0x5d: "SECURITY MODE COMMAND",
       0x5e: "SECURITY MODE COMPLETE", 0x62: "EMM INFORMATION"}

def find_nas(p):
    """The log payload has a small header before the NAS PDU whose length is
    not fixed across firmware. Rather than guess it, find the first offset that
    parses as a plain EMM message: low nibble 7 (EPS mobility management),
    security header 0 (plain), and a KNOWN message type. Guessing the header
    length is how a scanner starts finding things that are not there."""
    for off in range(0, min(len(p), 24)):
        if p[off] & 0x0F == 0x07 and (p[off] >> 4) == 0 and off + 1 < len(p):
            if p[off + 1] in EMM:
                return off, p[off + 1]
    return None, None

def walk(m, i):
    """Optional IEs of an ATTACH ACCEPT / TAU ACCEPT, by TS 24.301 8.2.1/8.2.26.

    ☠️ NOT every optional IE is TLV, and treating them as if they were is how
    the first version of this walk failed. 0x13 (Location area identification)
    is a TYPE-3 IE: fixed length, no length octet. Reading its first value
    octet as a length gave L=18, and every offset after it was fiction - the
    walk then overran and the closed=False guard refused a verdict, which is
    the only reason a wrong answer was not published.
    """
    TV = {0x13: 5, 0x53: 1, 0x17: 1, 0x59: 1, 0x5C: 1}   # IEI -> value octets
    ies = {}
    while i < len(m):
        iei = m[i]
        if (iei >> 4) in (0xB, 0xE, 0xF):        # type 1, value in the low nibble
            ies[iei & 0xF0] = bytes([iei & 0x0F])
            i += 1
            continue
        if iei in TV:                            # type 3, fixed length
            n = TV[iei]
            if i + 1 + n > len(m):
                return False, ies
            ies[iei] = m[i + 1 : i + 1 + n]
            i += 1 + n
            continue
        if i + 1 >= len(m):                      # type 4, TLV
            return False, ies
        ln = m[i + 1]
        if i + 2 + ln > len(m):
            return False, ies
        ies[iei] = m[i + 2 : i + 2 + ln]
        i += 2 + ln
    return True, ies

def main():
    src = sys.argv[1]
    seen = {}
    verdicts = []
    for code, p in entries(src):
        if code not in (0xB0EC, 0xB0ED):
            continue
        off, mt = find_nas(p)
        if mt is None:
            seen["<unparsed>"] = seen.get("<unparsed>", 0) + 1
            continue
        name = EMM.get(mt, "0x%02x" % mt)
        seen[name] = seen.get(name, 0) + 1
        if mt not in (0x42, 0x49):
            continue
        m = p[off:]
        # ATTACH ACCEPT:  hdr(2) + EPS attach result(1/2) + T3412(1) + TAI list(LV)
        # TAU ACCEPT:     hdr(2) + EPS update result(1/2)
        # Both then continue with optional IEs; step over the mandatory part by
        # its own encoding rather than by a constant.
        j = 2 + 1                                  # header + the half-octet result
        if mt == 0x42:
            j += 1                                 # T3412
            if j < len(m):
                j += 1 + m[j]                      # TAI list, LV
            # ☠️ The ESM message container is LV-E: its length is TWO octets,
            # big endian (TS 24.301 8.2.1). Reading one made the walk overrun
            # into the middle of the container and it did not close - which the
            # closed=False guard caught instead of letting a verdict out.
            if j + 1 < len(m):
                esm_len = (m[j] << 8) | m[j + 1]
                j += 2 + esm_len
        closed, ies = walk(m, j)
        if 0x64 in ies and ies[0x64]:
            bit = ies[0x64][0] & 0x01
            verdicts.append((name, closed, bit, len(ies)))
        else:
            verdicts.append((name, closed, None, len(ies)))
    print("EMM messages seen:", seen)
    if not verdicts:
        print("no ATTACH ACCEPT / TAU ACCEPT in this capture")
        return
    for name, closed, bit, n in verdicts:
        if bit is None:
            print("  %-14s IEs closed=%s (%d IEs) - NO 0x64 IE" % (name, closed, n))
        else:
            print("  %-14s IEs closed=%s (%d IEs)  IMS voice over PS = %s"
                  % (name, closed, n, "SUPPORTED" if bit else "NOT supported"))
    print()
    print("☠️ A verdict from a walk that did NOT close is not a measurement.")

main()
