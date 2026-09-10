#!/usr/bin/env python3
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
A=0x10007088
def rd(): x(fd,[(0,bytes([0x13,0x31]))]); x(fd,[(0,bytes([0x0D,0x10]))]); x(fd,[(0,bytes([0x00])+struct.pack("<I",A))]); x(fd,[(0,bytes([0x0C,0]))]); return x(fd,[(0,bytes([0x08])),(RD,bytes(4))])[1]
def wr(v): x(fd,[(0,bytes([0x13,0x31]))]); x(fd,[(0,bytes([0x0D,0x10]))]); x(fd,[(0,bytes([0x00])+struct.pack("<II",A,v))])
cur=struct.unpack("<I",rd())[0]; wr((cur&0xffffff00)|0x17); t0=time.time()
for d in (0,2,5,10,20,30):
    while time.time()-t0<d: time.sleep(0.1)
    print(f"+{d:2d} s  idle {rd().hex(' ')}", flush=True)
