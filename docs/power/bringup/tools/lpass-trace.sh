#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# lpass-trace — sample the LPASS master stats from before the freeze.
#
# LPASS stops shutting down at ~46 s of uptime, which is earlier than ssh is
# reachable on this device (~39 s, and not reliably). So this runs as a boot
# unit and just records, at 1 s granularity, the two counters and the uptime.
# Each sample also goes to /dev/kmsg so it sits in the journal next to whatever
# else happened at that instant - no clock arithmetic between three time bases.
set -u
OUT=/run/lpass-trace.log
MS=/sys/kernel/debug/qcom_rpm_master_stats
modprobe rpm_master_stats 2>/dev/null
exec >"$OUT" 2>&1
# Gate: refuse to produce a log at all rather than a log full of blanks.
[ -r "$MS/LPASS" ] || { echo "ABORT: $MS/LPASS unreadable (uid=$(id -u))"; exit 1; }
echo "== lpass-trace start uptime=$(cut -d. -f1 /proc/uptime)"
n=0
while [ $n -lt 240 ]; do
	u=$(cut -d. -f1 /proc/uptime)
	sd=$(awk '/^\tShutdown count/{print $NF}' "$MS/LPASS")
	xo=$(awk '/^\tXO shutdown count/{print $NF}' "$MS/LPASS")
	ls=$(awk '/Last shutdown @/{print $NF}' "$MS/LPASS")
	asd=$(awk '/^\tShutdown count/{print $NF}' "$MS/APSS")
	line="t=$u lpass_sd=$sd lpass_xo=$xo lpass_last=$ls apss_sd=$asd"
	echo "$line"
	# Also into the kernel ring, so the counter lands in the journal on the
	# journal's own clock. Correlating two clocks by arithmetic was the last
	# thing that went wrong here: the RPM tick counter leads /proc/uptime by
	# the bootloader's time, and the journal's monotonic base is a third
	# thing again. Writing the sample where the events are removes the step.
	echo "lpass-trace: $line" >/dev/kmsg 2>/dev/null
	n=$((n+1)); sleep 1
done
echo "== lpass-trace done uptime=$(cut -d. -f1 /proc/uptime)"
