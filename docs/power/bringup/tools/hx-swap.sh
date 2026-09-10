#!/bin/sh
# hx-swap.sh /path/to/new.ko   -- root, on pmOS. Hot-swap the himax_hx83112b module.
#
# ☠️ Only with the display ON: with it off the touch driver's regulator reference
# is the last holder of iovcc, unbind drops the rail, and probe then fails with
# ENXIO - measured 2026-09-10, a dead panel until the display was woken.
# The old module is kept next to the new one so the swap can be undone in place.
#
# ☠️ Kprobes on the module's own functions are disabled across the reload.
# Measured 2026-09-10: with hx_irq/hx_rd armed, insmod of the new module fired
# WARNING kernel/trace/ftrace.c ftrace_bug - ftrace tried to re-arm the probes
# on the old addresses. Disable before rmmod, re-enable after insmod.
set -u
NEW=${1:?new .ko}
K=/lib/modules/$(uname -r)/kernel/drivers/input/touchscreen/himax_hx83112b.ko
D=/sys/bus/i2c/drivers/Himax-hx83112b-TS
say() { echo "$(date +%T)  $*"; }
[ "$(cat /sys/class/drm/card0-DSI-1/dpms)" = "On" ] || { say "display is OFF - refusing"; exit 1; }
[ "$(modinfo -F vermagic "$NEW")" = "$(modinfo -F vermagic "$K")" ] || { say "vermagic differs - refusing"; modinfo -F vermagic "$NEW" "$K"; exit 1; }
say "old: $(md5sum < "$K" | cut -c1-12)  new: $(md5sum < "$NEW" | cut -c1-12)"
cp -a "$K" "$K.pre-swap.$(date +%s)" || exit 1
T=/sys/kernel/debug/tracing
KP=$(cat $T/events/kprobes/enable 2>/dev/null)
[ "$KP" = 1 ] && { echo 0 > $T/events/kprobes/enable; say "kprobes disabled for the reload"; }
echo 2-0048 > $D/unbind 2>&1 && say "unbound"
rmmod himax_hx83112b 2>&1 && say "rmmod ok"
cp "$NEW" "$K" && say "installed"
insmod "$K" 2>&1 && say "insmod ok"
[ "$KP" = 1 ] && { echo 1 > $T/events/kprobes/enable && say "kprobes re-enabled"; }
sleep 0.3
[ -e /sys/bus/i2c/devices/2-0048/driver ] || { echo 2-0048 > $D/bind 2>&1; say "bind issued"; }
sleep 0.5
say "driver: $(readlink /sys/bus/i2c/devices/2-0048/driver 2>/dev/null | sed 's#.*/##')  node: $(ls /sys/bus/i2c/devices/2-0048/input/input*/ 2>/dev/null | grep -o 'event[0-9]*')"
say "kernel log:"; journalctl -k --since "-30s" --no-pager -o cat 2>/dev/null | grep -iE "himax|hx83112" | tail -5
say "kprobes still armed: $(grep -c . /sys/kernel/debug/tracing/kprobe_events) events, enabled: $(cat /sys/kernel/debug/tracing/events/kprobes/enable 2>/dev/null)"
