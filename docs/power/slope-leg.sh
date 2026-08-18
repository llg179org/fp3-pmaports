#!/bin/sh
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# A slope leg with an arbitrary cut applied - the generalisation of leg3.sh and
# leg3-control.sh, which differed from each other only in a guard and a tag.
#
# Usage: slope-leg.sh <tag> [service ...]
#   tag        names the run: the log, the archived slope file, the samples
#   service    zero or more systemd units stopped for the whole leg, and
#              restarted on every exit path
#
# Examples:
#   slope-leg.sh baseline-20260819
#   slope-leg.sh nomodem-20260819 ModemManager rmtfs tqftpserv
#
# ☠️ The cut is applied AFTER the descent and BEFORE the slope instrument, so
# that phase A and phase B see exactly the same system. A cut applied halfway
# through would show up as a slope change in one phase and be read as a result.
#
# ☠️ The pack must be in the flat part of the discharge curve before phase A
# starts, or the two phases sit on different slopes - that is what withdrew the
# leg of 2026-08-17, and what still inflates every ratio taken since. Compare
# phase-A slopes BETWEEN legs; the derived mA is for scale only.
set -u

TAG=${1:?usage: slope-leg.sh <tag> [service ...]}
shift
CUTS="$*"

BATT=/sys/class/power_supply/pmi632-battery
CHG=/sys/class/power_supply/pmi632-charger
LOG=/var/log/slope-leg-$TAG.txt
SLOPE=/home/fp3/suspend-slope.txt
PIDS=/run/slope-leg-$TAG.pids
TARGET=4030000
FLOOR=3800000
START_MIN=4200000
START_CAP=99

say() { echo "$(cut -d. -f1 /proc/uptime) $TAG: $*" >> "$LOG"; }

# ☠️ USBIN suspend lives in the PMIC and survives a warm reboot; a leg that
# dies without restoring it leaves a phone that will not charge. The cut
# services come back on the same path, for the same reason.
restore() {
	echo Charging > "$CHG/status" 2>/dev/null
	for s in $CUTS; do systemctl start "$s" 2>/dev/null; done
	systemctl start greetd 2>/dev/null
}
trap restore EXIT INT TERM

v0=$(cat "$BATT/voltage_now")
c0=$(cat "$BATT/capacity")
say "start v=$v0 cap=$c0% cuts='${CUTS:-none}'"
say "kernel=$(uname -r) boot_id=$(cat /proc/sys/kernel/random/boot_id)"
say "cmdline=$(tr '\0' ' ' < /proc/cmdline)"

# ☠️ voltage_now is inflated while the charger is pushing, so it alone cannot
# say the pack is full; capacity is the second opinion. Legs that start from
# different amounts of charge cover different parts of the curve, and then the
# phases land in different places - the exact failure this guard exists for.
if [ "$v0" -lt "$START_MIN" ]; then
	say "ABORT: starting at $v0, below START_MIN=$START_MIN - charge first"
	exit 1
fi
if [ "$c0" -lt "$START_CAP" ]; then
	say "ABORT: capacity $c0% below START_CAP=$START_CAP% - charge first"
	exit 1
fi

# ☠️ suspend-slope.txt is append-only across runs. Move the previous leg aside
# before writing a line, or two legs end up in one file and the fitter reads
# the union as one run.
if [ -s "$SLOPE" ]; then
	mv "$SLOPE" "$SLOPE.pre-$TAG"
	say "moved previous slope file aside as $SLOPE.pre-$TAG"
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
if [ "$(cat $BATT/status)" = Charging ]; then
	say "ABORT: still charging after USBIN suspend - every sample would read the cable"
	exit 1
fi

load_start() {
	_n=$(nproc 2>/dev/null || echo 4)
	_i=0
	while [ "$_i" -lt "$_n" ]; do
		( while :; do :; done ) &
		echo $! >> "$PIDS"
		_i=$((_i + 1))
	done
	say "load started on $_n cores"
}

load_stop() {
	[ -f "$PIDS" ] || return 0
	while read -r pid; do kill "$pid" 2>/dev/null; done < "$PIDS"
	rm -f "$PIDS"
	say "load stopped"
}

rm -f "$PIDS"
trap 'load_stop; restore' EXIT INT TERM
load_start

# ☠️ NEVER TEST THE THRESHOLD UNDER LOAD. Measured 2026-08-18: eight busy cores
# pull the terminal voltage down by about 360 mV, so a check taken under load
# declared a 4.030 V target reached while the pack was resting at 4.238 V -
# deep in the steep region the target exists to avoid. Shed the load and let it
# recover before every comparison.
while :; do
	load_stop
	sleep 30
	v=$(cat "$BATT/voltage_now")
	say "rested v=$v t=$(cat $BATT/temp 2>/dev/null)"
	[ "$v" -le "$TARGET" ] && { say "reached target v=$v"; break; }
	[ "$v" -le "$FLOOR" ] && { say "ABORT: below floor at v=$v"; exit 1; }
	load_start
	sleep 90
done

# The cut goes on here: after the descent, before a single sample.
for s in $CUTS; do systemctl stop "$s" 2>/dev/null; done
for s in $CUTS; do say "cut $s -> $(systemctl is-active "$s" 2>/dev/null)"; done

say "cooling before the leg; temp=$(cat $BATT/temp 2>/dev/null)"
say "launching slope leg"
/root/suspend-slope.sh "$TAG" 900 6 1800
say "slope leg exited rc=$? v=$(cat $BATT/voltage_now)"
restore
say "done"
