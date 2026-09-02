#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# THE CLEAN MILLIAMP NUMBER — the rerun of ims-ma.sh with its four flaws closed.
#
#   ims-ma2.sh [min_per_leg] [alarm_s]      default 30 600, run as root
#
# The first census (`../captures/2026-09-02_ims-ma/`) got the shape right and the
# number soft: expensive leg 45.6 % duty / ~200 mA, cheap leg asleep the whole
# window / ~40 mA. Four things made the milliamps unquotable, and each has a
# named fix here:
#
#   1. NO BAND PIN, sampled only at the leg ends. This repo prices the band at
#      ~17 pp of duty and at an RF term the duty model does not carry - one
#      reselection can inject an error the size of the effect. Now: pinned, AND
#      sampled at every wake.
#   2. THE FIRST LEG STARTED ON SURFACE CHARGE, seconds after the charger was cut
#      at 100 % / 4.32 V, so its slope was relaxation plus load. Now: a settling
#      leg runs first and is thrown away.
#   3. NO REPEAT ARM. A → B cannot separate "IMS off is cheaper" from "the pack
#      drifted". Now A / B / A'.
#   4. `current_now` WAS NOT SAMPLED, although it is live on this device and the
#      very discharge reference the analysis leans on has a `cur_uA` column. It
#      cannot price a SLEEPING phone - the AP must be up to read it - but every
#      wake already has the AP up, so it costs nothing and prices the awake side
#      directly.
#
# ☠️ The sampling rides the wakes the run already performs. Anything that wakes
# the AP on its own schedule would be measuring its own footprint.
set -u
MIN=${1:-30}
ALARM=${2:-600}
BAND=${3:-eutran-1}
O=/var/log/fp3/ims-ma2-$(date +%s)
mkdir -p "$O"
L=$O/log.txt
BAT=/sys/class/power_supply/pmi632-battery
CHG=/sys/class/power_supply/pmi632-charger/status
s() { echo "$*" | tee -a "$L"; }

restore() {
	echo Charging > "$CHG" 2>/dev/null
	mmcli -m any --set-current-bands=any >/dev/null 2>&1
	python3 /tmp/ims-toggle.py on >>"$L" 2>&1
	s "# restored: charger=$(cat $CHG 2>/dev/null), bands any, IMS on"
}
trap 'restore' EXIT INT TERM

DEADLINE=$(( $(date +%s) + (MIN * 3 + 25) * 60 ))
systemd-run --unit=fp3-ims-ma2-deadman --collect /bin/sh -c \
	"while [ \$(date +%s) -lt $DEADLINE ]; do sleep 30; done; echo Charging > $CHG" >/dev/null 2>&1
[ "$(systemctl is-active fp3-ims-ma2-deadman.service 2>/dev/null)" = active ] \
	|| { s "# ☠️ DEAD-MAN IS NOT RUNNING - aborting rather than cutting the charger with no net"; exit 1; }
s "# dead-man armed and RUNNING until $(date -d @$DEADLINE '+%F %T' 2>/dev/null || echo $DEADLINE)"

s "# ims-ma2 $(date '+%F %T') ${MIN} min/leg alarm=${ALARM}s band=$BAND"
s "# battery at start: $(cat $BAT/capacity)% v=$(cat $BAT/voltage_now)uV status=$(cat $BAT/status)"
mmcli -m any --set-current-bands="$BAND" >/dev/null 2>&1 \
	|| s "# ☠️ set-current-bands=$BAND FAILED - the legs are NOT band-pinned"
echo Unknown > "$CHG"
sleep 5
s "# USB input suspended: charger status now '$(cat $CHG)'"

leg() {   # leg NAME IMSSTATE MINUTES
	s ""
	s "########## LEG $1  (IMS=$2)  $(date '+%F %T') ##########"
	python3 /tmp/ims-toggle.py "$2" 2>&1 | sed 's/^/#   /' | tee -a "$L"
	sleep 20
	sed 's/^/BEFORE /' /sys/kernel/debug/qcom_rpm_master_stats/MPSS >> "$O/mpss-$1.txt"
	end=$(( $(cut -d. -f1 /proc/uptime) + $3 * 60 ))
	while [ "$(cut -d. -f1 /proc/uptime)" -lt "$end" ]; do
		# ☠️ every field on ONE line, sampled while the AP is up anyway
		printf '%s t=%s v=%s cur=%s cap=%s band=%s cell=%s rsrp=%s state=%s\n' \
			"$1" "$(date '+%F %T')" \
			"$(cat $BAT/voltage_now)" "$(cat $BAT/current_now)" "$(cat $BAT/capacity)" \
			"$(qmicli -d qrtr://0 --nas-get-rf-band-info 2>/dev/null | sed -n "s/.*Active Band Class: *'\\([^']*\\)'.*/\\1/p" | head -1)" \
			"$(qmicli -d qrtr://0 --nas-get-cell-location-info 2>/dev/null | sed -n "s/.*Global Cell ID: *'\\([^']*\\)'.*/\\1/p" | head -1)" \
			"$(qmicli -d qrtr://0 --nas-get-signal-info 2>/dev/null | sed -n "s/.*RSRP: *//p" | head -1)" \
			"$(mmcli -m any 2>/dev/null | sed -n 's/.*state: *//p' | head -1)" \
			>> "$O/rounds-$1.txt"
		rtcwake -m mem -s "$ALARM" >/dev/null 2>&1
	done
	sed 's/^/AFTER /' /sys/kernel/debug/qcom_rpm_master_stats/MPSS >> "$O/mpss-$1.txt"
	s "#   $(grep -c . "$O/rounds-$1.txt") samples"
}

# ☠️ THROWN AWAY ON PURPOSE: walks the pack off the 4.3 V plateau so the first
# measured leg is not reading surface-charge relaxation as load.
leg settle on 20
rm -f "$O/mpss-settle.txt"

leg A  on  "$MIN"
leg B  off "$MIN"
leg A2 on  "$MIN"

s ""
s "# done $(date '+%F %T') battery $(cat $BAT/capacity)% v=$(cat $BAT/voltage_now)uV"
systemctl stop fp3-ims-ma2-deadman.service 2>/dev/null
