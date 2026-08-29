#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Is the modem's awake duty a per-BOOT constant, or does it DECAY after a boot?
#
#   duty-vs-uptime.sh [hours] [window_s]      (defaults 5, 360)
#
# ☠️ WHY THIS EXISTS. On 2026-08-28/29 the same phone gave two tight clusters of
# MPSS duty with nothing but a reboot between them: eight windows at 29-37 % on
# one boot, eight at 44-52 % on the next. That was written up as a "per-boot
# offset" - but the two boots were not sampled at the same age. The low cluster
# was measured 3-7 hours after its boot and the high cluster within one hour of
# its own, so "per-boot offset" and "post-boot decay" fit the same data exactly.
# One of them means every measurement needs a matching boot; the other means
# every measurement needs a matching UPTIME, which is a very different rule.
#
# So: one boot, sampled from the start, out to an age where the other cluster
# lives. The answer is a shape, not a number.
#
# ☠️ Wait for the modem to register before the first window - a window taken
# while it is still searching is not a window about idle behaviour, and that
# mistake has already cost one measurement here (44.4 %, mmcli still answering
# "couldn't find modem").
#
# ☠️ Do not poll the phone while this runs; every ssh login is a wake. Start it
# with systemd-run and read the file afterwards.
set -u
HOURS=${1:-5}; W=${2:-360}
O=/var/log/fp3/duty-vs-uptime-$(date +%s)
mkdir -p "$O"
LOG="$O/duty.txt"
: > "$LOG"

s(){ echo "$*" >> "$LOG"; }
s "# duty-vs-uptime hours=$HOURS window=${W}s start_uptime=$(cut -d. -f1 /proc/uptime)"
s "# kernel=$(uname -v)"

# ☠️ Registration first, with a bound - an unbounded wait would hang the whole
# unattended run if the SIM never comes up.
i=0
while [ $i -lt 60 ]; do
	st=$(mmcli -m 0 2>/dev/null | sed -n 's/.*state: *//p' | head -1)
	case "$st" in *registered*|*connected*) break ;; esac
	sleep 10; i=$((i + 1))
done
s "# modem at first window: state=$(mmcli -m 0 2>/dev/null | sed -n 's/.*state: *//p' | head -1) tech=$(mmcli -m 0 2>/dev/null | sed -n 's/.*access tech: *//p' | head -1)"
s "# uptime_s mpss_up_pct edge_per_s cap"

END=$(( $(cut -d. -f1 /proc/uptime) + HOURS * 3600 ))
while [ "$(cut -d. -f1 /proc/uptime)" -lt "$END" ]; do
	t0=$(cut -d. -f1 /proc/uptime)
	/usr/local/bin/burst-master.sh "$W" >/dev/null 2>&1
	d=$(ls -dt /var/log/fp3/burst-master-* | head -1)
	# Read the columns by HEADER position, not by a hard-coded index - the row
	# has been added to twice already.
	#
	# ☠️ busybox awk has no strtonum(), so do not convert the bitmask at all: the
	# question is only whether it is non-zero, and "0x0" answers that as a string.
	# The first version of this line called strtonum and the whole run would have
	# produced empty output with one "Call to undefined function" on stderr.
	awk -v t0="$t0" -v cap="$(cat /sys/class/power_supply/pmi632-battery/capacity)" '
		/^# t_s/ { for (i = 1; i <= NF; i++) h[$i] = i - 1; next }
		/^#/ { next }
		{ n++; if ($h["MPSS_cores"] != "0x0") up++; e += $h["edge_irq_per_s"] }
		END { if (n) printf "%s %.1f %.1f %s\n", t0, 100 * up / n, e / n, cap }
	' "$d/master.txt" >> "$LOG"
	rm -rf "$d"
done
s "# done uptime=$(cut -d. -f1 /proc/uptime)"
echo "$LOG"
