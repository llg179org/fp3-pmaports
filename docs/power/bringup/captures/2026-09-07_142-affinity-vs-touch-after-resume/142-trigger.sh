#!/bin/sh
# #142 - the reliable trigger, A/B'd against the screen.
#
# THE TRIGGER: the first i2c transaction after the touch driver is unbound.
# Measured 2026-09-04 across the day: 4 of 4 short-spacing runs stalled on that
# transaction for ~15 s with -110, versus 0 of 52 688 ordinary transactions.
# It was dismissed as an artifact and discarded as burn-in; it is in fact the
# only thing all day that produced the fault on demand, so it is the instrument.
#
# THE QUESTION: does the screen state gate it? The one run with the screen ON
# did not stall AND rebound on the first attempt, where five screen-off runs
# stalled and failed to rebind at all. That is one observation each - this
# turns it into 5 v 5, interleaved so nothing drifts between the arms.
#
# ☠️ The rebind is ALWAYS done with the screen ON. With it off the Himax probe
# returns -5 and the phone is left without a touchscreen (five reboots today).
set -u
PER=${PER:-5}
BLANK=${BLANK:-12}

bus=$(for a in /sys/bus/i2c/devices/i2c-*; do
        case "$(readlink -f "$a")" in *78b7000*) basename "$a" | cut -d- -f2 ;; esac
      done)
ts=$(for d in /sys/bus/i2c/devices/*-00*; do
        [ -r "$d/name" ] || continue
        [ "$(cat "$d/name")" = "hx83112b" ] && basename "$d"
     done)
[ -n "$bus" ] && [ -n "$ts" ] || { echo "FATAL: bus/device not found"; exit 1; }
[ -e "/sys/bus/i2c/devices/$ts/driver" ] || { echo "FATAL: driver not bound at start"; exit 1; }
drv=$(basename "$(readlink "/sys/bus/i2c/devices/$ts/driver")")

DB=$(tr '\0' '\n' < /proc/$(pgrep -x phosh | head -1)/environ 2>/dev/null | grep '^DBUS_SESSION_BUS_ADDRESS=' | cut -d= -f2-)
[ -n "$DB" ] || { echo "FATAL: no phosh session bus"; exit 1; }
ss() { su fp3 -c "DBUS_SESSION_BUS_ADDRESS='$DB' gdbus call --session --dest org.gnome.ScreenSaver --object-path /org/gnome/ScreenSaver --method org.gnome.ScreenSaver.SetActive $1" >/dev/null 2>&1; }
scr(){ cat /sys/class/drm/card0/card0-DSI-1/dpms 2>/dev/null; }

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

echo "=== #142 trigger A/B: unbind-then-probe, screen OFF vs ON, $PER each"
echo "=== started $(date '+%F %T'); bus i2c-$bus, device $ts, driver $drv"
echo
off_hit=0; on_hit=0; i=1
while [ "$i" -le "$PER" ]; do
  for arm in OFF ON; do
    if [ "$arm" = OFF ]; then ss true; else ss false; fi
    sleep 2
    got=$(scr)
    want=$( [ "$arm" = OFF ] && echo Off || echo On )
    if [ "$got" != "$want" ]; then
        echo "round $i $arm: SKIPPED - screen is $got, wanted $want"
        continue
    fi
    sleep "$BLANK"
    echo "$ts" > "/sys/bus/i2c/drivers/$drv/unbind" 2>/dev/null
    sleep 2
    if [ -e "/sys/bus/i2c/devices/$ts/driver" ]; then
        echo "round $i $arm: unbind FAILED - skipping"; continue
    fi
    r=$(probe); d=${r% *}; e=${r#* }
    case "$d" in [1-9]*) mark=">>> STALL";
        [ "$arm" = OFF ] && off_hit=$((off_hit+1)) || on_hit=$((on_hit+1)) ;;
      *) mark="ok" ;;
    esac
    printf "round %d %-3s screen=%-3s  first transaction after unbind: %9.4f s errno %s  %s\n" \
           "$i" "$arm" "$got" "$d" "$e" "$mark"

    # ☠️ always rebind with the screen ON - it is the only state it works in
    ss false; sleep 2
    ok=no
    for try in 1 2 3; do
        echo "$ts" > "/sys/bus/i2c/drivers/$drv/bind" 2>/dev/null
        sleep 4
        [ -e "/sys/bus/i2c/devices/$ts/driver" ] && { ok=yes; break; }
    done
    [ "$ok" = yes ] || { echo "   ☠️ REBIND FAILED after 3 tries - arming reboot"; \
        systemd-run --collect --on-active=5 --unit=fp3-142-recover5 /sbin/reboot; exit 1; }
  done
  i=$((i+1))
done

echo
echo "=== result ==="
echo "screen OFF: $off_hit / $PER stalled on the first transaction after unbind"
echo "screen ON : $on_hit / $PER stalled"
echo "touch driver now: $(basename "$(readlink /sys/bus/i2c/devices/$ts/driver 2>/dev/null)" 2>/dev/null || echo NONE)"
echo "=== done $(date '+%F %T') ==="
