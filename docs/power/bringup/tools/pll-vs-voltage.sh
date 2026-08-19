#!/bin/sh
# pll-vs-voltage.sh - run the same cpufreq sweep repeatedly while the battery
# falls, so the PLL failure rate can be read against supply voltage instead of
# against two anecdotes.
#
# The RUNBOOK asks for "a fixed sweep at high and low battery". Two points would
# answer the question only if the answer is large; a ramp answers it either way,
# costs the same night, and cannot be confounded by the two legs having run
# hours apart under different conditions - here every point is the same sweep on
# the same boot, minutes apart, with only the voltage moving.
#
# ☠️ USBIN is suspended to make the battery fall, and that bit lives in the PMIC
# and survives a warm reboot. Never reboot while it is set: the phone comes back
# unable to charge and gives no clue why. This script restores it on every exit
# path it can see - normal end, floor reached, INT/TERM - and prints the one
# command that undoes it by hand if it is killed in a way it cannot catch.
#
# Usage, on the device as root:
#   pll-vs-voltage.sh [--floor-uv 3600000] [--rounds 60] [--max-hours 8]
#
# Everything it prints is the measurement; redirect it to a file.

set -eu

FLOOR_UV=3600000		# stop here. Well above the pack's cutoff, and below
				# the 3.82 V where the storm was first seen.
ROUNDS=60			# per sweep point
MAX_HOURS=8
SWEEP=/tmp/pll-sweep.sh

while [ $# -gt 0 ]; do
	case $1 in
	--floor-uv) FLOOR_UV=$2; shift 2 ;;
	--rounds) ROUNDS=$2; shift 2 ;;
	--max-hours) MAX_HOURS=$2; shift 2 ;;
	--sweep) SWEEP=$2; shift 2 ;;
	*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
done

[ -x "$SWEEP" ] || [ -r "$SWEEP" ] || { echo "no sweep script at $SWEEP" >&2; exit 1; }

BAT=$(echo /sys/class/power_supply/*battery* | cut -d' ' -f1)
USB=$(echo /sys/class/power_supply/*charger* | cut -d' ' -f1)

# qcom_smbx makes POWER_SUPPLY_PROP_STATUS writable on the charger supply and
# maps it straight onto USBIN_SUSPEND_BIT in USBIN_CMD_IL, so writing the status
# takes the phone off VBUS without anybody touching the cable. The USB network
# link and fastboot keep working; only the charging path is suspended. This is
# the same instrument idle-leg.sh and suspend-leg.sh use - deliberately, because
# a second way of doing it would be a second thing to get wrong.
suspend_input() {
	echo Unknown > "$USB/status" 2>/dev/null || return 1
	return 0
}

resume_input() {
	echo Charging > "$USB/status" 2>/dev/null || true
}

trap 'echo; echo "restoring the charger input"; resume_input; exit' EXIT INT TERM

echo "battery: $BAT"
echo "usb:     $USB"
echo "floor:   $FLOOR_UV uV   rounds/point: $ROUNDS   cap: ${MAX_HOURS}h"
echo "☠️ if this is killed uncatchably, restore charging by hand with:"
echo "   echo Charging > $USB/status"
echo

v=$(cat "$BAT/voltage_now")
if [ "$v" -le "$FLOOR_UV" ]; then
	echo "already at or below the floor ($v uV) - charge the phone first"
	exit 1
fi

if ! suspend_input; then
	echo "could not suspend the charger input; nothing here would discharge" >&2
	exit 1
fi
echo "charger input suspended at $(date '+%H:%M:%S'), V=$v"

deadline=$(( $(cut -d. -f1 /proc/uptime) + MAX_HOURS * 3600 ))
point=0

while :; do
	v=$(cat "$BAT/voltage_now")
	c=$(cat "$BAT/capacity")
	now=$(cut -d. -f1 /proc/uptime)

	if [ "$v" -le "$FLOOR_UV" ]; then
		echo "=== floor reached: V=$v cap=$c%% - stopping ==="
		break
	fi
	if [ "$now" -ge "$deadline" ]; then
		echo "=== time cap reached: V=$v cap=$c%% - stopping ==="
		break
	fi

	point=$((point + 1))
	echo "########## point $point  $(date '+%H:%M:%S')  V=$v  cap=$c%% ##########"
	sh "$SWEEP" --rounds "$ROUNDS" || echo "(sweep exited non-zero)"
	echo
done

resume_input
trap - EXIT INT TERM
echo "charger input restored at $(date '+%H:%M:%S'), V=$(cat "$BAT/voltage_now")"
