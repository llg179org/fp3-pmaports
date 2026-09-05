#!/bin/sh
# The CID from one qmicli run is only reusable by the next if both go through
# qmi-proxy (-p). Without it each invocation opens its own connection and the
# second run reports "Unknown client N for service imsa" - which looks like the
# modem rejecting the query and is actually the client living in a process that
# has already exited.
D=qrtr://0
echo "=== bind (through the proxy), keeping the client ==="
out=$(timeout 25 qmicli -p -d $D --imsa-bind=0 --client-no-release-cid 2>&1)
echo "$out"
cid=$(echo "$out" | sed -n "s/.*CID: *'\([0-9]\+\)'.*/\1/p" | head -1)
echo "-- cid=$cid"
if [ -n "$cid" ]; then
	for q in --imsa-get-ims-registration-status --imsa-get-ims-services-status; do
		echo "---- $q ----"
		timeout 25 qmicli -p -d $D --client-cid="$cid" --client-no-release-cid "$q" 2>&1
		echo "     rc=$?"
	done
	timeout 25 qmicli -p -d $D --client-cid="$cid" --imsa-noop >/dev/null 2>&1
fi
echo "=== the IMS settings service, same pattern ==="
out=$(timeout 25 qmicli -p -d $D --ims-bind=0 --client-no-release-cid 2>&1)
echo "$out"
cid2=$(echo "$out" | sed -n "s/.*CID: *'\([0-9]\+\)'.*/\1/p" | head -1)
if [ -n "$cid2" ]; then
	echo "---- --ims-get-ims-services-enabled-setting ----"
	timeout 25 qmicli -p -d $D --client-cid="$cid2" --client-no-release-cid --ims-get-ims-services-enabled-setting 2>&1
	echo "     rc=$?"
	timeout 25 qmicli -p -d $D --client-cid="$cid2" --ims-noop >/dev/null 2>&1
fi
