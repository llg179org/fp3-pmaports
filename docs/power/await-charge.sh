#!/bin/sh
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Wait for the pack to reach the A leg's starting charge, then hand over to the
# control leg. This runs ON THE DEVICE as a transient unit, deliberately: the
# host-side version of this wait was killed three times in one afternoon, and a
# measurement that only proceeds while a laptop shell survives is not autonomous.
#
# ☠️ Bounded, and it checks the capacity is RISING. A charger that stopped -
# terminated, unplugged, USBIN suspended in the PMIC - would otherwise be
# waited on forever, which is the sixth loop that could not fail.
set -u
BATT=/sys/class/power_supply/pmi632-battery
LOG=/var/log/await-charge.txt
TARGET_CAP=99
MAX_MIN=90
STUCK_MIN=25

say() { echo "$(cut -d. -f1 /proc/uptime) await: $*" >> "$LOG"; }

prev=-1
stuck=0
i=0
while [ "$i" -lt "$MAX_MIN" ]; do
	i=$((i + 1))
	cap=$(cat "$BATT/capacity")
	say "i=$i cap=$cap% v=$(cat $BATT/voltage_now) status=$(cat $BATT/status)"
	if [ "$cap" -ge "$TARGET_CAP" ]; then
		say "charged at $cap%, launching the control leg"
		exec /root/leg3-control.sh
	fi
	if [ "$cap" = "$prev" ]; then stuck=$((stuck + 1)); else stuck=0; fi
	prev=$cap
	if [ "$stuck" -ge "$STUCK_MIN" ]; then
		say "ABORT: capacity stuck at $cap% for $STUCK_MIN minutes"
		exit 1
	fi
	sleep 60
done
say "ABORT: never reached $TARGET_CAP% in $MAX_MIN minutes"
exit 1
