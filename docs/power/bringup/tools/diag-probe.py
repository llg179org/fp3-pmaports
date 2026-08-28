#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Send a DIAG request to the modem and print what comes back.
#
#   diag-probe.py /dev/rpmsgN <hex-payload> [timeout_s]
#   diag-probe.py /dev/rpmsg0 00            # DIAG_VERNO_F, the cheapest hello
#   diag-probe.py /dev/rpmsg0 7c            # extended build ID
#
# Needs the endpoint from rpmsg-ept.py, which needs linux-fp3 r78
# (CONFIG_RPMSG_CTRL). See that file for the traps in opening the channel.
#
# ☠️ The SMD DIAG channel carries HDLC-framed packets: payload, then a CRC-16
# (X.25 - reflected CCITT, init 0xFFFF, xorout 0xFFFF), then 0x7E, with 0x7D and
# 0x7E escaped as 0x7D followed by the byte XOR 0x20. On Android the diag driver
# does this for you; on a raw rpmsg endpoint nothing does, and an unframed
# request is simply ignored - which reads as "the modem is not answering" rather
# than as a framing mistake.
import os
import select
import sys


def crc16_x25(data: bytes) -> int:
    crc = 0xFFFF
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ 0x8408 if crc & 1 else crc >> 1
    return crc ^ 0xFFFF


def hdlc_encode(payload: bytes) -> bytes:
    frame = payload + crc16_x25(payload).to_bytes(2, "little")
    out = bytearray()
    for b in frame:
        if b in (0x7D, 0x7E):
            out += bytes([0x7D, b ^ 0x20])
        else:
            out.append(b)
    out.append(0x7E)
    return bytes(out)


def hdlc_decode(buf: bytes):
    """Split on 0x7E, unescape, and drop the trailing CRC. Frames with a bad CRC
    are returned anyway, marked - a silently dropped frame looks identical to no
    answer at all, which is the failure mode this whole file exists to avoid."""
    for raw in buf.split(b"\x7e"):
        if not raw:
            continue
        out = bytearray()
        esc = False
        for b in raw:
            if esc:
                out.append(b ^ 0x20)
                esc = False
            elif b == 0x7D:
                esc = True
            else:
                out.append(b)
        if len(out) < 3:
            yield bytes(out), False
            continue
        body, crc = bytes(out[:-2]), int.from_bytes(out[-2:], "little")
        yield body, crc == crc16_x25(body)


dev = sys.argv[1]
payload = bytes.fromhex(sys.argv[2])
timeout = float(sys.argv[3]) if len(sys.argv) > 3 else 3.0

fd = os.open(dev, os.O_RDWR | os.O_NONBLOCK)
req = hdlc_encode(payload)
print(f"-> {req.hex()}")
os.write(fd, req)

buf = b""
while select.select([fd], [], [], timeout)[0]:
    chunk = os.read(fd, 8192)
    if not chunk:
        break
    buf += chunk
os.close(fd)

if not buf:
    print("<- nothing")
    sys.exit(1)
print(f"<- {len(buf)} bytes raw")
for body, ok in hdlc_decode(buf):
    print(f"   [{'crc ok ' if ok else 'CRC BAD'}] {body.hex()}")
