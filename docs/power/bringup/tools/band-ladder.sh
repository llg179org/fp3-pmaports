#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# THE BAND LADDER: the same window on every LTE band the UE will accept, inside
# one boot, ending where it started.
#
#   band-ladder.sh WINDOW_S BAND [BAND...]     e.g. band-ladder.sh 600 eutran-1 eutran-3 eutran-20
#
# This is `band-ab.sh` widened from two bands to a list, and it exists because
# the two-band form left the one band that matters unmeasured. It reuses that
# tool's leg body unchanged, including the restore rule below.
#
# WHY, measured 2026-09-01 16:07: the phone was found camped on eutran-1
# (2100 MHz, EARFCN 500, RSRP -94.0 dBm) while an eutran-20 (800 DD) neighbour
# sat 7 dB stronger at -87.2 dBm - and this repo's own band A/B prices eutran-1
# at 50.0 % MPSS duty against eutran-3's 36.4 %. The band is assigned by the
# network, so it survives every device-side arm that has been tried, and it was
# recorded in NONE of the 67 census windows that produced the "nothing moves the
# duty" conclusion. eutran-20 has never been measured at all.
#
# ☠️ THE LAST LEG REPEATS THE FIRST BAND. Without it a ladder cannot tell a band
# effect from the phone drifting between the first leg and the last, and drift
# is exactly what this investigation has been fooled by before.
#
# ☠️ RESTORE WITH `any`, NOT WITH THE CAPTURED LIST. What mmcli PRINTS as the
# current bands is a shorthand ("gsm-umts, lte") that mmcli will not accept back
# as an argument, so writing it back fails every time - measured twice. Leaving
# the modem pinned to one band after a run is a real way to lose coverage on a
# phone that has to be able to receive a call, so the restore is unconditional
# and its failure is shouted.
set -u
W=${1:?window seconds}; shift
[ $# -ge 1 ] || { echo "usage: band-ladder.sh WINDOW_S BAND [BAND...]" >&2; exit 2; }
BANDS="$*"
FIRST=$1
O=/var/log/fp3/band-ladder-$(date +%s)
mkdir -p "$O"; L=$O/log.txt
s(){ echo "$*" | tee -a "$L"; }

s "# band-ladder $(date '+%F %T') window=${W}s bands: $BANDS (then $FIRST again)"
s "# kernel=$(uname -v)"

witness(){
	rf=$(qmicli -d qrtr://0 --nas-get-rf-band-info 2>/dev/null)
	cl=$(qmicli -d qrtr://0 --nas-get-cell-location-info 2>/dev/null)
	printf '#   %s state=%s band=%s chan=%s cell=%s rsrp=%s\n' "$1" \
		"$(mmcli -m any 2>/dev/null | sed -n 's/.*  state: *//p' | head -1)" \
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

leg(){ # leg NAME BAND
	s "# --- leg $1: requesting $2"
	mmcli -m any --set-current-bands="$2" >/dev/null 2>&1 \
		|| { s "#   ☠️ set-current-bands=$2 FAILED - leg $1 is NOT a measurement of $2"; return 1; }
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
	# ☠️ Report the band the modem ACTUALLY camped on, not the one requested: a
	# lock the network refuses leaves the UE where it was and the leg then
	# measures the previous band under the next band's name.
	awk -v leg="$1" '
		/^# t_s/ { for (i = 1; i <= NF; i++) h[$i] = i - 1; next }
		/^#/ { next }
		{ n++; if ($h["MPSS_cores"] != "0x0") up++; e += $h["smd_irq_total_per_s"] }
		END { if (n) printf "RESULT %s mpss_up=%.1f%% edge_per_s=%.1f n=%d\n",
			leg, 100 * up / n, e / n, n }
	' "$O/$1.txt" | tee -a "$L"
}

i=1
for b in $BANDS; do leg "L$i-$b" "$b"; i=$((i + 1)); done
leg "L$i-$FIRST-repeat" "$FIRST"

s "# restoring: any"
mmcli -m any --set-current-bands=any >/dev/null 2>&1 \
	|| s "#   ☠️☠️ restore FAILED - the modem is still pinned; fix this by hand"
wait_reg || s "#   ☠️ not registered after restore"
witness "restored"
s "# done $(date '+%F %T')"
s "$O"
