#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# Does ModemManager's TERSE state buy residency? - the honest re-run.
#
# ☠️ WHAT THE FIRST ATTEMPT GOT WRONG, twice over. It ran six legs back to back
# with a ModemManager restart before each, on a 300 s alarm, and reported
# 52/61/62/61/63/63 s - "terse changes nothing". Both halves of that were
# instrument artefacts:
#   1. every leg after the first started inside the disturbance the previous leg
#      created, so BOTH arms were saturated. "No difference between the arms" and
#      "both arms saturated" produce the identical table.
#   2. the alarm was shorter than sleeps this phone has demonstrably taken
#      (300 s observed elsewhere the same day), so a leg that hit it would have
#      reported the clock rather than the phone.
# See leads/sleep-length-is-a-state.md.
#
# This version fixes both: a REST period before every leg, taken from the
# measured recovery curve rather than guessed, and an alarm longer than any
# sleep yet observed. One sleep per leg - a second would corrupt its own next
# point.
#
# The arms differ only in what ModemManager does on the logind sleep signal:
#   terse : --test-quick-suspend-resume  -> CLEANUP_TERSE (the distro default)
#   none  : --test-no-suspend-resume     -> the daemon does nothing at all
# Not the low-power arm: it disables the modem, which loses the call, and the
# goal is defined at the oracle's responsiveness (see captures/2026-08-30_terse-call/).
#
#   terse-ab-clean.sh <rest_min> <alarm_s> <rounds>
set -u
R=${1:-40}; S=${2:-1800}; N=${3:-2}
O=/var/log/fp3/terse-ab-clean.log
DROPIN=/etc/systemd/system/ModemManager.service.d/zz-terse-ab.conf
mkdir -p /var/log/fp3 "$(dirname $DROPIN)"
say(){ echo "$*" >> "$O"; }
: > "$O"
EDGE=$(awk '/smd-edge/ && $(NF-2)==57 {l=$1; sub(":","",l); print l}' /proc/interrupts | head -1)
say "# terse-ab-clean $(date '+%F %T') rest=${R}min alarm=${S}s rounds=$N edge=${EDGE:-?}"
say "# arm  rest_min  terse_lines  slept_s  ended_by"

arm(){ # $1 = terse|none
	if [ "$1" = terse ]; then rm -f "$DROPIN"
	else printf '[Service]\nExecStart=\nExecStart=/usr/sbin/ModemManager --test-no-suspend-resume\n' > "$DROPIN"; fi
	systemctl daemon-reload
	systemctl restart ModemManager
	_w=0
	while [ $_w -lt 90 ]; do
		case "$(mmcli -m any 2>/dev/null | sed -n 's/.*state: *//p' | head -1)" in
		*registered*|*connected*) break;; esac
		sleep 2; _w=$((_w + 2))
	done
	# the restart IS a disturbance; the rest period is what makes the arms comparable
	sleep $((R * 60))
	t0=$(date +%s)
	rtcwake -m no -s "$S" >/dev/null 2>&1     # backstop alarm, no suspend
	s0=$(cat /sys/power/suspend_stats/success)
	systemctl suspend
	_s=0; while [ "$(cat /sys/power/suspend_stats/success)" = "$s0" ] && [ $_s -lt 45 ]; do sleep 1; _s=$((_s + 1)); done
	while [ $(( $(date +%s) - t0 )) -lt $((S + 10)) ]; do sleep 5; done
	d=$(journalctl -k --since "@$t0" --no-pager 2>/dev/null | grep -E "PM: suspend (entry|exit)" \
	    | awk '{t=$3; m=$0; sub(/.*PM: /,"",m); split(t,c,":"); s=c[1]*3600+c[2]*60+c[3];
	            if (m ~ /entry/) e=s; else if (e) {print s-e; exit}}')
	tl=$(journalctl -u ModemManager --since "@$t0" --no-pager 2>/dev/null | grep -ci terse)
	w=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)
	if [ "${d:-0}" -ge $((S - 10)) ] 2>/dev/null; then by="THE ALARM (floor, not a value)"
	elif [ "${w:-}" = "${EDGE:-x}" ];         then by="modem edge"
	else                                           by="irq ${w:-?}"; fi
	printf '%-6s %8s  %11s  %7s  %s\n' "$1" "$R" "$tl" "${d:-?}" "$by" >> "$O"
}

i=1
while [ $i -le $N ]; do arm terse; arm none; i=$((i + 1)); done
rm -f "$DROPIN"; systemctl daemon-reload; systemctl restart ModemManager
say "# restored the distro default; done $(date '+%F %T')"
