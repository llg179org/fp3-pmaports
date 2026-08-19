#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# How much does the phone draw while it is actually asleep?
#
# ☠️ THE FIRST VERSION OF THIS SCRIPT WAS WRONG AND ITS NUMBERS ARE WITHDRAWN.
# It integrated charge_now across a window, on the assumption that a uAh-valued
# attribute is a coulomb count. It is not. This platform has no coulomb counter:
# qcom_smbx gets its capacity from drivers/power/supply/adc-battery-helper.c,
# which polls the battery every 30 s and looks the voltage up in an OCV table
# (power_supply_batinfo_ocv2cap) through a moving average. Its own header says
# so - it exists for devices whose hardware gauge is absent or limited.
#
# Two consequences, both measured on 2026-08-15:
#
#   * Integrating charge_now is not a current measurement. A 600 s awake window
#     gave 209 mA where current_now, sampled over the same conditions, gives
#     130 mA - the estimator was still walking the SoC down after the charger
#     was suspended, and that motion has nothing to do with the load.
#   * Across a suspend it reports exactly zero, because the poll worker does not
#     run while userspace is frozen. Zero drain is an artifact of a stopped
#     estimator, not a low-power result.
#
# The awake window was in that script as a same-instrument control, and catching
# this is the entire reason it was there. Keep controls like that.
#
# What this platform CAN measure over a suspend: voltage. voltage_now is a real
# ADC read, and after hours off VBUS with the phone asleep the pack is fully
# relaxed, which is the one condition in which an OCV-derived capacity is at its
# most trustworthy. So the instrument is a long suspend read at both ends:
#
#   capacity is 1% granular = 30.6 mAh on this pack, so a 3 h window separates
#   "still around 100 mA" (would drop ~13%) from "under 20 mA" (under 2%). That
#   is a coarse instrument and it is deliberately aimed at a coarse question -
#   which regime are we in - not at resolving a 10 mA effect.
#
# ☠️ Do not compare this against a voltage slope taken near full charge. At 97%
# on a freshly suspended port the pack is relaxing, relaxation flattens on its
# own, and a later leg reads flatter for that reason alone. Both ends of THIS
# measurement are taken relaxed, which is what makes the difference meaningful.
#
# ☠️ USBIN_SUSPEND_BIT lives in the PMIC and survives a warm reboot. If this
# script dies without restoring it, do NOT reboot the phone as-is - it once
# wedged the bootloader into a fastboot that answered no command.
#
#   suspend-leg.sh <tag> [asleep_s]
#
# Appends to /home/fp3/suspend-results.txt.

set -eu

TAG=${1:?usage: suspend-leg.sh <tag> [asleep_s]}
ASLEEP=${2:-10800}
SETTLE=300

BATT=/sys/class/power_supply/pmi632-battery
CHG=/sys/class/power_supply/pmi632-charger
RTC=/sys/class/rtc/rtc0/wakealarm
OUT=/home/fp3/suspend-results.txt

die() { echo "suspend-leg: $*" >&2; exit 1; }
say() { echo "suspend-leg: $*" | tee -a "$OUT" >&2; }
snap() { echo "cap=$(cat "$BATT/capacity") v=$(cat "$BATT/voltage_now") ocv=$(cat "$BATT/voltage_ocv") i=$(cat "$BATT/current_now")"; }

[ "$(id -u)" = 0 ] || die "must run as root"
[ -w "$RTC" ] || die "no writable rtc wakealarm"

# --- pin the display ---------------------------------------------------------
systemctl stop greetd 2>/dev/null || true
dpms=unknown
i=0
while [ "$i" -lt 15 ]; do
	for fb in /sys/class/graphics/fb*/blank; do
		[ -w "$fb" ] && echo 4 > "$fb"
	done
	sleep 2
	dpms=$(cat /sys/class/drm/card0/card0-DSI-1/dpms 2>/dev/null || echo unknown)
	[ "$dpms" = Off ] && break
	i=$((i + 1))
done
[ "$dpms" = Off ] || die "DSI-1 dpms is still '$dpms' after 30 s of blanking"

# --- take the phone off VBUS -------------------------------------------------
restore() {
	echo 0 > "$RTC" 2>/dev/null || true
	echo Charging > "$CHG/status" 2>/dev/null || true
	systemctl start greetd 2>/dev/null || true
}
trap restore EXIT INT TERM

echo Unknown > "$CHG/status"
sleep 10
[ "$(cat "$CHG/online")" = 0 ] || die "charger still online after suspending USBIN"
[ "$(cat "$BATT/status")" = Discharging ] || die "battery is '$(cat "$BATT/status")'"

# Let the estimator finish walking down from the charging reading before the
# first snapshot, or the settle itself lands inside the measured window.
say "$TAG settle ${SETTLE}s from $(snap)"
sleep "$SETTLE"

w0=$(cat /sys/power/suspend_stats/success)
s0=$(snap); t0=$(date +%s)
say "$TAG before $s0"

echo 0 > "$RTC"
echo "+$ASLEEP" > "$RTC"
echo mem > /sys/power/state || die "suspend refused"
t1=$(date +%s)
w1=$(cat /sys/power/suspend_stats/success)
[ "$w1" -gt "$w0" ] || die "suspend_stats/success did not advance - it never slept"

# Read immediately, before the estimator's poll worker restarts and before
# anything userspace does on resume can load the pack.
s1=$(snap)
say "$TAG after $s1 slept=$((t1 - t0))s suspends=$((w1 - w0))"

# And again once the estimator has had two poll intervals to catch up, because
# the immediate read is the last value from before the freeze.
sleep 90
say "$TAG settled $(snap)"
say "$TAG done - restoring charger and greetd"
