#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Get the pack to a terminated charge, then hand over to learn-cycle.sh.
#
#   learn-prep.sh [floor_pct]        (default 38, passed straight through)
#
# ☠️ WHY A PREP STEP EXISTS AT ALL. A pack sitting at 91 % on the cable does not
# charge: it is above the 4.30 V recharge threshold, so the charger inhibits and
# the phone stays there indefinitely. learn-cycle.sh refuses to start under 97 %,
# and correctly - its upper anchor is the charger saying it FINISHED. So the pack
# has to be walked down below the recharge threshold first and then allowed back
# up, which is a cycle, not a wait.
#
# Three phases, each with its own exit condition:
#   1. drain to DRAIN_TO % with the input cut, which puts the terminal voltage
#      under the recharge threshold;
#   2. restore the input and wait for status=Full - the termination anchor;
#   3. exec learn-cycle.sh, which owns the measurement.
#
# ☠️ The charge input is restored on every exit path, including a signal, because
# the suspend bit lives in the PMIC and survives a warm reboot. A prep script that
# died in phase 1 without restoring would leave a phone that never charges again
# and nobody watching.
set -u
FLOOR=${1:-38}
DRAIN_TO=${DRAIN_TO:-84}
BAT=/sys/class/power_supply/pmi632-battery
LOG=/var/log/fp3/learn-prep-$(date +%s).log
say(){ echo "$(date '+%F %T') $*" | tee -a "$LOG"; }

restore_input() {
	for f in /sys/class/power_supply/*/input_suspend; do
		[ -w "$f" ] && echo 0 > "$f" 2>/dev/null
	done
	for s in /sys/class/power_supply/*charger*/status; do
		[ -w "$s" ] && echo Charging > "$s" 2>/dev/null
	done
}
trap 'say "signal - restoring charge input"; restore_input; exit 143' INT TERM HUP

say "prep start cap=$(cat $BAT/capacity)% v=$(cat $BAT/voltage_now)uV status=$(cat $BAT/status)"

cap=$(cat "$BAT/capacity")
if [ "$cap" -gt "$DRAIN_TO" ]; then
	say "phase 1: draining to ${DRAIN_TO}% to get under the recharge threshold"
	for s in /sys/class/power_supply/*charger*/status; do
		[ -w "$s" ] && echo Unknown > "$s" 2>/dev/null
	done
	sleep 5
	[ "$(cat $BAT/status)" = Discharging ] || {
		say "STOP: still '$(cat $BAT/status)' after the cut"; restore_input; exit 1; }
	while [ "$(cat $BAT/capacity)" -gt "$DRAIN_TO" ]; do sleep 60; done
	say "phase 1 done cap=$(cat $BAT/capacity)% v=$(cat $BAT/voltage_now)uV"
fi

say "phase 2: charging to termination"
restore_input
i=0
while [ $i -lt 480 ]; do          # up to 8 hours
	st=$(cat "$BAT/status")
	[ "$st" = Full ] && break
	sleep 60; i=$((i + 1))
done
say "phase 2 done status=$(cat $BAT/status) cap=$(cat $BAT/capacity)% charge_full=$(cat $BAT/charge_full)"

[ "$(cat $BAT/status)" = Full ] || {
	say "STOP: never reached Full - not spending a pack cycle on a span with no upper anchor"
	exit 1; }

say "phase 3: handing over to learn-cycle.sh floor=${FLOOR}"
exec /usr/local/bin/learn-cycle.sh "$FLOOR"
