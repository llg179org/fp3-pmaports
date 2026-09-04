#!/bin/sh
# #142 - the reproducer, built from the operator's own observation:
#   power button off -> power button on -> the next touch stalls 15 s.
#
# ☠️ WHAT IS DIFFERENT FROM EVERY EARLIER RUN TODAY, and why those all measured
# nothing (0 stalls in 52 688 transactions):
#
#  1. THE DRIVER STAYS BOUND. Every earlier run began by unbinding it. If the
#     vulnerable state accumulates - a pad configuration lost behind Linux's
#     back, a stale pinctrl, a genpd cache - then the unbind destroyed it
#     before each measurement. It also cost five reboots, because the Himax
#     probe fails with -5 while the screen is off.
#  2. IT CYCLES THE SCREEN instead of hammering the bus. The i2c controller
#     CANNOT be the thing that suspends during continuous tapping: 12.6 touch
#     interrupts/s leaves 79 ms gaps and the autosuspend delay is 1000 ms.
#     What does cycle at that timescale is CPU/cluster power collapse
#     (cpuidle state1 'cpu-power-colla', usage in the hundreds of thousands),
#     which is what arm,psci-suspend-param on system-pc changes.
#  3. THE DENOMINATOR IS THE SCREEN CYCLE, not the transaction and not the
#     second. Both of those were fitted this afternoon and both are suspect.
#
# The probe goes to 0x50 (no device) so it cannot disturb the bound driver's
# register state; the i2c core serialises transfers on the adapter lock, so a
# single probe per cycle cannot collide with it either.
set -u
CYCLES=${CYCLES:-10}
BLANK=${BLANK:-12}          # seconds with the screen off, long enough for deep idle

BUS_PLAT=78b7000
bus=$(for a in /sys/bus/i2c/devices/i2c-*; do
        case "$(readlink -f "$a")" in *"$BUS_PLAT"*) basename "$a" | cut -d- -f2 ;; esac
      done)
[ -n "$bus" ] || { echo "FATAL: no i2c bus for $BUS_PLAT"; exit 1; }
ts=$(for d in /sys/bus/i2c/devices/*-00*; do
        [ -r "$d/name" ] || continue
        [ "$(cat "$d/name")" = "hx83112b" ] && basename "$d"
     done)
[ -n "$ts" ] || { echo "FATAL: no hx83112b"; exit 1; }
[ -e "/sys/bus/i2c/devices/$ts/driver" ] || { echo "FATAL: driver NOT bound - this test needs it bound"; exit 1; }

scr()  { cat /sys/class/drm/card0/card0-DSI-1/dpms 2>/dev/null; }
pc()   { awk '{s+=$1} END{print s}' /sys/devices/system/cpu/cpu*/cpuidle/state1/usage 2>/dev/null; }
e110() { dmesg 2>/dev/null | grep -c 'Failed to read input event: -110'; }

DB=$(tr '\0' '\n' < /proc/$(pgrep -x phosh | head -1)/environ 2>/dev/null | grep '^DBUS_SESSION_BUS_ADDRESS=' | cut -d= -f2-)
[ -n "$DB" ] || { echo "FATAL: no phosh session bus"; exit 1; }
ss() { su fp3 -c "DBUS_SESSION_BUS_ADDRESS='$DB' gdbus call --session --dest org.gnome.ScreenSaver --object-path /org/gnome/ScreenSaver --method org.gnome.ScreenSaver.SetActive $1" >/dev/null 2>&1; }

echo "=== #142 reproducer: $CYCLES screen off/on cycles, ${BLANK}s blank"
echo "=== started $(date '+%F %T'); bus i2c-$bus, touchscreen $ts, driver BOUND"
echo "=== TAP THE SCREEN once after each 'screen ON' line if you are nearby -"
echo "=== a driver -110 is the strongest evidence; the probe is the fallback."
echo
hits=0; drv_hits=0; base110=$(e110)
i=1
while [ "$i" -le "$CYCLES" ]; do
    ss true;  sleep 2
    off_pc=$(pc); off_110=$(e110)
    echo "cycle $i: screen OFF ($(scr)) at $(date '+%T'), blanking ${BLANK}s"
    sleep "$BLANK"
    ss false; sleep 1
    on_pc=$(pc)
    echo "cycle $i: screen ON  ($(scr)) at $(date '+%T')  cpu-pc exits during blank: $((on_pc - off_pc))"

    d=$(python3 -c "
import fcntl,os,time,errno,sys
f=os.open('/dev/i2c-$bus',os.O_RDWR)
try:
    fcntl.ioctl(f,0x0706,0x50)
    t=time.monotonic()
    try: os.read(f,1); e=0
    except OSError as ex: e=ex.errno
    print('%.4f %d'%(time.monotonic()-t,e))
finally: os.close(f)")
    dur=${d% *}; err=${d#* }
    case "$dur" in [1-9]*) hits=$((hits+1)); echo "cycle $i:   >>> PROBE STALLED ${dur}s errno $err" ;;
                        *) echo "cycle $i:   probe ${dur}s errno $err" ;; esac

    sleep 6                                    # a window for a human tap
    now110=$(e110)
    if [ "$now110" -gt "$off_110" ]; then
        drv_hits=$((drv_hits+1))
        echo "cycle $i:   >>> DRIVER -110 (a real touch stalled): $off_110 -> $now110"
    fi
    i=$((i+1))
done

echo
echo "=== result after $CYCLES cycles ==="
echo "probe stalls  : $hits / $CYCLES"
echo "driver -110   : $drv_hits / $CYCLES   (needs a finger; 0 here means nobody tapped)"
echo "dmesg -110    : $base110 -> $(e110)"
echo "touch driver  : $(basename "$(readlink /sys/bus/i2c/devices/$ts/driver 2>/dev/null)" 2>/dev/null || echo NONE)"
echo "=== done $(date '+%F %T') ==="
