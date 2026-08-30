#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# How long does a DISTURBANCE keep the modem from letting the phone sleep?
#
# ☠️ THIS REPLACES THE QUESTION, NOT JUST THE INSTRUMENT. For a day the modem
# front was "something rings the SMD edge every ~60 s, find the twelfth
# candidate". The host's USB log says otherwise: at 02:30 and 05:15 this phone
# slept its full 300 s and 240 s alarms, and only from 06:08 - after an hour of
# ModemManager restarts, call tests and rapid suspend cycles - did every sleep
# collapse to 51-63 s. Then, left alone from 07:17 to 07:50, it slept 254+ s
# again. So the ~60 s is a STATE with a decay time, and the useful question is
# what sets it and how long it lasts. If the answer is "our own measuring", then
# every A/B run this morning - the terse comparison included - compared two arms
# that were both inside the disturbed regime.
#
# The leg: disturb once, then sleep in a long loop and watch the sleep length
# recover. Nothing polls the phone; the durations are read afterwards from the
# kernel's own PM marks, and independently from the host's USB log.
#
#   decay.sh <disturbance> <rounds> <alarm_s>
#     disturbance: mm-restart | call-less | none
set -u
D=${1:-mm-restart}; N=${2:-20}; S=${3:-300}
O=/var/log/fp3/decay-$D.log
mkdir -p /var/log/fp3
say(){ echo "$*" >> "$O"; }
: > "$O"
say "# decay disturbance=$D rounds=$N alarm=${S}s start $(date '+%F %T')"
say "#   ExecStart: $(systemctl show ModemManager -p ExecStart --value | sed 's/.*argv\[\]=//; s/ ;.*//')"

case "$D" in
mm-restart)
	systemctl restart ModemManager
	_w=0
	while [ $_w -lt 90 ]; do
		case "$(mmcli -m any 2>/dev/null | sed -n 's/.*state: *//p' | head -1)" in
		*registered*|*connected*) break;; esac
		sleep 2; _w=$((_w + 2))
	done
	say "#   disturbed: ModemManager restarted, modem back after ${_w}s"
	;;
none)	say "#   no disturbance - this is the control arm";;
esac

T0=$(date +%s)
r=1
while [ $r -le $N ]; do
	rtcwake -m mem -s "$S" >/dev/null 2>&1
	r=$((r + 1))
	sleep 10
done

say ""
say "# minutes-since-disturbance vs how long each sleep lasted"
say "#   (kernel PM marks; the host's USB disconnect/connect log is the second witness)"
journalctl -k --since "@$T0" --no-pager 2>/dev/null | grep -E "PM: suspend (entry|exit)" \
	| awk -v t0="$T0" '{t=$3; m=$0; sub(/.*PM: /,"",m); split(t,c,":"); s=c[1]*3600+c[2]*60+c[3];
	    if (m ~ /entry/) {e=s; et=t}
	    else if (e) { if (!first) first=e; printf "   %5.1f min   %s  %3ds\n", (e-first)/60, et, s-e; e=0 }}' >> "$O"
say "# done $(date '+%F %T')"
