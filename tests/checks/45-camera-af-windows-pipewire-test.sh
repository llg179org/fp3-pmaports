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

# ☠️ The runner runs every check as root, and PipeWire is a *per-user* service.
# Root has no XDG_RUNTIME_DIR and no graph of its own, so every pw-cli call here
# used to come back empty - and the check then reported "no libcamera node in
# the PipeWire graph" and skipped. Measured 2026-08-16: as root `pw-cli ls Node`
# returns zero nodes of any kind, so that message was not a weaker version of
# the truth, it was a different claim altogether. The check had been proved in
# both directions by hand as the session user and never once under the runner,
# which is exactly how a check ends up passing on nothing.
#
# So find the logged-in session and speak to it, and keep the two failures
# apart below: "cannot reach a graph" is about this check, "the graph has no
# camera node" is about the device.
_row=$(loginctl list-users --no-legend 2>/dev/null |
	awk '$2 != "root" { print $1, $2; exit }')
sess_uid=${_row%% *}
sess_user=${_row#* }
[ -n "$_row" ] && [ -n "$sess_uid" ] && [ -n "$sess_user" ] || {
	echo "SKIP: no logged-in user session, so there is no PipeWire graph to"
	echo "      drive - this check measures the path an application uses"
	exit 0
}

# Setting XDG_RUNTIME_DIR by hand is how a dead session gets misdiagnosed as a
# broken daemon, so it is only ever done together with the reachability gate
# below - never as a way of assuming the session is alive.
if [ "$(id -u)" = "$sess_uid" ]; then
	as_user() { sh -c "$*"; }
else
	as_user() {
		su "$sess_user" -c "XDG_RUNTIME_DIR=/run/user/$sess_uid \
DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$sess_uid/bus $*"
	}
fi

nodes=$(as_user 'pw-cli ls Node' 2>/dev/null | grep -c '^	id ')
if [ "$nodes" -eq 0 ]; then
	echo "SKIP: cannot reach $sess_user's PipeWire graph, so nothing about"
	echo "      the camera was measured"
	echo "      cmd: su $sess_user -c 'XDG_RUNTIME_DIR=/run/user/$sess_uid pw-cli ls Node'"
	exit 0
fi

find_node() {
	as_user 'pw-cli ls Node' 2>/dev/null |
		awk '/^\tid [0-9]+,/ { id = $2; sub(",", "", id) }
		     /node\.name = "libcamera_input/ { print id; exit }'
}

node=$(find_node)
[ -n "$node" ] || {
	echo "SKIP: $sess_user's PipeWire graph has $nodes nodes but no camera"
	echo "      node, so there is nothing to send a focus window to"
	exit 0
}

# The property id the plugin publishes a control under is SPA_PROP_START_CUSTOM
# plus libcamera's control id, so it can be computed - but computing it would
# hide exactly the failure this check is for. Read it off the node instead: if
# AfWindows is not published, there is no id and the check says so.
props=$(mktemp) || exit 1
zones=$(mktemp) || exit 1
trap 'rm -f "$props" "$zones"; as_user "systemctl --user stop af-windows-probe" 2>/dev/null' EXIT

as_user "pw-cli enum-params $node PropInfo" > "$props" 2>/dev/null

af_windows=$(awk '/Id [0-9]+ +\(/ { id = $2 }
		  /String "AfWindows"/ { print id; exit }' "$props")
af_metering=$(awk '/Id [0-9]+ +\(/ { id = $2 }
		   /String "AfMetering"/ { print id; exit }' "$props")

if [ -z "$af_windows" ]; then
	echo "FAIL: the PipeWire node does not publish AfWindows"
	echo "      cmd: su $sess_user -c 'pw-cli enum-params $node PropInfo' | grep -B1 AfWindows"
	echo "      libcamera offers the control (44-camera-af-windows) but the"
	echo "      SPA plugin drops array-typed controls, so no application"
	echo "      reaching the camera through PipeWire can say where to focus."
	exit 1
fi

if ! grep -q 'PropInfo:container' "$props"; then
	echo "FAIL: AfWindows is published without a container"
	echo "      cmd: su $sess_user -c 'pw-cli enum-params $node PropInfo' | grep container"
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
as_user "systemctl --user set-environment LIBCAMERA_LOG_LEVELS=IPASoftAf:INFO"
as_user "systemctl --user restart pipewire wireplumber"
sleep 4

# Re-read the node id: restarting the stack renumbers the graph.
node=$(find_node)
[ -n "$node" ] || {
	echo "SKIP: the camera node did not come back after restarting the media"
	echo "      stack, so the windows could not be measured"
	as_user "systemctl --user unset-environment LIBCAMERA_LOG_LEVELS"
	exit 0
}

as_user "systemd-run --user --unit=af-windows-probe --collect \
	gst-launch-1.0 pipewiresrc target-object=$node ! videoconvert ! fakesink" \
	>/dev/null 2>&1
sleep 8

if ! as_user "systemctl --user is-active af-windows-probe" >/dev/null 2>&1; then
	echo "SKIP: could not hold a stream open on the camera node - another"
	echo "      application may already have it"
	as_user "systemctl --user unset-environment LIBCAMERA_LOG_LEVELS"
	exit 0
fi

metered_for() {
	as_user "pw-cli set-param $node Props '{ $af_windows: [ $1 ] }'" >/dev/null 2>&1
	sleep 3
	as_user "journalctl --user -n 80 --no-pager" 2>/dev/null |
		sed -n 's/.*Metering \([0-9]*\) of \([0-9]*\) zones.*/\1 \2/p' | tail -1
}

as_user "pw-cli set-param $node Props '{ $af_metering: 1 }'" >/dev/null 2>&1
sleep 2

full=$(metered_for "0, 0, 4032, 3024")
near=$(metered_for "0, 0, 400, 300")
far=$(metered_for "3600, 2700, 400, 300")

as_user "systemctl --user stop af-windows-probe" 2>/dev/null
as_user "systemctl --user unset-environment LIBCAMERA_LOG_LEVELS"

if [ -z "$full" ] || [ -z "$near" ] || [ -z "$far" ]; then
	echo "FAIL: the IPA never reported which zones it metered"
	echo "      cmd: su $sess_user -c \"pw-cli set-param $node Props '{ $af_windows: [ 0, 0, 400, 300 ] }'\""
	echo "           su $sess_user -c 'journalctl --user -n 80' | grep Metering"
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
	echo "      cmd: su $sess_user -c \"pw-cli set-param $node Props '{ $af_windows: [ 0, 0, 400, 300 ] }'\""
	echo "           su $sess_user -c 'journalctl --user -n 80' | grep Metering"
	echo "      A corner window answering the centre fallback's count means"
	echo "      the value did not arrive. Both corners answering it while"
	echo "      44-camera-af-windows passes puts the fault in the transport,"
	echo "      not in the IPA."
	fail=1
fi

exit $fail
