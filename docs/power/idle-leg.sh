#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# One leg of an idle-current measurement on the FP3, with the three traps that
# cost a night's work built in as preconditions rather than prose:
#
#   1. The panel keeps refreshing after the compositor is gone. fbcon holds DRM
#      DPMS on with no userspace client, and msm_mdss fires ~65 times a second -
#      roughly half of all wakeups, and far more current than any AP idle-depth
#      change. Blanking is part of the protocol, and it is verified, not assumed.
#   2. The pack must actually be discharging. With a USB cable attached
#      pmi632-charger/online reads 1, current_now reads 0 and voltage_now sits
#      flat, so a slope computed over that is noise with a sign.
#   3. The post-reboot voltage transient is larger than the effect. The same leg
#      reads -142 / +141 / +156 / +25 mV/h depending only on how much of the head
#      is dropped, so the settle is not optional and both legs must use the same
#      one.
#
# Run it as root on the device. Output is one "epoch uV capacity" line per
# sample, plus the fitted slope on stderr at the end.
#
#   idle-leg.sh <outfile> [samples] [interval_s] [settle_s]
#
# Defaults: 50 samples, 30 s apart, after a 600 s settle - the shape both legs
# of the 2026-08-15 A/B used.

set -eu

OUT=${1:?usage: idle-leg.sh <outfile> [samples] [interval_s] [settle_s]}
N=${2:-50}
IVAL=${3:-30}
SETTLE=${4:-600}

BATT=/sys/class/power_supply/pmi632-battery
CHG=/sys/class/power_supply/pmi632-charger

die() { echo "idle-leg: $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "must run as root"
[ -r "$BATT/voltage_now" ] || die "no $BATT - is the charger DT layer deployed?"

# --- precondition 2: the pack has to be discharging -------------------------
# Measure it rather than infer it. charger/online reads 1 whenever a cable is
# attached, including a suspended port that draws nothing and lets the pack fall
# perfectly well, so online alone would refuse a valid run. What matters is that
# the voltage is actually going down.
v0=$(cat "$BATT/voltage_now")
sleep 60
v1=$(cat "$BATT/voltage_now")
drop=$((v0 - v1))
if [ "$drop" -lt 100 ]; then
	die "voltage moved ${drop}uV in 60 s (charger/online=$(cat "$CHG/online" 2>/dev/null || echo ?)) - not discharging, nothing to measure"
fi
echo "idle-leg: discharging, ${drop}uV in 60 s" >&2

# --- precondition 1: the display has to be off, and proven off --------------
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

# --- precondition 3: settle before the first sample -------------------------
echo "idle-leg: preconditions met, settling ${SETTLE}s" >&2
sleep "$SETTLE"

: > "$OUT"
i=0
while [ "$i" -lt "$N" ]; do
	echo "$(date +%s) $(cat "$BATT/voltage_now") $(cat "$BATT/capacity")" >> "$OUT"
	i=$((i + 1))
	[ "$i" -lt "$N" ] && sleep "$IVAL"
done

awk '{n++; x[n]=$1; y[n]=$2; sx+=$1; sy+=$2}
     END {
       if (n < 2) { print "idle-leg: too few samples" > "/dev/stderr"; exit 1 }
       mx = sx/n; my = sy/n
       for (i = 1; i <= n; i++) { num += (x[i]-mx)*(y[i]-my); den += (x[i]-mx)^2 }
       slope = num/den                      # uV per second
       printf "idle-leg: samples=%d span=%ds dV=%duV slope=%.2f mV/h\n",
              n, x[n]-x[1], y[1]-y[n], -slope*3600/1000 > "/dev/stderr"
     }' "$OUT"
