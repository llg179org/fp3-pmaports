#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# THE CONFOUND NOBODY HAS EVER RECORDED: which cell, how good the signal, which
# radio technology.
#
# Every power and residency capture on this device - on BOTH systems, across
# every comparison made so far - was taken without any of that written down. A
# modem in poor coverage transmits harder and stays awake more, and the oracle
# and pmOS numbers that get laid against each other were taken on different days.
# So an unknown part of every cross-system difference is the network, and there
# is no way to go back and check, because the field was never captured.
#
# ☠️ It is also the leading alternative explanation for the 2026-08-30 regime
# change (52-63 s sleeps in the morning, filled 600 s windows at midday, same
# configuration). The hypothesis on the page is a radio cycle; "the cell got
# quieter" splits the day exactly the same way and cannot be distinguished
# without this. Run it at the top and tail of every window from now on.
#
# Read-only throughout: every command here is a `get`. Nothing is set, and the
# modem is not disabled, restarted or reconfigured.
#
#   radio-context.sh [label]
set -u
L=${1:-}
D=qrtr://0     # ☠️ no -p: with the proxy flag libqmi builds a QMUX endpoint even
               # for a qrtr:// device (qmi-device.c:2565) and the open fails
echo "# radio-context $(date '+%F %T') ${L:+[$L]}"

echo "-- ModemManager's view"
mmcli -m any 2>/dev/null | sed -n '/Status/,/Modes/p' | sed 's/^/   /' | head -20

echo "-- serving system (registration, RAT, PLMN)"
qmicli -d "$D" --nas-get-serving-system 2>&1 | sed 's/^/   /' | head -25

echo "-- signal info (the confound itself)"
qmicli -d "$D" --nas-get-signal-info 2>&1 | sed 's/^/   /' | head -25

echo "-- serving cell (which cell, so two windows can be compared at all)"
qmicli -d "$D" --nas-get-cell-location-info 2>&1 | sed 's/^/   /' | head -40

echo "-- RF band"
qmicli -d "$D" --nas-get-rf-band-info 2>&1 | sed 's/^/   /' | head -15

# ☠️ Say when a probe returned nothing. An absent section next to present ones
# reads as "nothing to report", and on this device that has been believed before.
echo "# end $(date '+%F %T') - a section that printed only an error is NOT a zero"
