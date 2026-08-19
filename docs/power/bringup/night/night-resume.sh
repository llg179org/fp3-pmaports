#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Bring a night back after a reboot.
#
# A night that ends at the first reboot is not autonomous, and the guardian's own
# answer to a dead eMMC IS a reboot - so without this the net and the runner work
# against each other: the net saves the phone and kills the night.
#
# ☠️ It refuses far more often than it acts, and that is the point. An enabled
# unit that starts a measurement at every boot would fire on a boot taken for any
# other reason - a flash, a hand reboot, a morning power-on - and would do it
# with nobody watching. It acts only when ALL of these hold:
#
#   * a cursor exists (a queue was interrupted rather than finished),
#   * the cursor is younger than MAX_AGE_H (a stale one is not a night),
#   * the job file it names still exists,
#   * preflight passes on the state the reboot left behind.
#
# Anything else and it logs why and exits 0, leaving the phone idle.

set -u

DIR=/root/night
CURSOR=$DIR/cursor
LOG=/run/night/resume.log
MAX_AGE_H=${NIGHT_RESUME_MAX_AGE_H:-12}

mkdir -p /run/night
say() { echo "$*" >> "$LOG"; echo "$*"; }

say "# night-resume at uptime=$(cut -d. -f1 /proc/uptime)"

[ -f "$CURSOR" ] || { say "# no cursor - nothing was interrupted, doing nothing"; exit 0; }

# ☠️ The RTC reads 1970 on this device, so file age cannot be measured against
# the wall clock. What CAN be compared is the cursor's mtime against the current
# time as the same clock sees them - both come from the filesystem, so the
# comparison is internally consistent even when the absolute values are wrong.
now=$(date +%s)
mt=$(stat -c %Y "$CURSOR" 2>/dev/null || echo 0)
age_h=$(( (now - mt) / 3600 ))
if [ "$age_h" -gt "$MAX_AGE_H" ] || [ "$age_h" -lt 0 ]; then
	say "# cursor is ${age_h}h old (limit ${MAX_AGE_H}h) - stale, not resuming"
	say "# leaving it in place for the morning to read: $(cat "$CURSOR")"
	exit 0
fi

read -r tag jobfile job < "$CURSOR"
say "# cursor: tag=$tag jobfile=$jobfile next-job=$job age=${age_h}h"

[ -f "$jobfile" ] || { say "# job file $jobfile is gone - not resuming"; exit 0; }

if ! "$DIR/preflight.sh" 50 >> /run/night/preflight-resume.txt 2>&1; then
	say "# preflight failed after the reboot - not resuming, see /run/night/preflight-resume.txt"
	exit 0
fi

# ☠️ The net first, always, and before the runner: the queue refuses to start
# without it, and on a resume after a card failure it is the whole reason to
# come back at all.
systemd-run --unit=night-guardian --collect "$DIR/guardian.sh" 30 2>/dev/null \
	|| say "# WARNING: could not start the guardian"
sleep 2
systemd-run --unit=night-queue --collect "$DIR/queue.sh" "$jobfile" "$tag" "$job" 2>/dev/null \
	&& say "# resumed $tag at job $job" \
	|| say "# FAILED to resume $tag"
