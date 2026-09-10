#!/usr/bin/env python3
# Read hx83112b FW-config registers through the AHB window, the way the mainline
# driver does (reg 0x00 <= address LE, reg 0x0C <= 0 = read, then 4 bytes from 0x08).
# I2C_RDWR does not check for a bound driver, so this coexists with himax_hx83112b;
# only run it with no finger on the panel.
import ctypes, fcntl, os, sys, struct
I2C_RDWR = 0x0707; I2C_M_RD = 1; BUS = "/dev/i2c-2"; ADDR = 0x48
class i2c_msg(ctypes.Structure):
    _fields_ = [("addr", ctypes.c_uint16), ("flags", ctypes.c_uint16),
                ("len", ctypes.c_uint16), ("buf", ctypes.POINTER(ctypes.c_uint8))]
class rdwr(ctypes.Structure):
    _fields_ = [("msgs", ctypes.POINTER(i2c_msg)), ("nmsgs", ctypes.c_uint32)]
def xfer(fd, msgs):
    arr = (i2c_msg * len(msgs))()
    keep = []
    for i, (flags, data) in enumerate(msgs):
        buf = (ctypes.c_uint8 * len(data))(*data); keep.append(buf)
        arr[i] = i2c_msg(ADDR, flags, len(data), ctypes.cast(buf, ctypes.POINTER(ctypes.c_uint8)))
    fcntl.ioctl(fd, I2C_RDWR, rdwr(arr, len(msgs)))
    return [bytes(b) for b in keep]
def knock(fd):
    # vendor himax_interface_on: the controller's I2C sleeps and NACKs the first
    # access; a dummy read of 0x08 (retried) wakes it, then burst mode is set and
    # read back until it sticks.
    import time
    tries=int(os.environ.get('KNOCK_TRIES','10')); nack=0
    for i in range(tries):
        try:
            xfer(fd, [(0, bytes([0x08])), (I2C_M_RD, bytes(4))]); print('knock: ACK after', nack, 'NACKs'); break
        except OSError:
            nack+=1; time.sleep(0.010)
    else:
        raise SystemExit(f"knock failed: {nack} NACKs over {tries*10} ms")
    for i in range(10):
        xfer(fd, [(0, bytes([0x13, 0x31]))]); xfer(fd, [(0, bytes([0x0D, 0x10]))])
        a = xfer(fd, [(0, bytes([0x13])), (I2C_M_RD, bytes(1))])[1]
        b = xfer(fd, [(0, bytes([0x0D])), (I2C_M_RD, bytes(1))])[1]
        if a == b"\x31" and b == b"\x10": return i
        time.sleep(0.001)
    raise SystemExit("burst mode did not stick")
def rd4(fd, address):
    # vendor himax_register_read, 4-byte case
    xfer(fd, [(0, bytes([0x13, 0x31]))]); xfer(fd, [(0, bytes([0x0D, 0x10]))])
    xfer(fd, [(0, bytes([0x00]) + struct.pack("<I", address))])
    xfer(fd, [(0, bytes([0x0C, 0x00]))])
    return xfer(fd, [(0, bytes([0x08])), (I2C_M_RD, bytes(4))])[1]
try:
    fd = os.open(BUS, os.O_RDWR)
except OSError as e:
    print("cannot open", BUS, e); sys.exit(1)
print("knock ok after", knock(fd), "burst retries")
regs = [(0x900000d0, "IC ID        (known positive: expect ..83112b)"),
        (0x10007F38, "charger/USB noise mode  (vendor: A55AA55A=cable in, 77887788=out)"),
        (0x10007088, "idle mode switch        (vendor: 17=off, 1F=on)"),
        (0x10007F40, "FW version              (vendor read_FW_ver)"),
        (0x100072C0, "CID/config version      (vendor read_FW_ver)"),
        (0x10007F10, "SMWP flag"), (0x10007F14, "HSEN flag"),
        (0x10007004, "panel_ver=b0  fw_ver=b1b2  ic_id=b3   (vendor read_FW_ver)"),
        (0x10007084, "touch_cfg_ver=b2  display_cfg_ver=b3"),
        (0x10007000, "cid_maj=b2  cid_min=b3"),
        (0x900000E4, "FW status (vendor sense_on expects 0x0100)"),
        (0x900000A8, "FW status 2")]
for a, what in regs:
    b = rd4(fd, a)
    print(f"0x{a:08x}  bytes[0..3]={b.hex(' ')}  u32le=0x{struct.unpack('<I', b)[0]:08x}   {what}")
