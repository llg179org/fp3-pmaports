#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Both arms of a sleeping-current comparison from ONE pack.
#
# `slope-leg.sh` prices one state per discharge: descend, settle, six sleeps, six
# awake controls, then charge back up. Two states cost two legs and two charges -
# nine hours and a night. The next question needs THREE (which of ModemManager,
# rmtfs and tqftpserv carries the modem's 36 %), and there is no cheaper meter:
# `charge_now` was tested and is an OCV lookup, not a coulomb count.
#
# So alternate the arms inside a single descent instead. Each cycle is one
# suspend with the cut applied and one without, and the two arms are fitted
# separately over the *same* span of time and voltage.
#
# Why that is better than two legs and not just faster:
#
#   * **drift is shared.** A warming SoC, a settling modem, a network
#     re-registration and the OCV curve's own shape all act on both arms
#     equally, because the arms are interleaved rather than consecutive. Two
#     separate legs put each arm on a different part of the curve and a different
#     hour, which is exactly the confound that forced every comparison so far to
#     carry a same-day control.
#   * **no cross-day comparison.** The instrument's own baseline reproduces to
#     1.4 %, and the effects being chased here are that size.
#
# ☠️ It cannot price an effect that needs time to appear. If a cut only pays off
# after the modem has been quiet for ten minutes, a 900 s alternation never sees
# it - the cut is re-applied from cold every cycle. Read a null from this leg as
# "no fast-acting difference", not as "no difference".
#
#   ab-leg.sh <tag> <cut-services> [cycles] [suspend_s]
#   ab-leg.sh dryrun-ab "rmtfs" 2 60      <- the gate; run it after any edit
#
# Everything else - the descent, the USBIN suspend, the floor, the restore - is
# slope-leg.sh's, deliberately, so the two instruments cannot drift apart.

set -u

TAG=${1:?usage: ab-leg.sh <tag> <cut-services> [cycles] [suspend_s]}
CUTS=${2:?usage: ab-leg.sh <tag> <cut-services> [cycles] [suspend_s]}
CYCLES=${3:-6}
SECS=${4:-900}

BATT=/sys/class/power_supply/pmi632-battery
CHG=/sys/class/power_supply/pmi632-charger
LOG=/var/log/ab-leg-$TAG.txt
OUT=/run/night/ab-leg-$TAG.txt
TARGET=4030000
FLOOR=3800000
START_MIN=4200000
START_CAP=${START_CAP:-95}

mkdir -p /run/night
say() { echo "$(cut -d. -f1 /proc/uptime) $TAG: $*" | tee -a "$LOG" >> "$OUT"; }
v() { cat "$BATT/voltage_now"; }
up() { cut -d. -f1 /proc/uptime; }

STOPPED=""
restore() {
	rc=$?
	echo Charging > "$CHG/status" 2>/dev/null
	for s in $CUTS; do systemctl start "$s" 2>/dev/null; done
	systemctl start greetd 2>/dev/null
	say "restored: charger=$(cat $CHG/status) online=$(cat $CHG/online) rc=$rc"
	exit $rc
}
trap restore EXIT INT TERM

say "start v=$(v) cap=$(cat $BATT/capacity)% cuts='$CUTS' cycles=$CYCLES suspend=${SECS}s"
say "kernel=$(uname -r) boot_id=$(cat /proc/sys/kernel/random/boot_id)"

[ "$(v)" -lt "$START_MIN" ] && { say "ABORT: $(v) below START_MIN=$START_MIN"; exit 1; }
[ "$(cat $BATT/capacity)" -lt "$START_CAP" ] && { say "ABORT: below START_CAP=$START_CAP%"; exit 1; }

# ☠️ backlight = 0 is not dpms off; a panel at zero brightness is still powered.
systemctl stop greetd 2>/dev/null
i=0
while [ "$i" -lt 15 ]; do
	for fb in /sys/class/graphics/fb*/blank; do [ -w "$fb" ] && echo 4 > "$fb"; done
	sleep 2
	[ "$(cat /sys/class/drm/card0/card0-DSI-1/dpms 2>/dev/null)" = Off ] && break
	i=$((i + 1))
done
say "dpms=$(cat /sys/class/drm/card0/card0-DSI-1/dpms 2>/dev/null)"

echo Unknown > "$CHG/status"
sleep 10
[ "$(cat $BATT/status)" = Charging ] && { say "ABORT: still charging after USBIN suspend"; exit 1; }
say "USBIN suspended: status=$(cat $BATT/status) online=$(cat $CHG/online)"

# --- descend to a fixed target so every leg's arms sit on the same curve -------
if [ "$(v)" -gt "$TARGET" ]; then
	say "descending to $TARGET"
	while [ "$(v)" -gt "$TARGET" ]; do
		n=$(nproc 2>/dev/null || echo 4); j=0
		while [ "$j" -lt "$n" ]; do ( while :; do :; done ) & echo $! >> /run/night/.abpids; j=$((j+1)); done
		sleep 90
		while read -r pid; do kill "$pid" 2>/dev/null; done < /run/night/.abpids; : > /run/night/.abpids
		sleep 30
		say "descent v=$(v)"
		[ "$(v)" -le "$FLOOR" ] && { say "ABORT: below floor"; exit 1; }
	done
fi
say "settled at v=$(v); alternating arms now"
say ""

cut_on() {
	STOPPED=""
	for s in $CUTS; do
		systemctl is-active --quiet "$s" 2>/dev/null && systemctl stop "$s" 2>/dev/null && STOPPED="$STOPPED $s"
	done
}
cut_off() { for s in $STOPPED; do systemctl start "$s" 2>/dev/null; done; STOPPED=""; }

# One arm: settle briefly so the state is the state, then one suspend, then read.
arm() {
	label=$1
	sleep 20
	t0=$(up); v0=$(v)
	rtcwake -m mem -s "$SECS" > /dev/null 2>&1
	t1=$(up); v1=$(v)
	say "ARM $label t0=$t0 v0=$v0 t1=$t1 v1=$v1 slept=$((t1-t0))s of ${SECS}s"
	[ "$v1" -le "$FLOOR" ] && { say "ABORT: below floor at v=$v1"; exit 1; }
}

c=1
while [ "$c" -le "$CYCLES" ]; do
	say "=== cycle $c of $CYCLES ==="
	cut_on
	say "cut applied:${STOPPED:- nothing was running}"
	arm "CUT"
	cut_off
	sleep 20
	arm "FULL"
	c=$((c + 1))
done

say ""
say "done - fit with tools/ab-leg-fit.py"
