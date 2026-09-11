#!/bin/sh
# Restart the .O tap-test app from the app grid: stop any running instance
# (same uid, so no root needed), then run it in this session.
# ☠️ The pattern is anchored on the full command line: a bare -f "fp3-taptest.py"
# also matches whatever shell happens to carry that string - measured 2026-09-11,
# it killed the ssh session that was deploying this file.
pkill -u "$(id -u)" -f '^/usr/bin/python3 /home/fp3/armb/fp3-taptest\.py' 2>/dev/null
sleep 0.5
export GDK_BACKEND=wayland
exec /usr/bin/python3 /home/fp3/armb/fp3-taptest.py >> /home/fp3/taptest-launcher.log 2>&1
