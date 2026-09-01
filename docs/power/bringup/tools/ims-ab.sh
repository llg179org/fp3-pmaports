#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# THE IMS A/B/A' LADDER — the controlled form of the intervention.
#
#   ims-ab.sh [seconds]        (default 600, run as root ON THE DEVICE)
#
# ☠️ WHY THIS EXISTS RATHER THAN THE ONE WINDOW ALREADY MEASURED. The first
# IMS-off duty window (2026-09-02 00:17) is unusable for two independent reasons,
# and both are the classic ones in this repo:
#
#   1. DIAG RESIDUE. The log mask is *modem-side* state set over DIAG_CTRL; it
#      outlives the capture process that set it. That window ran with the masks
#      still armed and no consumer, and the modem never entered XO shutdown once
#      in 600 s (0 wakes, exit > enter, `Active cores bitmask: 0x1`) — measured
#      still true 950 s later. A modem kept awake by its own logging cannot also
#      be a measurement of what IMS costs. Hence the firmware restart first: it
#      is the only thing that clears the masks without a reboot.
#
# ☠️ RUN IT UNDER systemd-run --unit=, NEVER `nohup ... &` OVER ssh. Measured
# 2026-09-02: launched with nohup from an ssh command, this script died the moment
# the ssh session closed - after it had stopped the modem firmware and before it
# started it again. The modem stayed OFF for an hour, unreachable for calls, and
# the watchdog missed it because its liveness check (`pgrep -f ims-ab.sh` over
# ssh) matched its own command line and always found "a process".
#
#   systemd-run --unit=fp3-ims-ab --collect sh /tmp/ims-ab.sh 600
#   systemctl is-active fp3-ims-ab      # the liveness check that cannot self-match
#
#   2. THE BAND MOVED INSIDE THE WINDOW (eutran-20/cell 1470722 before,
#      eutran-1/1470762 after). The band is worth ~17 pp of MPSS duty in this
#      repo's own ladder — more than most effects we chase — so an unpinned band
#      makes any leg uninterpretable. It has already overturned two conclusions
#      here (the bearer lead, and leg 1 of the mode ladder).
#
# ☠️ AND WHY A' EXISTS. A→B alone cannot separate "IMS off is cheaper" from "the
# modem drifted cheaper". The repeat of the first arm is the only thing that
# prices the drift, and this repo has been bitten by exactly that.
set -u
W=${1:-600}
O=/var/log/fp3/ims-ab-$(date +%s)
mkdir -p "$O"
L=$O/log.txt
s() { echo "$*" | tee -a "$L"; }

s "# ims-ab $(date '+%F %T') window=${W}s"
s "# kernel=$(uname -r) uptime=$(cut -d. -f1 /proc/uptime)"

# --- 1. clear the modem's diag state the only way short of a reboot ----------
s "# --- modem firmware restart (clears DIAG log masks) ---"
echo stop > /sys/class/remoteproc/remoteproc0/state 2>>"$L"
sleep 5
echo start > /sys/class/remoteproc/remoteproc0/state 2>>"$L"
sleep 5
# ☠️ THE RESTART IS NOT COMPLETE WITHOUT THIS. remoteproc comes back up ("remote
# processor is now up" in dmesg) but ModemManager does not re-enumerate the modem
# on its own: measured 2026-09-02, `mmcli -L` said "No modems were found" for an
# hour after a successful start, and the modem only reappeared once MM had been
# restarted by hand. A wait loop polling `mmcli -m any` therefore waits forever.
systemctl restart ModemManager
i=0
while [ $i -lt 60 ]; do
	i=$((i+1)); sleep 5
	st=$(mmcli -m any 2>/dev/null | sed -n 's/.*state: *//p' | head -1)
	s "#   wait $i: ${st:-<no modem>}"
	case "$st" in *registered*) break;; esac
done
case "${st:-}" in
	*registered*) ;;
	*) s "# ☠️ THE MODEM DID NOT COME BACK ($i tries, last: ${st:-<none>}). Aborting"
	   s "#    rather than measuring a legless ladder - and leaving the modem for"
	   s "#    hand recovery, because this script cannot tell a slow attach from a"
	   s "#    wedged one."; exit 1;;
esac

# --- 2. persistence: did the IMS write survive the restart? -----------------
s "# --- IMS state AFTER the firmware restart (persistence answer) ---"
python3 /tmp/ims-toggle.py read 2>&1 | sed 's/^/#   /' | tee -a "$L"

# --- 3. pin the band; every leg measures the same radio ---------------------
s "# --- pinning eutran-1 ---"
mmcli -m any --set-current-bands=eutran-1 >/dev/null 2>&1 \
	|| s "#   ☠️ set-current-bands=eutran-1 FAILED - the ladder is NOT band-pinned"
sleep 30

leg() {   # leg NAME IMSSTATE
	s ""
	s "########## LEG $1  (IMS=$2)  $(date '+%F %T') ##########"
	python3 /tmp/ims-toggle.py "$2" 2>&1 | sed 's/^/#   /' | tee -a "$L"
	sleep 20
	sh /tmp/modem-window.sh "$W" >/dev/null 2>&1
	cp /tmp/modem-window.txt "$O/window-$1.txt"
	s "#   window saved: $O/window-$1.txt"
	grep -E "Active Band Class|Global Cell ID" "$O/window-$1.txt" | sed 's/^/#   /' | tee -a "$L"
}

leg A  on
leg B  off
leg A2 on

# --- 4. restore: never leave the modem pinned or IMS-crippled ---------------
s ""
s "# --- restore ---"
mmcli -m any --set-current-bands=any >/dev/null 2>&1 && s "#   bands restored to any"
python3 /tmp/ims-toggle.py on 2>&1 | sed 's/^/#   /' | tee -a "$L"
s "# done $(date '+%F %T')"
