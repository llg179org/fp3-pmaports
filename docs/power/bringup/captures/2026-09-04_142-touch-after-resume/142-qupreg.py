#!/usr/bin/env python3
"""#142 - QUP registers AND the two i2c pads, while a transfer is hung.

QUP offsets from our driver drivers/i2c/busses/i2c-qup.c:
    QUP_STATE 0x004  QUP_OPERATIONAL 0x018  QUP_ERROR_FLAGS 0x01c
    QUP_HW_VERSION 0x030  QUP_I2C_STATUS 0x404
QUP_I2C_STATUS bits: BUS_ACTIVE = BIT(8) from that driver; BUS_MASTER = BIT(9)
from the downstream header it does not define (i2c-msm-v2.h:166-167).

TLMM pad readback from drivers/pinctrl/qcom/pinctrl-msm8953.c:
    io_reg = 0x4 + 0x1000 * id,  in_bit = 0,  TLMM base 0x01000000 (msm8953.dtsi)
The input buffer reads the pad whatever the pin is muxed to, so gpio10/gpio11
can be read while they are in blsp_i2c3 function.

☠️ NEVER read a clock-gated block. Every QUP sample is preceded by a read of the
controller's runtime_status and the loop stops as soon as it is not 'active'.
During a hung transfer the driver holds pm_runtime, so the block is clocked for
the whole 15 s - which is the only reason this measurement is possible.

usage: 142-qupreg.py <qup-base-hex> <runtime_status-path> <max-seconds>
"""
import sys, os, mmap, time

qup_base = int(sys.argv[1], 16)
rtpath   = sys.argv[2]
maxsec   = float(sys.argv[3])
PAGE = 0x1000
TLMM = 0x01000000
PINS = [10, 11]                       # blsp_i2c3, from msm8953.dtsi i2c_3_default

REGS = [("QUP_STATE",0x004), ("QUP_OPERATIONAL",0x018), ("QUP_ERROR_FLAGS",0x01c),
        ("QUP_I2C_STATUS",0x404)]
BITS = [("WR_BUF_FULL",1<<0), ("NACK",1<<3), ("IN_NOT_EMPTY",1<<5),
        ("BUS_ACTIVE",1<<8), ("BUS_MASTER",1<<9)]
OPER = [("OUT_NOT_EMPTY",1<<4), ("IN_NOT_EMPTY",1<<5), ("OUT_FULL",1<<6),
        ("NO_INPUT",1<<7), ("OUT_SVC",1<<8), ("IN_SVC",1<<9),
        ("MX_OUT_DONE",1<<10), ("MX_IN_DONE",1<<11)]

def dec(v, table):
    on = [n for n,b in table if v & b]
    return ",".join(on) if on else "-"

def rt():
    try:
        with open(rtpath) as f: return f.read().strip()
    except OSError: return "?"

fd = os.open("/dev/mem", os.O_RDONLY | os.O_SYNC)
def page(addr):
    return mmap.mmap(fd, PAGE, mmap.MAP_SHARED, mmap.PROT_READ, offset=addr)
try:
    mq  = page(qup_base)
    mp  = {p: page(TLMM + 0x1000*p) for p in PINS}
except Exception as e:
    print("MMAP FAILED: %s" % e); os._exit(1)

def rq(off): return int.from_bytes(mq[off:off+4], "little")
def pad(p):  return int.from_bytes(mp[p][0x4:0x8], "little") & 1

# ☠️ Instrument gate on a KNOWN answer: an idle, healthy i2c bus is pulled high,
# so both pads must read 1 here. If they do not, the pad readback is wrong and
# nothing it says during the hang is worth anything.
lvl = {p: pad(p) for p in PINS}
print("pad gate (bus idle, must be 1/1): " +
      " ".join("gpio%d=%d" % (p, lvl[p]) for p in PINS), flush=True)
if any(v != 1 for v in lvl.values()):
    print("GATE FAILED: an idle i2c bus is not reading high - not trusting the pads", flush=True)
    os._exit(1)

print("armed on 0x%08x, waiting for the controller to go active" % qup_base, flush=True)
t0 = time.monotonic()
while rt() != "active":
    if time.monotonic() - t0 > maxsec:
        print("NOTHING: never went active in %.0f s" % maxsec, flush=True); os._exit(0)
    time.sleep(0.001)

hw = rq(0x030); words = [rq(o) for _,o in REGS]
if hw in (0, 0xffffffff) or len(set(words + [hw])) == 1:
    print("JUNK: HW_VERSION=0x%08x, uniform - block not clocked" % hw, flush=True); os._exit(1)
print("qup gate ok: QUP_HW_VERSION = 0x%08x" % hw, flush=True)

t_act, last, n = time.monotonic(), None, 0
while True:
    if rt() != "active":
        print("[%7.3f] left 'active' after %d samples" % (time.monotonic()-t_act, n), flush=True); break
    if time.monotonic() - t_act > maxsec:
        print("[%7.3f] max seconds after %d samples" % (time.monotonic()-t_act, n), flush=True); break
    v = tuple(rq(o) for _,o in REGS) + tuple(pad(p) for p in PINS)
    n += 1
    if v != last:
        print("[%7.3f] STATE=0x%03x OPER=0x%06x[%s] ERR=0x%06x I2C_STATUS=0x%08x[%s]  gpio10=%d gpio11=%d"
              % (time.monotonic()-t_act, v[0], v[1], dec(v[1],OPER), v[2], v[3], dec(v[3],BITS), v[4], v[5]),
              flush=True)
        last = v
    time.sleep(0.002)
print("samples: %d" % n, flush=True)
