#!/bin/sh
# Restart the .O tap-test app from the app grid: bring its dependencies up
# (root helper, sudoers-limited), stop any running instance (same uid), start.
# ☠️ The pattern is anchored on the full command line: a bare -f "fp3-taptest.py"
# also matches whatever shell happens to carry that string - measured 2026-09-11,
# it killed the ssh session that was deploying this file.
LOG=/home/fp3/taptest-launcher.log
echo "$(date '+%F %T') launcher: $(sudo -n /usr/local/bin/fp3-taptest-deps.sh 2>&1)" >> $LOG
pkill -u "$(id -u)" -f '^/usr/bin/python3 /home/fp3/armb/fp3-taptest\.py' 2>/dev/null
sleep 0.5
export GDK_BACKEND=wayland
exec /usr/bin/python3 /home/fp3/armb/fp3-taptest.py >> $LOG 2>&1
