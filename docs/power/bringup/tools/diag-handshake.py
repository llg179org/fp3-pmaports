#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Walk the modem's DIAG control handshake to the point where the data channel is
# allowed to answer, then ask it one question.
#
#   diag-handshake.py [ctrl_dev] [settle_s]
#
# ☠️ This is an INTERVENTION, not an observation: struct diag_ctrl_msg_diagmode
# carries a sleep_vote, so bringing DIAG up changes the peripheral's sleep
# behaviour. Never run it while a duty measurement is in flight.
#
# WHY the sequence is what it is. diagfwd_write() in the vendor driver
# (diagfwd_peripheral.c) drops a TYPE_CMD packet with `return 0` - no error, no
# complaint, exactly the silence seen from every earlier attempt - unless three
# things hold: the peripheral's feature mask has been received, ours has been
# sent, and, when the peripheral advertises F_DIAG_DIAGID_SUPPORT, a DIAG_ID has
# been assigned and sent back. The third is the one every earlier attempt
# skipped, and it is not a packet we invent: the peripheral opens that exchange
# with DIAG_CTRL_MSG_DIAGID (33) carrying its process name, and the AP echoes the
# same structure with an id of its choosing (process_diagid(), diagfwd_cntl.c).
#
# ☠️ Only the reply whose process_name contains "root" sets diag_id_sent - the
# per-PD names are registered but do not open the gate. Echo every 33 we see and
# the root one will be among them.
import fcntl
import os
import select
import struct
import sys
import glob

RPMSG_CREATE_EPT_IOCTL = 0x4028B501
DIAG_CTRL_MSG_DIAGMODE = 3
DIAG_CTRL_MSG_FEATURE = 8
DIAG_CTRL_MSG_DIAGID = 33
FEATURE_MASK = 0xCA05          # exactly diag_send_feature_mask_update()


def open_channel(ctrl, name):
    """Create an endpoint and return the /dev/rpmsgN that appeared for it."""
    before = set(glob.glob("/dev/rpmsg[0-9]*"))
    fd = os.open(ctrl, os.O_RDWR)
    try:
        fcntl.ioctl(fd, RPMSG_CREATE_EPT_IOCTL,
                    struct.pack("32sII", name.encode(), 0xFFFFFFFF, 0xFFFFFFFF))
    finally:
        os.close(fd)
    new = sorted(set(glob.glob("/dev/rpmsg[0-9]*")) - before)
    if not new:
        sys.exit(f"no /dev/rpmsgN appeared for {name}")
    return new[0]


def packets(buf):
    """The control format is {cmd:u32, len:u32, body}, packed back to back."""
    i = 0
    while i + 8 <= len(buf):
        cmd, ln = struct.unpack_from("<II", buf, i)
        if i + 8 + ln > len(buf):
            break
        yield cmd, buf[i + 8:i + 8 + ln]
        i += 8 + ln


def drain(fd, timeout):
    buf = b""
    while select.select([fd], [], [], timeout)[0]:
        chunk = os.read(fd, 65536)
        if not chunk:
            break
        buf += chunk
    return buf


ctrl = sys.argv[1] if len(sys.argv) > 1 else "/dev/rpmsg_ctrl3"
settle = float(sys.argv[2]) if len(sys.argv) > 2 else 3.0

cntl_dev = open_channel(ctrl, "DIAG_CNTL")
cntl = os.open(cntl_dev, os.O_RDWR | os.O_NONBLOCK)
print(f"DIAG_CNTL -> {cntl_dev}")

buf = drain(cntl, settle)
print(f"on open: {len(buf)} bytes")

fm = struct.pack("<IIIH", DIAG_CTRL_MSG_FEATURE, 4 + 2, 2, FEATURE_MASK)
os.write(cntl, fm)
print(f"-> feature mask 0x{FEATURE_MASK:04x}")
buf += drain(cntl, settle)

seen = {}
answered = set()
for _ in range(6):
    for cmd, body in packets(buf):
        seen[cmd] = seen.get(cmd, 0) + 1
        if cmd != DIAG_CTRL_MSG_DIAGID or len(body) < 8:
            continue
        version, their_id = struct.unpack_from("<II", body, 0)
        name = body[8:].split(b"\0")[0].decode("ascii", "replace")
        if name in answered:
            continue
        answered.add(name)
        # Echo the same structure. The id is ours to choose; 1 is the AP's own
        # in the vendor driver, so start above it.
        our_id = len(answered) + 1
        nm = name.encode()[:29] + b"\0"
        ln = 4 + 4 + len(nm)
        pkt = struct.pack("<IIII", DIAG_CTRL_MSG_DIAGID, ln, 1, our_id) + nm
        os.write(cntl, pkt)
        print(f"-> DIAGID echo name={name!r} their_id={their_id} our_id={our_id}"
              f"{'  <- ROOT, this is the one that opens the gate' if 'root' in name else ''}")
    more = drain(cntl, settle)
    if not more:
        break
    buf = more

print("control packets seen:",
      ", ".join(f"{c}x{n}" for c, n in sorted(seen.items())))

# real_time = 1, everything else left at zero: sleep_vote is deliberately 0 so
# this does not additionally hold the peripheral awake by itself.
dm = struct.pack("<III" + "I" * 8, DIAG_CTRL_MSG_DIAGMODE, 4 * 9, 1,
                 0, 1, 0, 0, 0, 0, 0, 0)
os.write(cntl, dm)
print("-> DIAGMODE real_time=1 sleep_vote=0")
drain(cntl, settle)

data_dev = open_channel(ctrl, "DIAG")
data = os.open(data_dev, os.O_RDWR | os.O_NONBLOCK)
print(f"DIAG -> {data_dev}")


def crc16_x25(d):
    crc = 0xFFFF
    for b in d:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ 0x8408 if crc & 1 else crc >> 1
    return crc ^ 0xFFFF


def hdlc(payload):
    frame = payload + crc16_x25(payload).to_bytes(2, "little")
    out = bytearray()
    for b in frame:
        if b in (0x7D, 0x7E):
            out += bytes([0x7D, b ^ 0x20])
        else:
            out.append(b)
    out.append(0x7E)
    return bytes(out)


for req in (b"\x00", b"\x7c"):
    os.write(data, hdlc(req))
    ans = drain(data, settle)
    print(f"-> DIAG {req.hex()}   <- {len(ans)} bytes"
          + (f"  {ans[:64].hex()}" if ans else "  (still silent)"))

os.close(data)
os.close(cntl)
