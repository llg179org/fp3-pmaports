#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# One duty window per boot, with everything that might explain the boot's level
# recorded beside it.
#
#   boot-level-sample.sh [window_s]        (default 360)
#
# ☠️ WHY. The modem's awake duty is fixed at boot and does not decay: 46 windows
# over 4.8 hours of one boot held a median of 49.5-50.0 % with a slope of
# +0.36 %/hour, while an earlier boot held 29-37 % throughout. Something chosen at
# boot sets a ~15-point level, and nothing measured so far explains it. This
# collects one window per boot together with the candidates - camped cell, band,
# signal, operator, modem firmware state - so that a handful of boots can be
# correlated instead of argued about.
#
# ☠️ Wait for registration before the window; a window taken while the modem is
# still searching is not a window about idle behaviour.
set -u
W=${1:-360}
O=/var/log/fp3/boot-level.txt

s(){ echo "$*" >> "$O"; }

i=0
while [ $i -lt 60 ]; do
	case "$(mmcli -m 0 2>/dev/null | sed -n 's/.*state: *//p' | head -1)" in
		*registered*|*connected*) break ;;
	esac
	sleep 10; i=$((i + 1))
done

s ""
s "=== boot $(cat /proc/sys/kernel/random/boot_id) $(date '+%F %T')"
s "# uptime_at_start=$(cut -d. -f1 /proc/uptime) kernel=$(uname -v)"
mmcli -m 0 2>/dev/null | grep -aE "state:|access tech|signal quality|registration|packet service|operator (name|code)|firmware revision" \
	| sed 's/^/#   /' >> "$O"
qmicli -d qrtr://0 --nas-get-serving-system 2>/dev/null \
	| grep -aE "cell ID|tracking area|location area|MCC|MNC|Radio interfaces" | sed 's/^/#   /' >> "$O"
qmicli -d qrtr://0 --nas-get-rf-band-info 2>/dev/null | sed 's/^/#   band /' >> "$O"
s "#   cap=$(cat /sys/class/power_supply/pmi632-battery/capacity) status=$(cat /sys/class/power_supply/pmi632-battery/status)"

/usr/local/bin/burst-master.sh "$W" >/dev/null 2>&1
d=$(ls -dt /var/log/fp3/burst-master-* | head -1)
# ☠️ busybox awk has no strtonum(); the bitmask only has to be tested for
# non-zero, and "0x0" answers that as a string.
awk '
	/^# t_s/ { for (i = 1; i <= NF; i++) h[$i] = i - 1; next }
	/^#/ { next }
	{ n++; if ($h["MPSS_cores"] != "0x0") up++; e += $h["edge_irq_per_s"] }
	END { if (n) printf "RESULT mpss_up=%.1f%% edge_per_s=%.1f n=%d\n", 100 * up / n, e / n, n }
' "$d/master.txt" >> "$O"
rm -rf "$d"
tail -3 "$O"
