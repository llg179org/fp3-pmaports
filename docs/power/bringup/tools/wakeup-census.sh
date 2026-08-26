#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Does the modem keep WAKING the application processor, or does it merely never
# idle itself?
#
# Cutting the modem stack is the only intervention that has ever moved this
# phone's sleeping discharge slope - 36 % - and its mechanism is unnamed. The two
# candidates need different fixes:
#
#   * the MPSS wakes the AP repeatedly  -> the cost is on our side, in resumes,
#     and it shows up as wakeup-source counts and as suspends that end early;
#   * the MPSS simply never enters its own low-power state -> the cost is the
#     modem's own draw, invisible to every AP-side counter, and no amount of
#     wakeup accounting will find it.
#
# So this counts, per suspend: how long it actually stayed down against how long
# it was asked to, which wakeup sources moved, and which interrupts moved.
#
# ☠️ Alternating arms, not one then the other: anything drifting - a warming SoC,
# a settling modem, a network re-registration - shows up as a pattern in time
# rather than as a difference between the arms.
#
# ☠️ Reversible: the cut services are restarted on every exit path.
#
#   wakeup-census.sh [rounds] [suspend_s]        (defaults 3, 60)

set -u

ROUNDS=${1:-3}
SECS=${2:-60}
CUTS="ModemManager rmtfs tqftpserv"
OUT=/run/night/wakeup-census.txt
mkdir -p /run/night
say() { echo "$*" | tee -a "$OUT"; }

# ☠️ Rotate, do not truncate. The first run of this script was followed by a
# second with one extra column, and the second's `: > $OUT` destroyed the first
# run's raw capture before it had been copied to the host. Measured 2026-08-20,
# and the fix costs one line.
[ -s "$OUT" ] && mv "$OUT" "$OUT.$(cut -d. -f1 /proc/uptime)"
: > "$OUT"

STOPPED=""

# ☠️☠️ STARTING THE SERVICES DOES NOT BRING THE MODEM BACK, and until 2026-08-26
# this script assumed it did. `systemctl stop rmtfs` POWERS THE MODEM DOWN; the
# matching start does not undo that - it needs an explicit remoteproc start.
#
# The consequence here was worse than a bad restore, because this script
# ALTERNATES: after round 1's cut arm it restarted the services and went straight
# into round 2's arm labelled "MODEM UP" - with the modem still down. So every
# round after the first compared the cut state against itself, in a tool whose
# headline safety property is that it alternates. Any earlier capture from this
# script with rounds > 1 has to be re-read with that in mind: only round 1's
# "MODEM UP" arm was ever genuinely modem-up.
#
# Returns 0 only when a modem actually enumerates. Callers must treat non-zero
# as fatal, not as a warning: a census that continues from here is comparing two
# copies of the same arm.
modem_up() {
	for s in $CUTS; do systemctl start "$s" 2>/dev/null; done
	# Addressed by platform address, never by index - remoteproc numbering
	# moves between boots.
	for r in /sys/class/remoteproc/remoteproc*; do
		[ "$(cat "$r/name" 2>/dev/null)" = 4080000.remoteproc ] || continue
		if [ "$(cat "$r/state" 2>/dev/null)" = offline ]; then
			say "# modem remoteproc offline - starting it"
			echo start > "$r/state" 2>/dev/null
			sleep 15
			systemctl restart ModemManager 2>/dev/null
		fi
	done
	i=0
	while [ "$i" -lt 18 ]; do
		mmcli -L 2>/dev/null | grep -q 'Modem/' && { say "# modem up after ${i}0s"; return 0; }
		i=$((i + 1)); sleep 10
	done
	say "# ☠️ NO MODEM after 180s"
	return 1
}

restore() {
	rc=$?
	say ""
	modem_up || say "# ☠️ the phone is left WITHOUT A MODEM - a reboot is needed"
	STOPPED=""
	say "# ModemManager: $(systemctl is-active ModemManager 2>/dev/null), $(mmcli -L 2>&1 | head -1)"
	say "# done rc=$rc"
	exit $rc
}
trap restore EXIT INT TERM

RPM=/sys/kernel/debug/qcom_rpm_master_stats
mf() { sed -n "s/^[[:space:]]*$2[[:space:]]*:[[:space:]]*//p" "$RPM/$1" 2>/dev/null | head -1; }

snap() {
	# name:active_count:event_count for every source that has ever fired
	awk 'NR>1 && ($3+0)>0 {print $1":"$3":"$4}' /sys/kernel/debug/wakeup_sources 2>/dev/null | sort
}
irqs() { awk 'NR>1 {s=0; for(i=2;i<=NF-2;i++) if ($i ~ /^[0-9]+$/) s+=$i; print $1" "s}' /proc/interrupts | sort; }
up() { cut -d. -f1 /proc/uptime; }

arm() {
	label=$1
	snap > /run/night/.ws0; irqs > /run/night/.irq0
	s0=$(cat /sys/power/suspend_stats/success)
	# ☠️ The AP-side answer is only half of it. If nothing wakes the AP, the cost
	# is the modem's own, and the only AP-visible witness of that is the RPM's
	# per-master record: how often MPSS went down and how long it kept the
	# crystal off across the same window.
	m0=$(mf MPSS 'Shutdown count'); mx0=$(mf MPSS 'XO shutdown count')
	md0=$(mf MPSS 'XO total duration')
	t0=$(up)

	rtcwake -m mem -s "$SECS" > /dev/null 2>&1

	t1=$(up)
	s1=$(cat /sys/power/suspend_stats/success)
	snap > /run/night/.ws1; irqs > /run/night/.irq1

	m1=$(mf MPSS 'Shutdown count'); mx1=$(mf MPSS 'XO shutdown count')
	md1=$(mf MPSS 'XO total duration')
	slept=$(( t1 - t0 ))
	xoms=$(( ( ${md1:-0} - ${md0:-0} ) / 19200 ))
	say "$label  asked=${SECS}s  elapsed=${slept}s  suspends=+$(( s1 - s0 ))  MPSS +$(( ${m1:-0} - ${m0:-0} )) shutdowns, XO +$(( ${mx1:-0} - ${mx0:-0} )), XO off ${xoms}ms of $(( slept * 1000 ))ms"

	# ☠️ A source that fired is not necessarily the source that WOKE it: the
	# resume path itself activates several. What is informative is the set, and
	# how it differs between the arms.
	join -t: -j1 /run/night/.ws0 /run/night/.ws1 2>/dev/null >/dev/null
	awk -F: 'NR==FNR{a[$1]=$2; next} {if (a[$1]+0 != $2+0) printf "    wakeup %-28s active %s -> %s\n", $1, a[$1]+0, $2}' \
		/run/night/.ws0 /run/night/.ws1 | head -12 | tee -a "$OUT"
	awk 'NR==FNR{a[$1]=$2; next} {d=$2-a[$1]; if (d>0) printf "    irq %-22s +%d\n", $1, d}' \
		/run/night/.irq0 /run/night/.irq1 | sort -t+ -k2 -rn | head -8 | tee -a "$OUT"
}

say "# wakeup-census uptime=$(up) rounds=$ROUNDS suspend=${SECS}s cuts='$CUTS'"
say "# ☠️ elapsed < asked means something woke it early. That is the whole question."
say ""

r=1
while [ "$r" -le "$ROUNDS" ]; do
	say "== round $r =="
	arm "  MODEM UP  "
	for s in $CUTS; do
		systemctl is-active --quiet "$s" 2>/dev/null && systemctl stop "$s" 2>/dev/null && STOPPED="$STOPPED $s"
	done
	sleep 10
	arm "  MODEM CUT "

	# ☠️ Fatal, not advisory. If the modem does not come back, the next round's
	# "MODEM UP" arm would be a second cut arm under the wrong label, and the
	# alternation this script exists for would be silently gone.
	if ! modem_up; then
		say "# ☠️ ABORTING after round $r: the modem did not come back, so any"
		say "# ☠️ further round would compare the cut state against itself."
		break
	fi
	STOPPED=""
	# Give the modem time to re-register before the next MODEM UP arm; an
	# unregistered modem is not the state we are trying to characterise.
	sleep 60
	r=$((r + 1))
	say ""
done
say "# census done"
