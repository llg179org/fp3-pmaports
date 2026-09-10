#!/usr/bin/env python3
# Replay the DRIVER's exact byte sequences from userspace and compare with the
# vendor's, to find which step the controller rejects. Display must be on.
import ctypes, fcntl, os, struct, time
I2C_RDWR=0x0707; RD=1; ADDR=0x48
class m(ctypes.Structure): _fields_=[("addr",ctypes.c_uint16),("flags",ctypes.c_uint16),("len",ctypes.c_uint16),("buf",ctypes.POINTER(ctypes.c_uint8))]
class r(ctypes.Structure): _fields_=[("msgs",ctypes.POINTER(m)),("nmsgs",ctypes.c_uint32)]
def x(fd,msgs):
    a=(m*len(msgs))(); keep=[]
    for i,(f,d) in enumerate(msgs):
        b=(ctypes.c_uint8*len(d))(*d); keep.append(b); a[i]=m(ADDR,f,len(d),ctypes.cast(b,ctypes.POINTER(ctypes.c_uint8)))
    fcntl.ioctl(fd,I2C_RDWR,r(a,len(msgs))); return [bytes(k) for k in keep]
fd=os.open("/dev/i2c-2",os.O_RDWR)
for i in range(30):
    try: x(fd,[(0,bytes([0x08])),(RD,bytes(4))]); break
    except OSError: time.sleep(0.01)
W=0x10007F38
def rd_vendor():                 # burst_enable(0) 1-byte regs, addr, 0x0C 1 byte, read
    x(fd,[(0,bytes([0x13,0x31]))]); x(fd,[(0,bytes([0x0D,0x10]))])
    x(fd,[(0,bytes([0x00])+struct.pack("<I",W))]); x(fd,[(0,bytes([0x0C,0]))])
    return x(fd,[(0,bytes([0x08])),(RD,bytes(4))])[1]
def rd_driver(prelude):          # regmap: 4-byte values everywhere, NO burst regs for a 4-byte read
    if prelude: x(fd,[(0,bytes([0x13,0x31,0,0,0]))]); x(fd,[(0,bytes([0x0D,0x10,0,0,0]))])
    x(fd,[(0,bytes([0x00])+struct.pack("<I",W))]); x(fd,[(0,bytes([0x0C,0,0,0,0]))])
    return x(fd,[(0,bytes([0x08])),(RD,bytes(4))])[1]
def wr_driver(val):              # regmap: 4-byte burst regs then bulk_write 0x00 + 8 bytes
    x(fd,[(0,bytes([0x13,0x31,0,0,0]))]); x(fd,[(0,bytes([0x0D,0x10,0,0,0]))])
    x(fd,[(0,bytes([0x00])+struct.pack("<II",W,val))])
def wr_vendor(val):
    x(fd,[(0,bytes([0x13,0x31]))]); x(fd,[(0,bytes([0x0D,0x10]))])
    x(fd,[(0,bytes([0x00])+struct.pack("<II",W,val))])
print("T0 vendor read           :", rd_vendor().hex(' '))
print("T1 driver read, no prelude:", rd_driver(False).hex(' '))
print("T2 driver read, 4B prelude:", rd_driver(True).hex(' '))
wr_driver(0x77887788); time.sleep(0.01)
print("T3 after DRIVER-style write of 77887788, vendor read:", rd_vendor().hex(' '))
wr_vendor(0xA55AA55A); time.sleep(0.01)
print("T4 after vendor write of a55aa55a, vendor read       :", rd_vendor().hex(' '))
wr_driver(0x77887788); time.sleep(0.01)
print("T5 driver write again, then DRIVER read (4B prelude) :", rd_driver(True).hex(' '), " vendor read:", rd_vendor().hex(' '))
wr_vendor(0xA55AA55A); print("restored a55aa55a:", rd_vendor().hex(' '))
