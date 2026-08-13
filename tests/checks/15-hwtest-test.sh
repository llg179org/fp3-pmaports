#!/bin/sh
# Description: hwtest reports no hardware regression against the reference
#
# hwtest (MartijnBraam) already does the tedious half of a hardware pass -
# framebuffer, DRM, every input device - and it has real regression semantics:
# --export once, --verify after each bump, exit 1 when something that used to
# work no longer does. Reusing it beats reimplementing it, so this check only
# wires it up.
#
# Measured behaviour that shaped the code below:
#   - it needs root; as a normal user it dies on /dev/input/event5 with an
#     unhandled PermissionError
#   - the reference cannot live in /tmp: fs.protected_regular stops root from
#     writing over a file another user created in a sticky directory
#   - --verify returns 1 on a regression and 0 when clean
#
# Most of hwtest's components are skipped, and the reference in baseline/ was
# exported with exactly the same flags - see the comment at the top of that file
# for why each one goes. Both halves matter: --verify exits 1 when an option in
# the reference produces no result this run, so skipping a component on only one
# side turns it into a regression rather than a silence.
#
# What is left is what hwtest is genuinely good at and nothing else here covers:
# the framebuffer, the DRM connector, and every input device.
#
# ☠️ --skip is `action='append'`: it takes ONE component per flag and compares
# with `c.__name__ in args.skip`, so a comma-separated list matches nothing and
# skips nothing, silently.

# The reference travels with the suite rather than living only on the device:
# it is a baseline like every other file in baseline/, so it should be
# versioned, reviewable in a diff, and not lost to a reinstall.
REF="$DEVICE_DIR/baseline/hwtest-reference.ini"

# Keep in step with the reference: whatever is listed here has to have been
# passed to --export as well, or --verify reports the difference as a removal.
SKIP="--skip Camera --skip Audio --skip Vibrator --skip Magnetometer
	--skip Accelerometer --skip Gyroscope --skip Temperature --skip Proximity
	--skip Illuminance --skip Pressure --skip Led"

if ! command -v hwtest >/dev/null 2>&1; then
	echo "FAIL: hwtest is not installed (apk add hwtest)"
	exit 1
fi

if [ ! -f "$REF" ]; then
	echo "FAIL: no hwtest reference at $REF"
	echo "      Create one from a state you consider good, with the same skips:"
	echo "        hwtest $SKIP --export tests/baseline/hwtest-reference.ini"
	echo "      and edit it so components that SHOULD work read True, even if"
	echo "      they are broken today - otherwise the breakage becomes the"
	echo "      baseline and stops being reported."
	exit 1
fi

# shellcheck disable=SC2086  # SKIP is a deliberate list of separate flags
out=$(hwtest --formatter MarkdownTable $SKIP --verify "$REF" 2>&1)
rc=$?

if [ "$rc" -eq 0 ]; then
	echo "PASS: hwtest matches the reference"
	exit 0
fi

echo "FAIL: hwtest reports a regression against $REF"
printf '%s\n' "$out" | sed 's/^/  /'
exit 1
