#!/bin/sh
# Category: camera
# Description: a manual LensPosition request actually reaches the actuator
#
# 41-camera-focus-test is the structural half: a node, a driver, a control. It
# says nothing about whether writing the control does anything, and that half
# was assumed to need a scene to point the camera at. It does not. Autofocus
# needs a scene because it judges sharpness; *manual* focus does not judge
# anything - it asks for a distance and the actuator either goes there or it
# does not, in the dark, on a bench, with the lens cap on.
#
# ☠️ The failure this exists for, measured 2026-08-15 on libcamera 99990.7.1-r12:
# LensPosition was advertised and every request resolved to actuator code 0. The
# IPA kept the lens travel in members that only startScan() fills, and the manual
# path reaches moveTo() without a scan, so the clamp was std::clamp(pos, 0, 0).
# Nothing reported an error - the control read back the value it had been pinned
# to. Two patches, each correct alone. See docs/camera/bringup/README.md,
# "Manual focus was offered and did nothing".
#
# The instrument is the IPA's own log line, which prints the request and the
# result together:
#
#     Lens moved to 10 dioptres (1023)
#
# so one line is the whole verdict. The actuator control is read as well, since
# the log proves what the IPA computed and only the subdev proves what the
# hardware was told.

fail=0

command -v cam >/dev/null 2>&1 || {
	echo "SKIP: libcamera-tools not installed, nothing to ask"
	exit 0
}

# The subdev index moves between boots - match on the control, as 41 does.
lens=""
for sd in /dev/v4l-subdev*; do
	[ -e "$sd" ] || continue
	if v4l2-ctl -d "$sd" -l 2>/dev/null | grep -q 'focus_absolute'; then
		lens="$sd"
		break
	fi
done
[ -n "$lens" ] || {
	echo "SKIP: no subdev exposes focus_absolute (41-camera-focus covers that)"
	exit 0
}

max=$(v4l2-ctl -d "$lens" -l 2>/dev/null | sed -n 's/.*focus_absolute.*max=\([0-9]*\).*/\1/p')
[ -n "$max" ] && [ "$max" -gt 0 ] || {
	echo "SKIP: could not read the focus_absolute range from $lens"
	exit 0
}

work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT

# Manual mode, then the near end of the range. 10 dioptres is 0.1 m, which is
# the closest distance the tuning file declares; if the tuning has no lens
# calibration the control is not offered at all and the run says so below.
cat > "$work/script.yaml" <<'EOF'
frames:
  - 2:
      AfMode: 0
  - 8:
      LensPosition: 10.0
EOF

# 640x480 deliberately: the dma-heap CMA region cannot hold more than three
# 1920x1080 buffers, and this test does not look at the picture.
LIBCAMERA_LOG_LEVELS=IPASoftAf:DEBUG \
	timeout 60 cam -c1 --capture=25 -s width=640,height=480 \
	--script="$work/script.yaml" > "$work/out.txt" 2>&1
rc=$?

if [ $rc -ne 0 ] && ! grep -q 'IPASoftAf' "$work/out.txt"; then
	echo "FAIL: cam could not run a capture (rc=$rc)"
	echo "      cmd: cam -c1 --capture=25 -s width=640,height=480"
	sed -n 's/.*ERROR/ERROR/p' "$work/out.txt" | head -3 | sed 's/^/      /'
	echo "      A camera already open elsewhere wedges this; close any app first."
	exit 1
fi

if ! grep -q 'Manual focus from' "$work/out.txt"; then
	echo "SKIP: the tuning file declares no lens calibration, so LensPosition"
	echo "      is not offered and there is nothing to ask for. Add"
	echo "      lens-infinity-code / lens-closest-code / lens-closest-distance"
	echo "      to the Af block of the tuning file to enable manual focus."
	exit 0
fi

# "Lens moved to 10 dioptres (1023)" - request and result on one line.
moved=$(grep -o 'Lens moved to [0-9.]* dioptres ([0-9]*)' "$work/out.txt" | tail -1)
if [ -z "$moved" ]; then
	echo "FAIL: the IPA never acted on LensPosition"
	echo "      cmd: LIBCAMERA_LOG_LEVELS=IPASoftAf:DEBUG cam -c1 --capture=25 \\"
	echo "             -s width=640,height=480 --script=<manual focus script>"
	echo "      AfMode=Manual was set and a LensPosition was queued, but no"
	echo "      'Lens moved to' line was logged - the manual path did not run."
	exit 1
fi

code=$(echo "$moved" | sed 's/.*(\([0-9]*\))/\1/')
# A request for the near limit must land in the far half of the travel. The
# threshold is loose on purpose: the dioptre scale is an estimate, so this asks
# "did it go roughly where it was told", not "is the calibration right".
if [ "$code" -gt $((max / 2)) ]; then
	echo "PASS: $moved (of 0..$max)"
else
	echo "FAIL: a manual focus request did not reach the actuator"
	echo "      $moved  - expected a code in the far half of 0..$max"
	echo "      cmd: LIBCAMERA_LOG_LEVELS=IPASoftAf:DEBUG cam -c1 --capture=25 \\"
	echo "             -s width=640,height=480 --script=<manual focus script>"
	echo "      A code of 0 for every request is the clamp bug: the IPA clamps"
	echo "      against members only startScan() fills, and manual focus never"
	echo "      calls it. Clamp against context.lens.min/max instead."
	fail=1
fi

# What the IPA computed is not what the hardware was told. Read the subdev too.
hw=$(v4l2-ctl -d "$lens" --get-ctrl focus_absolute 2>/dev/null | sed 's/.*: *//')
if [ -n "$hw" ]; then
	echo "      actuator now reads focus_absolute=$hw on $lens"
fi

exit $fail
