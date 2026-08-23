#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# lpass-bisect — does the sensor stack pin the ADSP awake?
#
# LPASS stops shutting down at ~34 s of uptime on every boot measured so far.
# snsregd starts at ~33.6 s and SMGR runs ON the ADSP, so it is the candidate.
# This takes it away and watches the counter, with a BEFORE window that must
# show the counter flat - if it moves during BEFORE the premise is wrong and
# there is nothing to bisect.
set -u
MS=/sys/kernel/debug/qcom_rpm_master_stats
[ "$(id -u)" -eq 0 ] || { echo "ABORT: must run as root"; exit 1; }
modprobe rpm_master_stats 2>/dev/null
[ -r "$MS/LPASS" ] || { echo "ABORT: $MS/LPASS unreadable"; exit 1; }
sd() { awk '/^\tShutdown count/{print $NF}' "$MS/$1"; }
# ☠️ The count alone cannot tell "pinned awake" from "asleep and staying down".
st() { awk '/XO shutdown enter/{e=$NF} /XO shutdown exit/{x=$NF} /Active cores/{c=$NF}
            END{printf "%s(cores %s)", (e>x ? "ASLEEP" : "AWAKE"), c}' "$MS/$1"; }
watch() {
	l0=$(sd LPASS); a0=$(sd APSS); n=0
	while [ $n -lt "$2" ]; do sleep 5; n=$((n+5))
		echo "  $1 +${n}s LPASS=$(sd LPASS) $(st LPASS) APSS=$(sd APSS)"
	done
	echo "$1: LPASS $l0 -> $(sd LPASS) $(st LPASS)   APSS $a0 -> $(sd APSS)"
}
echo "== uptime $(cut -d. -f1 /proc/uptime)"
echo "-- BEFORE (premise check: LPASS must be flat)"
watch BEFORE 30
echo "-- removing the sensor stack"
systemctl stop iio-sensor-proxy.service snsregd.service
for m in smgr_accel smgr_prox smgr_gyro smgr_mag smgr sns_smgr; do
	rmmod "$m" 2>&1 && echo "   rmmod $m ok"
done
echo "   remaining: $(lsmod | grep -cE '^(smgr|sns_smgr)')"
echo "-- AFTER"
watch AFTER 60
echo "-- restoring"
for m in sns_smgr smgr smgr_accel smgr_gyro smgr_mag smgr_prox; do modprobe "$m" 2>/dev/null; done
systemctl start snsregd.service iio-sensor-proxy.service
echo "   iio devices back: $(ls /sys/bus/iio/devices/ 2>/dev/null | wc -l)"
echo "== DONE"
