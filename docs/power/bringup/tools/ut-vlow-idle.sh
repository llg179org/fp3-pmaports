#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 4.8) under the direction of Lajoshazi, Laszlo Gergely.
#
# Oracle half of the deep-sleep differential (UT 4.9, slot_a). The downstream
# kernel exposes NO vlow/vmin file (rpm_stats.c is not built) but DOES expose
# rpm_master_stats (per-master numshutdowns/xo_count) and lpm_stats. Those are
# the instruments the oracle has for "does the SoC reach its deepest sleep".
# Cable IN, runtime-idle, screen blanked.
#
#   ut-vlow-idle.sh <tag> [duration_s] [interval_s]   (run as root)
set -u
TAG=${1:?usage}
DUR=${2:-1800}
IVAL=${3:-60}
LOG=/tmp/vlow-idle-$TAG.log
D=/sys/kernel/debug
[ "$(id -u)" = 0 ] || { echo "need root" >&2; exit 1; }
mount -t debugfs none "$D" 2>/dev/null || true

boot0=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
{
echo "# ut-vlow tag=$TAG dur=${DUR}s ival=${IVAL}s boot=$boot0 kernel=$(uname -r)"
echo "# rpm_master_stats present=$([ -e $D/rpm_master_stats ] && echo yes || echo no); rpm_stats(vlow) present=$([ -e $D/rpm_stats ] && echo yes || echo no)"
} > "$LOG"

# blank the display (UT 4.9 fb sysfs)
for fb in /sys/class/graphics/fb*/blank; do [ -w "$fb" ] && echo 4 > "$fb" 2>/dev/null; done
echo "# fb blank written" >> "$LOG"

# compact per-master extractor: MASTER=numshutdowns/xo_count
snap_master() {
	awk '/^[A-Z]/{m=$1} /numshutdowns:/{ns[m]=$0} /xo_count:/{xc[m]=$0}
	     END{ for(k in ns){ gsub(/.*:/,"",ns[k]); gsub(/.*:/,"",xc[k]); printf "%s=%s/%s ",k,ns[k],xc[k] } }' \
	     "$D/rpm_master_stats" 2>/dev/null
}
# lpm system-pc success count
snap_lpm() {
	awk '/\[system\] system-pc:/{f=1} f&&/success count:/{print $NF; exit}' "$D/lpm_stats/stats" 2>/dev/null
}

echo "uptime | masters(numshutdowns/xo_count) | system-pc_success | suspend_success" >> "$LOG"
t=0
while [ "$t" -lt "$DUR" ]; do
	up=$(cut -d' ' -f1 /proc/uptime)
	ss=$(awk '/success/{print $2; exit}' /sys/power/suspend_stats/success 2>/dev/null; cat /sys/power/suspend_stats/success 2>/dev/null)
	printf '%s | %s| pc=%s ss=%s\n' "$up" "$(snap_master)" "$(snap_lpm)" "${ss:-?}" >> "$LOG"
	sleep "$IVAL"; t=$((t + IVAL))
	[ "$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)" = "$boot0" ] || { echo "# boot_id CHANGED" >> "$LOG"; break; }
done
echo "# done" >> "$LOG"
