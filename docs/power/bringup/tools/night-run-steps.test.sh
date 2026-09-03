#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# ☠️ THE TEST THE TWO REHEARSALS DID NOT DO: walk the STEP SEQUENCE, not a leg.
#
# Both rehearsals ran a shortened leg and checked what the leg produced. Neither
# walked the state machine across simulated reboots - and that is precisely where
# the bug lived: after leg 1 the "next state" write sat below reboot_now, which
# never returns, so the state stayed EVEN and the next boot fell straight through
# to the closing OCV. Three boots requested, one delivered, and the run reported
# "NIGHT COMPLETE" while doing so.
#
# This models the arithmetic only - no phone, no sleeping - and asserts that a
# BOOTS=3 run visits three legs and closes once.
set -u
BOOTS=3
MAXSTEP=40

# the model: exactly the branch structure of night-run.sh, with the actions
# replaced by echoes and reboot replaced by "stop this boot here"
# ☠️ THE STATE COMES BACK AS THE LAST LINE, because the caller runs this in a
# command substitution and a subshell cannot assign to its parent. The first
# version set a variable and the harness looped twelve times on step 0 - a test
# whose own plumbing failed, which is at least a loud failure rather than a
# quiet pass.
run_one_boot() {   # $1 = state in ; echoes events, then "STATE=<n>" last
	step=$1
	[ "$step" -le "$MAXSTEP" ] || { echo "GIVEUP"; return; }
	next=$((step + 1))                         # advance first
	if [ "$step" -eq 0 ]; then
		echo "OCV_START"; echo "REBOOT"; echo "STATE=$next"; return
	fi
	leg=$(( (step + 1) / 2 ))
	if [ "$leg" -le "$BOOTS" ] && [ $((step % 2)) -eq 1 ]; then
		echo "LEG$leg"
		next=$((step + 2))                 # ☠️ BEFORE the reboot, not after
		if [ "$leg" -lt "$BOOTS" ]; then echo "REBOOT"; echo "STATE=$next"; return; fi
	fi
	echo "OCV_END"; echo "COMPLETE"; echo "STATE=$next"
}

STATE=0
events=''
boots=0
while [ "$boots" -lt 12 ]; do
	boots=$((boots + 1))
	out=$(run_one_boot "$STATE")
	STATE=$(echo "$out" | sed -n 's/^STATE=//p')
	events="$events $(echo "$out" | grep -v '^STATE=' | tr '\n' ' ')"
	case "$out" in *COMPLETE*|*GIVEUP*) break ;; esac
done

echo "sequence:$events"
fail=0
for want in LEG1 LEG2 LEG3 OCV_START OCV_END COMPLETE; do
	case "$events" in
		*"$want"*) echo "  ok    $want reached" ;;
		*) echo "  FAIL  $want never reached"; fail=$((fail + 1)) ;;
	esac
done
n=$(echo "$events" | tr ' ' '\n' | grep -c '^COMPLETE$')
[ "$n" -eq 1 ] && echo "  ok    completed exactly once" \
	|| { echo "  FAIL  completed $n times"; fail=$((fail + 1)); }
n=$(echo "$events" | tr ' ' '\n' | grep -c '^REBOOT$')
[ "$n" -eq 3 ] && echo "  ok    3 reboots (opening + after legs 1 and 2)" \
	|| { echo "  FAIL  $n reboots, expected 3"; fail=$((fail + 1)); }

echo
[ "$fail" -eq 0 ] && echo "PASS" || echo "$fail FAILED"
exit "$fail"
