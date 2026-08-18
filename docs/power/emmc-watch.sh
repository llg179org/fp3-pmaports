#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Did the eMMC fall off the bus, and was the application processor collapsed
# when it did?
#
# On the night of 2026-08-17 the card stopped answering ("cache flush error
# -110", then "mmc_hs400_to_hs200 failed"), root went emergency_ro, and from
# that moment the journal recorded nothing but its own failure to write. So the
# one instrument that could have said when it happened and what the RPM was
# doing at the time was on the filesystem that had just died.
#
# ☠️ THIS LOG THEREFORE LIVES ON tmpfs. /run survives a read-only root, and it
# is the only reason this script exists rather than a journal grep.
#
# It also writes to root every cycle. That is the actual detector: emergency_ro
# is invisible to a reader, and the first failed touch stamps the transition to
# within one interval. Everything else on the line is context for that instant.
#
# ☠️ The RTC reads 1970 on this device, so every timestamp here is uptime.
#
#   emmc-watch.sh [interval_s]

set -u

GAP=${1:-30}
OUT=/run/emmc-watch.log
PROBE=/home/fp3/.emmc-watch-probe
RPM=/sys/kernel/debug/qcom_rpm_master_stats/APSS
STATS=/sys/kernel/debug/qcom_stats

f() { cat "$1" 2>/dev/null || echo '?'; }

# Pull one field out of a master-stats block.
# ☠️ The lines are TAB-INDENTED ("\tShutdown count: 41841"), so an
# expression anchored at ^ matches nothing and every reading silently prints
# '?'. Allow the leading whitespace. The anchor still has to be there, because
# the same file also carries "XO shutdown count" - different capital, so the
# two do not collide, but only as long as the pattern stays anchored.
m() { sed -n "s/^[[:space:]]*$1[[:space:]]*:[[:space:]]*//p" "$RPM" 2>/dev/null | head -1; }

# Sleep-record counts. Absent record => '?', not 0: a missing instrument and a
# zero reading are different answers and must not print the same.
c() { sed -n 's/^Count[[:space:]]*:[[:space:]]*//p' "$STATS/$1" 2>/dev/null | head -1; }

# ☠️ Nothing autoloads this one. rpm_master_stats is a module, the DT node
# binds no driver until it is inserted, and without it the whole APSS column is
# '?' - which looks like "the processor never collapsed" and is the opposite of
# what it means.
modprobe rpm_master_stats 2>/dev/null || true

echo "# emmc-watch start uptime=$(cut -d. -f1 /proc/uptime) gap=${GAP}s apss=$(m 'Shutdown count')" >> "$OUT"

while :; do
	apss_shut=$(m 'Shutdown count')
	apss_xo=$(m 'XO shutdown count')

	if : > "$PROBE" 2>/dev/null; then
		rw=ok
	else
		rw=FAIL
	fi

	vlow=$(c vlow); vmin=$(c vmin)
	printf 'up=%s write=%s timing=%s clock=%s apss_shut=%s apss_xo=%s vlow=%s vmin=%s susp_ok=%s susp_fail=%s\n' \
		"$(cut -d. -f1 /proc/uptime)" \
		"$rw" \
		"$(sed -n 's/^timing spec:[[:space:]]*//p' /sys/kernel/debug/mmc0/ios 2>/dev/null | head -1)" \
		"$(sed -n 's/^clock:[[:space:]]*//p' /sys/kernel/debug/mmc0/ios 2>/dev/null | head -1)" \
		"${apss_shut:-?}" \
		"${apss_xo:-?}" \
		"${vlow:-?}" \
		"${vmin:-?}" \
		"$(f /sys/power/suspend_stats/success)" \
		"$(f /sys/power/suspend_stats/fail)" \
		>> "$OUT"

	sleep "$GAP"
done
