#!/bin/sh
# #142 - touch after resume, on a kernel that ALREADY carries the system-pc
# affinity change (0x42000353, twin 0740bfb33b77 on debug-int/7.1.3).
#
# Prints one snapshot line set. Take it before the suspend and after the
# tapping; the DIFFERENCE is the measurement, never the absolute value.
#
# ! himax_resume() only calls enable_irq() - it does no i2c at all. So a
#   -110/-6 CANNOT appear at resume by itself; it needs a real touch to fire
#   the interrupt. That is why this probe cannot be run unattended.
echo "wall        $(date -Is)"
echo "uptime_s    $(cut -d' ' -f1 /proc/uptime)"
echo "suspends    $(cat /sys/power/suspend_stats/success 2>/dev/null) ok / $(cat /sys/power/suspend_stats/fail 2>/dev/null) fail"
echo "touch_irq   $(awk '/hx83112b/ {s=0; for(i=2;i<=NF;i++) if ($i ~ /^[0-9]+$/) s+=$i; print s}' /proc/interrupts)"
echo "err_110     $(dmesg | grep -c 'Failed to read input event: -110')"
echo "err_6       $(dmesg | grep -c 'Failed to read input event: -6')"
echo "err_any     $(dmesg | grep -c 'Failed to read input event')"
echo "qup_timeout $(dmesg | grep -c '78b7000.i2c: transfer to 0x48 timed out')"
echo "qup_cleared $(dmesg | grep -c '78b7000.i2c: bus cleared')"
echo "irq_disabled $(dmesg | grep -c 'Disabling IRQ')"
