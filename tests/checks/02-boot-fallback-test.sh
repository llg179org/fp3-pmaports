#!/bin/sh
# Description: the boot safety net is armed - a second bootable entry, a menu
# that can reach it, and panic=10 on both
#
# The phone has no console and both remote channels (ssh over the USB gadget
# and ssh over WiFi) need userspace to be running, so anything that hangs the
# boot leaves nothing but a held power button and a human in the room. The
# safety net against that is in docs/deploy/README.md: keep the last working
# kernel as a version-free `-fallback` copy, give extlinux a `timeout` and a
# `default`, and put `panic=10` on the append lines so a panicking kernel
# reboots itself.
#
# ☠️ It is not enough to have set this up once. `apk add linux-fp3` regenerates
# extlinux.conf from scratch and silently drops the hand-added fallback label,
# the menu timeout and panic=10 - which is exactly why the deploy doc says
# "check the file, do not assume". Nothing checked it, so nothing noticed: the
# net had been gone for an unknown number of installs when a kernel command
# line experiment hung the boot on 2026-08-16 and cost a physical recovery.
#
# ☠️ This check is about the *net*, not about any one experiment. Read a FAIL
# here as "the next hang costs a human", whatever causes it.

CONF=/boot/extlinux/extlinux.conf
BOOT=/boot
fail=0

if [ ! -r "$CONF" ]; then
	echo "FAIL: $CONF is not readable, so nothing here can be checked"
	echo "      cmd: sudo cat $CONF"
	exit 1
fi

# 1. Is there a second entry to fall back to, and do its files exist? A label
# pointing at a missing kernel is worse than no label: it looks like a net.
if ! grep -q '^label postmarketOS-fallback' "$CONF"; then
	echo "FAIL: no postmarketOS-fallback label - there is only one bootable"
	echo "      entry, so a bad kernel or command line has nothing to fall"
	echo "      back to"
	echo "      cmd: see fp3-pmaports/docs/deploy/README.md, 'the fallback entry'"
	fail=1
else
	missing=
	for f in vmlinuz-fallback sdm632-fairphone-fp3.dtb-fallback; do
		[ -e "$BOOT/$f" ] || missing="$missing $f"
	done
	if [ -n "$missing" ]; then
		echo "FAIL: the fallback label exists but its files do not:$missing"
		echo "      cmd: ls -l $BOOT"
		fail=1
	else
		echo "PASS: fallback entry present, with its kernel and dtb on disk"
	fi
fi

# 2. Can the menu actually be reached, and does it pick something? Without a
# timeout the bootloader takes the first label and a wrong default is
# unrecoverable without hands.
if ! grep -q '^timeout ' "$CONF"; then
	echo "FAIL: no 'timeout' line, so the boot menu never appears and the"
	echo "      fallback cannot be chosen at the phone"
	echo "      cmd: grep -E '^(timeout|default|menu)' $CONF"
	fail=1
elif ! grep -q '^default ' "$CONF"; then
	echo "FAIL: no 'default' line - which entry boots is then positional and"
	echo "      changes silently when the file is regenerated"
	echo "      cmd: grep -E '^(timeout|default|menu)' $CONF"
	fail=1
else
	echo "PASS: menu armed ($(grep -E '^(timeout|default) ' "$CONF" | tr '\n' ' '))"
fi

# 3. Does a panicking kernel come back by itself? This is the half of the net
# that works with nobody in the room. It does not help against a hang - only
# the watchdog does - but it is one word and it costs nothing.
appends=$(grep -c '^[[:space:]]*append ' "$CONF" 2>/dev/null)
panics=$(grep -c '^[[:space:]]*append .*panic=' "$CONF" 2>/dev/null)
if [ "${appends:-0}" -eq 0 ]; then
	echo "FAIL: no append line at all in $CONF"
	fail=1
elif [ "${panics:-0}" -lt "${appends:-0}" ]; then
	echo "FAIL: $panics of $appends boot entries carry panic=, so a panicking"
	echo "      kernel sits there instead of rebooting into something that works"
	echo "      cmd: grep append $CONF"
	fail=1
else
	echo "PASS: all $appends boot entries carry panic="
fi

# 4. Is the watchdog - the only thing that recovers a *hang* - actually running?
# The debug layer starts it at probe for exactly this reason.
if [ -e /dev/watchdog ] || [ -d /sys/class/watchdog/watchdog0 ]; then
	state=$(cat /sys/class/watchdog/watchdog0/state 2>/dev/null)
	if [ "$state" = active ]; then
		echo "PASS: watchdog0 is active (timeout $(cat /sys/class/watchdog/watchdog0/timeout 2>/dev/null)s)"
	else
		echo "FAIL: watchdog0 exists but is '$state', so a hung boot waits for"
		echo "      a held power button instead of resetting"
		echo "      cmd: cat /sys/class/watchdog/watchdog0/state"
		fail=1
	fi
else
	echo "FAIL: no watchdog device - the debug layer's watchdog-at-probe patch"
	echo "      is missing from the running kernel, so nothing recovers a hang"
	echo "      cmd: ls /sys/class/watchdog/; see fp3-pmaports/docs/debug/"
	fail=1
fi

exit $fail
