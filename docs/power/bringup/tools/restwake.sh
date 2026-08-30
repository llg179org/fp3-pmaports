#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# How long does the phone sleep as a function of HOW LONG IT WAS LEFT ALONE?
#
# ☠️ THE OBVIOUS INSTRUMENT MEASURES THE WRONG THING. The first attempt slept
# repeatedly with a short gap between rounds; every round after the first was
# inside the disturbance the previous round created, so the series read
# 43/1/3/7/18 s and said nothing about recovery. Recovery here is a tens-of-
# minutes process, so the gap has to be the INDEPENDENT VARIABLE, not a constant
# small number.
#
# One round = rest for N minutes doing nothing at all, then take exactly ONE
# sleep on an alarm longer than any sleep yet observed, so it ends on the phone's
# terms and not on the clock's. One number per round; the rounds are the curve.
#
# ☠️ Do not poll the phone during the rest period - an ssh login is a wake, and
# the rest is the measurement. Everything is read afterwards from the kernel's
# own PM marks, and independently from the host's USB log.
#
#   restwake.sh "<rest_minutes_list>" [alarm_s]     e.g. "2 5 10 20 40" 1800
set -u
GAPS=${1:-"2 5 10 20 40"}; S=${2:-1800}
O=/var/log/fp3/restwake.log
mkdir -p /var/log/fp3
say(){ echo "$*" >> "$O"; }
: > "$O"
say "# restwake $(date '+%F %T') gaps=[$GAPS] min  alarm=${S}s"
say "#   alarm is deliberately longer than any sleep observed so far, so a sleep"
say "#   that ends early ended on the phone's terms - see leads/sleep-length-is-a-state.md"
say "# rest_min  slept_s  ended_by"

for g in $GAPS; do
	sleep $((g * 60))
	t0=$(date +%s)
	rtcwake -m mem -s "$S" >/dev/null 2>&1
	# the authoritative duration is the kernel's own pair, not this script's clock
	d=$(journalctl -k --since "@$t0" --no-pager 2>/dev/null | grep -E "PM: suspend (entry|exit)" \
	    | awk '{t=$3; m=$0; sub(/.*PM: /,"",m); split(t,c,":"); s=c[1]*3600+c[2]*60+c[3];
	            if (m ~ /entry/) e=s; else if (e) {print s-e; exit}}')
	w=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)
	edge=$(awk '/smd-edge/ && $(NF-2)==57 {l=$1; sub(":","",l); print l}' /proc/interrupts | head -1)
	if [ "${d:-0}" -ge $((S - 5)) ] 2>/dev/null; then by="THE ALARM (so this is a floor, not a value)"
	elif [ "${w:-}" = "${edge:-x}" ];        then by="modem edge (irq $w)"
	else                                          by="irq ${w:-?}"; fi
	printf '%8s  %7s  %s\n' "$g" "${d:-?}" "$by" >> "$O"
done
say "# done $(date '+%F %T')"
