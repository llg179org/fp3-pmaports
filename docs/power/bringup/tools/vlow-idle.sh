#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 4.8) under the direction of Lajoshazi, Laszlo Gergely.
#
# Runtime-idle vlow/vmin witness, pmOS control half of the oracle differential.
# Cable stays IN (no USBIN suspend, no discharge). Question: does the RPM
# aggregate ever enter vlow/vmin while the AP idles with the display genuinely
# DPMS-off? Expected: no. This build's qcom_stats exposes only vlow+vmin
# (no rpm_master_stats), so this samples exactly those.
#
#   vlow-idle.sh <tag> [duration_s] [interval_s]
set -u
TAG=${1:?usage: vlow-idle.sh <tag> [duration_s] [interval_s]}
DUR=${2:-5400}
IVAL=${3:-30}
QS=/sys/kernel/debug/qcom_stats
LOG=/home/fp3/vlow-idle-$TAG.log
die() { echo "vlow-idle: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die "must run as root"
[ -r "$QS/vlow" ] || die "no $QS/vlow"

boot0=$(cat /proc/sys/kernel/random/boot_id)
echo "# vlow-idle tag=$TAG dur=${DUR}s ival=${IVAL}s boot_id=$boot0" > "$LOG"
echo "# link=wifi cable=in charger=$(cat /sys/class/power_supply/pmi632-charger/status 2>/dev/null)" >> "$LOG"

# --- pin the display DPMS-off (backlight=0 is NOT dpms off) ---
systemctl stop greetd 2>/dev/null || true
dpms=unknown; i=0
while [ "$i" -lt 15 ]; do
	for fb in /sys/class/graphics/fb*/blank; do [ -w "$fb" ] && echo 4 > "$fb"; done
	sleep 2
	dpms=$(cat /sys/class/drm/card0/card0-DSI-1/dpms 2>/dev/null || echo unknown)
	[ "$dpms" = Off ] && break
	i=$((i + 1))
done
[ "$dpms" = Off ] || { systemctl start greetd 2>/dev/null || true; die "dpms still '$dpms'"; }
m0=$(awk '/msm_mdss/{for(i=2;i<=NF;i++)if($i~/^[0-9]+$/)s+=$i}END{print s+0}' /proc/interrupts)
sleep 5
m1=$(awk '/msm_mdss/{for(i=2;i<=NF;i++)if($i~/^[0-9]+$/)s+=$i}END{print s+0}' /proc/interrupts)
echo "# dpms=Off mdss_delta_5s=$((m1-m0)) (must be 0 for a real off)" >> "$LOG"

trap 'systemctl start greetd 2>/dev/null || true' EXIT INT TERM

vfield() { awk -v k="$2" '$0 ~ k {print $NF; exit}' "$QS/$1" 2>/dev/null || echo "?"; }

echo "uptime vlow_count vmin_count vlow_votes vmin_votes" >> "$LOG"
t=0
while [ "$t" -lt "$DUR" ]; do
	up=$(cut -d' ' -f1 /proc/uptime)
	vl=$(vfield vlow '^Count:'); vm=$(vfield vmin '^Count:')
	vlv=$(vfield vlow 'Client Votes:'); vmv=$(vfield vmin 'Client Votes:')
	printf '%s %s %s %s %s\n' "$up" "$vl" "$vm" "$vlv" "$vmv" >> "$LOG"
	sleep "$IVAL"
	t=$((t + IVAL))
	[ "$(cat /proc/sys/kernel/random/boot_id)" = "$boot0" ] || { echo "# boot_id CHANGED - aborting" >> "$LOG"; break; }
done
echo "# done: final vlow=$(vfield vlow '^Count:') vmin=$(vfield vmin '^Count:')" >> "$LOG"
