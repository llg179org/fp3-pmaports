#!/bin/sh
# FULLY AUTOMATED: is the touch bus healthy in the moments right after resume?
#
# The operator's fault (2026-09-06): power button off, power button on, and then
# the first taps are dropped - a PIN digit not taken, digits missing in the
# calculator. Screen-off then screen-on is the gate; the loss is in the first
# seconds after the screen returns.
#
# ☠️ THE METHOD IS THE ONE THAT CAUGHT THE 15 SECOND STALL, not a synthetic
# touch. 142-trigger.sh established that "the first i2c transaction after the
# touch driver is unbound" provokes the fault on demand, and that the SCREEN
# STATE gates it: 5/5 stalls with the screen off, 0/5 with it on. A uinput
# injector is NOT that method and would prove nothing - it delivers events
# straight into the input layer, bypassing the controller and the bus.
#
# ☠️ WHAT IS NEW HERE. 142-trigger.sh probes WHILE the screen is off. This probes
# right AFTER it comes back, at several delays, which is the regime the operator
# actually hits and which nothing has sampled. The screen-on arm of the old
# script is not the same thing: it never had a blank before it.
#
# ☠️ The rebind is ALWAYS done with the screen ON - with it off the Himax probe
# returns -5 and the phone is left without a touchscreen (five reboots, 2026-09-04).
# Here the screen is on by construction at that point, which is why this shape is
# safe where probing during the blank is not.
set -u
ROUNDS=${ROUNDS:-4}
BLANK=${BLANK:-20}                 # >= the measured ~10 s idle gate
DELAYS=${DELAYS:-"0 1 3 10"}       # seconds after unblank, probed in order

bus=$(for a in /sys/bus/i2c/devices/i2c-*; do
        case "$(readlink -f "$a")" in *78b7000*) basename "$a" | cut -d- -f2 ;; esac
      done)
ts=$(for d in /sys/bus/i2c/devices/*-00*; do
        [ -r "$d/name" ] || continue
        [ "$(cat "$d/name")" = hx83112b ] && basename "$d"
     done)
[ -n "$bus" ] && [ -n "$ts" ] || { echo "FATAL: bus/device not found"; exit 1; }
[ -e "/sys/bus/i2c/devices/$ts/driver" ] || { echo "FATAL: driver not bound at start"; exit 1; }
drv=$(basename "$(readlink "/sys/bus/i2c/devices/$ts/driver")")

DB=$(tr '\0' '\n' < /proc/$(pgrep -x phosh | head -1)/environ 2>/dev/null |
     grep '^DBUS_SESSION_BUS_ADDRESS=' | cut -d= -f2-)
[ -n "$DB" ] || { echo "FATAL: no phosh session bus"; exit 1; }
scr()  { cat /sys/class/drm/card0/card0-DSI-1/dpms 2>/dev/null; }
ss()   { su fp3 -c "DBUS_SESSION_BUS_ADDRESS='$DB' gdbus call --session \
           --dest org.gnome.ScreenSaver --object-path /org/gnome/ScreenSaver \
           --method org.gnome.ScreenSaver.SetActive $1" >/dev/null 2>&1; }

probe() {   # one transaction on the touch bus to an address with no device
    python3 -c "
import fcntl,os,time
f=os.open('/dev/i2c-$bus',os.O_RDWR)
try:
    fcntl.ioctl(f,0x0706,0x50)
    t=time.monotonic()
    try: os.read(f,1); e=0
    except OSError as ex: e=ex.errno
    print('%.4f %d'%(time.monotonic()-t,e))
finally: os.close(f)"
}
kerr() { journalctl -k -b -o cat --no-pager 2>/dev/null |
         grep -cE 'Failed to read input event|timed out, bus|Disabling IRQ|consecutive failed'; }

rebind() {
    ok=no
    for try in 1 2 3; do
        echo "$ts" > "/sys/bus/i2c/drivers/$drv/bind" 2>/dev/null
        sleep 3
        [ -e "/sys/bus/i2c/devices/$ts/driver" ] && { ok=yes; break; }
    done
    [ "$ok" = yes ] || { echo "   ☠️ REBIND FAILED after 3 tries - arming reboot"
        systemd-run --collect --on-active=5 --unit=fp3-resume-recover /sbin/reboot; exit 1; }
}

echo "=== resume-probe: i2c health right after the screen comes back"
echo "=== $(date '+%F %T'); bus i2c-$bus, device $ts, driver $drv"
echo "=== $ROUNDS rounds, blank ${BLANK}s, probe delays: $DELAYS s"
echo
printf '%-3s %-8s %-6s %6s %10s %6s %s\n' rnd arm screen delay seconds errno verdict

r=1; stall_resume=0; stall_ctl=0; n_resume=0; n_ctl=0
while [ "$r" -le "$ROUNDS" ]; do
  for arm in RESUME CONTROL; do
    if [ "$arm" = RESUME ]; then ss true; else ss false; fi
    sleep 3
    mid=$(scr); want=$( [ "$arm" = RESUME ] && echo Off || echo On )
    if [ "$mid" != "$want" ]; then
        printf '%-3s %-8s %-6s %6s %10s %6s %s\n' "$r" "$arm" "$mid" - - - "SKIP wanted=$want"
        [ "$arm" = RESUME ] && ss false
        continue
    fi
    sleep $((BLANK - 3))
    [ "$arm" = RESUME ] && ss false
    sleep 1                                    # the screen is ON from here on

    for d in $DELAYS; do
        [ "$d" -gt 0 ] && sleep "$d"
        e0=$(kerr)
        echo "$ts" > "/sys/bus/i2c/drivers/$drv/unbind" 2>/dev/null
        sleep 1
        if [ -e "/sys/bus/i2c/devices/$ts/driver" ]; then
            printf '%-3s %-8s %-6s %6s %10s %6s %s\n' "$r" "$arm" "$(scr)" "$d" - - "unbind FAILED"
            continue
        fi
        res=$(probe); dur=${res% *}; err=${res#* }
        rebind
        de=$((`kerr` - e0))
        case "$dur" in
        [1-9]*) v=">>> STALL"
                if [ "$arm" = RESUME ]; then stall_resume=$((stall_resume+1)); else stall_ctl=$((stall_ctl+1)); fi ;;
        *)      v="ok" ;;
        esac
        [ "$arm" = RESUME ] && n_resume=$((n_resume+1)) || n_ctl=$((n_ctl+1))
        [ "$de" -gt 0 ] && v="$v  (+$de kernel errors)"
        printf '%-3s %-8s %-6s %6s %10s %6s %s\n' "$r" "$arm" "$(scr)" "$d" "$dur" "$err" "$v"
    done
  done
  r=$((r + 1))
done

echo
echo "=== result ==="
echo "after resume: $stall_resume / $n_resume probes stalled"
echo "control     : $stall_ctl / $n_ctl probes stalled"
echo "touch driver now: $(basename "$(readlink /sys/bus/i2c/devices/$ts/driver 2>/dev/null)" 2>/dev/null || echo NONE)"
echo "=== done $(date '+%F %T') ==="
