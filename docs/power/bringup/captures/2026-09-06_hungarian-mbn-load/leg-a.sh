#!/bin/sh
# Leg A of the carrier-config control: the same bearer test, with ROW_Commercial
# active. ☠️ EVERY mmcli/qmicli call is wrapped in `timeout`: the previous run
# of this test hung for 40 minutes on an unbounded qmicli and then again on an
# unbounded mmcli, and an unattended script must not be able to do that.
set -u
LOG=/var/log/fp3-leg-a.log
: > "$LOG"
say() { echo "$*" >> "$LOG"; }

say "active config: $(timeout 90 qmicli -d qrtr://0 --pdc-list-configs=software 2>/dev/null | grep -B3 'Status:      Active' | sed -n 's/.*Description: *//p')"
say "modem: $(timeout 30 mmcli -m any 2>/dev/null | sed -n 's/.*access tech: *//p' | head -1)"
for apn in internet.vodafone.net ims; do
    for b in $(timeout 30 mmcli -m any -K 2>/dev/null | sed -n 's/^modem\.generic\.bearers\.value\[[0-9]*\] *: *//p'); do
        timeout 30 mmcli -m any --delete-bearer="$b" >/dev/null 2>&1
    done
    B=$(timeout 30 mmcli -m any --create-bearer="apn=$apn,ip-type=ipv4" 2>&1 |
        sed -n 's,.*\(/org/freedesktop/ModemManager1/Bearer/[0-9]*\).*,\1,p')
    R=$(timeout 60 mmcli -b "$B" --connect 2>&1 | tail -1 | sed 's/^error: .*bearer: //')
    C=$(timeout 30 mmcli -b "$B" -K 2>/dev/null | sed -n 's/^bearer\.status\.connected *: *//p')
    say "A  APN=$apn connected=${C:-?}  $R"
    timeout 30 mmcli -m any --delete-bearer="$B" >/dev/null 2>&1
done
say "=== DONE ==="
