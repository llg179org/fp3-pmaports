#!/bin/sh
# #142 arm B — baseline before the deliberate suspend.
# Driver must be BOUND (that is the whole point: the rail fix is its devm vote).
OUT=/home/fp3/armb
mkdir -p "$OUT"
S="$OUT/baseline.txt"
{
  echo "=== date ==="            ; date -Is
  echo "=== boot_id ==="         ; cat /proc/sys/kernel/random/boot_id
  echo "=== uname ==="           ; uname -a
  echo "=== fp3-commit ==="      ; cat /usr/share/kernel/fp3/fp3-commit
  echo "=== uptime ==="          ; cat /proc/uptime
  echo "=== suspend success ===" ; cat /sys/power/suspend_stats/success
  echo "=== suspend fail ==="    ; cat /sys/power/suspend_stats/fail
  echo "=== himax irq ==="       ; grep hx83112b /proc/interrupts
  echo "=== dpms ==="            ; cat /sys/class/drm/card0-DSI-1/dpms
  echo "=== backlight ==="       ; cat /sys/class/backlight/*/brightness
  echo "=== touch driver ==="    ; readlink -f /sys/bus/i2c/devices/2-0048/driver
  echo "=== l6 consumers ==="    ; sudo awk '/ l6 /{f=1;print;next} f&&/^ +[a-z0-9]/{print;next} f{exit}' /sys/kernel/debug/regulator/regulator_summary
  echo "=== logind idle ==="     ; ls /etc/systemd/logind.conf.d/ 2>/dev/null; loginctl show-session c1 -p IdleHint
  echo "=== journal cursor ===" ; sudo journalctl -n0 --show-cursor 2>/dev/null | tail -1
} > "$S" 2>&1
cat "$S"
