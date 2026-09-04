#!/bin/sh
# #156 - does a periodic system wakeup re-arm the #142 stall?
#
# Gate 1 of docs/touch/142-i2c-stall.md is confounded: "longer idle" and "a 30 s
# watchdog tick fell inside the idle window" are the same variable in every arm
# measured so far. This holds the idle FIXED at 15 s and varies only whether
# fp3-usbnet-watchdog.timer runs.
#
# ☠️ PREDICTION, WRITTEN BEFORE THE RUN: both arms empty. In every screen-off
# run so far the fault fired once, on the first transaction after the arming
# event, and never again - 0 in 26158 subsequent probes across three runs, with
# the watchdog running throughout (~80 ticks). If the watchdog arm DOES produce
# stalls, that story is wrong and this run is the thing that says so.
#
# Interleaved in blocks so nothing drifts between the arms. The driver is
# unbound ONCE, at the start - re-unbinding between blocks would re-arm the
# fault and measure the artifact instead of the question.
set -u
BLOCKS=${BLOCKS:-5}; PER=${PER:-50}; IDLE=${IDLE:-15}
WD=fp3-usbnet-watchdog.timer

bus=$(for a in /sys/bus/i2c/devices/i2c-*; do
        case "$(readlink -f "$a")" in *78b7000*) basename "$a" | cut -d- -f2 ;; esac; done)
ts=$(for d in /sys/bus/i2c/devices/*-00*; do
        [ -r "$d/name" ] || continue
        [ "$(cat "$d/name")" = "hx83112b" ] && basename "$d"; done)
drv=$(basename "$(readlink "/sys/bus/i2c/devices/$ts/driver")")
DB=$(tr '\0' '\n' < /proc/$(pgrep -x phosh|head -1)/environ | grep DBUS_SESSION_BUS_ADDRESS= | cut -d= -f2-)
ss(){ su fp3 -c "DBUS_SESSION_BUS_ADDRESS='$DB' gdbus call --session --dest org.gnome.ScreenSaver --object-path /org/gnome/ScreenSaver --method org.gnome.ScreenSaver.SetActive $1" >/dev/null 2>&1; }

probe(){ python3 -c "
import fcntl,os,time
f=os.open('/dev/i2c-$bus',os.O_RDWR)
try:
    fcntl.ioctl(f,0x0706,0x50); t=time.monotonic()
    try: os.read(f,1); e=0
    except OSError as ex: e=ex.errno
    print('%.4f %d'%(time.monotonic()-t,e))
finally: os.close(f)"; }

echo "=== #156 watchdog A/B, started $(date '+%F %T')"
echo "uptime $(cut -d. -f1 /proc/uptime)s, suspends $(cat /sys/power/suspend_stats/success)"
ss true; sleep 3
echo "screen dpms=$(cat /sys/class/drm/card0/card0-DSI-1/dpms)"
echo "$ts" > "/sys/bus/i2c/drivers/$drv/unbind" 2>/dev/null; sleep 2
[ -e "/sys/bus/i2c/devices/$ts/driver" ] && { echo "FATAL: unbind failed"; ss false; exit 1; }
echo "driver unbound once; no further unbind until the end"

# burn off the arming hang so it is not counted in either arm
sleep "$IDLE"; r=$(probe); echo "arming probe (DISCARDED): ${r% *}s errno ${r#* }"

on_hit=0; on_n=0; off_hit=0; off_n=0; b=1
while [ "$b" -le "$BLOCKS" ]; do
  for arm in WD-ON WD-OFF; do
    if [ "$arm" = WD-ON ]; then systemctl start "$WD" 2>/dev/null; else systemctl stop "$WD" 2>/dev/null; fi
    sleep 2
    act=$(systemctl show -p ActiveState --value "$WD" 2>/dev/null)
    want=$( [ "$arm" = WD-ON ] && echo active || echo inactive )
    [ "$act" = "$want" ] || { echo "block $b $arm: SKIPPED - timer is $act, wanted $want"; continue; }
    h=0; n=0
    while [ "$n" -lt "$PER" ]; do
      sleep "$IDLE"
      r=$(probe); d=${r% *}
      case "$d" in [1-9]*) h=$((h+1)); echo "$(date '+%T') block $b $arm probe $n: ${d}s  >>> STALL" ;; esac
      n=$((n+1))
    done
    echo "block $b $arm: $h stalls in $n probes (screen $(cat /sys/class/drm/card0/card0-DSI-1/dpms))"
    if [ "$arm" = WD-ON ]; then on_hit=$((on_hit+h)); on_n=$((on_n+n));
    else off_hit=$((off_hit+h)); off_n=$((off_n+n)); fi
  done
  b=$((b+1))
done

systemctl start "$WD" 2>/dev/null
echo
echo "=== result: WD-ON $on_hit/$on_n   WD-OFF $off_hit/$off_n   (idle ${IDLE}s, screen off, arming probe discarded)"
echo "=== restoring (screen on first) ==="
ss false; sleep 2
ok=no
for t in 1 2 3; do echo "$ts" > "/sys/bus/i2c/drivers/$drv/bind" 2>/dev/null; sleep 4
    [ -e "/sys/bus/i2c/devices/$ts/driver" ] && { ok=yes; break; }; done
[ "$ok" = yes ] && echo "RESTORE VERIFIED: $(readlink /sys/bus/i2c/devices/$ts/driver | sed 's|.*/||')" \
  || { echo "RESTORE FAILED - arming reboot"; systemd-run --collect --on-active=5 --unit=fp3-142-recover8 /sbin/reboot; }
echo "watchdog timer left $(systemctl show -p ActiveState --value $WD 2>/dev/null)"
echo "=== done $(date '+%F %T')"
