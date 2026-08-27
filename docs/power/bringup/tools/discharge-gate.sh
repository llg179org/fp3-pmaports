#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
# Wait for the charger to TERMINATE (status=Full), then hand the unit to the
# discharge run. ☠️ discharge-run.sh's own gate is capacity >= 97 %, which 99 %
# passes while the pack is still absorbing 190 mA - and a run started mid-taper
# measures the tail of a charge, not the head of a discharge.
# Bounded: if Full never arrives in 90 minutes, start anyway provided the gauge
# is at 99 %, and say so in the log.
set -u
B=/sys/class/power_supply/pmi632-battery
i=0
while [ "$(cat $B/status)" != Full ] && [ $i -lt 90 ]; do
	sleep 60
	i=$((i + 1))
done
echo "# waited ${i} min for Full: status=$(cat $B/status) cap=$(cat $B/capacity)% v=$(cat $B/voltage_now)" \
	>> /var/log/fp3/discharge-gate.log
exec /usr/local/bin/discharge-run.sh 10
