#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# adsp-vlow — does the RPM reach vlow once the ADSP is gone entirely?
#
# The ADSP is the one master that stops voting itself down at ~34 s of uptime.
# Removing its clients one at a time acquitted the sensors. This removes the
# master: remoteproc stop, addressed BY NAME because the indices move between
# boots. If vlow Count leaves 0 in the window after that, the pinned ADSP is
# the blocker end to end; if it does not, the ADSP is not sufficient either.
set -u
MS=/sys/kernel/debug/qcom_rpm_master_stats
V=/sys/kernel/debug/qcom_stats
[ "$(id -u)" -eq 0 ] || { echo "ABORT: must run as root"; exit 1; }
modprobe rpm_master_stats 2>/dev/null
[ -r "$MS/LPASS" ] || { echo "ABORT: master stats unreadable"; exit 1; }
[ -r "$V/vlow" ]    || { echo "ABORT: no $V/vlow"; exit 1; }

RP=$(grep -l '^adsp$' /sys/class/remoteproc/*/name 2>/dev/null | head -1)
RP=${RP%/name}
[ -n "$RP" ] || { echo "ABORT: no remoteproc named 'adsp'"; exit 1; }
echo "adsp is $RP (state: $(cat "$RP/state"))"

sd()  { awk '/^\tShutdown count/{print $NF}' "$MS/$1"; }
cnt() { awk '/Count/{print $NF}' "$V/$1" 2>/dev/null; }
win() {
	echo "  $1: pre  LPASS=$(sd LPASS) vlow=$(cnt vlow) vmin=$(cnt vmin)"
	echo 0 >/sys/class/rtc/rtc0/wakealarm; echo +30 >/sys/class/rtc/rtc0/wakealarm
	systemctl suspend; sleep 4
	echo "  $1: post LPASS=$(sd LPASS) vlow=$(cnt vlow) vmin=$(cnt vmin)"
}

echo "== control window, ADSP running"
win CONTROL

echo "== stopping the ADSP"
echo stop > "$RP/state"; sleep 5
echo "   state now: $(cat "$RP/state")"
[ "$(cat "$RP/state")" = "offline" ] || echo "   WARN: not offline, the rest is not the intended test"

echo "== test window, ADSP offline"
win TEST

echo "== restarting the ADSP"
echo start > "$RP/state"; sleep 10
echo "   state now: $(cat "$RP/state")"
echo "   LPASS after restart: $(sd LPASS)"
echo "== DONE"
