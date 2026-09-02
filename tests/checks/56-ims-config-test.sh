#!/bin/sh
# Category: power
# Description: the modem's IMS service switches are off, so the 8.4 s IMS-PDN loop cannot run
#
# THE CONFIGURATION HALF of the IMS lever. Deterministic and network-independent:
# it reads the vector back through QMI and compares it with what we asked for.
#
# ☠️ WHAT IT PROVES AND WHAT IT DOES NOT. This is what the modem SAYS, which is
# exactly the layer that can be right while the behaviour is wrong. Its partner
# is 57-ims-duty-test.sh, which measures what the modem DOES and whose medium is
# the network. Neither replaces the other; a green pair is the claim.
#
# ☠️ WHY A CHECK AT ALL, when the setting was applied once by hand: because it
# does NOT survive a reboot. Measured 2026-09-02 - after a reboot, before any
# write, the original vector was back. fp3-ims-reconcile.timer re-asserts it, and
# this check is what notices when the reconciler is missing, masked or losing.
#
# ☠️ THE SETTERS AND THE GETTERS DO NOT CORRESPOND on this firmware - measured
# twice, on different switches - so the vector is read switch by switch and a
# single master flag is never trusted.

TOOL=/usr/local/bin/ims-toggle.py
if [ ! -x "$TOOL" ]; then
	echo "SKIP: $TOOL not installed - the bound-QMI IMS reader is part of the power work"
	exit 0
fi
if ! mmcli -m any >/dev/null 2>&1; then
	echo "SKIP: no modem present, nothing to read"
	exit 0
fi

out=$(python3 "$TOOL" read 2>&1)
if ! echo "$out" | grep -q "voice"; then
	echo "FAIL: could not read the IMS vector (the modem or the qrtr bus is not ready?)"
	echo "      cmd: python3 $TOOL read"
	echo "$out" | sed 's/^/      /'
	exit 1
fi

fail=0
on=$(echo "$out" | awk '/^ *(voice|video telephony|SMS|UT) /{if ($NF == "True") printf "%s ", $1}')
if [ -n "$on" ]; then
	echo "FAIL: IMS services still enabled: $on"
	echo "      the modem raises and drops an IMS PDN every 8.4 s in this state,"
	echo "      which holds the UE in RRC_CONNECTED and costs ~44 pp of modem duty"
	echo "      fix: systemctl start fp3-ims-reconcile   (and check its timer is enabled)"
	fail=1
else
	echo "PASS: every readable IMS service switch is off"
fi

# The reconciler is the reason the above stays true across reboots, so its
# absence is a finding even while the vector happens to be right.
if systemctl is-enabled fp3-ims-reconcile.timer >/dev/null 2>&1; then
	echo "PASS: fp3-ims-reconcile.timer is enabled (the setting is re-asserted, not just set)"
else
	echo "FAIL: fp3-ims-reconcile.timer is NOT enabled - the vector will revert at the next reboot"
	echo "      cmd: systemctl enable --now fp3-ims-reconcile.timer"
	fail=1
fi

exit $fail
