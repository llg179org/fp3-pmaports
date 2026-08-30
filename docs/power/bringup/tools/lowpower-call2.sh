#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# Does an incoming call still reach the phone when ModemManager puts the modem in
# LOW POWER for the duration of the suspend?
#
# ☠️ THIS EXISTS BECAUSE THE DOCUMENT SAID "expected to lose the call". That is a
# prediction, not a measurement, and predictions written in that tone have been
# wrong four times today on this front alone. The mode is the distro's other
# branch (--test-low-power-suspend-resume against the shipped
# --test-quick-suspend-resume), and if the call does survive it, it is the single
# biggest lever available: the modem is powered down for the whole sleep.
#
# ☠️ Awake, the modem is normal in this mode - MM only drops it to low power on
# the logind sleep signal and restores it on resume. So the leg must go down the
# LOGIND path, and the phone must be asleep when the call arrives, which is why
# this re-suspends in a loop instead of taking one sleep: the modem edge ends
# most sleeps within seconds, and a single sleep leaves the phone awake for
# almost all of the window (measured, 2026-08-30 07:11).
#
#   lowpower-call2.sh [window_s] [per_sleep_s]     default 900 300
set -u
W=${1:-900}; S=${2:-300}
O=/var/log/fp3/lowpower-call.log
DROPIN=/etc/systemd/system/ModemManager.service.d/zz-lowpower-test.conf
mkdir -p /var/log/fp3 "$(dirname $DROPIN)"
say(){ echo "$*" >> "$O"; }
: > "$O"
EDGE=$(awk '/smd-edge/ && $(NF-2)==57 {l=$1; sub(":","",l); print l}' /proc/interrupts | head -1)

cat > "$DROPIN" <<'EOF'
[Service]
# Test override: put the modem in LOW POWER across the suspend, instead of the
# distro's --test-quick-suspend-resume, which only sets it terse.
ExecStart=
ExecStart=/usr/sbin/ModemManager --test-low-power-suspend-resume
EOF
systemctl daemon-reload
systemctl restart ModemManager
_w=0
while [ $_w -lt 120 ]; do
	st=$(mmcli -m any 2>/dev/null | sed -n 's/.*state: *//p' | head -1)
	case "$st" in *registered*|*connected*) break;; esac
	sleep 2; _w=$((_w + 2))
done
say "# lowpower-call $(date '+%F %T') window=${W}s per-sleep=${S}s edge=${EDGE:-?}"
say "#   ExecStart: $(systemctl show ModemManager -p ExecStart --value | sed 's/.*argv\[\]=//; s/ ;.*//')"
say "#   modem awake state after restart: ${st:-?} (waited ${_w}s)"
say "#   >>> CALL THE PHONE ANY TIME IN THE NEXT ${W}s <<<"

T0=$(date +%s)
r=1
while [ $(( $(date +%s) - T0 )) -lt "$W" ]; do
	if journalctl --since "@$T0" --no-pager 2>/dev/null | grep -qiE "ringing-in|call state changed"; then
		say "# a call was seen; stopping after round $((r - 1))"; break
	fi
	rtcwake -m no -s "$S" >/dev/null 2>&1
	s0=$(cat /sys/power/suspend_stats/success)
	systemctl suspend
	_s=0; while [ "$(cat /sys/power/suspend_stats/success)" = "$s0" ] && [ $_s -lt 45 ]; do sleep 1; _s=$((_s + 1)); done
	# ☠️ DO NOT `sleep $S` HERE. Execution only resumes once the phone is awake
	# again, so a full-alarm wait spends the remainder of the round AWAKE - 302 s
	# of a 15 minute window in the first run of this script, which is exactly when
	# a call placed by hand is most likely to land. The point of the window is that
	# the phone is ASLEEP for as much of it as possible, so go straight back down.
	sleep 10
	r=$((r + 1))
done

say ""
say "-- kernel suspend windows (authoritative; the host's USB log is the second witness)"
journalctl -k --since "@$T0" --no-pager 2>/dev/null | grep -E "PM: suspend (entry|exit)" \
	| awk '{t=$3; m=$0; sub(/.*PM: /,"",m); split(t,c,":"); s=c[1]*3600+c[2]*60+c[3];
	        if (m ~ /entry/) {e=s; et=t} else if (e) {printf "   %s -> %s  = %4ds asleep\n", et, t, s-e; e=0}}' >> "$O"
say "-- did MM actually take it to low power? (the line a success prints)"
journalctl -u ModemManager --since "@$T0" --no-pager 2>/dev/null \
	| grep -iE "low power|sleep-monitor|terse|disabl" | sed 's/^/   /' | tail -20 >> "$O"
say "-- calls seen, WITH TIMESTAMPS - compare against the windows above"
journalctl --since "@$T0" --no-pager 2>/dev/null \
	| grep -iE "call state changed|ringing|incoming call" | sed 's/^/   /' >> "$O"

rm -f "$DROPIN"; systemctl daemon-reload; systemctl restart ModemManager
_w=0
while [ $_w -lt 120 ]; do
	st=$(mmcli -m any 2>/dev/null | sed -n 's/.*state: *//p' | head -1)
	case "$st" in *registered*|*connected*) break;; esac
	sleep 2; _w=$((_w + 2))
done
say "# restored the distro default; modem back to: ${st:-?}"
say "# done $(date '+%F %T')"
