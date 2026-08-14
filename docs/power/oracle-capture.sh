#!/bin/sh
# Capture the RPM-side ground truth from the Ubuntu Touch oracle on slot_a.
# Run from the host: ut-ssh.sh "$(cat oracle-capture.sh)" > capture.txt
echo "=== uptime ==="; cat /proc/uptime
echo "=== rpm_stats (vlow/vmin) ==="
cat /sys/kernel/debug/rpm_stats 2>/dev/null || echo "MISSING /sys/kernel/debug/rpm_stats"
echo "=== rpm_master_stats ==="
cat /sys/kernel/debug/rpm_master_stats 2>/dev/null || echo "MISSING"
echo "=== lpm_stats ==="
cat /sys/kernel/debug/lpm_stats/stats 2>/dev/null | head -60 || echo "MISSING"
