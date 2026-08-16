#!/bin/sh
# Which devices get their sync_state() callback, and when?
#
# Why this exists. The amplifier stops answering on i2c about 25 s into every
# boot with nothing in the kernel log, and sync_state() is the mechanism that
# turns off resources the bootloader left on, once the last consumer of a
# supplier has probed. That makes it a fair suspect: it is anchored to boot,
# it is silent, and what it switches off stays off.
#
# ☠️ Do NOT test this with fw_devlink=off on the command line. Measured
# 2026-08-16: it hangs the boot before the USB gadget comes up, and since the
# command line is on disk it repeats on every boot - the device needed a held
# power button and a human. Every variable on this phone has to be revertible
# over ssh. This script is the revertible way to ask the same question: it
# watches the per-device `state_synced` flags, which flip exactly when the
# callback runs.
#
# Run it from a Type=simple unit ordered After=sysinit.target, then diff the
# sample taken before the amplifier's death against the one after it. The death
# is timestamped by the driver's own WATCH line in dmesg.
OUT=${OUT:-/run/syncsnap}
SAMPLES=${SAMPLES:-60}
rm -rf "$OUT"; mkdir -p "$OUT"
i=0
while [ "$i" -lt "$SAMPLES" ]; do
	t=$(cut -d' ' -f1 /proc/uptime)
	# One line per device that carries the flag, so a diff names the device
	# whose callback ran between two samples.
	#
	# ☠️ Walk the whole tree, not a few glob levels. Measured 2026-08-17: a
	# three-level glob under /sys/devices/platform reached 13 of the 39 files
	# that exist, and none of the i2c devices - so it could not have seen the
	# amplifier's own supplier sync even if that were the cause. A null result
	# from an instrument that does not cover the question is not evidence.
	find /sys/devices -name state_synced 2>/dev/null | while read -r f; do
		[ -r "$f" ] || continue
		printf '%s %s\n' "$(cat "$f" 2>/dev/null)" "${f%/state_synced}"
	done | sort -k2 > "$OUT/$t"
	i=$((i+1))
	sleep 1
done
