#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# DOES CYCLING THE RADIO MOVE THE PHONE FROM THE SHORT SLEEP REGIME TO THE LONG ONE?
#
# On 2026-08-30 the same configuration slept 52-63 s all morning and filled four
# consecutive 600 s windows from midday on. The only lever anyone pulled in
# between was `mmcli --disable` / `--enable` at 10:10 (plus a ModemManager
# restart at 10:27). That is a clean split in time - and so is the clock, the
# network load and the serving cell, none of which was ever recorded. This
# script tests the lever; `radio-context.sh` records the alternatives so the
# result can be read at all.
#
# ☠️ THIS IS NOT AN A-B-A'. It cannot be, and pretending otherwise would be worse
# than admitting it: the lever CHANGES STATE. After leg B the radio has been
# cycled, so a third leg is not a return to A - it is a second B. What this
# script does instead is a **gated before/after**, and the gate is the whole
# design:
#
#   * leg A measures the regime the phone is ALREADY in;
#   * ☠️ if A comes out LONG, the script STOPS. There is nothing to improve, and
#     a B run against an already-long A produces the result we are hoping for
#     while measuring nothing. This is the single easiest way to fake this
#     experiment and it would not look faked afterwards;
#   * leg B cycles the radio and measures again.
#
# The counterfactual has to come from a different day: the same A protocol, in
# the short regime, followed by NO toggle. Without that, a positive B is
# consistent with "the regime ended on its own", which is exactly what the clock
# hypothesis says. Say so in the write-up rather than around it.
#
# ☠️ Do not poll the phone between legs - a login is a wake. Watch from the host.
#
#   radio-cycle-ab.sh A [alarm_s] [rounds]     measure the current regime
#   radio-cycle-ab.sh B [alarm_s] [rounds]     cycle the radio, then measure
set -u
LEG=${1:-A}; S=${2:-600}; N=${3:-3}
O=/var/log/fp3/radio-cycle-$LEG.log
mkdir -p /var/log/fp3
say(){ echo "$*" >> "$O"; }
: > "$O"
say "# radio-cycle leg=$LEG $(date '+%F %T') alarm=${S}s rounds=$N"

# The confound, on the record, at the head of every leg.
/usr/local/bin/radio-context.sh "leg-$LEG-head" >> "$O" 2>&1

say "-- XO accumulation before (the difference across the leg is the integral)"
/usr/local/bin/rpm-xo-snapshot.sh >> "$O" 2>&1

if [ "$LEG" = B ]; then
	say "-- cycling the radio"
	mmcli -m any --disable >/dev/null 2>&1; sleep 5
	mmcli -m any --enable  >/dev/null 2>&1
	w=0
	while [ $w -lt 90 ]; do
		st=$(mmcli -m any 2>/dev/null | sed -n 's/.*state: *//p' | head -1)
		case "$st" in *registered*) break;; esac
		sleep 3; w=$((w + 3))
	done
	say "   modem after the cycle: ${st:-<unknown>} (waited ${w}s)"
	# ☠️ A leg that starts unregistered measures a different phone. Refuse rather
	# than produce a number that will be quoted.
	case "${st:-}" in *registered*) ;; *) say "☠️ NOT registered - aborting leg B"; exit 1;; esac
fi

r=1; long=0
while [ $r -le $N ]; do
	rtcwake -m no -s "$S" >/dev/null 2>&1
	s0=$(cat /sys/power/suspend_stats/success)
	t0=$(date +%s)
	systemctl suspend
	w=0; while [ "$(cat /sys/power/suspend_stats/success)" = "$s0" ] && [ $w -lt 45 ]; do sleep 1; w=$((w + 1)); done
	sleep 8
	d=$(journalctl -k --since "@$t0" --no-pager 2>/dev/null | grep -E "PM: suspend (entry|exit)" \
	    | awk '{t=$3; m=$0; sub(/.*PM: /,"",m); split(t,c,":"); s=c[1]*3600+c[2]*60+c[3];
	            if (m ~ /entry/) e=s; else if (e) {print s-e; exit}}')
	wi=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)
	say "== $LEG round $r: slept ${d:-?}s of ${S}s  pm_wakeup_irq=${wi:-?}"
	[ "${d:-0}" -ge $((S * 3 / 4)) ] && long=$((long + 1))
	sleep 15
	r=$((r + 1))
done

say "-- XO accumulation after"
/usr/local/bin/rpm-xo-snapshot.sh >> "$O" 2>&1
/usr/local/bin/radio-context.sh "leg-$LEG-tail" >> "$O" 2>&1
say "# leg $LEG: $long of $N rounds filled at least three quarters of the window"

if [ "$LEG" = A ] && [ "$long" -gt 0 ]; then
	say ""
	say "☠️ STOP. Leg A is already in the LONG regime ($long/$N). Leg B must not be"
	say "   run against this: it would produce the hoped-for result while measuring"
	say "   nothing, and nothing about the output would look wrong afterwards."
	say "   Wait for the short regime and repeat leg A."
fi
say "# done $(date '+%F %T')"
