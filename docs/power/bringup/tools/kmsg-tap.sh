#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# kmsg-tap.sh OUTFILE - stream the device's kernel log to a file ON THE HOST.
#
# AI-generated content. Written 2026-08-23.
#
# ☠️ Why this exists. The camss/IOMMU wedge under investigation ends with the
# watchdog resetting the phone, and the phone's rootfs is 93% full, so journald
# sits permanently against its free-space guard and vacuums the boot before
# last. Measured the same day: a run that provably reset the device left
# `journalctl -k -b -1` answering "-- No entries --". The reset was confirmed
# and the evidence for it was gone.
#
# A log that lives on the host cannot be vacuumed by the device, and is already
# written when the device dies. That is the whole idea.
#
# `dmesg -w` prints the current ring buffer and then follows it, so every
# reconnect after a reset captures the new boot from the beginning too.
#
# Usage:
#   docs/power/bringup/tools/kmsg-tap.sh /path/to/kmsg.log &
#   ... run the battery ...
#   kill %1
#
# The device password comes from $FP3_PW so it is not written down here.
set -u

out=${1:?usage: kmsg-tap.sh OUTFILE}
pw=${FP3_PW:-<pw>}

trap 'echo "=== tap stopped $(date -Is)" >>"$out"; exit 0' INT TERM

echo "=== tap started $(date -Is)" >>"$out"
while :; do
	echo "=== attaching $(date -Is) (host clock)" >>"$out"
	# Record what the device thinks the time is, so a line in this file can
	# be tied to a device uptime after the fact.
	fp3-ssh "echo 'uptime_at_attach='\$(cut -d. -f1 /proc/uptime)" >>"$out" 2>&1
	# -w follows; the whole existing buffer is printed first, which is what
	# makes a post-reset reattach capture the new boot from its start.
	fp3-ssh "echo '$pw' | sudo -S dmesg -w" >>"$out" 2>&1
	echo "=== detached $(date -Is) - link lost or device reset, retrying" >>"$out"
	sleep 5
done
