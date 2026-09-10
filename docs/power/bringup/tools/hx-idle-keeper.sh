#!/bin/sh
# hx-idle-keeper.sh -- TEST INSTRUMENT, NOT A FIX. Root, on pmOS.
#
# The panel driver resets the TDDI die on every display prepare, the touch
# firmware reloads its defaults, and idle mode comes back (measured 2026-09-11:
# 0x17 -> 0x3f across one screensaver cycle). The real fix is a drm panel
# follower in the driver plus a `panel` phandle in the DT, which needs a reboot.
# Until then this re-applies idle-off + charger-mode from userspace 300 ms after
# every dpms Off->On edge, so a tapping session tonight measures the intended
# configuration. Logs every action so the effect can be attributed.
LOG=/var/log/fp3/hx-idle-keeper.log
prev=$(cat /sys/class/drm/card0-DSI-1/dpms)
echo "$(date '+%F %T') keeper start, dpms=$prev" >> $LOG
while :; do
    cur=$(cat /sys/class/drm/card0-DSI-1/dpms)
    if [ "$cur" = On ] && [ "$prev" != On ]; then
        sleep 0.3
        out=$(python3 /tmp/hx-idletest.py 2>&1 | grep -E "^E2" | sed 's/ -> read.*//'; /usr/local/bin/hx-charger-mode.py on 2>&1 | tail -1)
        echo "$(date '+%F %T') display woke: $out" | tr '\n' ' ' >> $LOG; echo >> $LOG
    fi
    prev=$cur; sleep 1
done
