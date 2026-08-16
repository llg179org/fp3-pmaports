#!/bin/sh
# Category: camera
# Description: a focus window survives the trip through PipeWire
#
# 44-camera-af-windows proves the camera offers focus windows and that the IPA
# aims at them. That is measured with `cam`, which talks to libcamera directly.
# Every application on this device talks to it through PipeWire instead, and
# for a long time the two answers differed: the camera offered the control and
# the node did not carry it, so "tap to focus" focused on the middle of the
# frame whatever the user tapped.
#
# ☠️ Two separate gates had to open, and each looks like the other's absence:
#
# 1. The libcamera SPA plugin dropped every array-typed control - it refused to
#    describe one and refused to parse one - so the node published only
#    AfMode, AfMetering, AfTrigger and LensPosition. The tap position had
#    nowhere to go.
#
# 2. pw-cli, and anything driving a node through it, sends an array value as a
#    POD *struct*, not a POD array: spa_json_to_pod_part() has only the static
#    type table to work from, every camera control is published past
#    SPA_PROP_START_CUSTOM and so appears in no table, and with no type it
#    turns a JSON array into a struct of ints. A plugin that accepts only
#    arrays therefore publishes a control that cannot be set - which from the
#    outside is indistinguishable from not publishing it.
#
# So the check exercises the whole chain the application uses, and it needs a
# stream: the IPA does not exist until somebody is capturing, and a control set
# against an idle node measures nothing.
#
# The verdict is the IPA's "Metering N of M zones" line read out of the
# journal. The centre fallback is 9 of 25, so a corner window answering 9 is
# the signature of a window that arrived nowhere.

fail=0

command -v pw-cli >/dev/null 2>&1 || {
	echo "SKIP: pw-cli not installed, nothing to drive the node with"
	exit 0
}
command -v gst-launch-1.0 >/dev/null 2>&1 || {
	echo "SKIP: gst-launch-1.0 not installed, nothing to hold a stream open"
	exit 0
}

node=$(pw-cli ls Node 2>/dev/null |
	awk '/^\tid [0-9]+,/ { id = $2; sub(",", "", id) }
	     /node\.name = "libcamera_input/ { print id; exit }')
[ -n "$node" ] || {
	echo "SKIP: no libcamera node in the PipeWire graph"
	exit 0
}

# The property id the plugin publishes a control under is SPA_PROP_START_CUSTOM
# plus libcamera's control id, so it can be computed - but computing it would
# hide exactly the failure this check is for. Read it off the node instead: if
# AfWindows is not published, there is no id and the check says so.
props=$(mktemp) || exit 1
zones=$(mktemp) || exit 1
trap 'rm -f "$props" "$zones"; systemctl --user stop af-windows-probe 2>/dev/null' EXIT

pw-cli enum-params "$node" PropInfo > "$props" 2>/dev/null

af_windows=$(awk '/Id [0-9]+ +\(/ { id = $2 }
		  /String "AfWindows"/ { print id; exit }' "$props")
af_metering=$(awk '/Id [0-9]+ +\(/ { id = $2 }
		   /String "AfMetering"/ { print id; exit }' "$props")

if [ -z "$af_windows" ]; then
	echo "FAIL: the PipeWire node does not publish AfWindows"
	echo "      cmd: pw-cli enum-params $node PropInfo | grep -B1 AfWindows"
	echo "      libcamera offers the control (44-camera-af-windows) but the"
	echo "      SPA plugin drops array-typed controls, so no application"
	echo "      reaching the camera through PipeWire can say where to focus."
	exit 1
fi

if ! grep -q 'PropInfo:container' "$props"; then
	echo "FAIL: AfWindows is published without a container"
	echo "      cmd: pw-cli enum-params $node PropInfo | grep container"
	echo "      An array property has to say it is one, or a client cannot"
	echo "      tell how many values the range describes."
	fail=1
fi

[ -n "$af_metering" ] || {
	echo "SKIP: the node publishes AfWindows but not AfMetering, so windowed"
	echo "      metering cannot be selected and the windows cannot take effect"
	exit 0
}

# The IPA only exists while somebody is capturing, and its log is what says
# where the score was metered from - so raise the level before the stream
# starts, not after.
systemctl --user set-environment LIBCAMERA_LOG_LEVELS=IPASoftAf:INFO
systemctl --user restart pipewire wireplumber
sleep 4

# Re-read the node id: restarting the stack renumbers the graph.
node=$(pw-cli ls Node 2>/dev/null |
	awk '/^\tid [0-9]+,/ { id = $2; sub(",", "", id) }
	     /node\.name = "libcamera_input/ { print id; exit }')

systemd-run --user --unit=af-windows-probe --collect \
	gst-launch-1.0 pipewiresrc target-object="$node" ! videoconvert ! fakesink \
	>/dev/null 2>&1
sleep 8

if ! systemctl --user is-active af-windows-probe >/dev/null 2>&1; then
	echo "SKIP: could not hold a stream open on the camera node - another"
	echo "      application may already have it"
	systemctl --user unset-environment LIBCAMERA_LOG_LEVELS
	exit 0
fi

metered_for() {
	pw-cli set-param "$node" Props "{ $af_windows: [ $1 ] }" >/dev/null 2>&1
	sleep 3
	journalctl --user -n 80 --no-pager 2>/dev/null |
		sed -n 's/.*Metering \([0-9]*\) of \([0-9]*\) zones.*/\1 \2/p' | tail -1
}

pw-cli set-param "$node" Props "{ $af_metering: 1 }" >/dev/null 2>&1
sleep 2

full=$(metered_for "0, 0, 4032, 3024")
near=$(metered_for "0, 0, 400, 300")
far=$(metered_for "3600, 2700, 400, 300")

systemctl --user stop af-windows-probe 2>/dev/null
systemctl --user unset-environment LIBCAMERA_LOG_LEVELS

if [ -z "$full" ] || [ -z "$near" ] || [ -z "$far" ]; then
	echo "FAIL: the IPA never reported which zones it metered"
	echo "      cmd: pw-cli set-param $node Props '{ $af_windows: [ 0, 0, 400, 300 ] }'"
	echo "           journalctl --user -n 80 | grep 'Metering'"
	echo "      Either nothing was streaming, or the value never reached"
	echo "      libcamera. pw-cli sends an array as a POD struct, so a plugin"
	echo "      that accepts only POD arrays silently drops it."
	exit 1
fi

total=${full#* }
full=${full%% *}
near=${near%% *}
far=${far%% *}
small=$((total / 4))

if [ "$full" -eq "$total" ] && [ "$near" -le "$small" ] && [ "$far" -le "$small" ]; then
	echo "PASS: focus windows reach the camera through PipeWire - whole frame" \
		"$full/$total zones, near corner $near, far corner $far"
else
	echo "FAIL: focus windows do not survive the trip through PipeWire"
	echo "      whole frame $full/$total zones, near corner $near, far corner $far"
	echo "      cmd: pw-cli set-param $node Props '{ $af_windows: [ 0, 0, 400, 300 ] }'"
	echo "           journalctl --user -n 80 | grep 'Metering'"
	echo "      A corner window answering the centre fallback's count means"
	echo "      the value did not arrive. Both corners answering it while"
	echo "      44-camera-af-windows passes puts the fault in the transport,"
	echo "      not in the IPA."
	fail=1
fi

exit $fail
