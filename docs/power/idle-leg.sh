#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# One leg of an idle-current measurement on the FP3.
#
# ☠️ This script used to fit a slope through voltage_now, because current_now
# reads 0 with a cable attached. That method is unusable near full charge: the
# pack is relaxing, relaxation flattens with time on its own, and a paired
# same-boot test returned a *lower* slope for the heavier load purely because it
# ran second. Do not go back to it.
#
# The instrument instead is the charger's own input suspend. qcom_smbx makes
# POWER_SUPPLY_PROP_STATUS writable on the charger supply and maps it straight
# onto USBIN_SUSPEND_BIT in USBIN_CMD_IL, so
#
#     echo Unknown  > /sys/class/power_supply/pmi632-charger/status   # suspend
#     echo Charging > /sys/class/power_supply/pmi632-charger/status   # release
#
# takes the phone off VBUS without anyone touching the cable, after which
# pmi632-battery/current_now is a direct reading. The USB network link and
# fastboot keep working; only the charging path is suspended.
#
# The other two preconditions are still preconditions:
#
#   * The panel keeps refreshing after the compositor is gone - fbcon holds DRM
#     DPMS on with no userspace client, and msm_mdss fires ~65 times a second.
#     It is worth only ~10 mA of ~150, so it is not the headline, but it is a
#     load that differs between runs if it is not pinned. Blank it and check.
#   * The post-reboot transient is larger than most effects being measured, so
#     the settle is part of the protocol and both legs must use the same one.
#
# ☠️ And the reading drifts: two panel-on means taken two minutes apart on one
# boot differed by 12 mA. Any comparison smaller than that needs interleaved
# A/B/A/B legs, not one of each.
#
#   idle-leg.sh <tag> [settle_s] [samples] [interval_s]
#
# Defaults: 300 s settle, 100 samples 3 s apart. Appends one line to
# /home/fp3/curr-results.txt and the raw samples to /home/fp3/curr-<tag>.raw.

set -eu

TAG=${1:?usage: idle-leg.sh <tag> [settle_s] [samples] [interval_s]}
SETTLE=${2:-300}
N=${3:-100}
IVAL=${4:-3}

BATT=/sys/class/power_supply/pmi632-battery
CHG=/sys/class/power_supply/pmi632-charger
OUT=/home/fp3/curr-results.txt
RAW=/home/fp3/curr-$TAG.raw

die() { echo "idle-leg: $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "must run as root"
[ -r "$BATT/current_now" ] || die "no $BATT - is the charger DT layer deployed?"

# --- pin the display ---------------------------------------------------------
systemctl stop greetd 2>/dev/null || true
for fb in /sys/class/graphics/fb*/blank; do
	[ -w "$fb" ] && echo 4 > "$fb"
done
sleep 3

dpms=$(cat /sys/class/drm/card0/card0-DSI-1/dpms 2>/dev/null || echo unknown)
[ "$dpms" = Off ] || die "DSI-1 dpms is '$dpms', not Off"

mdss0=$(awk '/msm_mdss/ {for (i=2;i<=NF;i++) if ($i ~ /^[0-9]+$/) s+=$i} END {print s+0}' /proc/interrupts)
sleep 5
mdss1=$(awk '/msm_mdss/ {for (i=2;i<=NF;i++) if ($i ~ /^[0-9]+$/) s+=$i} END {print s+0}' /proc/interrupts)
[ "$mdss1" -eq "$mdss0" ] || die "msm_mdss still counting ($((mdss1 - mdss0)) in 5 s) - the panel is alive"

# --- take the phone off VBUS -------------------------------------------------
echo Unknown > "$CHG/status"
sleep 10
[ "$(cat "$CHG/online")" = 0 ] || die "charger still online after suspending USBIN"
[ "$(cat "$BATT/status")" = Discharging ] || die "battery is '$(cat "$BATT/status")', not Discharging"
i0=$(cat "$BATT/current_now")
[ "$i0" -lt 0 ] || die "current_now is $i0, expected a negative (discharge) reading"

echo "idle-leg: discharging at ${i0}uA, settling ${SETTLE}s" >&2
sleep "$SETTLE"

: > "$RAW"
s=0
i=0
while [ "$i" -lt "$N" ]; do
	c=$(cat "$BATT/current_now")
	echo "$c" >> "$RAW"
	s=$((s + c))
	i=$((i + 1))
	[ "$i" -lt "$N" ] && sleep "$IVAL"
done

echo "$TAG mean_uA=$((s / N)) n=$N settle=${SETTLE}s" | tee -a "$OUT"
