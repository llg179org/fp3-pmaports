#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Map the oracle's idle current against state of charge, on ONE boot.
#
# Why: three idle-ab captures of Ubuntu Touch give floors of 15.3, 31.1 and
# 69.9 mA for the same phone in the same nominal state, and the readings rise
# with the pack. Two explanations survived - state of charge, or boot recency -
# and boot recency is now excluded: two windows on the same boot, at uptime
# 3 min and 66 min, agree to 1.5 mA (69.9 vs 71.4). So this walks the pack down
# instead, one 1-hour window at a time, on a boot that is already old.
#
# ☠️ There is no second instrument on this side. `current_now` and `cc_soc` are
# both the PMI632 QG block behind one current-sense front end, so they cannot
# check each other and this cannot decide "real draw" versus "gauge artifact".
# What it CAN decide is whether the effect tracks the pack at all, which is the
# question that has to be answered first - and it does it inside one boot, one
# cable state and one instrument, which none of the three historical captures
# did.
#
# ☠️ It polls nothing over ssh. 74 logins in 70 minutes were measured worth
# 18.3 mA, which is a third of the quantity under test.
#
#   soc-ladder.sh [rounds] [window_s]
set -u

ROUNDS=${1:-8}
WINDOW=${2:-3600}
BAT=/sys/class/power_supply/battery
LOG=/tmp/soc-ladder.log
say() { echo "$(date -u +%H:%M:%S) $*" >> "$LOG"; }

say "=== soc-ladder start rounds=$ROUNDS window=${WINDOW}s uptime=$(cut -d. -f1 /proc/uptime)s"
say "# round uptime_s v_uV capacity cc_soc  (before each window)"

n=1
while [ "$n" -le "$ROUNDS" ]; do
	# ☠️ The leg refuses to start unless the input is in its normal state, and
	# its own exit trap puts it back - so the pack charges for the couple of
	# seconds between legs. Logged rather than assumed: if that gap ever grows,
	# the ladder stops descending and the rounds quietly become repeats.
	say "$n $(cut -d. -f1 /proc/uptime) $(cat $BAT/voltage_now) $(cat $BAT/capacity) $(cat /sys/class/power_supply/bms/cc_soc) input_suspend=$(cat $BAT/input_suspend) status=$(cat $BAT/status)"

	if [ "$(cat $BAT/capacity)" -lt 20 ]; then
		say "☠️ stopping at ${n}: pack below 20 %, further rounds would measure a different chemistry region and risk the phone"
		break
	fi

	/bin/sh /tmp/idle-ab.sh "$WINDOW"
	f=$(ls -t /tmp/idle-ab-*.txt | head -1)
	cp "$f" "/tmp/ladder-$n.txt"
	say "$n done -> /tmp/ladder-$n.txt ($(grep -c '^[0-9]' "/tmp/ladder-$n.txt") samples)"
	n=$((n + 1))
done

echo 0 > "$BAT/input_suspend" 2>/dev/null
say "=== soc-ladder done, input_suspend=$(cat $BAT/input_suspend) status=$(cat $BAT/status)"
