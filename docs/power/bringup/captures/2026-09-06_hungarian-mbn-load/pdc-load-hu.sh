#!/bin/sh
# Load + activate the Vodafone Hungary MBN pulled off the UT slot.
# Runs on the device, unattended: qmicli PDC calls take minutes.
OUT=/var/log/fp3-pdc-hu.log
exec >"$OUT" 2>&1
set -x
date -Is
md5sum /tmp/hu.mbn

echo "=== BEFORE: active config ==="
sudo -n qmicli -d qrtr://0 --pdc-list-configs=software

echo "=== LOAD ==="
sudo -n qmicli -d qrtr://0 --pdc-load-config=/tmp/hu.mbn

echo "=== AFTER LOAD: config list ==="
sudo -n qmicli -d qrtr://0 --pdc-list-configs=software

date -Is
echo "=== SCRIPT DONE ==="
