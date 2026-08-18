#!/bin/sh
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Does stopping the modem stack pin the little cluster at a high OPP?
#
# The idle ladder of 2026-08-18 produced one thing it was not looking for: at
# stage S4, with ModemManager/rmtfs/tqftpserv stopped, the idle FLOOR doubled
# from ~85 mA to ~170 mA, the sample-to-sample variance collapsed, and the
# apcs-cpu0-pll warning storm went to EXACTLY ZERO for the 40 minutes S4 and S5
# lasted. Restoring the services reverted all three at once.
#
# Zero PLL warnings is not "the storm stopped being a problem" - the warning is
# emitted per failed frequency transition, so zero warnings with a doubled draw
# reads as "the cluster stopped changing frequency at all, at a high one". The
# ladder had no cpufreq instrumentation, so this cannot be settled from it.
#
# Three phases, one boot, no reboot in between:
#   P0  baseline
#   P1  modem stack stopped
#   P2  restored - the control, because a one-way change proves nothing
#
# Usage: freq-probe.sh [label]
set -u

LABEL=${1:-freq-probe}
B=/sys/class/power_supply/pmi632-battery
CHG=/sys/class/power_supply/pmi632-charger
CPU=/sys/devices/system/cpu/cpufreq
OUT=/run/$LABEL.txt
SETTLE=120
N=36
STEP=20
CUTS="ModemManager rmtfs tqftpserv"

say() { echo "$*" >> "$OUT"; }

restore() {
	echo Charging > $CHG/status 2>/dev/null
	for s in $CUTS; do systemctl start "$s" 2>/dev/null; done
}
trap restore EXIT INT TERM

: > "$OUT"
say "# $LABEL start uptime=$(cut -d. -f1 /proc/uptime) boot_id=$(cat /proc/sys/kernel/random/boot_id)"

systemctl stop greetd 2>/dev/null
sleep 5
for bl in /sys/class/backlight/*; do [ -w "$bl/brightness" ] && echo 0 > "$bl/brightness"; done

echo Unknown > $CHG/status
sleep 15
say "# charger online=$(cat $CHG/online) batt=$(cat $B/status) v=$(cat $B/voltage_now) cap=$(cat $B/capacity)%"
if [ "$(cat $B/status)" = Charging ]; then
	say "# ABORT: USBIN suspend did not take"
	exit 1
fi

# ☠️ Record the whole residency table, not just the current frequency. A single
# scaling_cur_freq read catches whatever the CPU is doing during the read - it
# is the same trap as reading current_now once. The residency delta over 20 s
# says where the cluster actually LIVED.
tis() {
	tr '\n' ',' < "$CPU/policy$1/stats/time_in_state" | tr -s ' '
}

sample() {
	say "$1 $(cut -d. -f1 /proc/uptime) $(cat $B/current_now) $(cat $B/voltage_now) $(cat $B/capacity) \
p0cur=$(cat $CPU/policy0/scaling_cur_freq) p4cur=$(cat $CPU/policy4/scaling_cur_freq) \
p0trans=$(cat $CPU/policy0/stats/total_trans) p4trans=$(cat $CPU/policy4/stats/total_trans) \
p0tis=[$(tis 0)] p4tis=[$(tis 4)]"
}

phase() {
	tag=$1
	say "# --- phase $tag settling ${SETTLE}s ---"
	sleep "$SETTLE"
	say "# phase $tag sampling $N x ${STEP}s"
	i=0
	while [ "$i" -lt "$N" ]; do
		sample "$tag"
		i=$((i + 1))
		sleep "$STEP"
	done
	say "# phase $tag done"
	cp "$OUT" /home/fp3/ 2>/dev/null || true
}

say "# === P0 baseline ==="
phase P0

say "# === P1 modem stack stopped ==="
for s in $CUTS; do systemctl stop "$s" 2>/dev/null; done
for s in $CUTS; do say "#   $s -> $(systemctl is-active "$s" 2>/dev/null)"; done
phase P1

say "# === P2 restored - the control ==="
for s in $CUTS; do systemctl start "$s" 2>/dev/null; done
sleep 20
for s in $CUTS; do say "#   $s -> $(systemctl is-active "$s" 2>/dev/null)"; done
phase P2

echo Charging > $CHG/status
say "# charger restored online=$(cat $CHG/online)"
say "# DONE"
cp "$OUT" /home/fp3/ 2>/dev/null || true
