#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# ONE cheap-state leg, in the format ma3-fit.py reads.
#
#   ims-ma3-leg.sh <minutes> <alarm-s> <outdir>
#
# This is the A/B/A' ladder's leg body on its own, because the overnight run needs
# ONE leg per boot: the boot-to-boot spread comes from comparing the LEG MEANS
# across boots, and a ladder inside each boot would measure something else.
#
# ☠️ Everything the ladder learned the hard way is kept:
#   * ONE grep pass for all four accumulator registers - it can wrap between two
#     reads, and then the sum and the count describe different windows
#   * the read is the FIRST thing after the wake, before anything else runs
#   * the alarm is 90 s, not 60 - shorter than the accumulator's ~76 s wrap and a
#     fifth of the samples carry the previous wake's awake current
#   * the IMS vector is read back at the leg's start AND end: a revert halfway is
#     not a noisy measurement, it is a measurement of something else
# It does NOT touch the charger or the bands - the caller owns those, because the
# caller is the one that has to put them back after a reboot.
set -u
MIN=${1:-75}
ALARM=${2:-90}
O=${3:-/var/log/fp3/leg-$(date +%s)}
mkdir -p "$O"
L=$O/log.txt
BAT=/sys/class/power_supply/pmi632-battery
REG=/sys/kernel/debug/regmap/0-02/registers
s() { echo "$*" | tee -a "$L"; }

ims_line() { python3 /usr/local/bin/ims-toggle.py read 2>/dev/null \
	| awk '/voice|VoWiFi|video|SMS|UT|USSD/{printf "%s=%s ", $1, $2} END{print ""}'; }

s "# leg $(date '+%F %T')  ${MIN} min  alarm=${ALARM}s"
s "# battery $(cat $BAT/capacity)% v=$(cat $BAT/voltage_now)uV status=$(cat $BAT/status)"
s "# IMS at start: $(ims_line)"
# ☠️ THIS PATTERN HAS TO KEEP THE QUOTES IN THE MATCH, NOT IN THE OUTPUT. The
# first version dropped the closing quote from the expression and printed an
# EMPTY band/cell - which the rehearsal showed as "# band/cell:" with nothing
# after it. The band is worth ~17 pp of duty and ~54 mA on this device, so a leg
# with no band recorded cannot be compared with any other leg.
band_cell() {
	b=$(qmicli -d qrtr://0 --nas-get-rf-band-info 2>/dev/null \
		| sed -n "s/.*Active Band Class: *'\([^']*\)'.*/\1/p" | head -1)
	c=$(qmicli -d qrtr://0 --nas-get-cell-location-info 2>/dev/null \
		| sed -n "s/.*Global Cell ID: *'\([^']*\)'.*/\1/p" | head -1)
	echo "${b:-UNKNOWN} / ${c:-UNKNOWN}"
}
START_BC=$(band_cell)
s "# band/cell: $START_BC"

# ☠️ THE LEG HAS TO NAME THE SERVICES IT RIDES ON, NOT JUST THE NUMBER IT
# PRODUCES. Three of this report's claims rest on parties outside the phone or
# outside our code, and a silent change in any of them turns a future leg into an
# unexplained regression: the modem FIRMWARE (the oracle comparison is only a
# comparison because both slots run the same one), MODEMMANAGER/libqmi (the IMS
# vector is written through them, so "want=off" means off only while their
# behaviour holds), and the SUBSCRIPTION (CS-domain reachability and IMS
# provisioning are per-SIM, not per-device). None costs a measurement - they are
# three reads at the top of a 75-minute leg - and without them the dependency
# table in the report is a footnote instead of an instrumented claim.
s "# mm=$(mmcli --version 2>/dev/null | head -1 | awk '{print $NF}') qmicli=$(qmicli --version 2>/dev/null | head -1 | awk '{print $NF}')"
s "# modem fw: $(qmicli -d qrtr://0 --dms-get-software-version 2>/dev/null | sed -n "s/.*version: *'\([^']*\)'.*/\1/p" | head -1)"
s "# subscription: $(qmicli -d qrtr://0 --dms-uim-get-imsi 2>/dev/null | sed -n "s/.*IMSI: *'\([0-9]\{6\}\)[0-9]*'.*/\1xxxxxxxxx/p" | head -1)"
sed 's/^/BEFORE /' /sys/kernel/debug/qcom_rpm_master_stats/MPSS >> "$O/mpss-B.txt"

# ☠️ THE INTERFERENCE DETECTOR HAS TO NAME WHAT HAPPENED, NOT JUST THAT IT DID.
# The median-sleep test in ma3-fit is statistical AND state-dependent: it works on
# a cheap leg, but an expensive leg's median sleep is 16-18 s against a 90 s alarm
# by its own nature, so the test would fire on every A leg and says nothing about
# an A leg that WAS disturbed. And it reports the symptom, never the cause.
#
# So the leg keeps its own witness: every ssh login accepted during it, and every
# unit that started while it ran. Either one non-empty means this leg was
# interfered with, with the reason attached. Written because an ssh sent to answer
# one question turned a 90 s alarm into a 9 s median and nothing on the phone
# recorded who did it.
LEG_START_WALL=$(date '+%Y-%m-%d %H:%M:%S')

end=$(( $(cut -d. -f1 /proc/uptime) + MIN * 60 ))
while [ "$(cut -d. -f1 /proc/uptime)" -lt "$end" ]; do
	rtcwake -m mem -s "$ALARM" >/dev/null 2>&1
	R=$(grep -E '^488[b-e]:' "$REG")
	acc=$(echo "$R" | awk -F': ' '/^488b/{a=$2} /^488c/{b=$2} /^488d/{c=$2} END{print c b a}')
	cnt=$(echo "$R" | awk -F': ' '/^488e/{print $2}')
	printf 'B t=%s acc=0x%s cnt=0x%s cur=%s v=%s cap=%s\n' \
		"$(date '+%F %T')" "$acc" "$cnt" \
		"$(cat $BAT/current_now)" "$(cat $BAT/voltage_now)" "$(cat $BAT/capacity)" \
		>> "$O/samples-B.txt"
done
sed 's/^/AFTER /' /sys/kernel/debug/qcom_rpm_master_stats/MPSS >> "$O/mpss-B.txt"
s "# IMS at end:   $(ims_line)"
END_BC=$(band_cell)
s "# band/cell at end: $END_BC"
# ☠️ SAY IT, do not leave it to whoever reads two lines twenty apart. A band change
# mid-leg is the largest confounder measured on this device (~17 pp duty, ~54 mA),
# and it happened in a six-minute rehearsal leg.
[ "$END_BC" = "$START_BC" ] || s "# ☠️☠️ THE BAND MOVED MID-LEG: $START_BC -> $END_BC — this leg is NOT comparable with a leg on another band"
# --- the interference audit -------------------------------------------------
logins=$(journalctl --since "$LEG_START_WALL" 2>/dev/null \
	| grep -c "Accepted publickey\|Accepted password" || true)
# ☠️ THE AUDIT NEEDS AN ALLOWLIST OR IT CONVICTS EVERY LEG. fp3-ims-reconcile
# starts a unit every five minutes - about fifteen times inside a 75 minute leg -
# and fp3-ringlog and the usbnet watchdog come and go too. Without this the
# morning would be an all-red night sitting on valid data, which is exactly the
# shape of the wrapper bug that matched the phone's permanent services.
EXPECTED='fp3-ims-reconcile|fp3-ringlog|fp3-usbnet-watchdog|systemd-tmpfiles|logrotate|apk-'
units=$(journalctl --since "$LEG_START_WALL" -o cat 2>/dev/null \
	| sed -n 's/^Started \(.*\)\.$/\1/p' | grep -Ev "$EXPECTED" | sort -u | head -8 | tr '\n' ';')

# ☠️ AND AN INCOMING CALL LEAVES NO SSH AND NO UNIT, yet it wakes the AP and tears
# a leg apart for minutes. The ring logger is already running for the reachability
# census - so the leg reads its own window out of it rather than pretending calls
# do not happen at 3 am.
calls=$(awk -v s="$LEG_START_WALL" '$0 !~ /^#/ && $1" "$2 >= s' /var/log/fp3/ringlog.tsv 2>/dev/null | grep -c . || true)

# ☠️☠️ AND THE WATCHDOG IS ONE OF THEM. 2026-09-02 19:22: the overnight run was
# being watched by a host-side loop that ssh'd in every 300 s - about fifteen
# logins inside a 75 minute leg, each one an AP wake, in a leg whose whole point
# is how long the AP stays asleep. The instrument built that morning to catch my
# ssh disturbance would have condemned every leg of the night, and it would have
# been RIGHT. The watchdog now polls every 1800 s and stamps each poll on the
# HOST (night-watch/polls.tsv) so the morning can attribute the logins it finds.
# The lesson is not "poll less": a watcher that reaches into the thing it watches
# is part of the experiment, and has to be budgeted like any other load.
# ☠️ A COUNT CAN ONLY CONVICT; A LEDGER CAN ATTRIBUTE. Where the login ledger is
# installed (userspace-power/fp3-login-ledger.sh via root's ~/.ssh/rc), print WHO
# came in and WHAT they ran, so the morning can tell the watchdog's 1800 s poll
# apart from a human at 03:14. Absent the ledger this degrades to the bare count,
# which is what every leg before 2026-09-02 had.
if [ -r /var/log/fp3/logins.tsv ]; then
	awk -v s="$LEG_START_WALL" -F'\t' '$1" "$2 >= s || $1 >= s {printf "#   %s  from %s  %s\n", $1, $3, $6}' \
		/var/log/fp3/logins.tsv 2>/dev/null | head -20 | tee -a "$L"
fi
s "# audit: ssh logins during the leg = ${logins:-0}"
s "# audit: unexpected units started = ${units:-none}"
s "# audit: incoming calls during the leg = ${calls:-0}"
[ "${calls:-0}" -eq 0 ] || s "# ☠️☠️ DISTURBED (call): ${calls} incoming call(s) landed during this leg - an incoming call is an AP wake and breaks the sleep pattern for minutes"
[ -z "$units" ] || s "# ☠️ DISTURBED (unit): something unexpected started during this leg: $units"
if [ "${logins:-0}" -gt 0 ]; then
	s "# ☠️☠️ THIS LEG WAS INTERFERED WITH: ${logins} ssh login(s) landed while it ran."
	s "#     An ssh login is an AP wake. Treat this leg's current as invalid, not noisy."
fi
s "# $(grep -c . "$O/samples-B.txt") samples, battery $(cat $BAT/capacity)% v=$(cat $BAT/voltage_now)uV"
