#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# WHAT THE IMS LOOP COSTS IN MILLIAMPS — the paired census the duty ladder cannot give.
#
#   ims-ma.sh [minutes_per_leg] [alarm_s]      default 45 600, run as root
#
# The 2026-09-02 ladder measured the duty (44.5 % IMS on → 4.8 % IMS off) but
# priced nothing: all three legs ran on the cable with the AP awake, so their
# voltage column is meaningless. The model would put 4.8 % at ~48 mA, but that
# rests on a fitted slope with a ≥15 mA structural residual - and the goal is a
# number, not an extrapolation. This measures both states directly, one after the
# other, in one boot, with the AP actually sleeping.
#
# ☠️ THE EXPENSIVE LEG GOES FIRST, ON PURPOSE. The pack is at 100 % / 4.32 V and
# the top of the curve is flat, which is the worst place to read current from
# dV/dt. Running the expensive state first walks the pack off the plateau before
# the leg whose number matters most.
#
# ☠️ NO CABLE IS PULLED - the USB input is suspended in the PMIC
# (`echo Unknown > .../pmi632-charger/status`), so ssh over USB keeps working
# while the system runs from the battery. THAT BIT SURVIVES A WARM REBOOT. It is
# restored on every exit path here, and a separate transient dead-man unit
# restores it even if this script is killed - which is not paranoia: on this same
# night a run launched with `nohup` died with its ssh session and left the modem
# firmware stopped for an hour.
set -u
MIN=${1:-45}
ALARM=${2:-600}
O=/var/log/fp3/ims-ma-$(date +%s)
mkdir -p "$O"
L=$O/log.txt
BAT=/sys/class/power_supply/pmi632-battery
CHG=/sys/class/power_supply/pmi632-charger/status
s() { echo "$*" | tee -a "$L"; }

restore() {
	echo Charging > "$CHG" 2>/dev/null
	python3 /tmp/ims-toggle.py on >>"$L" 2>&1
	s "# restored: charger=$(cat $CHG 2>/dev/null), IMS on"
}
trap 'restore' EXIT INT TERM

# The dead-man: restores charging even if this process is killed outright.
#
# ☠️ NOT A systemd TIMER. `systemd-run --on-active=` was measured flaky here -
# 3 of 4 arms fired, the fourth reported rc=0 AND `is-active`=active and then
# never ran. A guard that fails a quarter of the time is not a guard. A plain
# transient SERVICE that watches the wall clock is the same mechanism that just
# carried a 33-minute run without trouble.
#
# ☠️ AND IT WATCHES THE WALL CLOCK, NOT `sleep`. These legs suspend the AP with
# rtcwake, and CLOCK_MONOTONIC does not advance across suspend, so a single long
# `sleep` would drift far past its deadline - in the safe direction, but by an
# amount nobody can predict.
DEADLINE=$(( $(date +%s) + MIN * 2 * 60 + 900 ))
systemd-run --unit=fp3-ims-ma-deadman --collect /bin/sh -c \
	"while [ \$(date +%s) -lt $DEADLINE ]; do sleep 30; done; echo Charging > $CHG" \
	>/dev/null 2>&1
if [ "$(systemctl is-active fp3-ims-ma-deadman.service 2>/dev/null)" = active ]; then
	s "# dead-man armed and RUNNING: charging restored at $(date -d @$DEADLINE '+%F %T' 2>/dev/null || echo $DEADLINE)"
else
	s "# ☠️ DEAD-MAN IS NOT RUNNING - aborting rather than cutting the charger with no net"
	exit 1
fi

s "# ims-ma $(date '+%F %T') ${MIN} min/leg alarm=${ALARM}s"
s "# battery at start: $(cat $BAT/capacity)%  v=$(cat $BAT/voltage_now)uV  status=$(cat $BAT/status)"
echo Unknown > "$CHG"
sleep 5
s "# USB input suspended: charger status now '$(cat $CHG)'"

leg() {   # leg NAME IMSSTATE
	s ""
	s "########## LEG $1  (IMS=$2)  $(date '+%F %T') ##########"
	python3 /tmp/ims-toggle.py "$2" 2>&1 | sed 's/^/#   /' | tee -a "$L"
	sleep 20
	before=$(cat /sys/kernel/debug/qcom_rpm_master_stats/MPSS)
	echo "$before" | sed 's/^/BEFORE /' >> "$O/mpss-$1.txt"
	end=$(( $(cut -d. -f1 /proc/uptime) + MIN * 60 ))
	r=0
	while [ "$(cut -d. -f1 /proc/uptime)" -lt "$end" ]; do
		r=$((r+1))
		echo "# round=$r t=$(date '+%F %T') cap=$(cat $BAT/capacity)% v=$(cat $BAT/voltage_now)uV" >> "$O/rounds-$1.txt"
		rtcwake -m mem -s "$ALARM" >/dev/null 2>&1
		echo "# after: t=$(date '+%F %T') v=$(cat $BAT/voltage_now)uV" >> "$O/rounds-$1.txt"
	done
	cat /sys/kernel/debug/qcom_rpm_master_stats/MPSS | sed 's/^/AFTER /' >> "$O/mpss-$1.txt"
	s "#   $r rounds; $(grep -c '^# after' "$O/rounds-$1.txt") wakes recorded"
	s "#   band/cell: $(qmicli -d qrtr://0 --nas-get-rf-band-info 2>/dev/null | sed -n "s/.*Active Band Class: *//p" | head -1) $(mmcli -m any 2>/dev/null | sed -n 's/.*state: *//p' | head -1)"
}

leg expensive on
leg cheap off

s ""
s "# done $(date '+%F %T')  battery $(cat $BAT/capacity)%  v=$(cat $BAT/voltage_now)uV"
systemctl stop fp3-ims-ma-deadman.service 2>/dev/null
