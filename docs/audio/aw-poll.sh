#!/bin/sh
# Poll the amplifier's chip-ID register on the wire, from the earliest moment
# the driver's regmap exists, and record when it stops answering.
#
# The read must bypass the cache: AW8898_ID is not volatile, so a plain read is
# answered from the cache and would report a live chip forever.
D=/sys/kernel/debug/regmap/4-0034
LOG=/run/aw-poll.log
: > "$LOG"
i=0
while [ ! -e "$D/registers" ] && [ "$i" -lt 600 ]; do i=$((i+1)); usleep 100000; done
[ -e "$D/registers" ] || { echo "no regmap after wait" >> "$LOG"; exit 0; }
echo "regmap appeared at $(cut -d' ' -f1 /proc/uptime)" >> "$LOG"
fails=0
while [ "$fails" -lt 10 ]; do
	echo 1 > "$D/cache_bypass" 2>/dev/null
	v=$(head -1 "$D/registers" 2>/dev/null)
	echo 0 > "$D/cache_bypass" 2>/dev/null
	printf '%s %s\n' "$(cut -d' ' -f1 /proc/uptime)" "$v" >> "$LOG"
	case "$v" in *XXXX*) fails=$((fails+1)) ;; *) fails=0 ;; esac
	usleep 200000
done
echo "chip stopped answering; last uptime $(cut -d' ' -f1 /proc/uptime)" >> "$LOG"
