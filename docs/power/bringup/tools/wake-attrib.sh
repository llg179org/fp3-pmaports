#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# WHICH source wakes the phone from s2idle, on battery versus on the cable?
#
# ☠️ Two instruments were tried for this on 2026-08-25/26 and both came back
# empty, for reasons now understood and worth not repeating:
#
#   * `/sys/power/pm_wakeup_irq` DOES NOT EXIST on this kernel. It is gated on
#     CONFIG_PM_SLEEP_DEBUG (kernel/power/main.c:1095), which is def_bool y on
#     CONFIG_PM_DEBUG, and our config had `# CONFIG_PM_DEBUG is not set`. It was
#     read as an empty file and reported as "the counter does not attribute
#     s2idle wakes". Enabled in r77; until that ships, it is simply absent.
#   * `/sys/class/wakeup/*/wakeup_count` genuinely does not advance for an IRQ
#     armed through the plain `enable_irq_wake` path, because nothing on that
#     path calls `pm_wakeup_event()`. That one was measured, and it stands.
#
# But a driver that reports a wakeup THROUGH the wakeup-source API does advance
# those counters, and the charger/typec/battery devices on this PMIC each own a
# wakeup source. So this is the right instrument for exactly one question, which
# is the question in front of us: does suspending USBIN make the CHARGER wake the
# phone?
#
# ☠️ Read the header of /sys/kernel/debug/wakeup_sources, do not index blind.
# Ten fields: name active_count event_count wakeup_count expire_count
# active_since total_time max_time last_change prevent_suspend_time. A positional
# read one column off is how a settled exclusion appeared to collapse on
# 2026-08-26; last_change ($9) is a timestamp and is nonzero for anything that
# has ever fired.
#
#   wake-attrib.sh [seconds]        (default 600)
#
# ☠️ It suspends USBIN for the battery arm and restores it on every exit path,
# including a kill. The bit lives in the PMIC and survives a warm reboot.
set -u
SECS=${1:-600}
CHG=/sys/class/power_supply/pmi632-charger
BATT=/sys/class/power_supply/pmi632-battery
O=/run/wake-attrib.txt
: > "$O"
s(){ echo "$*" >> "$O"; }
restore(){ echo Charging > "$CHG/status" 2>/dev/null; }
trap restore EXIT INT TERM

ws(){ awk 'NR>1 {print $1":"$2":"$3":"$4}' /sys/kernel/debug/wakeup_sources | sort; }
irqs(){ awk 'NR>1 {t=0; for(i=2;i<=NF-3;i++) if ($i ~ /^[0-9]+$/) t+=$i; print $1, t}' /proc/interrupts | sort; }

arm(){
	label=$1
	ws > /run/.wa_ws0; irqs > /run/.wa_i0
	t0=$(cut -d. -f1 /proc/uptime)
	rtcwake -m mem -s "$SECS" >/dev/null 2>&1
	t1=$(cut -d. -f1 /proc/uptime)
	ws > /run/.wa_ws1; irqs > /run/.wa_i1
	sl=$((t1 - t0))
	s "$label slept=${sl}s of ${SECS}s  online=$(cat $CHG/online) status=$(cat $BATT/status)"
	# active_count / event_count / wakeup_count deltas - the API path a driver
	# uses to say "I woke the system", which is precisely what is under test.
	awk -F: 'NR==FNR{a[$1]=$2; e[$1]=$3; w[$1]=$4; next}
		{da=$2-a[$1]; de=$3-e[$1]; dw=$4-w[$1];
		 if (da||de||dw) printf "    ws %-46s active+%d event+%d wakeup+%d\n", $1, da, de, dw}' \
		/run/.wa_ws0 /run/.wa_ws1 >> "$O"
	# ☠️ NO head. The first run of this script truncated to 8 lines and the
	# result was nearly a finding: irq 140 showed at +36 in the battery arms and
	# was reported ABSENT from the cable arms - where the 8th line was +39, so a
	# +36 would have ranked 9th and been cut. A truncated list read as a complete
	# one is the same error as a mis-indexed column, and it very nearly launched
	# a whole experiment on an artifact.
	awk -v sl="$sl" 'NR==FNR{a[$1]=$2; next}
		{d=$2-a[$1]; if (d>0) printf "    irq %-12s +%-7d %.2f/s\n", $1, d, (sl>0 ? d/sl : 0)}' \
		/run/.wa_i0 /run/.wa_i1 | sort -t+ -k2 -rn >> "$O"
	s ""
}

s "# wake-attrib $(date) uptime=$(cut -d. -f1 /proc/uptime) secs=$SECS"
s "# ☠️ interleaved, not one arm then the other: anything drifting shows as a"
s "# pattern in time rather than as a difference between the arms."

i=1
while [ "$i" -le 2 ]; do
	s "== round $i =="
	restore; sleep 20
	arm "  CABLE   "
	echo Unknown > "$CHG/status"; sleep 20
	arm "  BATTERY "
	restore; sleep 60
	i=$((i + 1))
done
s "# done, charger restored: online=$(cat $CHG/online) status=$(cat $BATT/status)"
