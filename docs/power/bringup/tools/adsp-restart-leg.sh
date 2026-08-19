#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# What is the ADSP's held session worth?
#
# Measured 2026-08-19: one restart of the ADSP and the audio DSP power-collapses
# in every subsequent suspend, keeping the crystal off for the whole of it, where
# before it had collapsed twice since boot for 0.12 s in total. The mechanism has
# no price yet - this leg is the price.
#
# It restarts the DSP, verifies the counter actually moved across a short probe
# suspend BEFORE spending four hours on it, and only then hands over to the
# ordinary slope leg. ☠️ A leg that measures an intervention which silently did
# not take is the most expensive kind of null, and this project has already paid
# for one.
#
#   adsp-restart-leg.sh [tag]

set -u

TAG=${1:-adsprestart-20260819}
ADSP=/sys/class/remoteproc/remoteproc2
RPM=/sys/kernel/debug/qcom_rpm_master_stats

modprobe rpm_master_stats 2>/dev/null || true
mf() { sed -n "s/^[[:space:]]*$2[[:space:]]*:[[:space:]]*//p" "$RPM/$1" 2>/dev/null | head -1; }
say() { echo "$*"; }

[ "$(cat $ADSP/name 2>/dev/null)" = adsp ] || { say "# ABORT: $ADSP is not the adsp"; exit 1; }

say "# adsp-restart-leg $TAG uptime=$(cut -d. -f1 /proc/uptime)"
say "# LPASS before: shutdowns=$(mf LPASS 'Shutdown count') xo_dur=$(mf LPASS 'XO total duration')"

echo stop > $ADSP/state 2>/dev/null
sleep 3
echo start > $ADSP/state 2>/dev/null
sleep 30
say "# adsp state=$(cat $ADSP/state 2>/dev/null)"

# The gate: one 30 s suspend, and the XO duration has to move by most of it.
d0=$(mf LPASS 'XO total duration'); l0=$(mf LPASS 'Shutdown count')
rtcwake -m mem -s 30 > /dev/null 2>&1
d1=$(mf LPASS 'XO total duration'); l1=$(mf LPASS 'Shutdown count')
ms=$(( ( ${d1:-0} - ${d0:-0} ) / 19200 ))
say "# probe suspend: LPASS +$(( ${l1:-0} - ${l0:-0} ))  XO off ${ms}ms of 30000ms"

if [ "$ms" -lt 20000 ]; then
	say "# ABORT: the DSP did not collapse across the probe suspend."
	say "# Four hours measuring an intervention that did not take is worse than no leg."
	exit 1
fi

say "# gate passed - handing over to slope-leg.sh $TAG"
exec /root/slope-leg.sh "$TAG"
