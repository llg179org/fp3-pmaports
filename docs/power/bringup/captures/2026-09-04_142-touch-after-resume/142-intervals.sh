#!/bin/sh
# #142 - inter-stall intervals at two constant probe rates, one session.
#
# ☠️ ORDER: the 2 s arm runs FIRST this time. The previous A/B ran the fast arm
# first, so if both orders give the same answer that is evidence against an
# order effect; if they differ, the order is the finding.
set -u
P=/home/fp3/142-intervals.py
DUR=600

echo "=== #142 interval measurement, started $(date '+%F %T') ==="
ts=$(for d in /sys/bus/i2c/devices/*-00*; do
        [ -r "$d/name" ] || continue
        [ "$(cat "$d/name")" = "hx83112b" ] && basename "$d"
     done)
[ -n "$ts" ] || { echo "FATAL: no hx83112b found"; exit 1; }
drv=$(basename "$(readlink "/sys/bus/i2c/devices/$ts/driver")")
echo "touchscreen $ts, driver $drv"

# ☠️ Unbind so the probe cannot collide with the driver on the same bus. That
# collision wedged the controller into 1824 consecutive EIO on 2026-09-04.
echo "$ts" > "/sys/bus/i2c/drivers/$drv/unbind" 2>/dev/null
sleep 2
if [ -e "/sys/bus/i2c/devices/$ts/driver" ]; then
    echo "FATAL: unbind failed, refusing to probe beside a live driver"; exit 1
fi
echo "driver unbound - the phone has NO touch for the next ~21 min (by design)"

# ☠️ Instrument gate: 20 s at 0.5 s spacing, in a regime whose answer is on
# record (fast NACKs, ~1 ms). If this prints anything but ~40 fast probes and a
# well-formed null-interval line, the run below is not worth starting.
echo "--- INSTRUMENT GATE (20 s, expect ~40 probes, ms durations, 0 stalls)"
python3 "$P" 78b7000 0x50 0.5 20 "GATE"
echo "--- gate over; if it did not look right, kill the unit now"
sleep 5

python3 "$P" 78b7000 0x50 2.0 "$DUR" "B(1 probe / 2 s)"
echo "-- 30 s settle between arms"
sleep 30
python3 "$P" 78b7000 0x50 0.5 "$DUR" "A(2 probes / s)"

# --- restore, verify, and reboot if it cannot be restored
echo "=== restoring $drv on $ts ==="
ok=no
for try in 1 2 3; do
    echo "$ts" > "/sys/bus/i2c/drivers/$drv/bind" 2>/dev/null
    sleep 4
    if [ -e "/sys/bus/i2c/devices/$ts/driver" ]; then ok=yes; break; fi
    echo "   bind attempt $try failed"
done
if [ "$ok" = yes ]; then
    echo "RESTORE VERIFIED: $(readlink /sys/bus/i2c/devices/$ts/driver | sed 's|.*/||')"
else
    # ☠️ Detach the reboot into its OWN unit: a backgrounded child of a dying
    # unit's cgroup is killed with it and never runs (measured 2026-09-04).
    echo "RESTORE FAILED - arming a reboot in its own unit so the phone gets touch back"
    systemd-run --collect --on-active=5 --unit=fp3-142-recover /sbin/reboot
fi
echo "=== done $(date '+%F %T') ==="
