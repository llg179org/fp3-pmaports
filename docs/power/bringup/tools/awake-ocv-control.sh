#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# The CONTROL leg for sleep-night.sh: the same instrument, in the regime this
# phone already has a number for.
#
#   awake-ocv-control.sh [minutes] [gap_s]      (defaults 45, 620; run as root)
#
# ☠️ WHY THIS EXISTS. sleep-night.sh prices a suspend by fitting the rest-OCV
# voltage against time, and that fit has no known-positive of its own: it is a new
# instrument aimed at a regime nothing else can measure, which is exactly the
# shape that once produced a "spectacular sub-2 mA" reading. The control is the
# cheap fix - run the identical sampling with the phone AWAKE, where the answer is
# already known from the ladder (~98.5 mA on LTE), and see whether the fit
# reproduces it. If it does not, the sleeping number is not a measurement.
#
# It writes the SAME columns as sleep-night.sh, so sleep-night-fit.py reads it
# without changes; `slept_s` is 0 in every row, which is what marks it a control.
#
# ☠️ It cuts the charge input, exactly as sleep-night.sh does, and restores it on
# every exit path - the suspend bit lives in the PMIC and survives a warm reboot.
set -u
MIN=${1:-45}
GAP=${2:-620}
BAT=/sys/class/power_supply/pmi632-battery
O=/var/log/fp3/awake-ocv-$(date +%s)
mkdir -p "$O"
L=$O/log
say(){ echo "$(date '+%F %T') $*" >> "$L"; }

restore_input(){
	for s in /sys/class/power_supply/*charger*/status; do
		[ -w "$s" ] && echo Charging > "$s" 2>/dev/null
	done
}
trap 'say "signal - restoring charge input"; restore_input; exit 143' INT TERM HUP
trap 'restore_input' EXIT

# ☠️ Same gate as sleep-night.sh, for the same reason: with the daemon up this
# measures the daemon. The control must sit in the SAME configuration as the leg
# it is controlling, or it controls nothing.
systemctl is-active ModemManager >/dev/null 2>&1 && {
	say "STOP: ModemManager is running - the control must match sleep-night.sh's configuration"
	echo "STOP: ModemManager is running"; exit 1; }

for c in /usr/local/bin/idle-ab.sh; do [ -x "$c" ] && IDLE_AB=$c; done
: "${IDLE_AB:?idle-ab.sh not found - refusing to measure on a lit panel}"
say "borrowing a 20 s idle-ab window to lock the session and take the panel down"
"$IDLE_AB" 20 >/dev/null 2>&1 || true
bl=$(cat /sys/class/backlight/*/bl_power 2>/dev/null | head -1)
say "panel: bl_power='$bl'"
[ "${bl:-x}" = 4 ] || { say "STOP: panel is not down"; echo "STOP: panel is not down"; exit 1; }

for s in /sys/class/power_supply/*charger*/status; do
	[ -w "$s" ] && echo Unknown > "$s" 2>/dev/null
done
sleep 5
st=$(cat "$BAT/status")
say "charge input cut: status=$st"
[ "$st" = Discharging ] || { say "STOP: still '$st' after the cut"; echo "STOP: not discharging"; exit 1; }

say "start cap=$(cat $BAT/capacity)% v=$(cat $BAT/voltage_now)uV minutes=$MIN gap=${GAP}s"
echo "# round wall_s uptime_s slept_s cap v_uV temp_dC wake_irq susp_ok susp_fail" > "$O/rounds.txt"
t_start=$(cut -d. -f1 /proc/uptime)
end=$((t_start + MIN * 60))
r=0
while :; do
	t1=$(cut -d. -f1 /proc/uptime)
	[ "$t1" -ge "$end" ] && break
	r=$((r + 1))
	# slept_s is 0: this row is awake time, and that is the whole point
	echo "$r $((t1 - t_start)) $t1 0 $(cat $BAT/capacity) $(cat $BAT/voltage_now) $(cat $BAT/temp) awake $(cat /sys/power/suspend_stats/success 2>/dev/null) $(cat /sys/power/suspend_stats/fail 2>/dev/null)" >> "$O/rounds.txt"
	sync
	sleep "$GAP"
done

restore_input
say "end cap=$(cat $BAT/capacity)% v=$(cat $BAT/voltage_now)uV rounds=$r"
say "$O"
echo "$O"
