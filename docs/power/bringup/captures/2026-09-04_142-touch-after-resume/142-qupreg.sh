#!/bin/sh
# #142 - what the QUP registers say during the 15 s hang.
set -u
P=/home/fp3/142-qupreg.py
RT=/sys/devices/platform/soc@0/78b7000.i2c/power/runtime_status
bus=$(for a in /sys/bus/i2c/devices/i2c-*; do
        case "$(readlink -f "$a")" in *78b7000*) basename "$a" | cut -d- -f2 ;; esac; done)
ts=$(for d in /sys/bus/i2c/devices/*-00*; do
        [ -r "$d/name" ] || continue
        [ "$(cat "$d/name")" = "hx83112b" ] && basename "$d"; done)
drv=$(basename "$(readlink "/sys/bus/i2c/devices/$ts/driver")")
DB=$(tr '\0' '\n' < /proc/$(pgrep -x phosh|head -1)/environ | grep DBUS_SESSION_BUS_ADDRESS= | cut -d= -f2-)
ss(){ su fp3 -c "DBUS_SESSION_BUS_ADDRESS='$DB' gdbus call --session --dest org.gnome.ScreenSaver --object-path /org/gnome/ScreenSaver --method org.gnome.ScreenSaver.SetActive $1" >/dev/null 2>&1; }

probe() { python3 -c "
import fcntl,os,time
f=os.open('/dev/i2c-$bus',os.O_RDWR)
try:
    fcntl.ioctl(f,0x0706,$1); t=time.monotonic()
    try: os.read(f,1); e=0
    except OSError as ex: e=ex.errno
    print('  probe 0x%02x: %.4f s errno %d'%($1,time.monotonic()-t,e))
finally: os.close(f)"; }

echo "=== QUP register capture, $(date '+%F %T'); bus i2c-$bus, device $ts"

# ---- arm 1: a HEALTHY transfer, screen ON. The known answer, so the sampler
# has to reproduce something already on record before its stall output counts.
ss false; sleep 3
echo "--- ARM HEALTHY (screen $(cat /sys/class/drm/card0/card0-DSI-1/dpms), driver bound)"
python3 "$P" 078b7000 "$RT" 12 &
s=$!; sleep 1
probe 0x50
wait $s

# ---- arm 2: the hang. screen OFF + unbind, which has stalled 7/7.
echo
ss true; sleep 3
echo "--- ARM HUNG (screen $(cat /sys/class/drm/card0/card0-DSI-1/dpms))"
echo "$ts" > "/sys/bus/i2c/drivers/$drv/unbind" 2>/dev/null; sleep 2
[ -e "/sys/bus/i2c/devices/$ts/driver" ] && { echo "FATAL: unbind failed"; ss false; exit 1; }
python3 "$P" 078b7000 "$RT" 25 &
s=$!; sleep 1
probe 0x50
wait $s

echo
echo "=== restoring (screen on first - the only state the rebind works in) ==="
ss false; sleep 2
ok=no
for t in 1 2 3; do echo "$ts" > "/sys/bus/i2c/drivers/$drv/bind" 2>/dev/null; sleep 4
    [ -e "/sys/bus/i2c/devices/$ts/driver" ] && { ok=yes; break; }; done
[ "$ok" = yes ] && echo "RESTORE VERIFIED: $(readlink /sys/bus/i2c/devices/$ts/driver | sed 's|.*/||')" \
  || { echo "RESTORE FAILED - arming reboot"; systemd-run --collect --on-active=5 --unit=fp3-142-recover7 /sbin/reboot; }
echo "=== done $(date '+%F %T')"
