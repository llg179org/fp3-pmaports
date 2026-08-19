#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Take the rail census again with the USB PHY powered down.
#
# The census of 2026-08-19 found five enabled PMIC rails held through a suspend
# by the absence of a sleep vote - and three of the five were USB PHY rails, on a
# phone with a USB cable in it. That is our own confound, not a finding: every
# measurement here is taken over USB because that is how the data leaves the
# phone. This unbinds the controller and the PHY, re-runs the census, and puts
# them back.
#
# ☠️ RUN IT OVER WiFi (192.168.100.17). The USB link is what this removes.
# ☠️ RUN IT UNDER systemd-run. If it dies with the session, the phone comes back
#    with no USB and, on a bad day, no way in at all.
#
# The rebind is armed on every exit path AND on a deadline: whatever happens in
# between, the USB comes back.
#
#   usb-off-census.sh [seconds_of_census]

set -u

SECS=${1:-30}
DRV_USB=/sys/bus/platform/drivers/dwc3-qcom
DEV_USB=7000000.usb
DRV_PHY=/sys/bus/platform/drivers/qcom-qusb2-phy
DEV_PHY=79000.phy
OUT=/run/night/usb-off-census.txt

mkdir -p /run/night
say() { echo "$*" >> "$OUT"; echo "$*"; }
bound() { [ -e "$1/$2" ] && echo yes || echo no; }

UNBOUND_USB=0
UNBOUND_PHY=0

restore() {
	rc=$?
	say "# restoring USB"
	if [ "$UNBOUND_PHY" = 1 ]; then
		echo "$DEV_PHY" > "$DRV_PHY/bind" 2>/dev/null
		say "#   phy bound: $(bound "$DRV_PHY" "$DEV_PHY")"
	fi
	if [ "$UNBOUND_USB" = 1 ]; then
		echo "$DEV_USB" > "$DRV_USB/bind" 2>/dev/null
		say "#   usb bound: $(bound "$DRV_USB" "$DEV_USB")"
	fi
	say "# done rc=$rc uptime=$(cut -d. -f1 /proc/uptime)"
	exit $rc
}
trap restore EXIT INT TERM

: > "$OUT"
say "# usb-off-census uptime=$(cut -d. -f1 /proc/uptime) census=${SECS}s"
say "# before: usb=$(bound "$DRV_USB" "$DEV_USB") phy=$(bound "$DRV_PHY" "$DEV_PHY")"

echo "$DEV_USB" > "$DRV_USB/unbind" 2>/dev/null && UNBOUND_USB=1
say "# usb unbound: $UNBOUND_USB -> bound=$(bound "$DRV_USB" "$DEV_USB")"
sleep 3
echo "$DEV_PHY" > "$DRV_PHY/unbind" 2>/dev/null && UNBOUND_PHY=1
say "# phy unbound: $UNBOUND_PHY -> bound=$(bound "$DRV_PHY" "$DEV_PHY")"
sleep 5

# What the regulators say with the PHY gone - the cheap cross-check on whether
# the unbind did anything at all, before spending a suspend on it.
if [ -r /sys/kernel/debug/regulator/regulator_summary ]; then
	say "# ---- regulator_summary, USB down ----"
	grep -E 'l3|l7|l13|s3' /sys/kernel/debug/regulator/regulator_summary >> "$OUT" 2>/dev/null
fi

say "# ---- census ----"
/root/rail-census.sh "$SECS" >> "$OUT" 2>&1
cp /run/rail-census.txt /run/night/rail-census-usb-off.txt 2>/dev/null
say "# census done"
