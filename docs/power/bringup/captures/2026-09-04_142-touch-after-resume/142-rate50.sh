#!/bin/sh
# #142 - probe at the transaction rate of REAL USE.
#
# Measured from ledger-full.txt (2026-09-04, operator session 11:41-13:19):
#   12.6 touch interrupts/s while tapping x 4 i2c transactions per
#   himax_bus_read() = ~50 transactions/s on the bus.
# Every automated run before this one probed at 0.33-2 /s, i.e. 25-150x too
# slow, and the nulls they produced were predicted nulls: 1493 probes x
# 0.0097 %/transaction = 0.14 expected events.
#
# At ~50/s the same rate predicts one stall per ~8000 transactions = ~160 s,
# so a 600 s run should show 3-4. If it does not, the unused-address probe is
# NOT sampling the same population as the driver's own reads, and the active
# arm of the selftest cannot work.
set -u
DUR=600
echo "=== rate-matched probe, started $(date '+%F %T') ==="
echo "screen before: bl_power=$(cat /sys/class/backlight/*/bl_power 2>/dev/null) dpms=$(cat /sys/class/drm/card0/card0-DSI-1/dpms 2>/dev/null)"

ts=$(for d in /sys/bus/i2c/devices/*-00*; do
        [ -r "$d/name" ] || continue
        [ "$(cat "$d/name")" = "hx83112b" ] && basename "$d"
     done)
[ -n "$ts" ] || { echo "FATAL: no hx83112b found"; exit 1; }
drv=$(basename "$(readlink "/sys/bus/i2c/devices/$ts/driver")")
echo "touchscreen $ts, driver $drv"
echo "$ts" > "/sys/bus/i2c/drivers/$drv/unbind" 2>/dev/null
sleep 2
[ -e "/sys/bus/i2c/devices/$ts/driver" ] && { echo "FATAL: unbind failed"; exit 1; }
echo "driver unbound"

# ☠️ Burn off the first-transaction-after-unbind spike before the real run.
# 3 of 5 runs today stalled on trial 0 - ~1500x the background rate - which is
# an artifact of the unbind, not the fault under study. Discard it explicitly
# rather than letting it contaminate the interval statistics.
echo "--- burn-in (discarded): the trial-0 unbind artifact"
python3 /home/fp3/142-intervals.py 78b7000 0x50 0.02 20 "BURN-IN (discarded)"

echo "--- the measurement: ~50 transactions/s for ${DUR}s"
python3 /home/fp3/142-intervals.py 78b7000 0x50 0.02 "$DUR" "RATE50"

echo "screen after: bl_power=$(cat /sys/class/backlight/*/bl_power 2>/dev/null) dpms=$(cat /sys/class/drm/card0/card0-DSI-1/dpms 2>/dev/null)"
echo "=== restoring ==="
ok=no
for try in 1 2 3; do
    echo "$ts" > "/sys/bus/i2c/drivers/$drv/bind" 2>/dev/null
    sleep 4
    [ -e "/sys/bus/i2c/devices/$ts/driver" ] && { ok=yes; break; }
    echo "   bind attempt $try failed"
done
if [ "$ok" = yes ]; then
    echo "RESTORE VERIFIED: $(readlink /sys/bus/i2c/devices/$ts/driver | sed 's|.*/||')"
else
    echo "RESTORE FAILED - arming a reboot in its own unit"
    systemd-run --collect --on-active=5 --unit=fp3-142-recover3 /sbin/reboot
fi
echo "=== done $(date '+%F %T') ==="
