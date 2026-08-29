#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# What is suspend residency worth, in mA?
#
#   sleep-night.sh [floor_pct] [sleep_s] [gap_s]      (defaults 55, 600, 20)
#
# ☠️ WHY IT CANNOT BE current_now. The gauge's poll worker is frozen for the whole
# suspend, so `current_now` samples only the awake gaps - which is the part of the
# night this is trying not to measure. The answer has to come from the pack:
# charge delivered between two capacities, over a night that was mostly asleep,
# against the 98-101 mA the same phone draws awake.
#
# ☠️ IT NEEDS ModemManager STOPPED, and that is not a fix, it is the instrument.
# Measured 2026-08-29: with the daemon running every suspend dies within 16-53 s
# on the modem's SMD edge (`141:smd-edge`, 5 of 5); with it stopped the phone
# sleeps the full 602 s and wakes on its own alarm. A residency measurement with
# the daemon running would measure the daemon.
#
# ☠️ The charge input is restored on every exit path including SIGTERM, because
# the suspend bit lives in the PMIC and survives a warm reboot.
set -u
FLOOR=${1:-55}
SECS=${2:-600}
GAP=${3:-20}
BAT=/sys/class/power_supply/pmi632-battery
O=/var/log/fp3/sleep-night-$(date +%s)
mkdir -p "$O"
L=$O/log
say(){ echo "$(date '+%F %T') $*" >> "$L"; }

restore_input(){
	for f in /sys/class/power_supply/*/input_suspend; do
		[ -w "$f" ] && echo 0 > "$f" 2>/dev/null
	done
	for s in /sys/class/power_supply/*charger*/status; do
		[ -w "$s" ] && echo Charging > "$s" 2>/dev/null
	done
}
trap 'say "signal - restoring charge input"; restore_input; exit 143' INT TERM HUP
trap 'restore_input' EXIT

systemctl is-active ModemManager >/dev/null 2>&1 && {
	say "STOP: ModemManager is running - this would measure the daemon, not the phone"
	exit 1; }

for c in /usr/local/bin/idle-ab.sh; do [ -x "$c" ] && IDLE_AB=$c; done
: "${IDLE_AB:?idle-ab.sh not found - refusing to spend a night on a lit panel}"
say "borrowing a 20 s idle-ab window to lock the session and take the panel down"
"$IDLE_AB" 20 >/dev/null 2>&1 || true
bl=$(cat /sys/class/backlight/*/bl_power 2>/dev/null | head -1)
say "panel: bl_power='$bl'"
[ "${bl:-x}" = 4 ] || { say "STOP: panel is not down"; exit 1; }

for s in /sys/class/power_supply/*charger*/status; do
	[ -w "$s" ] && echo Unknown > "$s" 2>/dev/null
done
sleep 5
st=$(cat "$BAT/status")
say "charge input cut: status=$st"
[ "$st" = Discharging ] || { say "STOP: still '$st' after the cut"; exit 1; }

say "start cap=$(cat $BAT/capacity)% v=$(cat $BAT/voltage_now)uV floor=${FLOOR}% sleep=${SECS}s gap=${GAP}s"
echo "# round wall_s uptime_s slept_s cap v_uV temp_dC wake_irq susp_ok susp_fail" > "$O/rounds.txt"
t_start=$(cut -d. -f1 /proc/uptime)
r=0
while :; do
	cap=$(cat "$BAT/capacity")
	case "$cap" in ''|*[!0-9]*) break ;; esac
	[ "$cap" -le "$FLOOR" ] && { say "reached the ${FLOOR}% floor"; break; }
	r=$((r + 1))
	t0=$(cut -d. -f1 /proc/uptime)
	rtcwake -m mem -s "$SECS" >/dev/null 2>&1
	t1=$(cut -d. -f1 /proc/uptime)
	n=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)
	case "$n" in ''|*[!0-9]*) w=none ;;
		*) w="$n:$(awk -v k="$n:" '$1 == k { print $NF }' /proc/interrupts)" ;;
	esac
	echo "$r $((t1 - t_start)) $t1 $((t1 - t0)) $(cat $BAT/capacity) $(cat $BAT/voltage_now) $(cat $BAT/temp) $w $(cat /sys/power/suspend_stats/success 2>/dev/null) $(cat /sys/power/suspend_stats/fail 2>/dev/null)" >> "$O/rounds.txt"
	sync
	sleep "$GAP"
done

restore_input
say "end cap=$(cat $BAT/capacity)% v=$(cat $BAT/voltage_now)uV rounds=$r"
say "$O"
