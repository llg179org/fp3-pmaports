#!/bin/sh
# #142 arm capture: suspend/resume, then read the touch controller's i2c health.
# Writes the answer to $RES with an explicit sync before anything can reset us.
ARM="$1"; RES="/root/142-$ARM.txt"; rm -f "$RES"
{
echo "== arm=$ARM  $(date '+%F %H:%M:%S')"
echo "kernel: $(uname -v)  commit: $(cat /usr/share/kernel/fp3/fp3-commit 2>/dev/null)"
echo -n "system-pc param: "
od -An -tx1 /proc/device-tree/cpus/domain-idle-states/domain-system-power-collapse/arm,psci-suspend-param 2>/dev/null | tr -d ' \n'; echo
S0=$(cat /sys/power/suspend_stats/success); echo "suspend_success_before=$S0"
# marker inside the run, so both edges of the dmesg window are ours
MARK="FP3-142-$ARM-$(date +%s)"
echo "$MARK-START" > /dev/kmsg
IRQ0=$(grep -ci 'hx83112\|himax' /proc/interrupts)
rtcwake -m mem -s 60 >/dev/null 2>&1; RC=$?
echo "$MARK-END" > /dev/kmsg
sleep 3
S1=$(cat /sys/power/suspend_stats/success); echo "suspend_success_after=$S1  delta=$((S1-S0))  rtcwake_rc=$RC"
echo "-- dmesg between our two markers:"
dmesg | sed -n "/$MARK-START/,/$MARK-END/p" | tail -40
echo "-- i2c / touch errors in that window:"
dmesg | sed -n "/$MARK-START/,/$MARK-END/p" | grep -icE 'hx83112|himax|i2c.*(-110|-6)\b|i2c_geni|qup'
echo "-- touch irq count line:"
grep -i 'hx83112\|himax' /proc/interrupts
echo "-- input device still present:"
grep -il hx83112 /sys/class/input/*/device/name 2>/dev/null
echo "== done"
} > "$RES" 2>&1
sync
