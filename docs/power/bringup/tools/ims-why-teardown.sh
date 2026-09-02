#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# WHY DOES THE MODEM TEAR THE PDN DOWN 30 ms AFTER IT WAS ACCEPTED?
#
# The loop is measured from the outside: every 8.3-8.7 s the modem sends a
# PDN CONNECTIVITY REQUEST on APN `ims`, is granted a bearer, and drops it 30 ms
# after the accept, with NO ESM cause. Every cycle needs an RRC connection, which
# is what keeps the UE out of idle and costs ~50 mA at system level. What is not
# known is the modem's own reason - the ESM trace shows the request and the
# teardown and nothing in between.
#
# So ask the IMS state machine in its own words: log families 0x14 and 0x15 carry
# the SIP messages and the IMS state transitions.
#
# ☠️ THE LOOP ONLY EXISTS WITH IMS ON, so this window has to switch it back on -
# and it must therefore also STOP THE RECONCILER FIRST. fp3-ims-reconcile runs
# every five minutes and would put the vector back within one cycle, leaving a
# capture of a state machine that is not running. That is not a hypothetical: the
# reconciler was watched doing exactly this, correctly, to a check demonstration
# earlier the same day.
#
# ☠️ AND THE RESTORE IS A TRAP, NOT A LAST LINE. If this script dies halfway, the
# phone must not be left in the expensive configuration - so the restore runs from
# an EXIT trap, and it restarts the reconciler even if the direct write fails.
#
# ☠️ The DIAG log mask is MODEM-SIDE STATE that outlives this process: an earlier
# window was ruined by a mask left behind by a previous capture. The teardown in
# diag-log-capture.py zeroes it; do not skip the clean exit.
set -u
SECS=${1:-1800}
O=/var/log/fp3/ims-why-$(date +%s)
mkdir -p "$O"
s() { echo "$*" | tee -a "$O/log.txt"; }

restore() {
	s "# --- restore $(date '+%F %T') ---"
	python3 /usr/local/bin/ims-toggle.py off 2>&1 | sed 's/^/#   /' | tee -a "$O/log.txt"
	python3 /usr/local/bin/ims-toggle.py read 2>&1 | sed 's/^/#   /' | tee -a "$O/log.txt"
	systemctl start fp3-ims-reconcile.timer 2>/dev/null
	s "#   reconciler timer: $(systemctl is-active fp3-ims-reconcile.timer)"
}
trap restore EXIT INT TERM

s "# ims-why-teardown $(date '+%F %T')  ${SECS}s"
s "# battery: $(cat /sys/class/power_supply/*battery*/capacity)% $(cat /sys/class/power_supply/pmi632-charger/status)"

s "# --- stop the reconciler, or it undoes the intervention mid-capture ---"
systemctl stop fp3-ims-reconcile.timer
s "#   timer now: $(systemctl is-active fp3-ims-reconcile.timer)"

s "# --- IMS on (the loop only exists in this state) ---"
python3 /usr/local/bin/ims-toggle.py on 2>&1 | sed 's/^/#   /' | tee -a "$O/log.txt"
sleep 20
s "#   read back: $(python3 /usr/local/bin/ims-toggle.py read 2>&1 | tr '\n' ' ')"
s "#   band/cell: $(qmicli -d qrtr://0 --nas-get-rf-band-info 2>/dev/null | sed -n "s/.*Active Band Class: *'\([^']*\)'.*/\1/p" | head -1) / $(qmicli -d qrtr://0 --nas-get-cell-location-info 2>/dev/null | sed -n "s/.*Global Cell ID: *'\([^']*\)'.*/\1/p" | head -1)"

# 0x14, 0x15 = IMS / QIPCALL. 0x0B is the LTE family that already gave us the
# request and the teardown - kept so the SIP side can be aligned in time with the
# ESM messages instead of guessing which cycle a line belongs to.
s "# --- capture ${SECS}s: equips 0x14,0x15,0x0B ---"
python3 /usr/local/bin/diag-log-capture.py "$SECS" "$O/diag" "0x14,0x15,0x0B" \
	>>"$O/log.txt" 2>&1
s "# --- capture done $(date '+%F %T'); $(ls -l $O/diag* 2>/dev/null | wc -l) file(s) ---"
