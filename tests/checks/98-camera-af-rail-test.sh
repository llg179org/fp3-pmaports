#!/bin/sh
# Detached: yes
# Category: camera
# Description: a system resume leaves the focus motor's supply off
#
# Runs detached, and next to 99-suspend-test, because it needs a real suspend
# cycle: resuming re-enumerates USB and drops the CDC-NCM link, so a check
# driven from a live SSH session would die at the moment it matters.
#
# ☠️ The failure this exists for, measured 2026-08-16 on linux-fp3 7.1.3-r54:
#
#   BEFORE status=suspended rail_use_count=0 active_time=79383 af_state=disabled
#   AFTER  status=suspended rail_use_count=1 active_time=79383 af_state=enabled
#
# with focus_absolute reading 400 afterwards, so the coil was holding rather
# than merely supplied. ak7375 declared
#
#   SET_SYSTEM_SLEEP_PM_OPS(ak7375_vcm_suspend, ak7375_vcm_resume)
#
# and a system resume runs on every device whether or not runtime PM left it
# suspended. So the resume path powered the motor up for a lens nobody had
# asked for and drove it back to the last requested position, while runtime PM
# still had the device recorded as suspended - so it never called the suspend
# side again and the supplies stayed on for as long as the system was up.
#
# What makes this worth a check rather than a one-off measurement is that it is
# invisible: runtime_status still reads "suspended", active_time does not move,
# and nothing appears in dmesg. The only witness is the regulator.

fail=0

# Find the rail by name - the regulator.N index is assigned at probe and moves
# between boots, so hardcoding one measures a different rail after a reboot.
RAIL=
for f in /sys/class/regulator/regulator.*/name; do
	[ -r "$f" ] || continue
	if [ "$(cat "$f")" = "cam_af_2p85" ]; then
		RAIL=$(dirname "$f")
		break
	fi
done

if [ -z "$RAIL" ]; then
	echo "SKIP: no cam_af_2p85 regulator (no focus motor described?)"
	echo "      cmd: grep -l cam_af_2p85 /sys/class/regulator/regulator.*/name"
	exit 0
fi

VCM=
for d in /sys/bus/i2c/drivers/ak7375/*/; do
	[ -d "$d/power" ] && VCM=$d && break
done

if [ -z "$VCM" ]; then
	echo "SKIP: no ak7375 device bound (focus motor driver not loaded)"
	echo "      cmd: ls /sys/bus/i2c/drivers/ak7375/"
	exit 0
fi

USECOUNT=/sys/kernel/debug/regulator/cam_af_2p85/use_count
if [ ! -r "$USECOUNT" ]; then
	echo "SKIP: no regulator debugfs (CONFIG_DEBUG_FS, or not run as root)"
	echo "      cmd: cat $USECOUNT"
	exit 0
fi

# The premise: the motor has to be idle before the suspend, or the rail is
# legitimately on and the measurement says nothing. A camera left open is a
# skip, not a failure.
#
# ☠️ It does not become idle the moment the last capture ends, and until
# 2026-08-16 this check simply lost to that: 45-camera-af-windows-pipewire runs
# a stream a minute earlier, so the motor was still active here and the check
# skipped. It had only ever passed in a battery because that PipeWire check was
# itself skipping and never opened the camera - two checks that both looked
# fine, and between them nothing measured.
#
# Measured that day, and it settles the open question of who is holding it:
# waiting 240s changed nothing, and restarting wireplumber dropped the motor to
# suspended in under two seconds. So the holder is the session's media stack
# keeping the subdev open, not a slow release inside the driver - which means
# this check can close the camera itself instead of waiting on the run order.
. "$(dirname "$0")/../lib/session.sh"

settle() {
	_waited=0
	while [ "$_waited" -lt "$1" ]; do
		[ "$(cat "$VCM/power/runtime_status")" = suspended ] && return 0
		sleep 2
		_waited=$((_waited + 2))
	done
	[ "$(cat "$VCM/power/runtime_status")" = suspended ]
}

if ! settle 10; then
	# Give the session's media stack a chance to let go, then wait again.
	# If there is no session to restart it in, the wait above was all we had.
	if session_init; then
		as_user "systemctl --user restart wireplumber" >/dev/null 2>&1
		echo "      (restarted wireplumber to release the focus motor)"
	fi
	settle 20
fi

status=$(cat "$VCM/power/runtime_status")
if [ "$status" != "suspended" ]; then
	echo "SKIP: the focus motor is still $status after waiting and restarting"
	echo "      the media stack - something else is holding the camera"
	echo "      cmd: cat $VCM/power/runtime_status"
	exit 0
fi

before_use=$(cat "$USECOUNT")
before_state=$(cat "$RAIL/state" 2>/dev/null)
if [ "$before_use" != "0" ]; then
	echo "SKIP: cam_af_2p85 is already held ($before_use users) while the"
	echo "      motor is runtime-suspended - a different defect, measure that"
	echo "      first: cmd: cat /sys/kernel/debug/regulator/cam_af_2p85/use_count"
	exit 0
fi

if [ ! -e /sys/class/rtc/rtc0/wakealarm ]; then
	echo "SKIP: no RTC wakealarm - nothing can wake the device from suspend"
	exit 0
fi

SLEEP_TIME=6
now=$(cat /sys/class/rtc/rtc0/since_epoch)
target=$((now + SLEEP_TIME))

# Clear any stale alarm first: a leftover one in the past makes the write
# succeed and the wake never happen.
echo 0 >/sys/class/rtc/rtc0/wakealarm
echo "$target" >/sys/class/rtc/rtc0/wakealarm

sync
echo mem >/sys/power/state

after=$(cat /sys/class/rtc/rtc0/since_epoch)
if [ "$after" -lt "$target" ]; then
	echo "SKIP: the system never suspended, so nothing resumed either"
	echo "      (99-suspend-test is where that failure belongs)"
	exit 0
fi

after_use=$(cat "$USECOUNT")
after_state=$(cat "$RAIL/state" 2>/dev/null)

if [ "$after_use" = "0" ] && [ "$after_state" != "enabled" ]; then
	echo "PASS: the focus motor's supply stayed off across a suspend/resume" \
		"(use_count $before_use -> $after_use, state $before_state -> $after_state)"
else
	echo "FAIL: resuming turned the focus motor's supply on behind runtime PM"
	echo "      use_count $before_use -> $after_use, state $before_state -> $after_state"
	echo "      runtime_status is still $(cat "$VCM/power/runtime_status"), which is"
	echo "      the point: runtime PM believes the device is suspended, so it will"
	echo "      never call the suspend side again and the rail stays on until the"
	echo "      next system suspend. Expect the lens to be holding a position"
	echo "      too, not merely supplied:"
	for n in "$VCM"/video4linux/*; do
		[ -e "$n" ] || continue
		echo "      cmd: v4l2-ctl -d /dev/$(basename "$n") --get-ctrl focus_absolute"
	done
	echo "      The fix is SET_SYSTEM_SLEEP_PM_OPS(pm_runtime_force_suspend,"
	echo "      pm_runtime_force_resume) in drivers/media/i2c/ak7375.c."
	fail=1
fi

exit $fail
