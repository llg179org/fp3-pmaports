#!/bin/sh
# #155 - does the touchscreen now HOLD its rails when the display goes down?
#
# ☠️ This is NOT 142-trigger.sh, deliberately. That reproducer unbinds the
# driver before probing, and devm_regulator_bulk_get_enable releases the
# supplies on unbind - so on a fixed kernel it recreates exactly the pre-fix
# rail state and cannot show the fix working either way. Running it and reading
# a stall as "the fix failed" would be measuring the wrong thing.
#
# What this does instead is the measurement the root cause was FOUND with,
# with the driver BOUND, so the recorded pre-fix answer is the control:
#
#   pre-fix, 2026-09-04 (ROOTCAUSE-the-panel-owns-the-rail.md)
#     screen ON   l6 use=1  (only consumer 1a94000.dsi.0-iovcc)   l10 use=0, no consumer
#     screen OFF  l6 use=0  (that consumer released it)           l10 use=0
#
# The fix is working iff l6 keeps a non-zero use count with the screen OFF.
set -e
SUM=/sys/kernel/debug/regulator/regulator_summary
test -r "$SUM" || { echo "FATAL: no regulator_summary (CONFIG_DEBUG_FS?)"; exit 1; }

# ☠️ The trailing `true` is load-bearing under `set -e`: the loop's last
# iteration is a non-matching device, so the `for` exits non-zero, the command
# substitution inherits that, and the ASSIGNMENT fails - killing the script
# with no output at all. Measured here 2026-09-05: rc=1, both streams empty.
ts=$(for d in /sys/bus/i2c/devices/*-00*; do
        [ -r "$d/name" ] || continue
        [ "$(cat "$d/name")" = hx83112b ] && basename "$d"
     done; true)
[ -n "$ts" ] || { echo "FATAL: no hx83112b"; exit 1; }
[ -e "/sys/bus/i2c/devices/$ts/driver" ] || { echo "FATAL: driver NOT bound - this test requires it bound"; exit 1; }
echo "touchscreen $ts, driver $(basename "$(readlink "/sys/bus/i2c/devices/$ts/driver")"), BOUND"

DB=$(tr '\0' '\n' < "/proc/$(pgrep -x phosh | head -1)/environ" 2>/dev/null | grep '^DBUS_SESSION_BUS_ADDRESS=' | cut -d= -f2-)
[ -n "$DB" ] || { echo "FATAL: no phosh session bus"; exit 1; }
ss() { su fp3 -c "DBUS_SESSION_BUS_ADDRESS='$DB' gdbus call --session --dest org.gnome.ScreenSaver --object-path /org/gnome/ScreenSaver --method org.gnome.ScreenSaver.SetActive $1" >/dev/null 2>&1; }
scr(){ cat /sys/class/drm/card0/card0-DSI-1/dpms 2>/dev/null; }

rails() {   # print the l6/l10 lines and their consumers
	awk '/^ *l6 / || /^ *l10 / {print "   " $0; want=$1; next}
	     /iovcc|2-0048|3-0048|4-0048|dsi/ {print "     " $0}' "$SUM"
}

for arm in ON OFF ON; do
	case "$arm" in ON) ss false; want=On ;; OFF) ss true; want=Off ;; esac
	sleep 4
	got=$(scr)
	echo "=== screen $arm (dpms=$got) ==="
	[ "$got" = "$want" ] || echo "   ☠️ screen is $got, wanted $want - this arm is void"
	rails
done

# leave the screen on
ss false; sleep 2
echo "=== restored, dpms=$(scr) ==="
