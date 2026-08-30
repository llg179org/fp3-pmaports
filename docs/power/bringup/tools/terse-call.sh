#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# Does an incoming call reach the phone while ModemManager has it in TERSE state?
#
# ☠️ THIS IS THE MEASUREMENT THE POWER GOAL DEPENDS ON. The target is parity with
# the oracle *at the oracle's responsiveness*. TERSE buys quiet by disabling the
# modem's 3GPP unsolicited registration events and unsolicited events;
# ModemManager's source says calls and texts survive it ("only send important
# signals (call/text)"), but what survives on THIS QMI modem is a measurement.
#
# ☠️ THE EARLIER CALL TEST DOES NOT ANSWER IT: it ran during rtcwake cycles with
# zero terse lines in the journal - the state where the modem still signals
# everything. It proved the call path works when nothing has quieted the modem.
#
# ☠️ AND A SINGLE SUSPEND IS NOT AN ANSWERABLE WINDOW ON THIS PHONE. The modem
# edge ends every suspend after roughly a minute, and nothing puts the phone back
# to sleep afterwards - so a script that suspends once and then waits is awake for
# almost all of its "window", and a call placed into it lands on a phone that is
# already up. This version RE-SUSPENDS in a loop and reports, for the round the
# call landed in, whether the phone was asleep when it arrived.
#
#   terse-call.sh [total_window_s] [per_sleep_s]     default 900 120
set -u
W=${1:-900}; S=${2:-120}
O=/var/log/fp3/terse-call.log
mkdir -p /var/log/fp3
EDGE=$(awk '/smd-edge/ && $(NF-2)==57 {l=$1; sub(":","",l); print l}' /proc/interrupts | head -1)
say(){ echo "$*" >> "$O"; }
: > "$O"

systemctl restart ModemManager
_wr=0
while [ $_wr -lt 90 ]; do
	st=$(mmcli -m any 2>/dev/null | sed -n 's/.*state: *//p' | head -1)
	case "$st" in *registered*|*connected*) break;; esac
	sleep 2; _wr=$((_wr + 2))
done
say "# terse-call $(date '+%F %T') window=${W}s per-sleep=${S}s"
say "#   ExecStart: $(systemctl show ModemManager -p ExecStart --value | sed 's/.*argv\[\]=//; s/ ;.*//')"
say "#   modem state after restart: ${st:-?} (waited ${_wr}s)   edge irq=${EDGE:-?}"
say "#   >>> CALL THE PHONE ANY TIME IN THE NEXT ${W}s <<<"

T0=$(date +%s)
r=1
while [ $(( $(date +%s) - T0 )) -lt "$W" ]; do
	# stop as soon as a call has been seen - the question is answered
	if journalctl --since "@$T0" --no-pager 2>/dev/null | grep -qiE "ringing-in|call state changed"; then
		say "# a call was seen; stopping after round $((r - 1))"
		break
	fi
	rtcwake -m no -s "$S" >/dev/null 2>&1     # backstop alarm, no suspend
	s0=$(cat /sys/power/suspend_stats/success)
	systemctl suspend
	_sw=0
	while [ "$(cat /sys/power/suspend_stats/success)" = "$s0" ] && [ $_sw -lt 45 ]; do sleep 1; _sw=$((_sw + 1)); done
	sleep "$S"        # the phone wakes on its own well before this; that is the point
	r=$((r + 1))
done

say ""
say "-- kernel suspend windows (the authoritative measure; the host's USB"
say "   disconnect/connect log is the independent second witness)"
journalctl -k --since "@$T0" --no-pager 2>/dev/null | grep -E "PM: suspend (entry|exit)" \
	| awk '{t=$3; m=$0; sub(/.*PM: /,"",m); split(t,c,":"); s=c[1]*3600+c[2]*60+c[3];
	        if (m ~ /entry/) {e=s; et=t} else if (e) {printf "   %s -> %s  = %3ds asleep\n", et, t, s-e; e=0}}' >> "$O"
say "-- terse lines: $(journalctl -u ModemManager --since "@$T0" --no-pager 2>/dev/null | grep -ci terse)"
say "-- calls seen (WITH TIMESTAMPS - compare against the windows above)"
journalctl --since "@$T0" --no-pager 2>/dev/null \
	| grep -iE "call state changed|ringing|incoming|gnome.Calls" | sed 's/^/   /' >> "$O"
say "-- ModemManager, whole run"
journalctl -u ModemManager --since "@$T0" --no-pager 2>/dev/null | sed 's/^/   /' >> "$O"
say "# done $(date '+%F %T')"
