#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# How much does the phone draw while it is actually asleep?
#
# This is the third instrument aimed at that question. The first two failed for
# the same underlying reason, so state it once, plainly:
#
#   ☠️ ON THIS PLATFORM, capacity, charge_now AND voltage_ocv ARE ALL THE SAME
#      NUMBER, AND NONE OF THEM CAN CROSS A SUSPEND BOUNDARY.
#
# qcom_smbx has no coulomb counter. It gets all three from
# drivers/power/supply/adc-battery-helper.c, whose work function polls every
# 30 s (POLL_TIME), computes one OCV estimate as volt_uv - curr_ua * R, pushes
# it into an 8-deep ring (ADC_BAT_HELPER_MOV_AVG_WINDOW_SIZE = 8) and looks the
# *average* up in the device tree's ocv-capacity-table-0. So voltage_ocv is a
# four-minute trailing average, capacity is that average through a lookup table,
# and charge_now is capacity * charge_full / 100. One measurement, three names.
#
# A frozen kernel does not run that work function. Every one of the three is
# therefore stale on resume, and stays a blend of pre-freeze and post-resume
# samples for the next four minutes. Measured 2026-08-15: 90 s after a three
# hour suspend, five of the eight ring slots were still pre-suspend values.
#
# Only two attributes are live: VOLTAGE_NOW and CURRENT_NOW call
# get_voltage_and_current_now() on every sysfs read, straight to the ADC. They
# are the only things this script uses.
#
# THE METHOD
#
# Take voltage under a controlled load, repeatedly, and use the *slope*. A slope
# is immune to any constant offset - surface charge from the charger, the static
# 120 mOhm compensation being wrong, concentration polarisation after a wake -
# as long as the sampling conditions are identical at every point, which is what
# the fixed-length wake window buys.
#
# Then calibrate the slope against a known current instead of against the OCV
# table:
#
#   phase A - N sleeps of T seconds; after each, exactly SETTLE_WAKE seconds of
#             quiet awake time, then one live (v, i) read.
#   phase B - the same total time awake and idle, sampled the same way, where
#             current_now gives the true mean current directly.
#
#   I_sleep = I_awake * (slope_A / slope_B)
#
# The OCV table never enters. dV/dQ is near-constant over the span this covers
# (the table gives ~10.6 mV per 1% from 86% down to 68%), and A runs before B so
# both phases sit in a similar region of the curve.
#
# Phase B is the same-instrument control, and it is not optional. The awake
# current is already known independently (current_now, ~130 mA), so phase B has
# to reproduce it. If it does not, the slope method is wrong and phase A means
# nothing. That check is the entire reason the first instrument's error was
# caught, and it is cheap.
#
# ☠️ USBIN_SUSPEND_BIT lives in the PMIC and survives a warm reboot. If this
# script dies without restoring it, do NOT reboot the phone as-is - it once
# wedged the bootloader into a fastboot that answered no command. The EXIT trap
# clears it on every path.
#
#   suspend-slope.sh <tag> [sleep_s] [cycles] [settle_off_s]
#
# Appends to /home/fp3/suspend-slope.txt; one machine-readable sample per line.

set -eu

TAG=${1:?usage: suspend-slope.sh <tag> [sleep_s] [cycles] [settle_off_s]}
T=${2:-900}
N=${3:-8}
SETTLE_WAKE=20		# quiet awake seconds before each sample
SETTLE_OFF=${4:-900}	# shed surface charge after leaving the charger; 4th arg for dry runs

BATT=/sys/class/power_supply/pmi632-battery
CHG=/sys/class/power_supply/pmi632-charger
RTC=/sys/class/rtc/rtc0/wakealarm
OUT=/home/fp3/suspend-slope.txt

die() { echo "suspend-slope: $*" >&2; exit 1; }
say() { echo "suspend-slope: $*" | tee -a "$OUT" >&2; }

# How many times has the little cluster's PLL failed to lock so far this boot?
#
# Phase B is an awake leg, and an awake leg is exactly what the 2026-08-15 run
# lost: a storm of `apcs-cpu0-pll failed to enable!` ran through the whole of its
# control phase. That inflates the awake current AND steepens the slope, so the
# ratio moved by an unknown amount in an unknown direction and 116 mA had to be
# withdrawn. Carrying the count on every sample makes each leg say for itself
# whether it was contaminated, rather than leaving that to be reconstructed
# afterwards from a journal that may have rotated - and it costs one grep.
# ☠️ Read the journal, not dmesg. The kernel ring buffer wraps: measured
# 2026-08-17, two `dmesg | grep -c` reads twenty minutes apart on the same boot
# returned 35 and then 34, so the count went *down* while failures were still
# accumulating. pll-sweep.sh already takes a journalctl cursor for this reason.
pll_fails() {
	journalctl -k -b --no-pager 2>/dev/null | grep -c 'failed to enable' || true
}

# ☠️ ONE READ OF current_now IS NOT A MEASUREMENT. Characterised 2026-08-17:
# 90 reads two seconds apart on an idle phone gave mean 170 mA with a standard
# deviation of 70 and a range of 93 to 450, and the distribution is not
# Gaussian - it is bimodal, periodic activity beating against the sampler. A
# single read therefore carries about +/-138 mA at 95%, which through the
# 120 mOhm IR compensation below is +/-17 mV of injected noise. Phase A of the
# reference leg travels 23.6 mV in total. The correction was noisier than the
# signal it corrects, which is why that fit came back at r2 = 0.80.
#
# So average. Twenty reads over ten seconds cuts it to about +/-31 mA and
# +/-4 mV, and the median rather than the mean because of the bimodality. Both
# attributes get the same treatment: they are read from the same ADC in the
# same call, so voltage carries the same beat.
#
# ☠️ The same measurement also killed the tidier hypothesis it was run to test.
# There is no decaying resume transient to wait out: 0-20 s after a 900 s deep
# suspend reads 159 mA and 100-180 s after reads 170 mA. Lengthening the settle
# buys nothing; only averaging does.
NREAD=20
RGAP=0.5

median() {
	sort -n | awk '{v[NR]=$1} END {print (NR%2) ? v[(NR+1)/2] : int((v[NR/2]+v[NR/2+1])/2)}'
}

# Live ADC only. Never capacity, never voltage_ocv, never charge_now.
sample() {
	# Interleave rather than reading all the voltages and then all the
	# currents: the pair has to describe the same instant for the IR
	# compensation to mean anything.
	# ☠️ Never use $i here. The callers are `while [ "$i" -lt "$N" ]` loops
	# and sh has no function scope, so a counter named i inside sample()
	# ends every one of them after a single pass. Measured 2026-08-17: a
	# 4.25 h leg finished in 32 minutes with one settle sample, one sleep
	# and one control window, and said so in its own log line - "A20", where
	# the cycle number should have been 0.
	_sn=0
	_sv=""
	_si=""
	while [ "$_sn" -lt "$NREAD" ]; do
		_sv="$_sv$(cat "$BATT/voltage_now")
"
		_si="$_si$(cat "$BATT/current_now")
"
		sleep "$RGAP"
		_sn=$((_sn + 1))
	done
	printf '%s phase=%s n=%s t=%s v=%s i=%s pll=%s nread=%s\n' \
		"$TAG" "$1" "$2" "$(cut -d. -f1 /proc/uptime)" \
		"$(printf '%s' "$_sv" | median)" "$(printf '%s' "$_si" | median)" \
		"$(pll_fails)" "$NREAD" \
		| tee -a "$OUT" >&2
}

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
# ☠️ `systemctl start greetd` brings the greeter back, NOT the session. greetd's
# [initial_session] autologin only runs at boot, so after this script the phone
# sits at the greeter and `fp3-selftest --only 03-autologin` fails - measured
# 2026-08-17, and it is a leftover of the leg, not a regression. Reboot before
# reading the battery, or expect that one check to be a false alarm.
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

# Log the relaxation itself rather than assuming a settle time is enough - the
# shape of these lines says whether SETTLE_OFF was long enough, which no amount
# of reasoning about surface charge can.
say "$TAG === settle ${SETTLE_OFF}s off VBUS ==="
i=0
while [ "$i" -lt $((SETTLE_OFF / 60)) ]; do
	sample settle "$i"
	sleep 60
	i=$((i + 1))
done

# --- phase A: asleep ---------------------------------------------------------
say "$TAG === phase A: $N sleeps of ${T}s ==="
w0=$(cat /sys/power/suspend_stats/success)
i=0
while [ "$i" -lt "$N" ]; do
	echo 0 > "$RTC"
	echo "+$T" > "$RTC"
	a0=$(cut -d. -f1 /proc/uptime)
	echo mem > /sys/power/state || die "suspend refused in cycle $i"
	a1=$(cut -d. -f1 /proc/uptime)
	sleep "$SETTLE_WAKE"
	sample A "$i"
	# An early wake makes that interval shorter, not invalid - the sample
	# carries its own uptime, so the slope fit uses real elapsed time. But
	# say so, because a systematically short sleep means something is
	# waking it and phase A is then not measuring suspend.
	say "$TAG A$i slept=$((a1 - a0))s of ${T}s"
	i=$((i + 1))
done
w1=$(cat /sys/power/suspend_stats/success)
say "$TAG phase A done suspends=$((w1 - w0)) of $N"

# --- phase B: awake control, same duration, same load ------------------------
say "$TAG === phase B: awake control, $N x ${T}s ==="
i=0
while [ "$i" -lt "$N" ]; do
	sleep "$T"
	sleep "$SETTLE_WAKE"
	sample B "$i"
	i=$((i + 1))
done

say "$TAG done - restoring charger and greetd"
