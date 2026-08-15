#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Idle current awake vs in s2idle, measured with one instrument.
#
# Why not idle-leg.sh: current_now has to be sampled, and nothing samples while
# userspace is frozen. The fuel gauge's own accumulator does not need sampling -
# read charge_now before and after a window and the mean current over that window
# is (delta_uAh * 3600 / delta_s). Measured 2026-08-15, charge_now advances in
# 306 uAh quanta, so a 600 s window resolves ~2 mA.
#
# ☠️ Both windows use the accumulator, deliberately. Comparing a current_now mean
# against a charge_now integral would compare two instruments, and the difference
# between the phone awake and the phone asleep is exactly the thing being measured.
#
# Preconditions, all of them gated rather than assumed:
#
#   * The display really off - the compositor holds DRM master for a while after
#     systemctl stop returns, so blank in a retry loop and check dpms.
#   * The phone really off VBUS - USBIN_SUSPEND_BIT via the charger's status
#     attribute, verified by online=0 and a negative current_now.
#   * The RTC alarm really wakes it. Proven on 2026-08-15: 90 s requested, 91 s
#     slept, suspend_stats/success 0 -> 1. The RTC time itself is stuck in 1970
#     (no offset nvmem cell) but an alarm is relative, so this is unaffected.
#
# ☠️ USBIN_SUSPEND_BIT lives in the PMIC and survives a warm reboot. If this
# script dies without restoring it, the phone must NOT be rebooted as-is - it
# once wedged the bootloader into a fastboot that answered no command.
#
#   suspend-leg.sh <tag> [awake_s] [asleep_s]
#
# Appends to /home/fp3/suspend-results.txt.

set -eu

TAG=${1:?usage: suspend-leg.sh <tag> [awake_s] [asleep_s]}
AWAKE=${2:-600}
ASLEEP=${3:-600}
SETTLE=120

BATT=/sys/class/power_supply/pmi632-battery
CHG=/sys/class/power_supply/pmi632-charger
RTC=/sys/class/rtc/rtc0/wakealarm
OUT=/home/fp3/suspend-results.txt

die() { echo "suspend-leg: $*" >&2; exit 1; }
say() { echo "suspend-leg: $*" | tee -a "$OUT" >&2; }

[ "$(id -u)" = 0 ] || die "must run as root"
[ -r "$BATT/charge_now" ] || die "no $BATT/charge_now"
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

say "$TAG start cap=$(cat "$BATT/capacity")% settling ${SETTLE}s"
sleep "$SETTLE"

# --- window A: awake ---------------------------------------------------------
qa0=$(cat "$BATT/charge_now"); ta0=$(date +%s)
sleep "$AWAKE"
qa1=$(cat "$BATT/charge_now"); ta1=$(date +%s)
say "$TAG awake dq=$((qa0 - qa1))uAh dt=$((ta1 - ta0))s mean_uA=$(( (qa0 - qa1) * 3600 / (ta1 - ta0) ))"

# --- window B: s2idle --------------------------------------------------------
w0=$(cat /sys/power/suspend_stats/success)
qb0=$(cat "$BATT/charge_now"); tb0=$(date +%s)
echo 0 > "$RTC"
echo "+$ASLEEP" > "$RTC"
echo mem > /sys/power/state || die "suspend refused"
tb1=$(date +%s)
qb1=$(cat "$BATT/charge_now")
w1=$(cat /sys/power/suspend_stats/success)

[ "$w1" -gt "$w0" ] || die "suspend_stats/success did not advance - it never slept"
say "$TAG asleep dq=$((qb0 - qb1))uAh dt=$((tb1 - tb0))s mean_uA=$(( (qb0 - qb1) * 3600 / (tb1 - tb0) )) suspends=$((w1 - w0))"

say "$TAG done cap=$(cat "$BATT/capacity")% - restoring charger and greetd"
