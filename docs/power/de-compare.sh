#!/bin/sh
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# One leg of a desktop-environment power comparison. Run it once per (DE,
# screen-state) pair, each from its own boot, and compare the medians.
#
# Usage: de-compare.sh <label> <on|off>
#   label       phosh | sxmo   - recorded, and checked against what is running
#   on|off      screen on at a fixed brightness, or blanked
#
# ☠️ Two legs are needed per DE, not one. Screen-on is what the user feels but
# the panel swamps the difference; screen-off is where a shell's daemons and a
# shell's scripts actually diverge. Reporting only the first would hide the
# result and reporting only the second would not answer the question asked.
#
# ☠️ Median, never mean. One current_now read on this device scatters by about
# 138 mA; the figure is the median of the samples, and the spread is printed
# next to it so a quiet leg can be told from a noisy one.
#
# ☠️ Logs to tmpfs. If the eMMC drops off the bus mid-leg - which it did on the
# night of 2026-08-18 - a log on the root filesystem is lost along with the
# night. Copied to /home/fp3 at the end, best effort.
set -u
LABEL=${1:?label}
SCREEN=${2:?on|off}
B=/sys/class/power_supply/pmi632-battery
OUT=/run/de-compare-$LABEL-$SCREEN.txt
SETTLE=600
N=50
STEP=30
BRIGHT_PCT=50

say() { echo "$*" >> "$OUT"; }

# ☠️ The USBIN suspend bit lives in the PMIC and survives a warm reboot, so a
# leg that dies before its last line would leave the phone unable to charge
# until someone noticed. Restore it on every exit path, not just the happy one.
restore() { echo Charging > /sys/class/power_supply/pmi632-charger/status 2>/dev/null; }
trap restore EXIT INT TERM

: > "$OUT"
say "# de-compare label=$LABEL screen=$SCREEN uptime=$(cut -d. -f1 /proc/uptime)"

# What is actually running - the label is a promise, this is the fact.
sess=$(ps -eo comm | grep -cE '^(phosh|sway)$' 2>/dev/null || true)
say "# phosh=$(pgrep -c phosh 2>/dev/null || echo 0) sway=$(pgrep -c sway 2>/dev/null || echo 0) procs_matched=$sess"
say "# greetd_session=$(sed -n 's/^command *= *//p' /etc/greetd/config.toml 2>/dev/null | tr -d '\"' | head -2 | tr '\n' ' ')"

bl=$(ls -d /sys/class/backlight/* 2>/dev/null | head -1)
if [ -n "$bl" ]; then
	max=$(cat "$bl/max_brightness")
	want=$((max * BRIGHT_PCT / 100))
	if [ "$SCREEN" = on ]; then
		echo "$want" > "$bl/brightness" 2>/dev/null
	else
		echo 0 > "$bl/brightness" 2>/dev/null
		for fb in /sys/class/graphics/fb*/blank; do [ -w "$fb" ] && echo 4 > "$fb"; done
	fi
	say "# backlight=$bl set=$(cat $bl/brightness) max=$max"
else
	say "# backlight: none found"
fi
say "# dpms=$(cat /sys/class/drm/card0/card0-DSI-1/dpms 2>/dev/null || echo '?')"

# ☠️ Off the charger, or every sample reads the charger and not the phone.
echo Unknown > /sys/class/power_supply/pmi632-charger/status 2>/dev/null
sleep 10
say "# charger online=$(cat /sys/class/power_supply/pmi632-charger/online) status=$(cat $B/status)"
say "# start v=$(cat $B/voltage_now) cap=$(cat $B/capacity)%"

sleep "$SETTLE"
say "# settled, sampling $N x ${STEP}s"

i=0
while [ "$i" -lt "$N" ]; do
	say "$(cut -d. -f1 /proc/uptime) $(cat $B/current_now) $(cat $B/voltage_now) $(cat $B/capacity)"
	i=$((i + 1))
	sleep "$STEP"
done

say "# end v=$(cat $B/voltage_now) cap=$(cat $B/capacity)%"
echo Charging > /sys/class/power_supply/pmi632-charger/status 2>/dev/null
say "# charger restored online=$(cat /sys/class/power_supply/pmi632-charger/online)"
say "# DONE"
cp "$OUT" /home/fp3/ 2>/dev/null || true
