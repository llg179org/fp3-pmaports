#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Is there a fast instrument hiding in the fuel gauge?
#
# Every sleeping current on this project costs a four-and-a-half-hour slope leg,
# because the only reliable signal is a voltage slope integrated over hours: one
# `current_now` read scatters by ±138 mA. That cost is now the bottleneck - the
# next question (which of three modem-facing services carries the 36 %) needs
# three legs, which is two nights.
#
# `charge_now` is a µAh value. If it moves in usefully small steps during a real
# discharge, then I = dQ/dt prices a state in fifteen minutes instead of four
# hours, with no OCV curve, no awake control and no ratio.
#
# ☠️ It was already sampled once, on the charger with a full pack, and it stood
# still for three minutes with `current_now` reading exactly 0 - because the
# system was running off USB and the battery was neither charging nor
# discharging. That measurement said nothing about the counter; it said the pack
# was idle. This one suspends USBIN so there is a real discharge to count.
#
# ☠️ Restores the charger on every exit path. USBIN suspend lives in the PMIC and
# survives a warm reboot.
#
#   coulomb-probe.sh [minutes] [interval_s]        (defaults 10, 20)

set -u

MINS=${1:-10}
GAP=${2:-20}
B=/sys/class/power_supply/pmi632-battery
CHG=/sys/class/power_supply/pmi632-charger
OUT=/run/night/coulomb-probe.txt
mkdir -p /run/night
[ -s "$OUT" ] && mv "$OUT" "$OUT.$(cut -d. -f1 /proc/uptime)"
say() { echo "$*" | tee -a "$OUT"; }
: > "$OUT"

restore() {
	rc=$?
	echo Charging > $CHG/status 2>/dev/null
	sleep 5
	say "# charger restored: status=$(cat $B/status) online=$(cat $CHG/online)"
	say "# done rc=$rc"
	exit $rc
}
trap restore EXIT INT TERM

# Median of nine, because one read scatters by ±138 mA.
med_i() {
	i=0
	while [ "$i" -lt 9 ]; do cat $B/current_now; i=$((i + 1)); sleep 1; done | sort -n | sed -n 5p
}

say "# coulomb-probe uptime=$(cut -d. -f1 /proc/uptime) minutes=$MINS gap=${GAP}s"
say "# charge_full=$(cat $B/charge_full) capacity=$(cat $B/capacity)%"

echo Unknown > $CHG/status
sleep 15
if [ "$(cat $B/status)" = Charging ]; then
	say "# ABORT: still charging after USBIN suspend - every sample would read the cable"
	exit 1
fi
say "# USBIN suspended: status=$(cat $B/status) online=$(cat $CHG/online)"
say ""
say "# t_s  charge_now_uAh  voltage_uV  capacity  median_i_uA"

end=$(( $(cut -d. -f1 /proc/uptime) + MINS * 60 ))
while [ "$(cut -d. -f1 /proc/uptime)" -lt "$end" ]; do
	say "$(cut -d. -f1 /proc/uptime) $(cat $B/charge_now) $(cat $B/voltage_now) $(cat $B/capacity) $(med_i)"
	sleep "$GAP"
done

say ""
say "# ☠️ Read the second column. If it never changes, there is no fast"
say "# instrument here and the slope leg stays the only way."
