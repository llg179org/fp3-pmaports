#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Does the audio DSP collapse only while nothing has opened a path on it?
#
# The one observed 30.9 s LPASS collapse (2026-08-19 19:03) happened ten minutes
# after the ADSP had been stopped and restarted, in a suspend taken with USB
# unbound. The USB half was tested first and came back a clean negative: three
# alternating rounds, no collapse on either arm
# ([`../captures/2026-08-19_lpass-usb-ab.txt`](../captures/2026-08-19_lpass-usb-ab.txt)).
#
# What is left of that morning's difference is the DSP restart itself - and the
# shape fits: the counters reset at every boot, and every boot shows two or three
# collapses of about 0.12 s in the first seconds and then nothing for hours. That
# is what a processor that collapses freely until something opens a session and
# never lets go looks like.
#
# So: alternate a plain suspend against a suspend taken on a freshly restarted
# ADSP with nothing having touched audio in between.
#
# ☠️ Run under systemd-run. The ADSP is restarted here; on this kernel that is
# reversible (unlike unbinding the sound card, which costs a reboot).
#
#   lpass-restart-ab.sh [rounds] [suspend_s] [settle_s]     (defaults 3, 30, 20)

set -u

ROUNDS=${1:-3}
SECS=${2:-30}
SETTLE=${3:-20}
RPM=/sys/kernel/debug/qcom_rpm_master_stats
STATS=/sys/kernel/debug/qcom_stats
ADSP=/sys/class/remoteproc/remoteproc2

modprobe rpm_master_stats 2>/dev/null || true
say() { echo "$*"; }
mf() { sed -n "s/^[[:space:]]*$2[[:space:]]*:[[:space:]]*//p" "$RPM/$1" 2>/dev/null | head -1; }
cnt() { sed -n 's/^Count[[:space:]]*:[[:space:]]*//p' "$STATS/$1" 2>/dev/null | head -1; }
up() { cut -d. -f1 /proc/uptime; }

[ "$(cat $ADSP/name 2>/dev/null)" = adsp ] || { say "# ABORT: $ADSP is not the adsp"; exit 1; }

restore() {
	rc=$?
	[ "$(cat $ADSP/state 2>/dev/null)" = running ] || echo start > $ADSP/state 2>/dev/null
	sleep 3
	say "# restored: adsp=$(cat $ADSP/state 2>/dev/null) rc=$rc"
	exit $rc
}
trap restore EXIT INT TERM

arm() {
	label=$1
	l0=$(mf LPASS 'Shutdown count'); x0=$(mf LPASS 'XO shutdown count')
	d0=$(mf LPASS 'XO total duration'); v0=$(cnt vlow); n0=$(cnt vmin)
	s0=$(cat /sys/power/suspend_stats/success)

	rtcwake -m mem -s "$SECS" > /dev/null 2>&1

	l1=$(mf LPASS 'Shutdown count'); x1=$(mf LPASS 'XO shutdown count')
	d1=$(mf LPASS 'XO total duration'); v1=$(cnt vlow); n1=$(cnt vmin)
	s1=$(cat /sys/power/suspend_stats/success)

	ms=$(( ( ${d1:-0} - ${d0:-0} ) / 19200 ))
	say "$label  suspends +$(( s1 - s0 ))  LPASS +$(( ${l1:-0} - ${l0:-0} ))  XO +$(( ${x1:-0} - ${x0:-0} ))  XOdur +${ms}ms  vlow $v0->$v1  vmin $n0->$n1"
}

restart_adsp() {
	echo stop > $ADSP/state 2>/dev/null
	sleep 3
	echo start > $ADSP/state 2>/dev/null
	sleep "$SETTLE"
	say "  (adsp restarted, state=$(cat $ADSP/state 2>/dev/null), settled ${SETTLE}s)"
}

say "# lpass-restart-ab uptime=$(up) rounds=$ROUNDS suspend=${SECS}s settle=${SETTLE}s"
say "# LPASS at start: shutdowns=$(mf LPASS 'Shutdown count') xo=$(mf LPASS 'XO shutdown count') xo_dur=$(mf LPASS 'XO total duration')"
say "# audio services: $(systemctl is-active fp3-voiced 2>/dev/null) $(systemctl is-active spkwatch 2>/dev/null) $(systemctl is-active ringwatch 2>/dev/null)"
say ""

r=1
while [ "$r" -le "$ROUNDS" ]; do
	say "== round $r =="
	arm "  PLAIN        "
	restart_adsp
	arm "  AFTER RESTART"
	r=$((r + 1))
done

say ""
say "# lpass-restart-ab done uptime=$(up)"
