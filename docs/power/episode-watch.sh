#!/bin/sh
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Catch the episode.
#
# On 2026-08-18 this phone's idle floor doubled - 85.6 to 169.7 mA - held there
# for about 44 minutes, silenced the apcs-cpu0-pll warning storm completely
# while it lasted, and then cleared on its own. The idle ladder recorded it only
# because it happened to span two of its stages, and attributed it to the cut at
# its boundary; the controlled probe four hours later exonerated that cut and
# left the episode with no explanation and no instrument.
#
# This is the instrument. One sample a minute, to tmpfs, of the four things that
# moved together: current, cpufreq residency, transition count, and the PLL
# failure count.
#
# ☠️ DO NOT RUN THIS DURING A SUSPEND LEG. A wakeup every 60 s is exactly what a
# slope leg's phase A must not have - it would break the suspends it is trying
# to measure, and the leg would report a draw that is partly this watcher.
#
# ☠️ tmpfs on purpose. The eMMC on this device fell off the bus on the night of
# 2026-08-18; a log on the root filesystem is lost with it, and this watcher is
# most valuable precisely on the night something goes wrong.
set -u

B=/sys/class/power_supply/pmi632-battery
CPU=/sys/devices/system/cpu/cpufreq
OUT=/run/episode-watch.txt
STEP=${1:-60}
KEEP=${2:-2880}          # samples to retain; 2880 x 60 s = 48 h

# ☠️ One current_now read scatters by about 138 mA on this gauge. A single read
# per minute would make every sample uninterpretable, so each one is the median
# of nine taken back to back - enough to find the floor, cheap enough to run all
# day.
med9() {
	for _ in 1 2 3 4 5 6 7 8 9; do cat "$B/current_now"; done \
		| sed 's/-//' | sort -n | sed -n 5p
}

pllcount() {
	journalctl -k -b --no-pager 2>/dev/null | grep -c 'wait_for_pll' || echo 0
}

: > "$OUT"
echo "# episode-watch step=${STEP}s boot_id=$(cat /proc/sys/kernel/random/boot_id)" >> "$OUT"
echo "# uptime cur_uA volt_uV cap p0trans p4trans pll p0res614 p0res_top" >> "$OUT"

while :; do
	t0=$(cat "$CPU/policy0/stats/time_in_state")
	low=$(echo "$t0" | head -1 | awk '{print $2}')
	top=$(echo "$t0" | tail -1 | awk '{print $2}')
	printf '%s %s %s %s %s %s %s %s %s\n' \
		"$(cut -d. -f1 /proc/uptime)" \
		"$(med9)" \
		"$(cat $B/voltage_now)" \
		"$(cat $B/capacity)" \
		"$(cat $CPU/policy0/stats/total_trans)" \
		"$(cat $CPU/policy4/stats/total_trans)" \
		"$(pllcount)" \
		"$low" "$top" >> "$OUT"

	# Keep the file bounded - this is meant to run for days.
	lines=$(wc -l < "$OUT")
	if [ "$lines" -gt "$((KEEP + 2))" ]; then
		{ head -2 "$OUT"; tail -n "$KEEP" "$OUT"; } > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
	fi
	sleep "$STEP"
done
