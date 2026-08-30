#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# HOST side: deploy tools/wake-qmi.sh to the phone and run the census.
#
# Answers two open questions in one window, because they need the same probe:
#   * WHICH QMI messages are the ~60 s noise - if they are ones ModemManager
#     subscribed to, the fix is userspace and no kernel patch is needed
#     (leads/selective-smd-wakeup.md, "the cheaper fork in the road");
#   * WHICH message and port an incoming SMS arrives on - the filter's wake list
#     currently has the call (Voice, port 39) measured and nothing else, so a
#     filter built today would swallow SMS exactly as the low-power arm swallowed
#     the call.
#
# ☠️ Deliberately NOT combined with a ModemManager debug-log run. Raising the log
#    level changes the system while it is being measured, and the debug log can
#    only ever confirm a failed unregister, never clear one (see
#    leads/modemmanager-suspend-modes.md). Keep the census clean; run the log
#    check separately if the census says the indications survived terse.
#
# ☠️ Do not poll the phone while this runs - a login is a wake, and the wake IS
#    the measurement. The host USB log (host-sleep-census.sh) is the free,
#    zero-disturbance second witness; use that to watch progress.
#
#   run-wake-qmi.sh [alarm_s] [rounds]        default 600 3
set -eu
S=${1:-600}; N=${2:-3}
D=$(dirname "$0")

echo "=== deploy $(date '+%T')"
for f in wake-qmi.sh qmi-msgids.txt; do
	fp3-ssh "cat > /tmp/$f" < "$D/$f"
done
fp3-ssh 'echo <pw> | sudo -S sh -c "install -m755 /tmp/wake-qmi.sh /usr/local/bin/wake-qmi.sh;
	install -m644 /tmp/qmi-msgids.txt /usr/local/bin/qmi-msgids.txt" 2>/dev/null'
fp3-ssh 'sh -n /usr/local/bin/wake-qmi.sh && echo "syntax ok on device"'

echo "=== state before the run (so a later reader can see what it described)"
fp3-ssh 'systemctl show ModemManager -p ExecStart --value | sed "s/.*argv\[\]=//; s/ ;.*//";
	 mmcli -m any 2>/dev/null | sed -n "s/.*state: *//p" | head -1'

# Two free NAS reads, taken while the phone is awake and before the census, so
# they cost nothing and cannot disturb it. They close (or fail to close) the
# eDRX question without guessing a message id:
#   * get-supported-messages returns the modem's own bitmask of NAS message ids.
#     If it contains nothing beyond what libqmi defines, this firmware has no
#     eDRX message to call and the avenue is closed by the modem, not by our
#     tooling. If it does, the extra ids are a measured list to identify - still
#     not a licence to guess which one is eDRX.
#   * get-drx reports the 2G/3G paging cycle. Recorded as data; it cannot be the
#     ~60 s wake (its whole range is 0.32-2.56 s) and it is not the eDRX lever
#     despite the name.
echo "=== NAS reads before the census"
fp3-ssh 'qmicli -p -d qrtr://0 --nas-get-supported-messages 2>&1 | head -40' || true
fp3-ssh 'qmicli -p -d qrtr://0 --nas-get-drx 2>&1 | head -10' || true

echo "=== census starts $(date '+%T'); ${N} rounds of ${S}s"
echo "    >>> SEND THE SMS during round 2, i.e. roughly $(date -d "+$((S + 40)) seconds" '+%H:%M') <<<"
fp3-ssh "echo <pw> | sudo -S systemd-run --unit=wakeqmi --collect \
	/usr/local/bin/wake-qmi.sh $S $N logind 2>/dev/null"
