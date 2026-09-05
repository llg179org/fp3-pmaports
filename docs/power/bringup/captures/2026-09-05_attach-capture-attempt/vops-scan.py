#!/usr/bin/env python3
"""Read the IMS-voice-over-PS bit the network sends this UE.

    vops-scan.py <capture.pcap>

Finds EPS ATTACH ACCEPT (EMM 0x42) and TAU ACCEPT (EMM 0x49) in the GSMTAP
LTE-NAS packets QCSuper writes, walks the mandatory part by its own field
lengths, then walks the optional IEs by IEI and length, and REQUIRES the walk to
close exactly on the message boundary. A message whose walk does not close is
reported as such and never contributes a finding.

The bit: TS 24.301 9.9.3.12A, "EPS network feature support", IEI 0x64,
octet 3 bit 1 = IMS voice over PS session indicator (0 = not supported).
"""
import sys, struct

GSMTAP_LTE_NAS = 0x12

def pcap_packets(fn):
    b = open(fn,'rb').read()
    if len(b) < 24: return
    magic = b[:4]
    if magic in (b'\xd4\xc3\xb2\xa1', b'\x4d\x3c\xb2\xa1'): end = '<'
    elif magic in (b'\xa1\xb2\xc3\xd4', b'\xa1\xb2\x3c\x4d'): end = '>'
    else: raise SystemExit("not a pcap: %r" % magic)
    linktype = struct.unpack(end+'I', b[20:24])[0]
    off = 24
    while off + 16 <= len(b):
        _, _, caplen, _ = struct.unpack(end+'IIII', b[off:off+16])
        off += 16
        yield linktype, b[off:off+caplen]
        off += caplen

def nas_from(linktype, pkt):
    # strip link layer -> IP -> UDP -> GSMTAP
    p = pkt
    if linktype == 1:      p = p[14:]
    elif linktype == 101:  pass          # raw IP
    elif linktype == 113:  p = p[16:]    # linux cooked
    if len(p) < 20 or (p[0] >> 4) != 4: return None
    ihl = (p[0] & 0xF) * 4
    if p[9] != 17: return None           # UDP
    u = p[ihl:]
    if len(u) < 8: return None
    if struct.unpack('>H', u[2:4])[0] != 4729: return None
    g = u[8:]
    if len(g) < 16: return None
    hdr_words = g[1]
    if g[2] != GSMTAP_LTE_NAS: return None
    return g[hdr_words*4:]

def walk_optional(m, i, out):
    """Walk TLV/TV optional IEs from offset i. Returns (closed, ies)."""
    ies = {}
    while i < len(m):
        iei = m[i]
        if iei & 0xF0 and iei not in (0x50,):  # type-length-value
            pass
        # every optional IE we care about is TLV: IEI, length, value
        if i + 1 >= len(m): return False, ies
        ln = m[i+1]
        if i + 2 + ln > len(m): return False, ies
        ies.setdefault(iei, []).append(m[i+2:i+2+ln])
        i += 2 + ln
    return i == len(m), ies

def main():
    fn = sys.argv[1]
    total = nas = accepts = 0
    for linktype, pkt in pcap_packets(fn):
        n = nas_from(linktype, pkt)
        total += 1
        if not n or len(n) < 2: continue
        nas += 1
        pd, mt = n[0] & 0x0F, n[1]
        if pd != 0x07 or mt not in (0x42, 0x49): continue
        accepts += 1
        name = "ATTACH ACCEPT" if mt == 0x42 else "TAU ACCEPT"
        print(f"\n== {name} (EMM 0x{mt:02x}), {len(n)} bytes")
        i = 2
        if mt == 0x42:
            i += 1                       # EPS attach result (+spare half octet)
            i += 1                       # T3412
            ln = n[i]; i += 1 + ln       # TAI list, LV
            if i + 2 > len(n): print("   walk failed: truncated before ESM container"); continue
            ln = struct.unpack('>H', n[i:i+2])[0]; i += 2 + ln   # ESM container, LV-E
        else:
            i += 1                       # EPS update result (+spare)
        closed, ies = walk_optional(n, i, {})
        print(f"   optional-IE walk closed on the message boundary: {closed}")
        if not closed:
            print("   -> DISCARDED: a walk that does not close proves nothing")
            continue
        v = ies.get(0x64)
        if not v:
            print("   EPS network feature support (0x64): ABSENT")
            print("   -> the network sent no IMS-voice indication in this message")
        else:
            for val in v:
                b0 = val[0]
                print(f"   EPS network feature support (0x64) = {val.hex(' ')}")
                print(f"      IMS voice over PS session indicator = {b0 & 0x01}"
                      f"   ({'SUPPORTED' if b0 & 0x01 else 'NOT supported'})")
                print(f"      EMC BS = {(b0>>1)&1}, EPC-LCS = {(b0>>3)&1}, CS-LCS = {(b0>>4)&3}")
    print(f"\n-- {total} packets, {nas} LTE-NAS, {accepts} attach/TAU accepts")
    if accepts == 0:
        print("-- NO ACCEPT IN THIS CAPTURE: nothing is concluded from it")

main()
