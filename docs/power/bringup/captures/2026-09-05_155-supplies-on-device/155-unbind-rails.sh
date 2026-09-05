#!/bin/sh
# Does unbinding the driver release the rails it now holds?
#
# This decides whether 142-trigger.sh can test the supply fix at all. That
# reproducer unbinds before probing; if unbind releases the supplies, the
# reproducer recreates the pre-fix rail state and a stall there says nothing
# about the fix.
#
# ☠️ Screen stays ON throughout. Unbind with the screen OFF leaves the Himax
# probe returning -5 and the phone without a touchscreen (five reboots on
# 2026-09-04). Unbind + screen ON is the documented safe arm (0/7 stalls).
set -e
SUM=/sys/kernel/debug/regulator/regulator_summary
ts=$(for d in /sys/bus/i2c/devices/*-00*; do
        [ -r "$d/name" ] || continue
        [ "$(cat "$d/name")" = hx83112b ] && basename "$d"
     done; true)
[ -n "$ts" ] || { echo "FATAL: no hx83112b"; exit 1; }
drv=$(basename "$(readlink "/sys/bus/i2c/devices/$ts/driver")")
echo "touchscreen $ts, driver $drv"
echo "screen dpms=$(cat /sys/class/drm/card0/card0-DSI-1/dpms 2>/dev/null)  (must be On)"

rails() { grep -E "^ *(l6|l10) |$ts-iovcc|$ts-vdda|dsi\.0-iovcc" "$SUM" | sed 's/^/   /'; }

echo "=== BOUND ==="; rails
echo "$ts" > "/sys/bus/i2c/drivers/$drv/unbind"; sleep 2
echo "=== UNBOUND ==="; rails
echo "$ts" > "/sys/bus/i2c/drivers/$drv/bind"; sleep 4
echo "=== REBOUND ==="; rails
echo "restore check: driver=$(basename "$(readlink "/sys/bus/i2c/devices/$ts/driver" 2>/dev/null)" 2>/dev/null || echo NONE)"
