#!/bin/sh
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Does zeroing the sleep-set XO vote save any current?
#
# The A leg of an A/B. This one runs with clk_smd_rpm.xo_sleep_off=1 on the
# command line, under which the application processor shuts the crystal down
# constantly instead of never. The control is the same script with the
# parameter absent, which is the plain postmarketOS boot label.
#
# ☠️ It refuses to run without the parameter, because a leg that cannot say
# which side of the A/B it is measuring is worth nothing. The tag is written
# into every sample line, but the tag is a promise; the parameter is the fact.
#
# ☠️ The pack has to be in the flat part of the discharge curve before phase A
# starts, or the two phases sit on different slopes - that is what withdrew the
# leg of 2026-08-17.
set -u
BATT=/sys/class/power_supply/pmi632-battery
CHG=/sys/class/power_supply/pmi632-charger
LOG=/var/log/leg3-20260818.txt
PARAM=/sys/module/clk_smd_rpm/parameters/xo_sleep_off
TARGET=4030000
FLOOR=3800000
TAG=xo-on-20260818

say() { echo "$(cut -d. -f1 /proc/uptime) leg3: $*" >> "$LOG"; }
restore() { echo Charging > "$CHG/status" 2>/dev/null; }
trap restore EXIT INT TERM

p=$(cat "$PARAM" 2>/dev/null || echo "<absent>")
say "start v=$(cat $BATT/voltage_now) cap=$(cat $BATT/capacity)% xo_sleep_off=$p"
if [ "$p" != Y ] && [ "$p" != 1 ]; then
	say "ABORT: xo_sleep_off is '$p', this is not the A leg"
	exit 1
fi

systemctl stop greetd 2>/dev/null
i=0
while [ "$i" -lt 15 ]; do
	for fb in /sys/class/graphics/fb*/blank; do [ -w "$fb" ] && echo 4 > "$fb"; done
	sleep 2
	[ "$(cat /sys/class/drm/card0/card0-DSI-1/dpms 2>/dev/null)" = Off ] && break
	i=$((i + 1))
done
say "dpms=$(cat /sys/class/drm/card0/card0-DSI-1/dpms 2>/dev/null)"

echo Unknown > "$CHG/status"
sleep 10
say "off VBUS online=$(cat $CHG/online) status=$(cat $BATT/status)"

while :; do
	v=$(cat "$BATT/voltage_now")
	[ "$v" -le "$TARGET" ] && { say "reached target v=$v"; break; }
	[ "$v" -le "$FLOOR" ] && { say "ABORT: below floor at v=$v"; exit 1; }
	say "discharging v=$v i=$(cat $BATT/current_now) xo=$(sed -n 's/^[[:space:]]*XO shutdown count[[:space:]]*:[[:space:]]*//p' /sys/kernel/debug/qcom_rpm_master_stats/APSS 2>/dev/null | head -1)"
	sleep 300
done

say "launching slope leg"
/root/suspend-slope.sh "$TAG" 900 6
say "slope leg exited rc=$? v=$(cat $BATT/voltage_now)"
restore
say "done"
