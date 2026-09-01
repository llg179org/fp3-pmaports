#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# THE RAT-LIST LADDER: does narrowing what the UE is allowed to camp on shorten
# the modem's wake?
#
#   mode-ladder.sh WINDOW_S MODE [MODE...]   e.g. mode-ladder.sh 600 lte lte,umts,gsm
#
# WHY. Measured 2026-09-01 across a slot switch: both stacks wake the modem at
# the SAME rate (3.14/s oracle, 2.38/s ours) and our wakes are SEVEN TIMES
# LONGER - 157 ms against 22 ms. Nothing the AP polls runs at 2.4 Hz, so the
# extra time is work the modem does per paging occasion. The obvious candidate
# is inter-RAT measurement, and our system-selection preference names every RAT
# the chip has: 'cdma-1x, cdma-1xevdo, gsm, umts, lte, td-scdma', acquisition
# order 'lte, umts, gsm, cdma-1x, cdma-1xevdo'. That list is AP-side runtime
# state - the daemon writes it - which is exactly the kind of difference a slot
# switch CAN produce, unlike anything in the modem's own NV.
#
# ☠️ AN LTE-ONLY LEG CAN COST INCOMING CALLS. With no GSM/UMTS to fall back to,
# a network that uses CSFB for voice cannot deliver a call while this is set, and
# this phone has no IMS. That is acceptable for a measurement window and NOT
# acceptable as a shipped default; the restore below is unconditional.
#
# ☠️ THE LAST LEG REPEATS THE FIRST MODE, for the same reason the band ladder
# does: without it a ladder cannot tell the knob from drift.
set -u
W=${1:?window seconds}; shift
[ $# -ge 1 ] || { echo "usage: mode-ladder.sh WINDOW_S MODE [MODE...]" >&2; exit 2; }
MODES="$*"; FIRST=$1
O=/var/log/fp3/mode-ladder-$(date +%s)
mkdir -p "$O"; L=$O/log.txt
s(){ echo "$*" | tee -a "$L"; }
D=qrtr://0

orig=$(qmicli -d $D --nas-get-system-selection-preference 2>/dev/null | sed -n "s/.*Mode preference: *'\([^']*\)'.*/\1/p" | head -1)
s "# mode-ladder $(date '+%F %T') window=${W}s modes: $MODES (then $FIRST again)"
s "# kernel=$(uname -v)"
s "# original mode preference: $orig"

witness(){
	rf=$(qmicli -d $D --nas-get-rf-band-info 2>/dev/null)
	sp=$(qmicli -d $D --nas-get-system-selection-preference 2>/dev/null)
	cl=$(qmicli -d $D --nas-get-cell-location-info 2>/dev/null)
	printf '#   %s state=%s mode=%s band=%s chan=%s cell=%s rsrp=%s\n' "$1" \
		"$(mmcli -m any 2>/dev/null | sed -n 's/.*  state: *//p' | head -1)" \
		"$(echo "$sp" | sed -n "s/.*Mode preference: *'\([^']*\)'.*/\1/p" | head -1)" \
		"$(echo "$rf" | sed -n "s/.*Active Band Class: *'\([^']*\)'.*/\1/p" | head -1)" \
		"$(echo "$rf" | sed -n "s/.*Active Channel: *'\([^']*\)'.*/\1/p" | head -1)" \
		"$(echo "$cl" | sed -n "s/.*Global Cell ID: *'\([^']*\)'.*/\1/p" | head -1)" \
		"$(echo "$cl" | sed -n "s/.*RSRP: *'\([-0-9.]*\).*/\1/p" | head -1)" \
		| tee -a "$L"
}

wait_reg(){
	i=0; while [ $i -lt 30 ]; do
		case "$(mmcli -m any 2>/dev/null | sed -n 's/.*  state: *//p' | head -1)" in
			registered|connected) return 0 ;;
		esac
		sleep 5; i=$((i + 1))
	done
	return 1
}

leg(){ # leg NAME MODE
	s "# --- leg $1: requesting mode preference '$2'"
	qmicli -d $D --nas-set-system-selection-preference="$2" >/dev/null 2>&1 \
		|| { s "#   ☠️ set mode-preference=$2 FAILED - leg $1 is NOT a measurement of $2"; return 1; }
	wait_reg || s "#   ☠️ did not register within 150 s"
	sleep 20
	witness "$1 before"
	# ☠️ MID-LEG COVARIATES. Endpoint witnesses missed a band that moved INSIDE a
	# leg, and a leg whose band moved is not a measurement of anything it claims.
	# The sampler perturbs the modem it watches, so it runs at the SAME interval
	# in every leg - identical perturbation cancels in a comparison, a
	# perturbation present in one arm only does not.
	/usr/local/bin/leg-covariates.sh --watch 60 "$W" "$1 mid" >> "$L" 2>&1 &
	COV=$!
	# ☠️ leg names carry '|' (a mode list is spelled gsm|umts|lte); unsanitised
	# that is a pipe in a filename, and the redirect writes somewhere nobody
	# looks for it.
	safe=$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_')
	/usr/local/bin/xo-series.sh "$W" MPSS > "${L%.txt}-xo-$safe.txt" 2>&1 &
	XOS=$!
	/usr/local/bin/burst-master.sh "$W" >/dev/null 2>&1
	kill $COV $XOS 2>/dev/null
	wait $COV $XOS 2>/dev/null
	d=$(ls -dt /var/log/fp3/burst-master-* | head -1)
	mv "$d/master.txt" "$O/$1.txt"; rm -rf "$d"
	witness "$1 after"
	awk -v leg="$1" '
		/^# t_s/ { for (i = 1; i <= NF; i++) h[$i] = i - 1; next }
		/^#/ { next }
		{ n++; if ($h["MPSS_cores"] != "0x0") up++; e += $h["smd_irq_total_per_s"];
		  c += $h["cur_mA"] }
		END { if (n) printf "RESULT %s mpss_up=%.1f%% edge_per_s=%.1f cur_mA=%.0f n=%d\n",
			leg, 100 * up / n, e / n, c / n, n }
	' "$O/$1.txt" | tee -a "$L"
}

i=1
for m in $MODES; do leg "L$i-$m" "$m"; i=$((i + 1)); done
leg "L$i-$FIRST-repeat" "$FIRST"

# ☠️ Restore unconditionally and shout if it fails: an LTE-only phone cannot be
# reached by a CSFB call, which is the one thing this whole investigation is
# supposed to preserve.
#
# ☠️ AND TRANSLATE THE LIST BEFORE WRITING IT BACK. qmicli PRINTS the preference
# comma-and-space separated ("gsm, umts, lte") and ACCEPTS it pipe separated
# ("gsm|umts|lte"). Writing back what it printed fails every time - the identical
# trap band-ab.sh documents for the band list, and it fails silently into
# "restore FAILED" if nobody translates.
RESTORE=$(echo "$orig" | sed 's/, */|/g')
s "# restoring mode preference: $RESTORE   (printed as: $orig)"
qmicli -d $D --nas-set-system-selection-preference="$RESTORE" >/dev/null 2>&1 \
	|| s "#   ☠️☠️ restore FAILED - the modem is still restricted; fix this by hand"
wait_reg || s "#   ☠️ not registered after restore"
witness "restored"
# ☠️ Prove the restore, do not assume it: compare what came back to what we saved.
back=$(qmicli -d $D --nas-get-system-selection-preference 2>/dev/null | sed -n "s/.*Mode preference: *'\([^']*\)'.*/\1/p" | head -1)
if [ "$back" = "$orig" ]; then
	s "# restore VERIFIED: mode preference is back to '$back'"
else
	s "#   ☠️☠️ RESTORE DID NOT TAKE: now '$back', was '$orig' - FIX BY HAND"
fi
s "# done $(date '+%F %T')"
s "$O"
