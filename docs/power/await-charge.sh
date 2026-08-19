#!/bin/sh
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Wait until the pack is charged, then hand over to the next measurement.
#
# Usage: await-charge.sh <script> [args ...]
#   e.g. await-charge.sh /root/slope-leg.sh baseline-20260819
#
# ☠️ It runs ON THE DEVICE as a transient unit, and that is the whole point. The
# host-side version of this was killed three times in one night - once by a
# terminal closing, twice by me - and each time the leg it was gating never
# started. A chain that lives on the host is a chain with a link in someone
# else's process tree.
#
# ☠️ It execs rather than calls, so the next thing inherits the unit: one unit,
# one `systemctl is-active`, and no window where the waiter has exited and the
# leg has not yet appeared.
set -u

NEXT=${1:?usage: await-charge.sh <script> [args ...]}
shift

BATT=/sys/class/power_supply/pmi632-battery
LOG=/var/log/await-charge.txt
WANT=99
MAX_MIN=180
STUCK_MIN=30

say() { echo "$(cut -d. -f1 /proc/uptime) await: $*" >> "$LOG"; }

: > "$LOG"
say "waiting for capacity >= $WANT%% then exec $NEXT $*"
say "start cap=$(cat $BATT/capacity)% v=$(cat $BATT/voltage_now) status=$(cat $BATT/status)"

# ☠️ Bounded, and bounded twice. A charger that never reaches the threshold and
# a gauge that stops moving look identical from here, and neither should leave a
# unit waiting until someone notices tomorrow.
last=$(cat "$BATT/capacity")
stuck=0
i=0
while [ "$i" -lt "$MAX_MIN" ]; do
	cap=$(cat "$BATT/capacity")
	if [ "$cap" -ge "$WANT" ]; then
		say "reached cap=$cap%% after ${i}min - handing over"
		exec "$NEXT" "$@"
	fi
	if [ "$cap" = "$last" ]; then
		stuck=$((stuck + 1))
		if [ "$stuck" -ge "$STUCK_MIN" ]; then
			say "ABORT: capacity stuck at $cap%% for ${STUCK_MIN}min - is the cable in?"
			exit 1
		fi
	else
		[ "$((i % 10))" -eq 0 ] && say "cap=$cap%% v=$(cat $BATT/voltage_now)"
		stuck=0
		last=$cap
	fi
	sleep 60
	i=$((i + 1))
done
say "ABORT: still $(cat $BATT/capacity)%% after ${MAX_MIN}min"
exit 1
