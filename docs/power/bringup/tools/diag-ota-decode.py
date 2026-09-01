#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
"""Decode the LTE RRC OTA stream a diag capture recorded — WHICH channel, not just how many.

    diag-ota-decode.py raw/diag.bin [raw/diag-ims-off.bin ...]

☠️ THE CHANNEL ENUM IS NOT TAKEN ON FAITH. `pdu_num` is a firmware-version
dependent enum, and this repo has been burned by decoding half-known structures.
So the tool prints the raw histogram first and the names second, and the names
are only trustworthy because a behavioural cross-check confirms them: the
dedicated-channel codes must collapse between the IMS-on and IMS-off captures
(the ESM loop rode them), while the paging code must stay put. Run it on both
files in one go and read that comparison, not the labels.

Framing, established by hexdump against this capture set:
    98 01 00 00 01 00 00 00     8-byte rpmsg/diag prefix
    10 <more> <len16>           DIAG_LOG_F
    <len16> <code16> <ts64>     the log entry itself
    ...payload... <crc16> 7e
The 0xB0C0 payload fields were fitted against known covariates and all three
agreed: PCI 109 = the serving cell ID mmcli reported, EARFCN 6200 = the band the
window recorded, and msg_len exactly consuming the remaining bytes.
"""
import struct, sys, collections

# 3GPP TS 24.301 §9.8 - ESM message identities, the ones this loop uses.
ESM = {0xC1: "ACTIVATE DEFAULT EPS BEARER CTX REQUEST",
       0xC2: "ACTIVATE DEFAULT EPS BEARER CTX ACCEPT",
       0xCD: "DEACTIVATE EPS BEARER CTX REQUEST",
       0xCE: "DEACTIVATE EPS BEARER CTX ACCEPT",
       0xD0: "PDN CONNECTIVITY REQUEST",
       0xD2: "PDN DISCONNECT REQUEST"}
# ESM log codes. 0xB0E1 carries ciphered NAS (its message-type byte is random),
# so it is counted and never decoded.
ESM_CODES = {0xB0E2: "ESM in", 0xB0E3: "ESM out"}

CH = {1: "BCCH_BCH", 2: "BCCH_DL_SCH", 3: "MCCH", 4: "PCCH(paging)",
      5: "DL_CCCH", 6: "DL_DCCH", 7: "UL_CCCH", 8: "UL_DCCH"}

def entries(path):
    b = open(path, "rb").read()
    i, out = 0, []
    while i + 14 <= len(b):
        if b[i] == 0x10 and i + 4 <= len(b):
            ln, = struct.unpack_from("<H", b, i + 2)
            if 12 <= ln <= 4096 and i + 4 + ln <= len(b):
                ln2, code = struct.unpack_from("<HH", b, i + 4)
                ts, = struct.unpack_from("<Q", b, i + 8)
                if ln2 == ln:
                    out.append((code, ts, b[i + 16 : i + 4 + ln]))
                    i += 4 + ln
                    continue
        i += 1
    return out

def rrc(p):
    if len(p) < 21:
        return None
    ver, rel = p[0], p[1]
    pci,  = struct.unpack_from("<H", p, 4)
    earf, = struct.unpack_from("<I", p, 6)
    sfn,  = struct.unpack_from("<H", p, 10)
    pdu   = p[12]
    mlen, = struct.unpack_from("<H", p, 17)
    return dict(ver=ver, rel=rel, pci=pci, earfcn=earf, sfn=sfn >> 4,
                subfn=sfn & 0xF, pdu=pdu, mlen=mlen, body=p[19:19 + mlen])

for path in sys.argv[1:]:
    es = entries(path)
    codes = collections.Counter(c for c, _, _ in es)
    print("== %s: %d log entries" % (path, len(es)))
    for c, n in codes.most_common():
        print("   code 0x%04X  %5d" % (c, n))
    ch = collections.Counter()
    cov = collections.Counter()
    for c, _, p in es:
        if c != 0xB0C0:
            continue
        d = rrc(p)
        if not d:
            continue
        ch[d["pdu"]] += 1
        cov[(d["pci"], d["earfcn"], d["ver"])] += 1
    if ch:
        print("   -- 0xB0C0 by pdu_num (raw value first, name is the unverified enum)")
        for k, n in sorted(ch.items()):
            print("      pdu_num=%-3d %5d   %s" % (k, n, CH.get(k, "?")))
        print("   -- covariates seen (pci, earfcn, hdr_ver): %s" % dict(cov))
    # ESM payload: 4-byte log header, then the NAS PDU - pd/ebi, pti, msg type.
    esm = collections.Counter()
    for c, _, p in es:
        if c in ESM_CODES and len(p) > 6:
            esm[(ESM_CODES[c], p[6])] += 1
    if esm:
        print("   -- ESM message identities (TS 24.301 9.8)")
        for (d, t), n in sorted(esm.items(), key=lambda x: -x[1]):
            print("      %-8s 0x%02X %5d   %s" % (d, t, n, ESM.get(t, "?")))
