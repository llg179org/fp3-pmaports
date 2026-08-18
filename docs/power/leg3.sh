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

# Ride it down under load. At idle this stretch is 4.34 V to 4.03 V at about
# 130 mA, which is the best part of seven hours before the leg can even start;
# eight busy cores do it in rather less. The load is only for the descent - it
# is stopped before anything is measured.
#
# ☠️ That heat has to come back out before the first sample, or the settle
# slope is a cooling curve. SETTLE_OFF is doubled to 1800 s for this leg for
# that reason, and the settle rows in the log are what say whether it was
# enough - read them, do not assume.
load_start() {
	_n=$(nproc 2>/dev/null || echo 4)
	_i=0
	while [ "$_i" -lt "$_n" ]; do
		( while :; do :; done ) &
		echo $! >> /run/leg3-load.pids
		_i=$((_i + 1))
	done
	say "load started on $_n cores"
}

load_stop() {
	[ -f /run/leg3-load.pids ] || return 0
	while read -r pid; do kill "$pid" 2>/dev/null; done < /run/leg3-load.pids
	rm -f /run/leg3-load.pids
	say "load stopped"
}

rm -f /run/leg3-load.pids
load_start
trap 'load_stop; restore' EXIT INT TERM

# ☠️ NEVER TEST THE THRESHOLD UNDER LOAD. Measured 2026-08-18: eight busy
# cores pull the terminal voltage down by about 360 mV, so the first check
# read 3.954 V against a 4.030 V target defined for a resting pack, declared
# the target reached after sixty seconds, and handed a leg to the slope
# instrument at 4.238 V - deep in the steep region the whole exercise exists
# to avoid. Shed the load and let it recover before every comparison.
while :; do
	load_stop
	sleep 30
	v=$(cat "$BATT/voltage_now")
	say "rested v=$v t=$(cat $BATT/temp 2>/dev/null) xo=$(sed -n 's/^[[:space:]]*XO shutdown count[[:space:]]*:[[:space:]]*//p' /sys/kernel/debug/qcom_rpm_master_stats/APSS 2>/dev/null | head -1)"
	[ "$v" -le "$TARGET" ] && { say "reached target v=$v"; break; }
	[ "$v" -le "$FLOOR" ] && { say "ABORT: below floor at v=$v"; exit 1; }
	load_start
	sleep 90
done
say "cooling before the leg; temp=$(cat $BATT/temp 2>/dev/null)"

say "launching slope leg"
/root/suspend-slope.sh "$TAG" 900 6 1800
say "slope leg exited rc=$? v=$(cat $BATT/voltage_now)"
restore
say "done"
