#!/bin/sh
# #142 - the rate-matched probe again, but with the SCREEN ON.
#
# The screen-off twin (16:43, unit fp3-142-rate50) produced 0 stalls in 26040
# transactions at 43.4/s, where the operator's own session gave one per ~8000.
# Two explanations survived that null and it could not separate them:
#   (a) an unused-address probe does not sample what the driver's reads sample
#   (b) the screen being off suppresses the fault
# This run changes ONLY the screen. Same address, same rate, same duration.
set -u
DUR=600
echo "=== rate-matched probe, SCREEN ON, started $(date '+%F %T') ==="

scr() { echo "bl_power=$(cat /sys/class/backlight/*/bl_power 2>/dev/null) bright=$(cat /sys/class/backlight/*/actual_brightness 2>/dev/null) dpms=$(cat /sys/class/drm/card0/card0-DSI-1/dpms 2>/dev/null)"; }
echo "screen at start: $(scr)"
case "$(scr)" in *"dpms=On"*) ;; *) echo "FATAL: screen is not on - refusing to run the ON arm"; exit 1;; esac

ts=$(for d in /sys/bus/i2c/devices/*-00*; do
        [ -r "$d/name" ] || continue
        [ "$(cat "$d/name")" = "hx83112b" ] && basename "$d"
     done)
[ -n "$ts" ] || { echo "FATAL: no hx83112b found"; exit 1; }
drv=$(basename "$(readlink "/sys/bus/i2c/devices/$ts/driver")")
echo "touchscreen $ts, driver $drv"
echo "$ts" > "/sys/bus/i2c/drivers/$drv/unbind" 2>/dev/null
sleep 2
[ -e "/sys/bus/i2c/devices/$ts/driver" ] && { echo "FATAL: unbind failed"; exit 1; }
echo "driver unbound"

# ☠️ Sample the screen throughout. Without this the arm's label is an assumption:
# phosh could blank it midway and the run would still be reported as "screen on".
( while :; do echo "   [screen] $(date '+%T') $(scr)"; sleep 30; done ) &
sampler=$!
trap 'kill $sampler 2>/dev/null' EXIT INT TERM

echo "--- burn-in (discarded): the trial-0 unbind artifact, 4/4 so far"
python3 /home/fp3/142-intervals.py 78b7000 0x50 0.02 20 "BURN-IN (discarded)"
echo "--- the measurement: ~50 transactions/s for ${DUR}s, screen ON"
python3 /home/fp3/142-intervals.py 78b7000 0x50 0.02 "$DUR" "RATE50-SCREEN-ON"

kill $sampler 2>/dev/null
echo "screen at end: $(scr)"
echo "=== restoring ==="
ok=no
for try in 1 2 3; do
    echo "$ts" > "/sys/bus/i2c/drivers/$drv/bind" 2>/dev/null
    sleep 4
    [ -e "/sys/bus/i2c/devices/$ts/driver" ] && { ok=yes; break; }
    echo "   bind attempt $try failed"
done
if [ "$ok" = yes ]; then
    echo "RESTORE VERIFIED: $(readlink /sys/bus/i2c/devices/$ts/driver | sed 's|.*/||')"
else
    echo "RESTORE FAILED - arming a reboot in its own unit"
    systemd-run --collect --on-active=5 --unit=fp3-142-recover4 /sbin/reboot
fi
echo "=== done $(date '+%F %T') ==="
