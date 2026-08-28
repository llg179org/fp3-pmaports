#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# The oracle-side master-stats window, WITH the modem's state inside the capture.
#
#   oracle-modem-window.sh [seconds]        (default 600)   -- runs on Ubuntu Touch
#
# ☠️ WHY THIS EXISTS: the 2026-08-24 pair this whole comparison rests on
# (`ut-master-stats-idle-before.txt` / `-after.txt`, 565 s, MPSS awake 6.3 %) is
# 72 lines of raw master-stats and records NOTHING about the radio. Three separate
# variables have since turned out to be the deciding one, and the capture carries
# none of them:
#
#   power state    - closed from the pmOS side on 2026-08-28: a powered-down modem
#                    reads 0.0 % duty, and 6.3 % is not 0 %.
#   access tech    - THE live question. On pmOS the same MPSS duty is 34.8 % on LTE
#                    and 6.5 % on 2G. If the oracle was not on LTE, "the oracle is
#                    five times better" is a RAT difference and not a finding.
#   signal / cell  - a modem in poor coverage stays awake more, and the two systems
#                    were measured on different days.
#
# So this writes the modem's full state into the SAME file as the counters, before
# and after, rather than leaving it to be remembered. ☠️ A capture re-read for a
# question it was not taken for must carry the variables that question cares about.
#
# ☠️ UT specifics, learned the hard way:
#   - the cellular modem is ofono-managed (/ril_0 AND /ril_1 - there are TWO, and
#     reading only the first is how a null result gets manufactured);
#   - the ofono scripts emit NUL bytes, so pipe through `tr -d '\000'` and grep -a;
#   - master stats are ONE file here (`/sys/kernel/debug/rpm_master_stats`), not a
#     directory as on mainline.
set -u
SECS=${1:-600}
O=/tmp/oracle-modem-window.txt
: > "$O"
s(){ echo "$*" >> "$O"; }

modem_state() {
	for m in /ril_0 /ril_1; do
		s "#   --- ofono $m"
		for script in list-modems; do
			[ -x "/usr/share/ofono/scripts/$script" ] || continue
			/usr/share/ofono/scripts/$script 2>/dev/null | tr -d '\000' \
				| grep -aE "^\[ $m|Powered|Online|Technology|Status|Strength|CellId|LocationAreaCode|MobileNetworkCode|Name =" \
				| sed 's/^/#     /' >> "$O"
		done
	done
	s "#   --- rfkill"
	rfkill list 2>/dev/null | sed 's/^/#     /' >> "$O"
}

s "# oracle-modem-window secs=$SECS $(date '+%F %T')"
s "# kernel=$(uname -r) $(uname -v)"
s "# uptime=$(cut -d. -f1 /proc/uptime)"
s "# cable: $(cat /sys/class/power_supply/*/online 2>/dev/null | tr '\n' ' ')"
s "# BEFORE ------------------------------------------------------------"
modem_state
s "# cc_soc=$(cat /sys/class/power_supply/bms/cc_soc 2>/dev/null) v=$(cat /sys/class/power_supply/*/voltage_now 2>/dev/null | head -1)"
s "# t0=$(cut -d. -f1 /proc/uptime)"
cat /sys/kernel/debug/rpm_master_stats > /tmp/.omw_before 2>/dev/null
sed 's/^/BEFORE /' /tmp/.omw_before >> "$O"

sleep "$SECS"

cat /sys/kernel/debug/rpm_master_stats > /tmp/.omw_after 2>/dev/null
s "# t1=$(cut -d. -f1 /proc/uptime)"
sed 's/^/AFTER /' /tmp/.omw_after >> "$O"
s "# AFTER -------------------------------------------------------------"
modem_state
s "# cc_soc=$(cat /sys/class/power_supply/bms/cc_soc 2>/dev/null) v=$(cat /sys/class/power_supply/*/voltage_now 2>/dev/null | head -1)"
s "# done"
echo "$O"
