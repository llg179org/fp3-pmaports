#!/bin/sh
# Category: camera
# Description: focus windows are offered in a fixed space and actually aim
#
# 43-camera-manual-focus proves the lens goes where it is told. This proves the
# other half of "tap to focus": that an application can say *where* to focus,
# in a coordinate space it can compute a tap position in, and that the request
# reaches the metering.
#
# Two independent failures, both measured on this device on 2026-08-16, and
# both invisible without a machine check:
#
# 1. libcamera r16 and earlier advertised AfWindows with both bounds set to the
#    empty rectangle - [(0, 0)/0x0..(0, 0)/0x0] - so an application reading the
#    control to find out what it may ask for was told the only legal window has
#    no area.
#
# 2. r17 stated a real range, but stated it in the software ISP's *output
#    frame*. The IPA takes the sensor information once, at init, from the
#    format the sensor happens to be in - and a V4L2 format outlives the
#    process that set it. The same control therefore read
#    (0, 0)/1x1..(0, 0)/1920x1080 after a 1080p capture and .../4032x3024
#    after a full-resolution one, so the space an application was told to
#    compute in was decided by whoever used the camera last. Anything that
#    computed a tap in the wrong space landed outside the clip, selected no
#    zone, and silently fell back to metering the centre - which looks exactly
#    like tap-to-focus not being implemented at all.
#
# The fix is to use the sensor's active pixel array, which is hardware and does
# not move. So the check is: force the sensor into a small format, then ask
# what space the camera offers. It must be the active area, not the format.
#
# The aiming half uses the IPA's own line, which is there because this failure
# is otherwise unobservable from outside the IPA - a window that reached
# nothing looks identical to one that was never sent:
#
#     Metering 1 of 25 zones (windows, 1 window(s) requested)

fail=0

command -v cam >/dev/null 2>&1 || {
	echo "SKIP: libcamera-tools not installed, nothing to ask"
	exit 0
}

work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT

# The active pixel array, as the camera itself reports it. This is the answer
# the advertised window space has to agree with.
#   Property: PixelArrayActiveAreas = [ (8, 24)/4032x3024 ]
area=$(cam -c1 --list-properties 2>/dev/null |
	sed -n 's/.*PixelArrayActiveAreas *= *\[ *([0-9]*, *[0-9]*)\/\([0-9]*x[0-9]*\).*/\1/p' |
	head -1)
[ -n "$area" ] || {
	echo "SKIP: the camera reports no PixelArrayActiveAreas, so there is no"
	echo "      fixed space to check the control against"
	exit 0
}

# ☠️ Leave the sensor in a format that is NOT the active area, so that a space
# taken from the format is distinguishable from one taken from the hardware.
# Without this step the two answers coincide and the check passes on a build
# that has the bug.
timeout 60 cam -c1 --capture=2 -s width=640,height=480 >/dev/null 2>&1

# Control: [inout] libcamera::AfWindows: [(0, 0)/1x1..(0, 0)/4032x3024]
advertised=$(cam -c1 --list-controls 2>/dev/null |
	sed -n 's/.*AfWindows: *\[.*\.\.([0-9]*, *[0-9]*)\/\([0-9]*x[0-9]*\)\].*/\1/p' |
	head -1)

if [ -z "$advertised" ]; then
	echo "FAIL: the camera does not offer AfWindows at all"
	echo "      cmd: cam -c1 --list-controls | grep AfWindows"
	echo "      Without it an application cannot say where to focus. The IPA"
	echo "      only advertises the control when it knows the sensor's active"
	echo "      area; a 'focus windows unavailable' line in the IPA log says"
	echo "      that is what happened."
	exit 1
fi

if [ "$advertised" = "$area" ]; then
	echo "PASS: focus windows are offered in the active pixel array ($area)," \
		"after leaving the sensor in 640x480"
else
	echo "FAIL: focus windows are offered in the wrong coordinate space"
	echo "      advertised $advertised, active pixel array $area"
	echo "      cmd: cam -c1 --capture=2 -s width=640,height=480 >/dev/null"
	echo "           cam -c1 --list-controls | grep AfWindows"
	echo "      A space that follows the last capture's format is the IPA"
	echo "      reading sensorInfo.outputSize instead of activeAreaSize - the"
	echo "      format persists in the driver between processes, so the answer"
	echo "      depends on session history rather than on the hardware."
	fail=1
fi

# --- the aiming half -------------------------------------------------------
#
# Three windows, chosen so that the counts tell the failure modes apart:
#   whole area  -> every zone           (the mapping is not shrinking things)
#   one corner  -> few zones            (windows aim, and reach the corners)
#   the other   -> few zones            (not one hard-coded region)
#
# The centre fallback is 9 of 25, so a corner window answering 9 is the
# signature of a window that selected nothing.

zones_for() {
	cat > "$work/script.yaml" <<EOF
frames:
  - 0:
      AfMetering: 1
      AfWindows: [ $1 ]
EOF
	LIBCAMERA_LOG_LEVELS=IPASoftAf:INFO \
		timeout 60 cam -c1 --capture=4 -s width=640,height=480 \
		--script="$work/script.yaml" > "$work/out.txt" 2>&1
	sed -n 's/.*Metering \([0-9]*\) of \([0-9]*\) zones.*/\1 \2/p' "$work/out.txt" | tail -1
}

# Split "8, 24" style geometry into the numbers the windows are built from.
aw=${area%x*}
ah=${area#*x}

set -- "0, 0, $aw, $ah" "0, 0, $((aw / 8)), $((ah / 8))" \
	"$((aw - aw / 8)), $((ah - ah / 8)), $((aw / 8)), $((ah / 8))"

full=$(zones_for "$1")
near=$(zones_for "$2")
far=$(zones_for "$3")

if [ -z "$full" ] || [ -z "$near" ] || [ -z "$far" ]; then
	echo "FAIL: the IPA never reported which zones it metered"
	echo "      cmd: LIBCAMERA_LOG_LEVELS=IPASoftAf:INFO cam -c1 --capture=4 \\"
	echo "             -s width=640,height=480 --script=<AfWindows script>"
	echo "      Either no capture ran, or this libcamera predates the"
	echo "      'Metering N of M zones' line - without which a window that"
	echo "      reached nothing cannot be told from one never sent."
	sed -n 's/.*ERROR/ERROR/p' "$work/out.txt" | head -3 | sed 's/^/      /'
	exit 1
fi

total=${full#* }
full=${full%% *}
near=${near%% *}
far=${far%% *}

# A quarter of the zones is a generous ceiling for a window an eighth of the
# frame across: it is well under the 9-of-25 centre fallback, and well over
# the 1 zone the geometry actually gives, so the check is about aiming rather
# than about the exact zone grid.
small=$((total / 4))

if [ "$full" -eq "$total" ] && [ "$near" -le "$small" ] && [ "$far" -le "$small" ]; then
	echo "PASS: focus windows aim - whole area $full/$total zones," \
		"near corner $near, far corner $far"
else
	echo "FAIL: focus windows do not aim"
	echo "      whole area $full/$total zones, near corner $near, far corner $far"
	echo "      cmd: LIBCAMERA_LOG_LEVELS=IPASoftAf:INFO cam -c1 --capture=4 \\"
	echo "             -s width=640,height=480 --script=<AfWindows script>"
	echo "      A corner window answering the same count as the centre"
	echo "      fallback means it selected no zone - it was clipped away,"
	echo "      which is what a wrong coordinate space does. A whole-area"
	echo "      window short of $total means the mapping loses part of the frame."
	fail=1
fi

exit $fail
