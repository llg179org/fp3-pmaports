#!/bin/sh
# Snapshot everything this qmicli can say about IMS / voice / registration.
# Deployed as a file, not an ssh argument string. No `set -e`: every probe here
# is allowed to fail, and a failure is itself part of the record.
echo "=== $(date -Is)  kernel $(uname -r) $(uname -v) ==="
for v in \
	--nas-get-system-info \
	--nas-get-serving-system \
	--imsa-get-ims-registration-status \
	--imsa-get-ims-services-status \
	--ims-get-ims-services-enabled-setting \
	--imsp-get-enabler-state \
	--voice-get-config
do
	echo "----- qmicli $v -----"
	timeout 25 qmicli -d qrtr://0 "$v" 2>&1
	echo "   rc=$?"
done
echo "----- active PDC config -----"
timeout 25 qmicli -d qrtr://0 --pdc-list-configs=software 2>&1 | grep -B4 "Status:      Active"
echo "----- ModemManager -----"
mmcli -m any 2>&1 | grep -iE "state|access tech|operator|registration|3gpp" | head -20
