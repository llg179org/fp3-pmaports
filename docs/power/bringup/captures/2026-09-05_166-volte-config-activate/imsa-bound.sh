#!/bin/sh
# Ask IMSA/IMS for registration status the way libqmi wants it: BIND first,
# keep the client, then query on the same CID. Without the bind these return
# QMI error 70 InvalidOperation, which is easy to misread as "the modem has no
# IMS" when it only means "this client never said which subscription it wants".
# Read-only throughout.
D=qrtr://0
for b in 0 1; do
	echo "########## binding=$b ##########"
	out=$(timeout 25 qmicli -d $D --imsa-bind=$b --client-no-release-cid 2>&1)
	echo "$out"
	cid=$(echo "$out" | sed -n 's/.*CID: *.\([0-9]\+\).*/\1/p' | head -1)
	[ -n "$cid" ] || cid=$(echo "$out" | grep -oE '[0-9]+' | tail -1)
	echo "-- cid=$cid"
	[ -n "$cid" ] || { echo "-- no CID, skipping queries"; continue; }
	for q in --imsa-get-ims-registration-status --imsa-get-ims-services-status; do
		echo "---- $q ----"
		timeout 25 qmicli -d $D --client-cid="$cid" --client-no-release-cid "$q" 2>&1
		echo "     rc=$?"
	done
	# release the client
	timeout 25 qmicli -d $D --client-cid="$cid" --imsa-noop >/dev/null 2>&1
	echo "-- client released"
done
