#!/usr/bin/env python3
# After a driver rebind (= GPIO reset + probe), watch the idle word and the
# firmware's reload indicator over time.
import ctypes, fcntl, os, struct, time, subprocess
I2C_RDWR=0x0707; RD=1; ADDR=0x48
class m(ctypes.Structure): _fields_=[("addr",ctypes.c_uint16),("flags",ctypes.c_uint16),("len",ctypes.c_uint16),("buf",ctypes.POINTER(ctypes.c_uint8))]
class r(ctypes.Structure): _fields_=[("msgs",ctypes.POINTER(m)),("nmsgs",ctypes.c_uint32)]
def x(fd,msgs):
    a=(m*len(msgs))(); keep=[]
    for i,(f,d) in enumerate(msgs):
        b=(ctypes.c_uint8*len(d))(*d); keep.append(b); a[i]=m(ADDR,f,len(d),ctypes.cast(b,ctypes.POINTER(ctypes.c_uint8)))
    fcntl.ioctl(fd,I2C_RDWR,r(a,len(msgs))); return [bytes(k) for k in keep]
def rd(fd,a):
    x(fd,[(0,bytes([0x13,0x31]))]); x(fd,[(0,bytes([0x0D,0x10]))])
    x(fd,[(0,bytes([0x00])+struct.pack("<I",a))]); x(fd,[(0,bytes([0x0C,0]))]); return x(fd,[(0,bytes([0x08])),(RD,bytes(4))])[1]
fd=os.open("/dev/i2c-2",os.O_RDWR)
D="/sys/bus/i2c/drivers/Himax-hx83112b-TS"; T="/sys/kernel/debug/tracing/events/kprobes/enable"
open(T,"w").write("0")
open(D+"/unbind","w").write("2-0048"); t0=time.time(); open(D+"/bind","w").write("2-0048")
tb=time.time()-t0
print(f"bind took {tb*1000:.0f} ms (probe incl. 20 ms settle + reset + apply)")
for d in (0.01,0.05,0.1,0.2,0.5,1.0,2.0,3.0):
    while time.time()-t0 < tb+d: time.sleep(0.002)
    try:
        i=rd(fd,0x10007088); c=rd(fd,0x100072c0); f=rd(fd,0x10007f00)
        print(f"+{d*1000:5.0f} ms  idle {i.hex(' ')}   reload@72c0 {c.hex(' ')}   @7f00 {f.hex(' ')}")
    except OSError as e: print(f"+{d*1000:5.0f} ms  NACK {e}")
open(T,"w").write("1")
