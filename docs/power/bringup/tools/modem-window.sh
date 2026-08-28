#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# ONE instrument, BOTH systems: an RPM master-stats window with the modem's full
# state written into the same file, before and after.
#
#   modem-window.sh [seconds]     (default 600)   -- runs on pmOS *and* on UT
#
# ☠️ WHY ONE SCRIPT AND NOT TWO. On 2026-08-28 a whole line of work rested on
# "the two systems run different modem firmware", and it was wrong: one side had
# been read from a metadata file (`verinfo/ver_info.txt`, whose "modem" field
# mirrors Meta_Build_ID) and the other from the image's own compiled-in
# QC_IMAGE_VERSION_STRING. Two witnesses at different layers, read as one
# comparison. The rule that catches it is to **ask the same question of both sides
# with the same instrument**, which is only credible if it is literally the same
# file. So this branches on the stack, never on the question.
#
# ☠️ WHAT THE CAPTURE MUST CARRY, learned by having it missing three times. The
# 2026-08-24 oracle pair (565 s, MPSS awake 6.3 %) is 72 lines of raw counters and
# records none of:
#   power state    - closed 2026-08-28: a powered-down modem reads 0.0 % duty,
#                    and 6.3 % is not 0 %.
#   access tech    - decisive: on pmOS the same duty is 34.8 % on LTE and 6.5 % on
#                    2G. Without this field "the oracle is five times better" and
#                    "the oracle was on a cheaper RAT" are the same observation.
#   signal / cell  - poor coverage keeps a modem awake, and the two systems were
#                    measured on different days.
#
# ☠️ Do not poll the phone while this runs; it sleeps through the window on purpose.
# systemd-run it (pmOS) or nohup it (UT) and read the file afterwards.
set -u
SECS=${1:-600}
O=/tmp/modem-window.txt
: > "$O"
s(){ echo "$*" >> "$O"; }

# ---- which stack -----------------------------------------------------------
# ☠️ Decide by what is present, not by uname: both systems are Linux and both
# have a modem. The master-stats layout differs too - a directory of files on
# mainline, a single file downstream - and reading the wrong one silently yields
# nothing rather than an error.
if [ -d /sys/kernel/debug/qcom_rpm_master_stats ]; then
	STACK=pmos; RPM_DIR=/sys/kernel/debug/qcom_rpm_master_stats
elif [ -f /sys/kernel/debug/rpm_master_stats ]; then
	STACK=ut; RPM_FILE=/sys/kernel/debug/rpm_master_stats
else
	echo "no RPM master stats on this system" >&2; exit 1
fi

dump_rpm(){
	if [ "$STACK" = pmos ]; then
		for m in APSS MPSS PRONTO TZ LPASS; do
			echo "$1 [$m]"; sed "s/^/$1 /" "$RPM_DIR/$m" 2>/dev/null
		done
	else
		sed "s/^/$1 /" "$RPM_FILE" 2>/dev/null
	fi >> "$O"
}

modem_state(){
	if [ "$STACK" = pmos ]; then
		s "#   --- mmcli -m 0"
		mmcli -m 0 2>/dev/null | grep -aE \
			"state:|power state:|access tech:|signal quality:|registration:|packet service|operator|current:|firmware revision" \
			| sed 's/^/#     /' >> "$O"
		s "#   --- modem remoteproc: $(cat /sys/class/remoteproc/remoteproc1/state 2>/dev/null)"
	else
		# ☠️ There are TWO ofono modems (/ril_0 and /ril_1). Reading only the
		# first is how a null result gets manufactured. And the ofono scripts
		# emit NUL bytes, hence tr -d '\000' and grep -a.
		for m in /ril_0 /ril_1; do
			s "#   --- ofono $m"
			/usr/share/ofono/scripts/list-modems 2>/dev/null | tr -d '\000' \
				| grep -aE "^\[ $m|Powered|Online|Technology|Status|Strength|CellId|LocationAreaCode|MobileNetworkCode|Name =" \
				| sed 's/^/#     /' >> "$O"
		done
	fi
	s "#   --- rfkill"
	rfkill list 2>/dev/null | sed 's/^/#     /' >> "$O"
}

batt(){
	for f in /sys/class/power_supply/*/voltage_now; do
		[ -r "$f" ] || continue; echo "v=$(cat "$f") ($f)"; break
	done
	echo "cc_soc=$(cat /sys/class/power_supply/bms/cc_soc 2>/dev/null)"
	echo "cap=$(cat /sys/class/power_supply/*/capacity 2>/dev/null | head -1)"
}

s "# modem-window stack=$STACK secs=$SECS $(date '+%F %T')"
s "# kernel=$(uname -r) $(uname -v)"
s "# uptime=$(cut -d. -f1 /proc/uptime)"
s "# BEFORE ------------------------------------------------------------"
modem_state
batt | sed 's/^/# /' >> "$O"
s "# t0=$(cut -d. -f1 /proc/uptime)"
dump_rpm BEFORE

sleep "$SECS"

s "# t1=$(cut -d. -f1 /proc/uptime)"
dump_rpm AFTER
s "# AFTER -------------------------------------------------------------"
modem_state
batt | sed 's/^/# /' >> "$O"
s "# done"
echo "$O"
