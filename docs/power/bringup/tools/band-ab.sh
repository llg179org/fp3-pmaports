#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# A-B-A' on the LTE band the modem is allowed to camp on, inside one boot.
#
#   band-ab.sh BAND_A BAND_B [window_s]      e.g. band-ab.sh eutran-3 eutran-1 360
#
# ☠️ WHY inside one boot. The modem's awake duty is fixed at boot and does not
# decay, so two windows from two boots differ for reasons no leg controls. Any
# claim about a lever has to put A, B and A' inside a single boot.
#
# ☠️ The witness must watch the variable the lever moves. This lever changes the
# band the modem camps on, so every leg records --nas-get-rf-band-info, not the
# modem's power state: a leg whose active band class is not the one requested is
# void, not evidence.
#
# ☠️ Restoring the band list matters: leaving the modem pinned to one band after
# the run is a configuration change nobody asked for. The original "current"
# list is captured before the first leg and written back at the end, and the
# script prints what it restored so a failed restore is visible.
set -u
A=${1:?band A}; B=${2:?band B}; W=${3:-360}
O=/var/log/fp3/band-ab-$(date +%s)
mkdir -p "$O"; L=$O/log.txt
s(){ echo "$*" | tee -a "$L"; }

# ☠️ mmcli wraps a long band list over several lines, and the sed range that
# looked obvious ('/current:/,/^$/') ran past the list and swallowed the entire
# rest of the modem dump - IMEI included - which then failed as a band argument.
# Take the remainder of the 'current:' line and only the continuation lines,
# which are the ones with no colon of their own.
orig=$(mmcli -m 0 2>/dev/null | awk '
	/current:/ { sub(/.*current: */, ""); print; inlist = 1; next }
	inlist && /:/ { exit }
	inlist { gsub(/^ *\| */, ""); print }
' | tr -d '|' | tr '\n' ' ' | sed 's/  */ /g; s/, *$//; s/^ *//; s/ *$//')
s "# band-ab $(date '+%F %T') A=$A B=$B window=${W}s"
s "# kernel=$(uname -v)"
s "# original bands: $orig"

witness(){
	printf '#   %s state=%s tech=%s band=%s chan=%s\n' "$1" \
		"$(mmcli -m 0 2>/dev/null | sed -n 's/.*  state: *//p' | head -1)" \
		"$(mmcli -m 0 2>/dev/null | sed -n 's/.*access tech: *//p' | head -1)" \
		"$(qmicli -d qrtr://0 --nas-get-rf-band-info 2>/dev/null | sed -n "s/.*Active Band Class: *'\([^']*\)'.*/\1/p" | head -1)" \
		"$(qmicli -d qrtr://0 --nas-get-rf-band-info 2>/dev/null | sed -n "s/.*Active Channel: *'\([^']*\)'.*/\1/p" | head -1)" \
		| tee -a "$L"
}

wait_reg(){
	i=0; while [ $i -lt 30 ]; do
		case "$(mmcli -m 0 2>/dev/null | sed -n 's/.*  state: *//p' | head -1)" in
			registered|connected) return 0 ;;
		esac
		sleep 5; i=$((i + 1))
	done
	return 1
}

leg(){ # leg NAME BAND
	s "# --- leg $1: requesting $2"
	mmcli -m 0 --set-current-bands="$2" >/dev/null 2>&1 \
		|| { s "#   ☠️ set-current-bands=$2 FAILED"; return 1; }
	wait_reg || s "#   ☠️ did not register within 150 s"
	sleep 20
	witness "$1 before"
	/usr/local/bin/burst-master.sh "$W" >/dev/null 2>&1
	d=$(ls -dt /var/log/fp3/burst-master-* | head -1)
	mv "$d/master.txt" "$O/$1.txt"; rm -rf "$d"
	witness "$1 after"
	awk -v leg="$1" '
		/^# t_s/ { for (i = 1; i <= NF; i++) h[$i] = i - 1; next }
		/^#/ { next }
		{ n++; if ($h["MPSS_cores"] != "0x0") up++; e += $h["edge_irq_per_s"];
		  c[n] = $h["current_ua"] }
		END { if (n) printf "RESULT %s mpss_up=%.1f%% edge_per_s=%.1f n=%d\n",
			leg, 100 * up / n, e / n, n }
	' "$O/$1.txt" | tee -a "$L"
}

leg A "$A"
leg B "$B"
leg Ap "$A"

s "# restoring: $orig"
mmcli -m 0 --set-current-bands="$(echo "$orig" | tr -d ' ')" >/dev/null 2>&1 \
	|| { s "#   ☠️ restore FAILED - falling back to 'any'"
	     mmcli -m 0 --set-current-bands=any >/dev/null 2>&1 \
		|| s "#   ☠️☠️ fallback FAILED TOO - the modem is still pinned"; }
wait_reg || s "#   ☠️ not registered after restore"
witness "restored"
s "$O"
