#!/bin/sh
# #142 - replicate the productive regime: 60 probes at 15 s idle, screen off.
#
# This repeats the 14:29 "audio campaign" (60 probes, 15 s idle) which gave
# 1 stall, and which every later run failed to match because the probe rate was
# raised and the idle fell below the 3-10 s threshold.
#
# ☠️ Trial 0 is DISCARDED: the first transaction after an unbind with the screen
# off stalls 5/5 by itself (see TRIGGER-screen-gates-it.md). Counting it would
# guarantee a "hit" that says nothing about the regime under test.
set -u
N=${N:-60}; IDLE=${IDLE:-15}
bus=$(for a in /sys/bus/i2c/devices/i2c-*; do
        case "$(readlink -f "$a")" in *78b7000*) basename "$a" | cut -d- -f2 ;; esac; done)
ts=$(for d in /sys/bus/i2c/devices/*-00*; do
        [ -r "$d/name" ] || continue
        [ "$(cat "$d/name")" = "hx83112b" ] && basename "$d"; done)
drv=$(basename "$(readlink "/sys/bus/i2c/devices/$ts/driver")")
DB=$(tr '\0' '\n' < /proc/$(pgrep -x phosh|head -1)/environ | grep DBUS_SESSION_BUS_ADDRESS= | cut -d= -f2-)
ss(){ su fp3 -c "DBUS_SESSION_BUS_ADDRESS='$DB' gdbus call --session --dest org.gnome.ScreenSaver --object-path /org/gnome/ScreenSaver --method org.gnome.ScreenSaver.SetActive $1" >/dev/null 2>&1; }

echo "=== 15 s idle replication, $(date '+%F %T')"
echo "gate 3 evidence - boot age and suspends, the leg with one observation each way:"
echo "  uptime            $(cut -d. -f1 /proc/uptime) s"
echo "  suspend success   $(cat /sys/power/suspend_stats/success 2>/dev/null)"
echo "  boot              $(uptime -s 2>/dev/null)"
ss true; sleep 3
echo "  screen            dpms=$(cat /sys/class/drm/card0/card0-DSI-1/dpms)"
echo "$ts" > "/sys/bus/i2c/drivers/$drv/unbind" 2>/dev/null; sleep 2
[ -e "/sys/bus/i2c/devices/$ts/driver" ] && { echo "FATAL: unbind failed"; exit 1; }
echo "  driver unbound; $N probes at ${IDLE}s, trial 0 discarded"
echo

hits=0; n=0
while [ "$n" -lt "$N" ]; do
    sleep "$IDLE"
    r=$(python3 -c "
import fcntl,os,time
f=os.open('/dev/i2c-$bus',os.O_RDWR)
try:
    fcntl.ioctl(f,0x0706,0x50); t=time.monotonic()
    try: os.read(f,1); e=0
    except OSError as ex: e=ex.errno
    print('%.4f %d'%(time.monotonic()-t,e))
finally: os.close(f)")
    d=${r% *}; e=${r#* }
    case "$d" in [1-9]*)
        if [ "$n" = 0 ]; then
            echo "trial 0: ${d}s errno $e  -- DISCARDED (the known unbind artifact)"
        else
            hits=$((hits+1))
            echo "$(date '+%T') trial $n: ${d}s errno $e   >>> STALL ($hits so far)"
        fi ;;
    esac
    n=$((n+1))
done

echo
echo "=== result: $hits stalls in $((N-1)) counted probes at ${IDLE}s idle, screen off"
echo "=== the 14:29 run in the same regime gave 1 / 60"
ss false; sleep 2
ok=no
for t in 1 2 3; do echo "$ts" > "/sys/bus/i2c/drivers/$drv/bind" 2>/dev/null; sleep 4
    [ -e "/sys/bus/i2c/devices/$ts/driver" ] && { ok=yes; break; }; done
if [ "$ok" = yes ]; then echo "RESTORE VERIFIED: $(readlink /sys/bus/i2c/devices/$ts/driver | sed 's|.*/||')"
else echo "RESTORE FAILED - arming reboot"; systemd-run --collect --on-active=5 --unit=fp3-142-recover6 /sbin/reboot; fi
echo "=== done $(date '+%F %T')"
