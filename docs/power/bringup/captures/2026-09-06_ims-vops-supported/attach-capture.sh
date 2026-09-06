#!/bin/sh
# ☠️ -m any, NOT -m 0. Three attempts failed because the scripts hardcoded index
# 0 while the modem had renumbered to Modem/1 after a reinitialisation - every
# mmcli call returned rc=1 and the window held only paging. The index is an
# allocation, exactly like the i2c bus number and the input node on this device.
set -u
OUT=/var/lib/attach-capture
mkdir -p "$OUT"; rm -f "$OUT"/*.bin "$OUT"/capture.log
trap 'mmcli -m any --set-power-state-on >/dev/null 2>&1; mmcli -m any --enable >/dev/null 2>&1; echo "trap: modem restored"' INT TERM EXIT
echo "start $(date +%H:%M:%S)"
python3 /tmp/diag-log-capture.py 150 "$OUT" > "$OUT/capture.log" 2>&1 &
CAP=$!
sleep 12
echo "RF off $(date +%H:%M:%S)"
mmcli -m any --disable >/dev/null 2>&1 && echo "  disabled ok"
mmcli -m any --set-power-state-low >/dev/null 2>&1 && echo "  low ok"
sleep 15
echo "RF on  $(date +%H:%M:%S)"
mmcli -m any --set-power-state-on >/dev/null 2>&1 && echo "  on ok"
mmcli -m any --enable >/dev/null 2>&1 && echo "  enabled ok"
sleep 60
echo "state: $(mmcli -m any -K 2>/dev/null | sed -n 's/^modem.generic.state *: *//p')"
wait $CAP
echo "vege $(date +%H:%M:%S)"
