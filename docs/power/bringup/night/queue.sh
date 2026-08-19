#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Run a night's worth of measurements back to back with nobody in the room.
#
# Everything before this ran as a hand-launched transient unit with a host-side
# poller babysitting it, which capped a night at whatever one leg could fill and
# put a human in the loop at every handover. A queue is the difference between
# "a leg ran overnight" and "the night ran".
#
# ☠️ It refuses to start unless preflight.sh passes AND the guardian is running.
# The net is not optional: the reason long unattended runs were barred is that
# the one failure this device has shown destroys its own record.
#
#   queue.sh <jobfile> [tag] [start_at_job]
#
# Job file grammar, one directive per line:
#
#   # ...                  comment
#   @preflight [pct]       run the gate; a failure aborts the whole queue
#   @charge <pct> [maxmin] wait for the pack to reach pct (default max 180 min)
#   @timeout <seconds>     wall-clock cap for each following job
#   @stop-on-fail          from here on, a failed job ends the queue
#   @note <text>           write a line into the log
#   <anything else>        a command; run it, time it, keep its output
#
# ☠️ Run this under systemd-run, never in the foreground over ssh. An ssh
# timeout once killed a probe mid-script and left the modem and the ADSP
# unbound with nothing running to rebind them.

set -u

JOBFILE=${1:?usage: queue.sh <jobfile> [tag] [start_at_job]}
TAG=${2:-night}
START_AT=${3:-1}
DIR=/run/night
LOG=$DIR/queue.log
CHG=/sys/class/power_supply/pmi632-charger
BAT=/sys/class/power_supply/pmi632-battery
HERE=$(dirname "$0")
CURSOR=/root/night/cursor

mkdir -p "$DIR"
up() { cut -d. -f1 /proc/uptime; }
say() { echo "[$(up)] $*" >> "$LOG"; echo "[$(up)] $*"; }
f() { cat "$1" 2>/dev/null || echo '?'; }

# ☠️ Whatever else happened, the charger comes back. USBIN_SUSPEND_BIT is in the
# PMIC and survives a reboot; a queue that dies with it set hands over a phone
# that will not charge and a next night that starts from a falling pack.
finish() {
	rc=$?
	echo Charging > $CHG/status 2>/dev/null || true
	say "# queue $TAG ends rc=$rc charger=$(f $CHG/status) online=$(f $CHG/online) cap=$(f $BAT/capacity)%"
	echo "QUEUE FINISHED rc=$rc" >> "$LOG"
	exit $rc
}
trap finish EXIT INT TERM

say "# queue $TAG start jobfile=$JOBFILE cap=$(f $BAT/capacity)% v=$(f $BAT/voltage_now)"

if ! systemctl is-active --quiet night-guardian 2>/dev/null; then
	if [ "${NIGHT_ALLOW_NO_GUARDIAN:-0}" = 1 ]; then
		say "# WARNING: no guardian, running anyway because NIGHT_ALLOW_NO_GUARDIAN=1"
	else
		say "# ABORT: night-guardian is not running - the eMMC net is the precondition for running unattended"
		exit 1
	fi
fi

# ☠️ Nothing may make a sound at night. This is checked rather than trusted:
# someone is asleep next to the phone, and a job file is written by whoever is
# in a hurry. The audible things on this device are the acoustic audio check
# (which plays a tone and listens for it), the vibrator check, and any direct
# player. The silent audio coverage - the codec/PCM check and the amplifier's
# control-bus check - is deliberately NOT in this list and may run all night.
refuse_if_audible() {
	case "$1" in
	*--acoustic*|*aplay*|*paplay*|*speaker-test*|*pw-play*|*pactl\ play*|*21-audio-acoustic*|*--only\ vibrator*|*16-vibrator*)
		say "# ABORT: job would make a sound and it is a night queue: $1"
		return 1 ;;
	esac
	return 0
}

TIMEOUT=14400
STOP_ON_FAIL=0
n=0
failed=0

wait_for_charge() {
	want=$1; maxmin=${2:-180}
	say "# charge: waiting for >= ${want}%, cap now $(f $BAT/capacity)%, max ${maxmin} min"
	echo Charging > $CHG/status 2>/dev/null || true
	t0=$(up); last=''; stuck=0
	while :; do
		cap=$(f $BAT/capacity)
		[ "${cap:-0}" -ge "$want" ] 2>/dev/null && { say "# charge: reached ${cap}% after $((($(up) - t0) / 60)) min"; return 0; }
		if [ "$(( $(up) - t0 ))" -ge "$((maxmin * 60))" ]; then
			say "# charge: TIMED OUT at ${cap}% after ${maxmin} min - continuing anyway"
			return 1
		fi
		# A pack that has not moved for half an hour is not charging, and
		# waiting three hours to find that out wastes the night.
		if [ "$cap" = "$last" ]; then stuck=$((stuck + 1)); else stuck=0; last=$cap; fi
		if [ "$stuck" -ge 60 ]; then
			say "# charge: stuck at ${cap}% for 30 min, online=$(f $CHG/online) status=$(f $CHG/status) - continuing"
			return 1
		fi
		sleep 30
	done
}

# ☠️ Copy the job file onto tmpfs and read the loop FROM THAT FILE, for two
# separate reasons, both of which have burned a night before:
#
#   1. The original lives on the eMMC, and the whole point of the guardian is
#      that the eMMC may stop answering halfway through - at which moment a
#      queue still reading its own script line by line stops silently.
#   2. `cat file | while ... done` puts the loop in a SUBSHELL, so `exit 1` on a
#      failed preflight would end the subshell and let the queue carry on and
#      report success. A redirect keeps the loop in this shell, where exit means
#      exit and the EXIT trap still restores the charger.
JOBTMP=$DIR/jobs-$TAG.txt
cat "$JOBFILE" > "$JOBTMP"

while IFS= read -r line; do
	case "$line" in
	''|'#'*) continue ;;
	'@note '*)  say "# note: ${line#@note }" ; continue ;;
	'@timeout '*) TIMEOUT=${line#@timeout }; say "# timeout is now ${TIMEOUT}s"; continue ;;
	'@stop-on-fail') STOP_ON_FAIL=1; say "# stop-on-fail armed"; continue ;;
	'@preflight'*)
		arg=${line#@preflight}; arg=${arg# }
		say "# preflight ${arg:-(default)}"
		if "$HERE/preflight.sh" ${arg:-} >> "$DIR/preflight.txt" 2>&1; then
			say "# preflight PASSED"
		else
			say "# preflight FAILED - see $DIR/preflight.txt - aborting the queue"
			exit 1
		fi
		continue ;;
	'@charge '*)
		set -- ${line#@charge }
		wait_for_charge "$1" "${2:-180}"
		continue ;;
	esac

	# The guardian has its own deadline, and a queue can outlive it. Checking
	# only at startup would mean the net quietly disappears halfway through the
	# night, which is exactly the half where it matters.
	if ! systemctl is-active --quiet night-guardian 2>/dev/null; then
		say "# guardian is gone - restarting it before job $((n + 1))"
		systemd-run --unit=night-guardian --collect "$HERE/guardian.sh" 30 2>/dev/null \
			|| say "# WARNING: could not restart the guardian"
	fi

	refuse_if_audible "$line" || exit 1

	n=$((n + 1))
	if [ "$n" -lt "$START_AT" ]; then
		say "# job $n SKIPPED (resuming at $START_AT): $line"
		continue
	fi

	# ☠️ The cursor lives on the eMMC on purpose. Everything else this harness
	# writes is on tmpfs so it survives a read-only root - but the one thing
	# that has to survive a REBOOT cannot be on tmpfs, and a reboot is exactly
	# what the guardian does when the card dies. Written before the job, so a
	# reboot mid-job resumes by repeating that job rather than skipping it.
	printf '%s %s %s\n' "$TAG" "$JOBFILE" "$n" > "$CURSOR" 2>/dev/null || true

	slug=$(echo "$line" | tr -c 'A-Za-z0-9' '-' | cut -c1-40)
	out=$(printf '%s/%02d%s.txt' "$DIR" "$n" "$slug")
	say "# job $n START (timeout ${TIMEOUT}s): $line"
	t0=$(up)
	# ☠️ < /dev/null: the loop is reading from $JOBTMP, and a job that reads
	# stdin would eat the rest of the night's job list.
	if timeout "$TIMEOUT" sh -c "$line" > "$out" 2>&1 < /dev/null; then
		rc=0
	else
		rc=$?
	fi
	say "# job $n END rc=$rc after $(( $(up) - t0 ))s -> $out"
	if [ "$rc" -ne 0 ]; then
		failed=$((failed + 1))
		[ "$STOP_ON_FAIL" = 1 ] && { say "# stop-on-fail: ending the queue"; exit 1; }
	fi
done < "$JOBTMP"

rm -f "$CURSOR"
say "# queue $TAG done, $failed job(s) failed - cursor cleared"
