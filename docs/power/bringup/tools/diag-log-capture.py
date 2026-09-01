#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
"""Turn on the modem's LTE log stream and record it — the OTA instrument.

    diag-log-capture.py [seconds] [outdir]        (ON THE DEVICE, root)

WHY THIS AND NOT diag-probe.py
==============================
[`../leads/diag-bringup.md`] stalled on the DIAG **command** path: the modem
answers control messages and never answers a command, and no write on the data
channel has ever been shown to reach it. That page has been trying to ask the
modem a question.

**The power question does not need a question asked.** What it needs is the
modem's own LOG STREAM - the RRC and NAS packets it emits by itself - and those
are turned on by a control message, on the channel that already works:

    DIAG_CTRL_MSG_LOG_MASK = 9      (diagchar.h, vendor tree on disk)

The peripheral's own feature mask (0x3EF7, decoded 2026-08-29) sets bit 11,
MASK_CENTRALIZATION, so it expects its masks over DIAG_CNTL rather than as
commands. That is the door that was never tried.

WHAT IT TURNS ON, and why these codes
=====================================
equip_id = log_code >> 12, item = log_code & 0xFFF. All LTE codes are 0xB0xx,
so equip_id 0xB:

    0xB0C0  LTE RRC OTA message      <- carries the connection-request and its
                                        ESTABLISHMENT CAUSE, which names the
                                        procedure the modem keeps running
    0xB0C1  LTE RRC MIB
    0xB0C2  LTE RRC serving-cell info
    0xB0E0..0xB0E3  LTE NAS ESM plain OTA, in and out
    0xB0EC, 0xB0ED  LTE NAS EMM plain OTA, in and out

Deliberately NOT the whole equip: PHY logs in the same range are high-rate and
would bury a ten-minute idle capture.

☠️ TWO WARNINGS THAT BELONG WITH THE RESULT
===========================================
1. **DIAG is not a neutral observer.** `struct diag_ctrl_msg_diagmode` has a
   `sleep_vote` field: the AP's diag client has a say over whether the peripheral
   sleeps. So a duty measured with logging on is NOT the same measurement as a
   duty measured without it. Take the duty separately, or take it both ways.
2. **The control handshake is answered ONCE PER BOOT.** Measured: the first
   DIAG_CNTL endpoint of a boot draws 6160 bytes, every later one draws 9. So
   this tool opens every endpoint and does the whole sequence in ONE process, and
   a retry after a failure means a REBOOT, not a re-run.
"""
import os
import select
import struct
import sys
import time
import fcntl
import glob

RPMSG_CREATE_EPT_IOCTL = 0x4028B501
FEATURE_MASK = 0xCA05          # what the vendor AP advertises
LOG_CODES = [0xB0C0, 0xB0C1, 0xB0C2, 0xB0E0, 0xB0E1, 0xB0E2, 0xB0E3,
             0xB0EC, 0xB0ED]
NUM_ITEMS = 0x100              # covers every item above; mask is 32 bytes


def modem_ctrl():
    """/dev/rpmsg_ctrlN for the modem — mapped, never guessed."""
    for c in sorted(glob.glob("/sys/class/rpmsg/rpmsg_ctrl*")):
        tgt = os.path.realpath(os.path.join(c, "device"))
        if "remoteproc0" in tgt or "mpss" in tgt or "modem" in tgt:
            return "/dev/" + os.path.basename(c)
    return None


def open_ept(ctrl, name):
    """Create an endpoint and return (fd, path). The node appears after ioctl."""
    before = set(glob.glob("/dev/rpmsg[0-9]*"))
    fd = os.open(ctrl, os.O_RDWR)
    fcntl.ioctl(fd, RPMSG_CREATE_EPT_IOCTL,
                struct.pack("32sII", name.encode(), 0xFFFFFFFF, 0xFFFFFFFF))
    for _ in range(50):
        new = set(glob.glob("/dev/rpmsg[0-9]*")) - before
        if new:
            p = sorted(new)[0]
            return os.open(p, os.O_RDWR | os.O_NONBLOCK), p, fd
        time.sleep(0.02)
    os.close(fd)
    raise RuntimeError("no rpmsg node appeared for " + name)


def ctrl_feature():
    return struct.pack("<IIIH", 8, 6, 2, FEATURE_MASK)


def ctrl_diagmode(sleep_vote=1, real_time=1):
    # ctrl_pkt_id, data_len, version, sleep_vote, real_time, use_nrt_values,
    # commit_threshold, sleep_threshold, sleep_time, drain_timer_val,
    # event_stale_timer_val   (diagfwd_cntl.h, __packed, all u32)
    body = struct.pack("<9I", 1, sleep_vote, real_time, 0, 0, 0, 0, 0, 0)
    return struct.pack("<II", 3, len(body)) + body


def ctrl_log_mask(codes, num_items=NUM_ITEMS):
    equip = {c >> 12 for c in codes}
    if len(equip) != 1:
        raise ValueError("one equip_id per packet")
    equip_id = equip.pop()
    size = (num_items + 7) // 8
    m = bytearray(size)
    for c in codes:
        i = c & 0xFFF
        m[i // 8] |= 1 << (i % 8)
    # cmd_type u32, data_len u32, stream_id u8, status u8, equip_id u8,
    # num_items u32, log_mask_size u32   (diag_ctrl_log_mask, __packed)
    hdr = struct.pack("<IIBBBII", 9, 11 + size, 1, 3, equip_id, num_items, size)
    return hdr + bytes(m)


def main():
    secs = int(sys.argv[1]) if len(sys.argv) > 1 else 600
    out = sys.argv[2] if len(sys.argv) > 2 else "/var/log/fp3/diag-%d" % time.time()
    os.makedirs(out, exist_ok=True)

    ctrl = modem_ctrl()
    if not ctrl:
        print("no modem rpmsg control device", file=sys.stderr)
        return 1
    print("modem control device: %s" % ctrl)

    # ☠️ Order matters: DIAG_CNTL first, and everything in this one process.
    cfd, cpath, ch1 = open_ept(ctrl, "DIAG_CNTL")
    dfd, dpath, ch2 = open_ept(ctrl, "DIAG")
    print("DIAG_CNTL -> %s   DIAG -> %s" % (cpath, dpath))

    cnt_raw = open(os.path.join(out, "cntl.bin"), "wb")
    dat_raw = open(os.path.join(out, "diag.bin"), "wb")

    def drain(timeout):
        """Read whatever is there for `timeout` seconds; return (ncntl, ndata)."""
        a = b = 0
        end = time.time() + timeout
        while time.time() < end:
            r, _, _ = select.select([cfd, dfd], [], [], 0.2)
            for fd in r:
                try:
                    buf = os.read(fd, 65536)
                except BlockingIOError:
                    continue
                except OSError as e:
                    print("read error on %s: %s" % (fd, e))
                    continue
                if not buf:
                    continue
                if fd == cfd:
                    cnt_raw.write(buf); a += len(buf)
                else:
                    dat_raw.write(buf); b += len(buf)
        cnt_raw.flush(); dat_raw.flush()
        return a, b

    a, b = drain(3.0)
    print("open burst: cntl %d bytes, diag %d bytes" % (a, b))
    if a < 100:
        print("☠️ short control burst (%d) - this boot has already consumed the "
              "handshake. The result below is NOT a clean negative; reboot and "
              "re-run." % a)

    for label, pkt in (("FEATURE", ctrl_feature()),
                       ("DIAGMODE", ctrl_diagmode()),
                       ("LOG_MASK", ctrl_log_mask(LOG_CODES))):
        try:
            os.write(cfd, pkt)
            print("sent %s (%d bytes)" % (label, len(pkt)))
        except OSError as e:
            print("☠️ %s write failed: %s" % (label, e))
        a, b = drain(2.0)
        print("   after %s: cntl +%d, diag +%d" % (label, a, b))

    print("\ncapturing %d s ..." % secs)
    t0 = time.time()
    ta = tb = 0
    while time.time() - t0 < secs:
        a, b = drain(10.0)
        ta += a; tb += b
        print("  +%4ds  cntl %7d  diag %7d" % (time.time() - t0, ta, tb),
              flush=True)

    cnt_raw.close(); dat_raw.close()
    print("\ntotal: cntl %d bytes, diag %d bytes -> %s" % (ta, tb, out))
    if tb == 0:
        print("☠️ THE DATA CHANNEL STAYED SILENT. The log mask was accepted by "
              "the transport but produced no stream. That is the same wall the "
              "command path hit, now shown for the mask path too - record it as "
              "such, do not read it as 'the modem is quiet'.")
    for fd in (cfd, dfd, ch1, ch2):
        try:
            os.close(fd)
        except OSError:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
