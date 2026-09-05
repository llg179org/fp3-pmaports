#!/bin/sh
# Rebind the touchscreen when the kernel disables its interrupt.
#
# ☠️ THIS IS A BAND-AID FOR r84 AND MUST BE REMOVED ONCE r85 IS ON THE PHONE.
# The real fault is in the driver: himax_irq_handler returns IRQ_NONE when the
# event read fails, the line is level triggered, so every retry counts as an
# unhandled interrupt and note_interrupt() disables IRQ 127 after 100 000 of
# them - measured 2026-09-05 at ~7800/s, so eleven seconds. c59812386d99 fixes
# that in the kernel; this only shortens the dead-panel window until it ships.
#
# ☠️ It is BOUNDED. A rebind that keeps being needed is a fault to look at, not
# a thing to paper over forever, so it stops after MAX_REBINDS in an hour and
# says so.
set -u
MAX_REBINDS=6
count=0
window=$(date +%s)

find_ts() {   # ☠️ by name: the i2c bus number moved twice on this device in a day
	for d in /sys/bus/i2c/devices/*-00*; do
		[ -r "$d/name" ] || continue
		[ "$(cat "$d/name" 2>/dev/null)" = hx83112b ] && { basename "$d"; return 0; }
	done
	return 1
}

rebind() {
	ts=$(find_ts) || { logger -t fp3-touch-guard "no hx83112b found, not rebinding"; return; }
	drv=/sys/bus/i2c/drivers/Himax-hx83112b-TS
	[ -d "$drv" ] || { logger -t fp3-touch-guard "driver dir missing"; return; }
	echo "$ts" > "$drv/unbind" 2>/dev/null
	sleep 1
	echo "$ts" > "$drv/bind"   2>/dev/null
	sleep 2
	if [ -e "/sys/bus/i2c/devices/$ts/driver" ]; then
		logger -t fp3-touch-guard "rebound $ts after the kernel disabled its IRQ (rebind $count/$MAX_REBINDS this hour)"
	else
		logger -t fp3-touch-guard "REBIND FAILED for $ts - the panel is dead until a reboot"
	fi
}

logger -t fp3-touch-guard "watching for 'Disabling IRQ' on the touch interrupt"
journalctl -kf -o cat -n 0 2>/dev/null | while read -r line; do
	case "$line" in
	*"Disabling IRQ #"*) ;;
	*) continue ;;
	esac
	now=$(date +%s)
	[ $((now - window)) -gt 3600 ] && { window=$now; count=0; }
	count=$((count + 1))
	if [ "$count" -gt "$MAX_REBINDS" ]; then
		logger -t fp3-touch-guard "$count disables in this hour - refusing to rebind again, this needs looking at"
		continue
	fi
	logger -t fp3-touch-guard "kernel line: $line"
	rebind
done
