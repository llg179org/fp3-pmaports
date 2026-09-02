#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Does this network provision VoLTE for this SIM? Read it out of a capture we
# already have, rather than measuring anything new.
#
# The IMS-PDN loop's ACTIVATE DEFAULT EPS BEARER CONTEXT ACCEPT (0xC2) carries a
# Protocol Configuration Options IE, and inside it the network returns the
# P-CSCF addresses under container id 0x0001 (IPv6) or 0x000C (IPv4). A P-CSCF
# address IS the VoLTE provisioning: it is the SIP proxy the UE would register
# with. No address, no VoLTE for this subscription - whatever a daemon on the AP
# might do.
#
# ☠️ WHY THIS MATTERS BEYOND CURIOSITY. Switching IMS off is only safe while the
# network offers a CS domain to fall back to (see leads/csfb-is-a-dependency.md).
# The imsd path is the contingency for that - but a contingency that the NETWORK
# will not provision is not a contingency at all, and then the honest answer to a
# 2G retirement is "this phone stops being usable on this network", not "we will
# write a daemon".
#
#   pcscf-scan.py <capture.bin> [...]
import collections
import struct
import sys

PREFIX = bytes.fromhex("9801000001000000")
ESM_CODES = {0xB0E2: "in", 0xB0E3: "out"}


def entries(path):
    """Yield (log_code, payload) using the framing diag-ota-decode.py established."""
    b = open(path, "rb").read()
    out, i = [], 0
    while True:
        i = b.find(PREFIX, i)
        if i < 0:
            return out
        j = i + len(PREFIX)
        if j + 4 > len(b):
            return out
        j += 2                                   # 10 <more>
        ln, = struct.unpack_from("<H", b, j)
        j += 2
        if j + 12 > len(b) or ln < 12:
            i += 1
            continue
        code, = struct.unpack_from("<H", b, j + 2)
        out.append((code, b[j + 12:j + ln]))
        i = j + ln


def pcscf(payload):
    """Container ids the network uses to hand back a P-CSCF address."""
    found = []
    # PCO containers are id(2) len(1) value; scan for the two known ids rather
    # than parsing the whole ESM message - the framing above is fitted, not
    # specified, so a targeted scan fails loudly instead of silently mis-parsing.
    for cid, size, kind in ((0x0001, 16, "IPv6"), (0x000C, 4, "IPv4")):
        tag = struct.pack(">H", cid)
        k = 0
        while True:
            k = payload.find(tag, k)
            if k < 0 or k + 3 > len(payload):
                break
            ln = payload[k + 2]
            if ln == size and k + 3 + size <= len(payload):
                v = payload[k + 3:k + 3 + size]
                txt = (":".join("%02x%02x" % (v[m], v[m + 1]) for m in range(0, 16, 2))
                       if kind == "IPv6" else ".".join(str(x) for x in v))
                found.append((kind, txt))
            k += 1
    return found


total = collections.Counter()
for path in sys.argv[1:]:
    es = entries(path)
    hits = []
    accepts = 0
    for code, p in es:
        if code not in ESM_CODES or len(p) < 7:
            continue
        if p[6] == 0xC2:                          # ACTIVATE DEFAULT EPS BEARER ACCEPT
            accepts += 1
        got = pcscf(p)
        if got:
            hits.extend(got)
    print("== %s: %d log entries, %d ESM 0xC2 (bearer accept)" % (path, len(es), accepts))
    if not hits:
        print("   no P-CSCF container found")
    for (kind, txt), n in collections.Counter(hits).most_common(6):
        print("   P-CSCF %-4s %-18s x%d" % (kind, txt, n))
    total.update(hits)

print()
if total:
    print("☠️ A P-CSCF address means the network DOES provision IMS for this SIM -")
    print("   so the imsd contingency has a network to register with. It does NOT")
    print("   mean the operator would admit THIS device: IMS registration is often")
    print("   gated by a device policy (IMEI list) as well. Two gates, this is one.")
else:
    print("☠️ NO P-CSCF address in these captures. That is not yet proof of absence:")
    print("   the framing here is fitted rather than specified, and a bearer accept")
    print("   whose PCO was not requested carries none either. Before concluding")
    print("   'this network gives no VoLTE', check that any 0xC2 was seen at all.")
