#!/bin/sh
# Description: the vibrator is bound and advertises force feedback
#
# This exists because 15-hwtest stopped running hwtest's Vibrator component:
# that probe shakes the phone, and everything audible or otherwise noisy in this
# suite is opt-in. The coverage it used to give is small but real - that the
# PMIC's vibrator bound a driver and appears as a force-feedback input device -
# and this check keeps it without touching the motor.
#
# ☠️ Deliberately does NOT actuate. A check that buzzes cannot run unattended at
# night, which is the whole reason the hwtest component was dropped. Whether the
# motor physically moves is a question for a human with the phone in hand.

fail=0

DEV=""
for d in /sys/class/input/event*/device; do
	name=$(cat "$d/name" 2>/dev/null) || continue
	case "$name" in *vib*) DEV="$d"; DEV_NAME="$name"; break ;; esac
done

if [ -z "$DEV" ]; then
	echo "FAIL: no input device with a vibrator name"
	echo "      expected pm8xxx_vib_ffmemless from the PMIC's vibrator@5700"
	exit 1
fi

echo "PASS: vibrator input device present ($DEV_NAME)"

# The force-feedback capability mask is what a haptics client actually looks
# for; a bound driver that advertises nothing is useless to feedbackd.
ff=$(cat "$DEV/capabilities/ff" 2>/dev/null)
case "$ff" in
""|0|"0 0")
	echo "FAIL: the device advertises no force-feedback capabilities"
	fail=1
	;;
*)
	echo "PASS: force feedback advertised (ff mask $ff)"
	;;
esac

# Bound to the PMIC's own vibrator node rather than to something generic: this
# is the difference between the real hardware and a leftover virtual device.
if readlink -f "$DEV" | grep -q "vibrator@"; then
	echo "PASS: bound to the PMIC vibrator node"
else
	echo "FAIL: not bound to a PMIC vibrator@ node: $(readlink -f "$DEV")"
	fail=1
fi

exit $fail
