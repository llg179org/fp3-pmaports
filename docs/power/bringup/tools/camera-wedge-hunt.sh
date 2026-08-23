#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# camera-wedge-hunt.sh [PASSES] [OUTDIR] - reproduce the camss/IOMMU wedge and
# keep the kernel log of the onset.
#
# AI-generated content. Written 2026-08-23.
#
# ☠️ Why a hunt and not a bisect. The wedge fires on roughly half of the runs
# that touch the camera, so a single clean run says nothing: an afternoon of
# one-run-per-arm bisecting "cleared" four different arms and every one of those
# clearances was a coin flip. With an intermittent fault the useful move is not
# to narrow the input but to catch the onset with the instrument already
# running.
#
# Each pass starts from a fresh reboot so the passes are independent, and the
# kernel log is streamed to the HOST by kmsg-tap.sh, because the phone's rootfs
# is 93% full and journald vacuums the boot before last - a reset destroys its
# own evidence otherwise.
#
# Stops at the first pass that shows a fault, leaving:
#   OUTDIR/kmsg.log        the whole kernel log, all passes, across reboots
#   OUTDIR/pass-N.log      the battery output for each pass
#   OUTDIR/summary.txt     one line per pass, and the verdict
set -u

PASSES=${1:-10}
OUTDIR=${2:-./wedge-hunt}
# Seconds to let the phone sit after boot before touching the camera. The
# reason this is a knob: eight passes at ~43 s of uptime produced no wedge at
# all, while all three wedges seen on 2026-08-23 began at 290 s, 1444 s and
# 2198 s of uptime. Boot age is the one measured difference between the arms,
# so it is the one to vary.
SETTLE=${3:-0}
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../../.." && pwd)
PW=${FP3_PW:-<pw>}

mkdir -p "$OUTDIR"
KMSG="$OUTDIR/kmsg.log"
SUM="$OUTDIR/summary.txt"
: >"$SUM"

FAULTS='TLB SYNC|VFE halt|rcu_preempt detected|watchdog0: pretimeout'

say() { echo "$*" | tee -a "$SUM"; }

# ☠️ Count faults with this, never with `grep -c ... || echo 0`.
# `grep -c` already prints 0 when nothing matches - and *also* exits 1, so the
# `|| echo 0` fires as well and the variable becomes two lines ("0\n0"). The
# later `[ "$after" -gt "$before" ]` then errors on a non-integer and returns
# non-zero, which reads exactly like "no wedge": a detector that can never
# fire. Caught 2026-08-23 on the first pass of the first hunt.
count_faults() {
	c=$(grep -cE "$FAULTS" "$KMSG" 2>/dev/null | head -1 | tr -dc '0-9')
	echo "${c:-0}"
}

# One tap for the whole hunt: it reattaches by itself after a reset, so it
# spans the reboots between passes as well as the one that ends the hunt.
"$HERE/kmsg-tap.sh" "$KMSG" &
TAP=$!
# Kill by the PID we hold. ☠️ Never `pkill -f kmsg-tap.sh` from here - the
# pattern matches this script's own command line and kills the hunt instead.
trap 'kill $TAP 2>/dev/null; exit 0' INT TERM
sleep 3

boot_id() { fp3-ssh 'cat /proc/sys/kernel/random/boot_id' 2>/dev/null | tr -dc 'a-f0-9-'; }

say "camera-wedge-hunt: $PASSES passes max, settle ${SETTLE}s, output in $OUTDIR"

n=1
while [ "$n" -le "$PASSES" ]; do
	fp3-ssh "echo '$PW' | sudo -S reboot" >/dev/null 2>&1
	# The witness that the reboot happened is the device coming back with a
	# small uptime, not the return code of the reboot command.
	sleep 20
	while :; do
		u=$(fp3-ssh 'cut -d. -f1 /proc/uptime' 2>/dev/null | tr -dc '0-9')
		[ -n "$u" ] && [ "$u" -gt $(( 40 + SETTLE )) ] && break
		sleep 10
	done

	before_faults=$(count_faults)
	b0=$(boot_id)
	say "pass $n: boot $b0 uptime ${u}s, faults so far $before_faults"

	(cd "$REPO" && ./tests/fp3-selftest --pw "$PW" --only camera,suspend \
		--allow-uncovered audio --allow-uncovered voice \
		--allow-uncovered charger --allow-uncovered sensor \
		--allow-uncovered power) >"$OUTDIR/pass-$n.log" 2>&1
	rc=$?

	# Give a wedged device time to reach the watchdog: the storm has run for
	# up to ten minutes before the reset in every instance so far.
	sleep 60
	after_faults=$(count_faults)
	b1=$(boot_id)

	say "pass $n: rc=$rc faults $before_faults -> $after_faults boot $b0 -> ${b1:-unreachable}"

	if [ "$after_faults" -gt "$before_faults" ]; then
		say "pass $n: WEDGE REPRODUCED - the onset is in $KMSG"
		grep -nE "$FAULTS" "$KMSG" | head -5 | tee -a "$SUM"
		kill $TAP 2>/dev/null
		exit 0
	fi
	if [ -n "$b1" ] && [ "$b1" != "$b0" ]; then
		say "pass $n: the device rebooted with no fault line captured - the tap may have been detached"
	fi
	n=$((n + 1))
done

say "no wedge in $PASSES passes - the rate is lower than assumed, or something changed"
kill $TAP 2>/dev/null
