#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# An idle-ab.sh ladder that needs nothing from the host: it runs on the phone,
# survives a reboot, and leaves the pack in a safe state whatever happens to it.
#
# ☠️ WHY THIS EXISTS. On 2026-08-26 an eight-hour ladder was three rungs in when
# the phone was accidentally powered off. Everything was lost: the run was a
# transient `systemd-run --collect` unit, so not even a failed unit remained,
# and the completed rungs were in /tmp, which is tmpfs. The host was also the
# only thing that knew the run existed. Each of those is fixed here.
#
#   night-ladder.sh [rounds] [window_s]        (default 8 x 3600)
#
# THE THREE SAFETY PROPERTIES, in the order they matter:
#
#   1. The charge input is restored on EVERY exit path - normal end, error,
#      SIGTERM at shutdown, and the capacity floor. ☠️ `input_suspend` lives in
#      the PMIC and survives a warm reboot, so a run that dies with it set
#      leaves a phone that will not charge and nobody watching. The companion
#      unit fp3-charge-guard.service clears it at boot as a second line; this
#      trap is the first.
#   2. A capacity floor stops the ladder rather than measuring the pack flat.
#   3. State is on persistent storage and each rung is written as it finishes,
#      so an interruption costs one rung and not the night.
set -u

ROUNDS=${1:-8}
WINDOW=${2:-3600}
FLOOR_PCT=${FLOOR_PCT:-20}

# Persistent, not tmpfs. Picked at run time because the two systems differ.
for d in /var/log/fp3 /home/user/fp3 /home/phablet/fp3 /userdata/fp3; do
	mkdir -p "$d" 2>/dev/null && [ -w "$d" ] && OUTDIR="$d" && break
done
: "${OUTDIR:?no writable persistent directory found}"
STATE="$OUTDIR/ladder.state"
LOG="$OUTDIR/ladder.log"

say() { echo "$(date '+%F %T') $*" >> "$LOG"; }

BAT=/sys/class/power_supply/battery
[ -d "$BAT" ] || BAT=$(dirname "$(ls /sys/class/power_supply/*/capacity 2>/dev/null | head -1)")

restore_input() {
	# ☠️ Unconditional and idempotent: this runs on paths where we do not know
	# what state we are in, which is exactly when a conditional would be wrong.
	for f in /sys/class/power_supply/*/input_suspend; do
		[ -w "$f" ] && echo 0 > "$f" 2>/dev/null
	done
	for s in /sys/class/power_supply/*/status; do
		case "$s" in *pmi632*|*charger*) echo Charging > "$s" 2>/dev/null ;; esac
	done
}
trap 'say "signal caught - restoring charge input and exiting"; restore_input; exit 143' INT TERM HUP
trap 'restore_input' EXIT

# Resume rather than restart: the rung number lives on disk, so a reboot in the
# middle costs that rung only.
START=1
[ -r "$STATE" ] && START=$(cat "$STATE" 2>/dev/null) && [ -n "$START" ] || START=1
say "=== night-ladder start rounds=$ROUNDS window=${WINDOW}s resuming at rung $START outdir=$OUTDIR"

n=$START
while [ "$n" -le "$ROUNDS" ]; do
	# ☠️ Distinguish "the pack is low" from "I could not read the pack". Both
	# must stop the run - refusing to measure is the safe direction either way -
	# but a log that calls the second one a low battery sends the next session
	# hunting for a discharge that never happened. Verified by firing: on a host
	# with no such sysfs node this refused to start and said which case it was.
	cap=$(cat "$BAT/capacity" 2>/dev/null)
	case "$cap" in
	""|*[!0-9]*)
		say "STOP: capacity unreadable at $BAT/capacity (got: $cap) - refusing to run blind"
		break ;;
	esac
	if [ "$cap" -lt "$FLOOR_PCT" ]; then
		say "STOP: capacity ${cap}% is below the ${FLOOR_PCT}% floor - not measuring the pack flat"
		break
	fi
	say "rung $n/$ROUNDS begin: uptime=$(cut -d' ' -f1 /proc/uptime) cap=${cap}% v=$(cat "$BAT/voltage_now" 2>/dev/null) temp=$(cat "$BAT/temp" 2>/dev/null) status=$(cat "$BAT/status" 2>/dev/null)"

	if /tmp/idle-ab.sh "$WINDOW" >/dev/null 2>&1 || true; then :; fi
	src=$(ls -t /tmp/idle-ab-*.txt 2>/dev/null | head -1)
	if [ -n "$src" ] && [ -s "$src" ]; then
		cp "$src" "$OUTDIR/rung-$n.txt"
		sync
		say "rung $n done -> $OUTDIR/rung-$n.txt ($(grep -c '^[0-9]' "$OUTDIR/rung-$n.txt") samples)"
	else
		say "rung $n produced no output - see $src"
	fi

	n=$((n + 1))
	echo "$n" > "$STATE"; sync
done

say "=== night-ladder finished at rung $((n - 1)) of $ROUNDS"
restore_input
say "charge input restored: $(cat "$BAT/status" 2>/dev/null)"
