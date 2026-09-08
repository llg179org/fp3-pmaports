#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# ims-duty-leg.sh [seconds]   (default 600)   -- run as root on pmOS
#
# Measure the modem's MPSS XO duty with its own IMS service switches ON, and
# put them back afterwards. This is the ONLY instrument that can speak about
# the "IMS PDN every 8.4 s" loop.
#
# ☠️ WHY NOT THE MODEMMANAGER JOURNAL. Measured 2026-09-08: MM's QMI debug dump
# carries service = nas / voice / wds / dsd / wms and NOT ONE ims message - MM
# never binds an IMS client, so the modem's IMS traffic cannot appear there
# however verbose the log level is. A 4-minute "no loop seen" read out of that
# journal measured nothing at all. The loop was originally found in the duty:
# 44.5 -> 4.8, 45.6 -> asleep, 48.0 -> 4.4 (three pairs, fp3-ims-reconcile.py).
#
# ☠️ THE STATE IS HELD BY SOMETHING. fp3-ims-reconcile.timer re-asserts "IMS off"
# every 5 minutes, which is shorter than this window - so the timer is stopped
# for the duration or the window measures the reconciler, not the modem.
#
# ☠️ DEAD-MAN FIRST. The restore is armed BEFORE the change, so a dropped ssh
# session, a crash or a reboot-less hang still leaves the phone in the cheap
# configuration rather than burning ~44 pp of modem duty overnight.
#
# ☠️ CONDITIONS TRAVEL WITH THE NUMBER. The duty is 34.8 % on LTE and 6.5 % on
# 2G for the same phone, so a window that overlaps a CSFB call is worthless.
# Do not run this while a call is expected. modem-window.sh records the access
# technology, signal and power state into the capture for exactly this reason.
set -u
SECS=${1:-600}
OUT=/tmp/duty-ims-on.txt
GRACE=300

restore() {
	/usr/local/bin/fp3-ims-reconcile.py off
	systemctl start fp3-ims-reconcile.timer
}

# 1. dead-man BEFORE the change
systemctl stop fp3-ims-deadman.timer 2>/dev/null
systemd-run --on-active=$((SECS + GRACE)) --unit=fp3-ims-deadman --collect \
	sh -c '/usr/local/bin/fp3-ims-reconcile.py off; systemctl start fp3-ims-reconcile.timer' \
	|| { echo "could not arm the dead-man - refusing to change anything" >&2; exit 1; }

# 2. stop what is holding the state
systemctl stop fp3-ims-reconcile.timer

# 3. change it, and let the reconciler's own read-back be the verdict
if ! /usr/local/bin/fp3-ims-reconcile.py on; then
	echo "IMS switches did not come on - restoring, nothing measured" >&2
	restore; systemctl stop fp3-ims-deadman.timer 2>/dev/null
	exit 1
fi

# 4. the window
/usr/local/bin/modem-window.sh "$SECS" > "$OUT" 2>/dev/null

# 5. restore, then disarm the dead-man we no longer need
restore
systemctl stop fp3-ims-deadman.timer 2>/dev/null
echo "ims-duty-leg: done, capture in $OUT"
