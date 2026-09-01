#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# CAPTURE THE MODEM'S OWN STORY - every read, one command, one file.
#
#   modem-story.sh [outfile]        (RUNS ON THE DEVICE, needs root for nothing
#                                    but qmicli; run it as the normal user)
#
# WHY THIS EXISTS
# ===============
# The search for a MISSING AP-SIDE SIGNAL is over. The argument that closed it is
# not the QMI census but the over-the-air one: **the modem transmits, regularly,
# with zero user data**. No unset flag, unserved lookup or missing handshake makes
# a modem key its transmitter - those retry locally and cheaply. Radio
# transmission means network-facing procedures; the network is exonerated (the
# oracle is cheap on the same cells with the same SIM); so what is left is
# modem-internal clients acting on modem-internal configuration.
#
# That does NOT mean the AP cannot reach it. It means the levers are READS and
# CONFIG WRITES, not runtime signalling. This script is the read half.
#
# ☠️ EVERY LINE HERE IS AN INTERACTION WITH THE MODEM. Never run it inside an
# undisturbed window - it belongs after a measurement closes, or before one opens.
#
# ☠️ AND IT IS NOT A DUTY MEASUREMENT. It records configuration. Do not read a
# duty number out of it and do not run it expecting one.
set -u

OUT=${1:-/tmp/modem-story-$(date +%s).txt}
D="qmicli -d qrtr://0"
run() {
	printf '\n===== %s\n' "$*"
	timeout 25 $D "$@" 2>&1 | sed 's/^/  /'
}

{
	echo "# modem-story $(date -Iseconds)"
	echo "# kernel: $(uname -r) $(uname -v)"
	echo "# uptime: $(cut -d. -f1 /proc/uptime) s"
	echo "# ModemManager: $(systemctl is-active ModemManager 2>/dev/null)"

	# --- where the UE is, so every line below has a context
	run --nas-get-serving-system
	run --nas-get-system-selection-preference
	run --nas-get-rf-band-info
	run --nas-get-signal-info

	# --- the attach configuration. The PDN list is the piece this project has
	#     NEVER read; the PDC active config it HAS (2026-09-01 17:30,
	#     ROW_Commercial), and it is repeated here only so one file holds the
	#     whole picture.
	run --wds-get-lte-attach-pdn-list
	run --wds-get-lte-attach-parameters
	run --wds-get-max-lte-attach-pdn-num
	run --wds-get-profile-list=3gpp
	run --wds-get-default-profile-number=3gpp
	run --wds-get-autoconnect-settings
	run --wds-get-packet-service-status
	run --pdc-list-configs=software
	run --pdc-list-configs=platform

	# --- the SIM side
	run --uim-get-card-status

	echo
	echo "===== IMS (bound read; qmicli cannot bind over qrtr - see ims-state.py)"
	if [ -x /usr/local/bin/ims-state.py ]; then
		timeout 60 python3 /usr/local/bin/ims-state.py 2>&1 | sed 's/^/  /'
	elif [ -x /tmp/ims-state.py ]; then
		timeout 60 python3 /tmp/ims-state.py 2>&1 | sed 's/^/  /'
	else
		echo "  ims-state.py not installed - the IMS branch of the plan is unread"
	fi

	echo
	echo "# done $(date -Iseconds)"
} > "$OUT" 2>&1

cat "$OUT"
echo "$OUT" >&2
