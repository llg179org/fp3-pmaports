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
# Usage: freq-probe.sh <label> [cut ...]
#   cut   a systemd unit to stop, or the literal token "wifi" for the radio
#
# ☠️ With no cuts it degenerates into three identical phases, which is not
# useless - it measures this instrument's own repeatability - but it is not
# what you usually want.
set -u

LABEL=${1:?usage: freq-probe.sh <label> [cut ...]}
shift
B=/sys/class/power_supply/pmi632-battery
CHG=/sys/class/power_supply/pmi632-charger
CPU=/sys/devices/system/cpu/cpufreq
OUT=/run/$LABEL.txt
SETTLE=120
N=36
STEP=20
CUTS="$*"

# ☠️ "wifi" is not a unit. Stopping NetworkManager would take usb0 with it -
# the last way in once the radio is down - so the radio goes down with nmcli
# and NM stays up.
cut_off() {
	for s in $CUTS; do
		if [ "$s" = wifi ]; then nmcli radio wifi off 2>/dev/null
		elif [ "$s" = display ]; then
			# ☠️ "cutting" the display means forcing DPMS off. Setting the
			# backlight to 0 is NOT the same thing and was the trap: a panel at
			# zero brightness is still powered, and a leg that only dimmed it
			# measured the panel as if it were off.
			for d in /sys/class/drm/card0/card0-*/dpms; do
				[ -w "$d" ] && echo off > "$d"
			done
			for fb in /sys/class/graphics/fb*/blank; do [ -w "$fb" ] && echo 4 > "$fb"; done
		else systemctl stop "$s" 2>/dev/null; fi
	done
}
cut_on() {
	for s in $CUTS; do
		if [ "$s" = wifi ]; then nmcli radio wifi on 2>/dev/null
		elif [ "$s" = display ]; then
			for fb in /sys/class/graphics/fb*/blank; do [ -w "$fb" ] && echo 0 > "$fb"; done
			for d in /sys/class/drm/card0/card0-*/dpms; do
				[ -w "$d" ] && echo on > "$d"
			done
		else systemctl start "$s" 2>/dev/null; fi
	done
}
cut_state() {
	for s in $CUTS; do
		if [ "$s" = wifi ]; then say "#   wifi radio -> $(nmcli radio wifi 2>/dev/null)"
		elif [ "$s" = display ]; then say "#   dpms -> $(cat /sys/class/drm/card0/card0-DSI-1/dpms 2>/dev/null)"
		else say "#   $s -> $(systemctl is-active "$s" 2>/dev/null)"; fi
	done
}

say() { echo "$*" >> "$OUT"; }

restore() {
	echo Charging > $CHG/status 2>/dev/null
	cut_on
}
trap restore EXIT INT TERM

: > "$OUT"
say "# $LABEL start uptime=$(cut -d. -f1 /proc/uptime) boot_id=$(cat /proc/sys/kernel/random/boot_id)"

systemctl stop greetd 2>/dev/null
sleep 5
for bl in /sys/class/backlight/*; do [ -w "$bl/brightness" ] && echo 0 > "$bl/brightness"; done

# ☠️ A probe has to ESTABLISH the un-cut state, not assume it. Measured
# 2026-08-19: this was launched to test the display with the panel already
# blanked by phosh, so P0 and P1 would have been the same state and the probe
# would have reported "the display costs nothing" - a null produced by the
# setup, not by the device. Whatever is in CUTS, put it back on first.
case " $CUTS " in
*" display "*)
	for d in /sys/class/drm/card0/card0-*/dpms; do [ -w "$d" ] && echo on > "$d"; done
	say "# forced dpms on for the baseline -> $(cat /sys/class/drm/card0/card0-DSI-1/dpms 2>/dev/null)"
	;;
esac

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
p0tis=[$(tis 0)] p4tis=[$(tis 4)] \
dpms=$(cat /sys/class/drm/card0/card0-DSI-1/dpms 2>/dev/null) \
bl=$(cat /sys/class/backlight/*/brightness 2>/dev/null | head -1)"
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

say "# === P1 cut: $CUTS ==="
cut_off
cut_state
phase P1

say "# === P2 restored - the control ==="
cut_on
sleep 20
cut_state
phase P2

echo Charging > $CHG/status
say "# charger restored online=$(cat $CHG/online)"
say "# DONE"
cp "$OUT" /home/fp3/ 2>/dev/null || true
