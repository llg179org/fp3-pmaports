#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# One line carrying every covariate a modem leg is allowed to be compared on.
#
# THE HISTORY THIS EXISTS TO STOP. Three cross-configuration claims fell in one
# day, all with the same shape: a difference between two arms was attributed to
# the thing being varied, while a covariate that was measured on NEITHER side
# had moved. Twice it was the serving band (worth 17 duty points here, more than
# most arms under test); once it was the regime the system happened to be in.
# Endpoint sampling was not enough - the band moved MID-LEG in the RAT ladder of
# 2026-09-01 and only showed up because the next leg's opening witness differed
# from the previous leg's closing one.
#
# So: sample it inside the window, not only at its edges, and carry the fields
# that no capture in this tree has ever recorded - the CS domain in particular.
# A cyclically failing combined attach is an expensive, state-like retry loop
# and nobody has ever looked.
#
# ☠️ THIS PERTURBS WHAT IT MEASURES. Each sample is a handful of QMI reads, and
# QMI reads wake the modem - the thing under measurement. That is acceptable
# ONLY because the perturbation is identical in every leg and so cancels in a
# comparison; it is NOT acceptable to run it in one arm and not the other, and
# it is not acceptable inside a sleep census, where it would suppress the very
# suspend being counted. Same interval in every leg, or no interval at all.
#
# ☠️ A FIELD THAT DID NOT READ PRINTS `?`, NEVER AN EMPTY COLUMN. An empty
# column between full ones reads as "nothing to report", and on this device that
# has been believed before.
#
#   leg-covariates.sh <label>                       one line, now
#   leg-covariates.sh --watch <every_s> <for_s> <label>   a line every <every_s>
set -u
D=qrtr://0     # ☠️ no -p: with the proxy flag libqmi builds a QMUX endpoint even
               # for a qrtr:// device (qmi-device.c:2565) and the open fails

one() {
	rf=$(qmicli -d $D --nas-get-rf-band-info 2>/dev/null)
	sp=$(qmicli -d $D --nas-get-system-selection-preference 2>/dev/null)
	cl=$(qmicli -d $D --nas-get-cell-location-info 2>/dev/null)
	ss=$(qmicli -d $D --nas-get-serving-system 2>/dev/null)
	si=$(qmicli -d $D --nas-get-signal-info 2>/dev/null)
	g() { v=$(echo "$2" | sed -n "s/.*$1: *'\([^']*\)'.*/\1/p" | head -1); echo "${v:-?}"; }
	printf '#   %s t=%s state=%s cs=%s ps=%s mode=%s band=%s chan=%s cell=%s tac=%s rsrp=%s rsrq=%s snr=%s\n' \
		"$1" \
		"$(awk '{printf "%.0f", $1}' /proc/uptime)" \
		"$(mmcli -m any 2>/dev/null | sed -n 's/.*  state: *//p' | head -1)" \
		"$(g CS "$ss")" "$(g PS "$ss")" \
		"$(g 'Mode preference' "$sp")" \
		"$(g 'Active Band Class' "$rf")" "$(g 'Active Channel' "$rf")" \
		"$(g 'Global Cell ID' "$cl")" "$(g 'Tracking Area Code' "$cl")" \
		"$(echo "$cl" | sed -n "s/.*RSRP: *'\([-0-9.]*\).*/\1/p" | head -1)" \
		"$(echo "$si" | sed -n "s/.*RSRQ: *'\([-0-9.]*\).*/\1/p" | head -1)" \
		"$(echo "$si" | sed -n "s/.*SNR: *'\([-0-9.]*\).*/\1/p" | head -1)"
}

if [ "${1:-}" = "--watch" ]; then
	every=$2; for_s=$3; label=${4:-mid}
	t0=$(awk '{printf "%.0f", $1}' /proc/uptime)
	while :; do
		one "$label"
		sleep "$every"
		now=$(awk '{printf "%.0f", $1}' /proc/uptime)
		[ $((now - t0)) -ge "$for_s" ] && break
	done
else
	one "${1:-now}"
fi
