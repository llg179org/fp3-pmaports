#!/usr/bin/env python3
"""Trap the aw8898 death (~24 s after boot) with ftrace armed.

Arms regulator/gpio/clk/RPM-vote/workqueue trace events from early boot, polls
the amp bus-direct every 0.1 s, and on the first NAK stops tracing immediately
and dumps the buffer plus gpio/regulator state.  The question it answers: does
the *kernel* touch any regulator, gpio, clock or RPM vote at the death instant,
and which workqueue item fired just before it.

Run as root from an early systemd unit (the death predates sshd).
Output: /home/fp3/awdeath/<n>/
"""
import fcntl, os, time, glob, shutil

T = "/sys/kernel/tracing"
OUTBASE = "/home/fp3/awdeath"
I2C_SLAVE_FORCE, ADDR = 0x0706, 0x34

os.makedirs(OUTBASE, exist_ok=True)
run = 1 + max([0] + [int(os.path.basename(d)) for d in glob.glob(OUTBASE + "/[0-9]*") if os.path.basename(d).isdigit()])
OUT = f"{OUTBASE}/{run}"
os.makedirs(OUT)
log = open(f"{OUT}/trap.log", "w", buffering=1)

def up():
    return float(open("/proc/uptime").read().split()[0])

def say(m):
    log.write(f"{up():8.2f} {m}\n")

def w(path, val):
    try:
        open(path, "w").write(val)
    except OSError as e:
        say(f"write {path} <- {val!r} failed: {e}")

# --- arm tracing ---------------------------------------------------------
w(f"{T}/tracing_on", "0")
w(f"{T}/trace", "")            # clear
w(f"{T}/buffer_size_kb", "16384")
EVENTS = [
    "regulator", "gpio", "qcom_smd_rpm",
]
for ev in EVENTS:
    w(f"{T}/events/{ev}/enable", "1")
for ev in ["clk/clk_disable", "clk/clk_unprepare", "clk/clk_disable_complete",
           "workqueue/workqueue_execute_start"]:
    w(f"{T}/events/{ev}/enable", "1")
w(f"{T}/tracing_on", "1")
say("tracing armed")

# --- wait for the amp ----------------------------------------------------
def bus():
    for d in sorted(os.listdir("/sys/bus/i2c/devices")):
        if d.endswith("-0034"):
            return int(d.split("-")[0])
    return None

n = bus()
while n is None and up() < 60:
    time.sleep(0.1)
    n = bus()
if n is None:
    say("amp never instantiated")
    raise SystemExit(1)
say(f"amp on i2c-{n}")
fd = os.open(f"/dev/i2c-{n}", os.O_RDWR)
fcntl.ioctl(fd, I2C_SLAVE_FORCE, ADDR)

def rd(reg):
    os.write(fd, bytes([reg]))
    b = os.read(fd, 2)
    return (b[0] << 8) | b[1]

def snap(name):
    with open(f"{OUT}/{name}", "w") as f:
        f.write(f"uptime={up()}\n")
        for src in ["/sys/kernel/debug/gpio",
                    "/sys/kernel/debug/regulator/regulator_summary"]:
            f.write(f"===== {src}\n")
            try:
                f.write(open(src).read())
            except OSError as e:
                f.write(f"unreadable: {e}\n")

# --- baseline snapshot once alive ---------------------------------------
alive = False
while up() < 60:
    try:
        c = rd(0x00)
        say(f"alive chipid=0x{c:04x}")
        alive = True
        break
    except OSError:
        time.sleep(0.1)
if not alive:
    say("amp never answered - died before we started?")
snap("before.txt")

# --- poll until death ----------------------------------------------------
last_ok = None
while up() < 180:
    try:
        rd(0x00)
        last_ok = up()
    except OSError as e:
        w(f"{T}/tracing_on", "0")
        say(f"DIED errno={e.errno} last_ok={last_ok}")
        break
    time.sleep(0.1)
else:
    w(f"{T}/tracing_on", "0")
    say(f"no death by 180 s, last_ok={last_ok}")

snap("after.txt")
with open(f"{OUT}/trace.txt", "w") as f:
    shutil.copyfileobj(open(f"{T}/trace"), f)
# dmesg tail for correlation
os.system(f"dmesg | tail -100 > {OUT}/dmesg-tail.txt")
say("done")
