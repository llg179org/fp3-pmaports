#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Does the USB PHY stop the audio DSP from power-collapsing?
#
# Seen once, 2026-08-19 19:03, and only because the guardian was sampling every
# 30 s: LPASS had shut down twice since boot, all night, through seven suspends -
# and on the eighth, the one taken with the USB controller and QUSB2 PHY
# unbound, it shut down and kept the XO off for 30.9 s, the whole suspend.
#
# Ten minutes earlier the same freshly-restarted ADSP had sat through a 30 s
# suspend with USB attached and not collapsed once. Two suspends, one difference.
#
# ☠️ n=1 on each side. That is a lead, not a result. This alternates the two
# conditions so that anything slowly drifting - a warming SoC, a settling modem,
# a DSP that only collapses once per boot - shows up as a pattern in time rather
# than as a difference between the arms.
#
# ☠️ RUN OVER WiFi and UNDER systemd-run: it removes the USB link, and the USB
# comes back on every exit path.
#
#   lpass-usb-ab.sh [rounds] [suspend_s]        (defaults 3, 30)

set -u

ROUNDS=${1:-3}
SECS=${2:-30}
DRV_USB=/sys/bus/platform/drivers/dwc3-qcom
DEV_USB=7000000.usb
DRV_PHY=/sys/bus/platform/drivers/qcom-qusb2-phy
DEV_PHY=79000.phy
RPM=/sys/kernel/debug/qcom_rpm_master_stats
STATS=/sys/kernel/debug/qcom_stats

modprobe rpm_master_stats 2>/dev/null || true
say() { echo "$*"; }
mf() { sed -n "s/^[[:space:]]*$2[[:space:]]*:[[:space:]]*//p" "$RPM/$1" 2>/dev/null | head -1; }
cnt() { sed -n 's/^Count[[:space:]]*:[[:space:]]*//p' "$STATS/$1" 2>/dev/null | head -1; }
up() { cut -d. -f1 /proc/uptime; }

restore() {
	rc=$?
	[ -e "$DRV_PHY/$DEV_PHY" ] || echo "$DEV_PHY" > "$DRV_PHY/bind" 2>/dev/null
	[ -e "$DRV_USB/$DEV_USB" ] || echo "$DEV_USB" > "$DRV_USB/bind" 2>/dev/null
	say "# restored: usb=$([ -e "$DRV_USB/$DEV_USB" ] && echo yes || echo no) phy=$([ -e "$DRV_PHY/$DEV_PHY" ] && echo yes || echo no) rc=$rc"
	exit $rc
}
trap restore EXIT INT TERM

usb_off() {
	echo "$DEV_USB" > "$DRV_USB/unbind" 2>/dev/null
	sleep 2
	echo "$DEV_PHY" > "$DRV_PHY/unbind" 2>/dev/null
	sleep 3
}
usb_on() {
	echo "$DEV_PHY" > "$DRV_PHY/bind" 2>/dev/null
	sleep 2
	echo "$DEV_USB" > "$DRV_USB/bind" 2>/dev/null
	sleep 3
}

# One arm: read, suspend, read. The XO duration is the informative half - a
# shutdown count of +1 says it collapsed, the duration says for how long, and a
# collapse that lasts the whole suspend is a different animal from a blink.
arm() {
	label=$1
	l0=$(mf LPASS 'Shutdown count'); x0=$(mf LPASS 'XO shutdown count')
	d0=$(mf LPASS 'XO total duration'); v0=$(cnt vlow); n0=$(cnt vmin)
	a0=$(mf APSS 'Shutdown count'); s0=$(cat /sys/power/suspend_stats/success)

	rtcwake -m mem -s "$SECS" > /dev/null 2>&1

	l1=$(mf LPASS 'Shutdown count'); x1=$(mf LPASS 'XO shutdown count')
	d1=$(mf LPASS 'XO total duration'); v1=$(cnt vlow); n1=$(cnt vmin)
	a1=$(mf APSS 'Shutdown count'); s1=$(cat /sys/power/suspend_stats/success)

	dur=$(( ${d1:-0} - ${d0:-0} ))
	# 19.2 MHz XO ticks -> milliseconds, without floating point.
	ms=$(( dur / 19200 ))
	say "$label  suspends +$(( s1 - s0 ))  APSS +$(( a1 - a0 ))  LPASS +$(( ${l1:-0} - ${l0:-0} ))  XO +$(( ${x1:-0} - ${x0:-0} ))  XOdur +${ms}ms  vlow $v0->$v1  vmin $n0->$n1"
}

say "# lpass-usb-ab uptime=$(up) rounds=$ROUNDS suspend=${SECS}s"
say "# LPASS at start: shutdowns=$(mf LPASS 'Shutdown count') xo=$(mf LPASS 'XO shutdown count') xo_dur=$(mf LPASS 'XO total duration')"
say ""

r=1
while [ "$r" -le "$ROUNDS" ]; do
	say "== round $r =="
	usb_on
	arm "  USB ON  "
	usb_off
	arm "  USB OFF "
	usb_on
	r=$((r + 1))
done

say ""
say "# lpass-usb-ab done uptime=$(up)"
