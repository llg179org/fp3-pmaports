#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# ims-modem-leg.sh [seconds] [label]   (default 420, "modem")  -- root, on pmOS
#
# Switch the modem's own IMS stack ON and sample its REGISTRATION STATE for the
# window, so a call placed during it can be aligned against what the modem's IMS
# client was doing at that second. Restores the shipped configuration afterwards.
#
# ☠️ WHY NOT ims-why-teardown.sh. That script asks the same question through the
# DIAG log families (0x14 IMS / 0x15 QIPCALL), which is the right channel and the
# richer answer - and on 2026-09-08 it returned `diag 0 bytes` for a 600 s window:
# the mask was accepted by the transport and no stream followed. Its own output
# says so and says not to read it as "the modem is quiet". Until that wall is
# understood, the QMI IMSA reading below is what is actually available.
#
# ☠️ WHAT THIS CANNOT SEE. IMSA reports a state, not a conversation: registered
# or not, over which technology, with which error code. It does NOT carry the SIP
# exchange, so it can say "the modem never registered" and cannot say what the
# network answered. Do not let a clean sample here be written up as "the modem
# made no attempt" - that is a different claim, and this instrument cannot make it.
#
# ☠️ fp3-ims-reconcile.timer re-asserts "IMS off" every 5 minutes, which is
# shorter than this window: stop it, or the window measures the reconciler.
# The restore is armed BEFORE the change and runs from an EXIT trap as well, so a
# dropped session cannot leave the modem's IMS on unattended.
set -u
SECS=${1:-420}
LABEL=${2:-modem}
EVERY=15
GRACE=180
O=/var/log/fp3/ims-leg-$LABEL-$(date +%s).log

s() { echo "$*" >> "$O"; }

restore() {
	s "# --- restore $(date '+%F %T') ---"
	/usr/local/bin/fp3-ims-reconcile.py off 2>&1 | sed 's/^/#   /' >> "$O"
	systemctl start fp3-ims-reconcile.timer 2>/dev/null
	s "#   reconciler timer: $(systemctl is-active fp3-ims-reconcile.timer)"
	systemctl stop fp3-ims-deadman.timer 2>/dev/null
}
trap restore EXIT INT TERM

: > "$O"
s "# ims-modem-leg $(date '+%F %T')  ${SECS}s  label=$LABEL  sample every ${EVERY}s"

# dead-man BEFORE the change: a crash or a reboot-less hang must not leave IMS on
systemctl stop fp3-ims-deadman.timer 2>/dev/null
systemd-run --on-active=$((SECS + GRACE)) --unit=fp3-ims-deadman --collect \
	sh -c '/usr/local/bin/fp3-ims-reconcile.py off; systemctl start fp3-ims-reconcile.timer' \
	>/dev/null 2>&1 || { s "# could not arm the dead-man - nothing changed"; exit 1; }

s "# --- stop the reconciler ---"
systemctl stop fp3-ims-reconcile.timer
s "#   timer now: $(systemctl is-active fp3-ims-reconcile.timer)"

s "# --- IMS ON ---"
if ! /usr/local/bin/fp3-ims-reconcile.py on 2>&1 | sed 's/^/#   /' >> "$O"; then
	s "# IMS did not come on - nothing measured"; exit 1
fi

s "# --- sampling ---"
t=0
while [ "$t" -lt "$SECS" ]; do
	s "== $(date '+%F %T') t=${t}s  tech=$(mmcli -m 0 2>/dev/null | sed -n 's/.*access tech: *//p' | head -1)"
	/usr/local/bin/ims-state.py 2>&1 | sed 's/^/   /' >> "$O"
	t=$((t + EVERY)); sleep "$EVERY"
done
s "# --- window done $(date '+%F %T') ---"
