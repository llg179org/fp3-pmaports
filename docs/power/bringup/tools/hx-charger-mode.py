#!/usr/bin/env python3
# hx-charger-mode.py read|on|off   -- root, on pmOS, DISPLAY MUST BE ON
#
# Mirror of the vendor driver's himax_usb_detect_set(): the FW-config word at
# 0x10007F38 is A55AA55A with a charger present and 77887788 without. The
# mainline driver never writes it; measured 2026-09-10 on this phone the FW's
# post-reset value is 5CA3A6A8 (neither), while the phone sat on a charger.
#
# ☠ The controller answers userspace I2C only while the panel is on: with the
# display off every transaction NACKs (measured 200/200 over 2 s), and unbinding
# the driver in that state drops the last holder of the iovcc rail - the probe
# then fails and the panel is dead until the display is woken. Read before write,
# write, read back; a write that is not read back is a hope, not a change.
import ctypes, fcntl, os, struct, sys, time
I2C_RDWR=0x0707; I2C_M_RD=1; ADDR=0x48; REG=0x10007F38
ON=bytes.fromhex("5AA55AA5")     # LE bytes of 0xA55AA55A as the vendor lays them out: data[0]=0x5A,[1]=0xA5,[2]=0x5A,[3]=0xA5
OFF=bytes.fromhex("88778877")    # 0x77887788: data[0]=0x88,[1]=0x77,[2]=0x88,[3]=0x77
class i2c_msg(ctypes.Structure):
    _fields_=[("addr",ctypes.c_uint16),("flags",ctypes.c_uint16),("len",ctypes.c_uint16),("buf",ctypes.POINTER(ctypes.c_uint8))]
class rdwr(ctypes.Structure):
    _fields_=[("msgs",ctypes.POINTER(i2c_msg)),("nmsgs",ctypes.c_uint32)]
def xfer(fd,msgs):
    arr=(i2c_msg*len(msgs))(); keep=[]
    for i,(fl,d) in enumerate(msgs):
        b=(ctypes.c_uint8*len(d))(*d); keep.append(b)
        arr[i]=i2c_msg(ADDR,fl,len(d),ctypes.cast(b,ctypes.POINTER(ctypes.c_uint8)))
    fcntl.ioctl(fd,I2C_RDWR,rdwr(arr,len(msgs))); return [bytes(k) for k in keep]
def burst_off(fd): xfer(fd,[(0,bytes([0x13,0x31]))]); xfer(fd,[(0,bytes([0x0D,0x10]))])
def rd4(fd):
    burst_off(fd); xfer(fd,[(0,bytes([0x00])+struct.pack("<I",REG))]); xfer(fd,[(0,bytes([0x0C,0x00]))])
    return xfer(fd,[(0,bytes([0x08])),(I2C_M_RD,bytes(4))])[1]
def wr4(fd,data):   # vendor himax_flash_write_burst: one write to reg 0x00 = [addr LE 4][data 4]
    burst_off(fd); xfer(fd,[(0,bytes([0x00])+struct.pack("<I",REG)+data)])
if open("/sys/class/drm/card0-DSI-1/dpms").read().strip()!="On": sys.exit("display is off - the controller will NACK; wake it first")
fd=os.open("/dev/i2c-2",os.O_RDWR)
for i in range(30):
    try: xfer(fd,[(0,bytes([0x08])),(I2C_M_RD,bytes(4))]); break
    except OSError: time.sleep(0.01)
else: sys.exit("controller never ACKed")
mode=sys.argv[1] if len(sys.argv)>1 else "read"
before=rd4(fd); print(f"before: {before.hex(' ')}")
if mode in ("on","off"):
    wr4(fd, ON if mode=="on" else OFF); time.sleep(0.01)
    after=rd4(fd); want=ON if mode=="on" else OFF
    print(f"after:  {after.hex(' ')}   {'OK - read back matches' if after==want else 'MISMATCH - the write did not take'}")
    sys.exit(0 if after==want else 1)
