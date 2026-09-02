#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Does this network provision VoLTE for this SIM? Read it out of a capture we
# already have, rather than measuring anything new.
#
# The IMS-PDN loop's ACTIVATE DEFAULT EPS BEARER CONTEXT REQUEST (0xC1) carries a
# Protocol Configuration Options IE, and inside it the network returns the
# P-CSCF addresses under container id 0x0001 (IPv6) or 0x000C (IPv4). A P-CSCF
# address IS the VoLTE provisioning: it is the SIP proxy the UE would register
# with. No address, no VoLTE for this subscription - whatever a daemon on the AP
# might do.
#
# ☠️ CORRECTED 2026-09-02 EVENING: THE FIRST VERSION NAMED THE WRONG MESSAGE and
# only got the right answer by scanning too widely. It counted 0xC2 (ACCEPT, the
# UE's uplink confirmation) and byte-scanned EVERY ESM message for the container
# id, so the '22 addresses against 22 accepts' it reported was a coincidence of
# two unrelated counts. The network returns P-CSCF in the downlink REQUEST; the
# ACCEPT carries no PCO at all, which the strict walk below reports as '0 of 22'.
# The conclusion survived the correction, but it was not the tool's doing.
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
ESM_REQUEST = 0xC1   # ACTIVATE DEFAULT EPS BEARER CONTEXT REQUEST (network -> UE)
ESM_ACCEPT = 0xC2    # ...ACCEPT (UE -> network): carries no PCO, kept only as a control


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


# Containers the network can hand back inside the PCO (24.008 10.5.6.3). The DNS
# ones are not what this tool is looking for - they are the CONTROL: a walk that
# finds a plausible DNS server in the same PCO understands the structure, while a
# byte-scan that only ever matches the one id it was told to look for has proved
# nothing about the structure at all.
CONTAINERS = {
    0x0001: ("P-CSCF IPv6", 16),
    0x000C: ("P-CSCF IPv4", 4),
    0x0003: ("DNS IPv6", 16),
    0x000D: ("DNS IPv4", 4),
    # ☠️ NOT AN ADDRESS, AND THE STRONGEST ROW HERE. 0x0002 is the IM CN Subsystem
    # Signalling Flag: the network stating, per bearer, that this PDN is for IMS
    # signalling. An address could in principle be a stale provisioning leftover;
    # this flag is the network answering the question in the same breath.
    0x0002: ("IMS signalling flag", None),
}
PCO_IEI = 0x27


def fmt(v):
    if len(v) == 4:
        return ".".join(str(x) for x in v)
    if len(v) == 16:
        return ":".join("%02x%02x" % (v[m], v[m + 1]) for m in range(0, 16, 2))
    return v.hex()


def walk_pco(payload):
    """Walk the PCO IE as a length-checked TLV chain; return (containers, why).

    ☠️ THE BYTE SCAN THIS REPLACES COULD NOT TELL A CONTAINER FROM ITS ECHO.
    Searching the message for the two-byte id 0x000C and accepting whatever
    followed it will also match those bytes INSIDE another container's payload -
    and the correlated structure lives exactly there, so the IMS-off control
    (no accepts, no addresses) does not exclude it. A walk that starts at the PCO
    header, steps by each container's own length field, and requires the lengths
    to ADD UP to the IE length cannot match by accident: an off-by-one lands on a
    length that does not close, and the walk reports the failure instead of a
    finding.
    """
    out = []
    k = payload.find(bytes([PCO_IEI]))
    while k >= 0:
        if k + 2 > len(payload):
            break
        ielen = payload[k + 1]
        body = payload[k + 2:k + 2 + ielen]
        if len(body) == ielen and ielen >= 1 and (body[0] & 0x80):
            # octet 3: ext=1, bits 3-1 = configuration protocol (000 = PPP)
            got, i, ok = [], 1, True
            while i + 3 <= len(body):
                cid = struct.unpack_from(">H", body, i)[0]
                ln = body[i + 2]
                if i + 3 + ln > len(body):
                    ok = False
                    break
                got.append((cid, body[i + 3:i + 3 + ln]))
                i += 3 + ln
            # the lengths must CLOSE on the IE boundary - this is the whole check
            if ok and i == len(body) and got:
                return got, "walk closed on the IE boundary (%d containers, %d bytes)" % (len(got), ielen)
            out.append("IE at %d did not close (%d of %d bytes consumed)" % (k, i, len(body)))
        k = payload.find(bytes([PCO_IEI]), k + 1)
    return [], "; ".join(out) or "no PCO IE (0x27) in this message"


total = collections.Counter()
walked = collections.Counter()
for path in sys.argv[1:]:
    es = entries(path)
    hits, accepts, requests, closed, failed, others = [], 0, 0, 0, [], collections.Counter()
    for code, p in es:
        if code not in ESM_CODES or len(p) < 7:
            continue
        if p[6] == ESM_ACCEPT:
            accepts += 1
        if p[6] != ESM_REQUEST:
            continue
        requests += 1
        got, why = walk_pco(p)
        if not got:
            failed.append(why)
            continue
        closed += 1
        for cid, v in got:
            name, size = CONTAINERS.get(cid, (None, None))
            if name is None:
                others[cid] += 1
            elif size is None or len(v) == size:
                txt = "set" if size is None else fmt(v)
                if "P-CSCF" in name:
                    hits.append((name, txt))
                walked[(name, txt)] += 1
            else:
                others[cid] += 1
    print("== %s: %d log entries, %d ESM 0xC1 (bearer request), %d 0xC2 (accept)"
          % (path, len(es), requests, accepts))
    print("   PCO walk: %d of %d requests parsed with the lengths CLOSING on the IE boundary"
          % (closed, requests))
    if failed:
        for why, n in collections.Counter(failed).most_common(3):
            print("   ☠️ %d accept(s): %s" % (n, why))
    for (name, txt), n in walked.most_common(8):
        print("   %-12s %-18s x%d" % (name, txt, n))
    if others:
        print("   other container ids seen: %s"
              % ", ".join("0x%04x x%d" % (c, n) for c, n in others.most_common(6)))
    total.update(hits)
    walked.clear()

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
