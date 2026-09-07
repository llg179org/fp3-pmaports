#!/bin/sh
# #142 arm A - the PRE-REGISTERED confirmation of the rail fix on r88.
# Criterion, registered 2026-09-04 on #80-fp3: screen-off 5/5 must become 0/5.
# Idempotent: everything below can be re-run; the actual run is a systemd unit,
# so a second attempt is refused rather than duplicated.
set -u
echo "=== kernel ==="; uname -v
echo "=== rail fix present in the running DTB? ==="
for n in iovcc vdda; do
  printf '%s-supply: ' "$n"
  if [ -e "/proc/device-tree/soc@0/i2c@78b7000/touchscreen@48/${n}-supply" ]; then echo PRESENT; else echo ABSENT; fi
done
echo "=== l6 consumers (the whole root cause, in one line) ==="
grep -A3 -w 'l6' /sys/kernel/debug/regulator/regulator_summary 2>/dev/null | head -6
echo "=== DISARM the idle-suspend drop-in (arm A blanks the screen for 12 s a round) ==="
rm -fv /etc/systemd/logind.conf.d/*idle*.conf /etc/systemd/logind.conf.d/*suspend*.conf 2>/dev/null
ls -la /etc/systemd/logind.conf.d/ 2>/dev/null || echo "  (no drop-in dir)"
systemctl restart systemd-logind 2>/dev/null && echo "  logind restarted"
echo "=== instrument present? ==="
ls -la /home/fp3/142-trigger.sh 2>/dev/null || echo "  MISSING - must be copied from the capture"
echo "=== starting arm A as a unit ==="
systemd-run --collect --unit=fp3-142-armA \
  /bin/sh -c '/bin/sh /home/fp3/142-trigger.sh > /home/fp3/142-armA-r88.txt 2>&1' \
  && echo "  ARMED - result will be /home/fp3/142-armA-r88.txt (~7 min)" \
  || echo "  already running or failed to start"
