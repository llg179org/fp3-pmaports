#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# THE CURRENT NUMBER, WITH AN INSTRUMENT THAT SEES THE SLEEPING PHONE.
#
#   ims-ma3.sh [min_per_leg] [alarm_s] [band]     default 25 60 eutran-1
#
# Two earlier censuses got the duty right and the milliamps wrong, for reasons
# now understood: `voltage_now` read right after wake reports IR drop, and
# `current_now` needs the AP awake, so a 600 s alarm gave three samples per leg
# whose scatter (A −148.0 against A′ −202.9 mA, the same configuration) exceeded
# the effect. This one uses the PMI632 fuel gauge's hardware current accumulator,
# which keeps counting while the AP is suspended - see
# `../leads/qg-accumulator-current.md` for how it was validated.
#
# ☠️ HENCE A SHORT ALARM, NOT 600. The accumulator wraps at ACCUM_CNT = 255 and
# samples arrive at ~3.35/s, so it spans at most ~76 s: it is an average over the
# last minute, not a charge counter.
#
# ☠️☠️ AND THE ALARM SHOULD BE 90 s, NOT 60 - the first run of this script used
# 60 and was wrong. The contaminating current is not this wake's, it is the
# PREVIOUS one's: if the sleep is shorter than the wrap period and no wrap falls
# inside it, the window read at wake reaches back past the sleep and carries the
# previous wake's awake current. At 60 s a wrap lands inside the sleep with
# probability 60/76, so about a fifth of the samples are contaminated - and
# always upward. At 90 s a wrap is guaranteed to fall inside, and the window
# always covers sleep alone; the older part being dropped is not a loss, it is
# exactly the contaminated part being dropped.
#
# ☠️ ANALYSE cnt-WEIGHTED, and gate on it. Aggregate as sum(accum)/sum(cnt), not
# the mean of per-sample means. And with a sleep shorter than the wrap period,
# discard any sample whose cnt implies a window longer than the sleep
# (cnt >= 3.35 * alarm) - that sample's window began before the sleep did.
#
# ☠️ WHAT IS MEASURED IS THE SLEEPING FLOOR, not the average a user would see:
# the resume path's own ~0.5-1 s of awake current sits inside the window (~1-3 mA
# upward), and the wake overhead itself (~3 s in every alarm period) is not
# counted at all. Both are identical in every leg, so they cancel in a
# difference; they do not cancel in an absolute number.
#
# ☠️ THE IMS VECTOR IS READ BACK AT EACH LEG'S START AND END. The setting does
# not survive a reboot and can revert; a revert in mid-leg is exactly the silent
# state change that stayed invisible for sixteen days in the speaker-amp saga.
set -u
MIN=${1:-25}
ALARM=${2:-60}
BAND=${3:-eutran-1}
O=/var/log/fp3/ims-ma3-$(date +%s)
mkdir -p "$O"
L=$O/log.txt
BAT=/sys/class/power_supply/pmi632-battery
CHG=/sys/class/power_supply/pmi632-charger/status
REG=/sys/kernel/debug/regmap/0-02/registers
s() { echo "$*" | tee -a "$L"; }

restore() {
	echo Charging > "$CHG" 2>/dev/null
	mmcli -m any --set-current-bands=any >/dev/null 2>&1
	python3 /usr/local/bin/ims-toggle.py on >>"$L" 2>&1
	s "# restored: charger=$(cat $CHG 2>/dev/null), bands any, IMS on"
}
trap 'restore' EXIT INT TERM

DEADLINE=$(( $(date +%s) + (MIN * 3 + 20) * 60 ))
systemd-run --unit=fp3-ims-ma3-deadman --collect /bin/sh -c \
	"while [ \$(date +%s) -lt $DEADLINE ]; do sleep 30; done; echo Charging > $CHG" >/dev/null 2>&1
[ "$(systemctl is-active fp3-ims-ma3-deadman.service 2>/dev/null)" = active ] \
	|| { s "# ☠️ DEAD-MAN IS NOT RUNNING - aborting rather than cutting the charger with no net"; exit 1; }
s "# dead-man armed until $(date -d @$DEADLINE '+%F %T' 2>/dev/null || echo $DEADLINE)"

s "# ims-ma3 $(date '+%F %T') ${MIN} min/leg alarm=${ALARM}s band=$BAND"
s "# battery: $(cat $BAT/capacity)% v=$(cat $BAT/voltage_now)uV status=$(cat $BAT/status)"
mmcli -m any --set-current-bands="$BAND" >/dev/null 2>&1 \
	|| s "# ☠️ set-current-bands=$BAND FAILED - the legs are NOT band-pinned"
echo Unknown > "$CHG"; sleep 5
s "# USB input suspended: charger status '$(cat $CHG)'"

ims_line() { python3 /usr/local/bin/ims-toggle.py read 2>/dev/null \
	| awk '/voice|VoWiFi|video|SMS|UT|USSD/{printf "%s=%s ", $1, $2} END{print ""}'; }

leg() {   # leg NAME IMSSTATE
	s ""
	s "########## LEG $1  (IMS=$2)  $(date '+%F %T') ##########"
	python3 /usr/local/bin/ims-toggle.py "$2" >/dev/null 2>&1
	sleep 15
	s "#   IMS at leg start: $(ims_line)"
	sed 's/^/BEFORE /' /sys/kernel/debug/qcom_rpm_master_stats/MPSS >> "$O/mpss-$1.txt"
	end=$(( $(cut -d. -f1 /proc/uptime) + MIN * 60 ))
	while [ "$(cut -d. -f1 /proc/uptime)" -lt "$end" ]; do
		rtcwake -m mem -s "$ALARM" >/dev/null 2>&1
		# ☠️ FIRST thing after wake, before anything else runs: one grep pass,
		# because the accumulator can wrap between reads and then the sum and
		# the count describe different windows.
		R=$(grep -E '^488[b-e]:' "$REG")
		acc=$(echo "$R" | awk -F': ' '/^488b/{a=$2} /^488c/{b=$2} /^488d/{c=$2} END{print c b a}')
		cnt=$(echo "$R" | awk -F': ' '/^488e/{print $2}')
		printf '%s t=%s acc=0x%s cnt=0x%s cur=%s v=%s cap=%s\n' \
			"$1" "$(date '+%F %T')" "$acc" "$cnt" \
			"$(cat $BAT/current_now)" "$(cat $BAT/voltage_now)" "$(cat $BAT/capacity)" \
			>> "$O/samples-$1.txt"
	done
	sed 's/^/AFTER /' /sys/kernel/debug/qcom_rpm_master_stats/MPSS >> "$O/mpss-$1.txt"
	s "#   IMS at leg end:   $(ims_line)"
	s "#   band/cell: $(qmicli -d qrtr://0 --nas-get-rf-band-info 2>/dev/null | sed -n "s/.*Active Band Class: */ /p" | head -1) $(mmcli -m any 2>/dev/null | sed -n 's/.*state: *//p' | head -1)"
	s "#   $(grep -c . "$O/samples-$1.txt") samples"
}

leg A  on
leg B  off
leg A2 on

s ""
s "# done $(date '+%F %T') battery $(cat $BAT/capacity)% v=$(cat $BAT/voltage_now)uV"
systemctl stop fp3-ims-ma3-deadman.service 2>/dev/null
