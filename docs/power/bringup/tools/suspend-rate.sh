#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# How OFTEN does a suspend end early, and under which conditions?
#
# ☠️ This exists because of a mistake worth not repeating. On 2026-08-26 five
# consecutive radio-up suspends ended early (leg A's 50/89/32/59 s of 600, and a
# census arm's 67 s of 600) and that was written up as a categorical statement
# about the device. One hour later a sixth, under conditions nobody had varied on
# purpose, slept the full 601 s and the statement had to be withdrawn from three
# documents.
#
# When the data says "sometimes", the next instrument is a RATE, not another
# story. So: one condition, repeated n times, with every candidate variable
# recorded PER ROUND rather than inferred afterwards from what the operator
# happens to remember about the session.
#
#   suspend-rate.sh [n] [seconds] [gap_s]  (defaults 8, 600, 150)
#
# ☠️☠️ THE GAP IS A SAFETY PARAMETER, NOT A SETTLING TIME, and the first version
# of this script got it wrong at 30 s. Measured 2026-08-26: with 8 x 600 s
# suspends and a 30 s gap, the phone was **unreachable for over 80 minutes** on
# both links. The USB gadget does not re-enumerate within 30 s of a resume, so a
# host watching `lsusb` every 2 seconds saw nothing at all - and "cycling
# normally, windows too short to catch" and "wedged in suspend" produce the
# IDENTICAL observation from outside.
#
# That is not a monitoring inconvenience; it means an unattended run cannot be
# distinguished from a dead phone, so nobody can decide whether to intervene. The
# gap must be longer than the slowest link's own recovery - measured at ~39 s for
# this device's RNDIS after a reboot, so 150 s carries real margin. The cost is
# 2 minutes per round; the thing it buys is the ability to know what is happening.
#
# Read the output as a fraction, not as a narrative: "k of n ended early". Only
# then ask what k depends on, and change ONE recorded variable at a time.
#
# ☠️ Do not poll the phone while this runs. Every ssh login is a wakeup, and on
# this measurement the wakeups ARE the phenomenon. Start it with
# `systemd-run --unit=srate --collect` and read /run/srate.txt afterwards.
#
# ☠️ It does not touch the charger and cuts nothing, so it is safe to run on a
# phone that must stay usable - and it deliberately does NOT stop the modem
# stack: `systemctl stop rmtfs` powers the modem down and would silently change
# the very condition being measured.
set -u
N=${1:-8}; SECS=${2:-600}; GAP=${3:-150}
O=/run/srate.txt
: > "$O"
s(){ echo "$*" >> "$O"; }
mreg(){ mmcli -m 0 2>/dev/null | sed -n 's/.*state: *//p' | head -1; }

s "# srate n=$N secs=$SECS gap=${GAP}s start_uptime=$(cut -d. -f1 /proc/uptime) kernel=$(uname -v)"
s "# cable: online=$(cat /sys/class/power_supply/pmi632-charger/online) status=$(cat /sys/class/power_supply/pmi632-battery/status)"
# ☠️ How the modem came up is a candidate variable in its own right and cannot be
# recovered later: a modem started by the boot and one restarted by hand through
# remoteproc are not obviously the same state.
s "# modem remoteproc state at start: $(cat /sys/class/remoteproc/remoteproc1/state 2>/dev/null)"
s "# round uptime_s slept_s asked_s modem_state cap mpss_xo_delta wake_irq"

# ☠️ THE FIELD THAT NAMES THE CULPRIT. Every round of this script used to record
# how long the suspend lasted and which interrupt lines moved across the whole
# round - gap included - and none of that says which line ENDED the suspend.
# /sys/power/pm_wakeup_irq does, in one read, and it is the only reason the
# 2026-08-26 answer (the modem's SMD edge, 4 of 4) was reachable at all. Resolve
# it to a name here, because a bare Linux irq number is an allocation and moves
# between boots - which is exactly the trap the modem-edge identification hit.
wake_irq(){
	n=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)
	case "$n" in ''|*[!0-9]*) echo "none"; return ;; esac
	printf '%s:%s\n' "$n" \
		"$(awk -v k="$n:" '$1 == k { print $NF }' /proc/interrupts)"
}

RPM=/sys/kernel/debug/qcom_rpm_master_stats
mf(){ sed -n "s/^[[:space:]]*$1[[:space:]]*:[[:space:]]*//p" "$RPM/MPSS" 2>/dev/null | head -1; }

# ☠️ Sum every CPU column, but STOP before the trailing text fields - a
# /proc/interrupts row ends with the controller, hwirq, type and name, and one of
# those is numeric. Indexing by position without allowing for that is the
# 2026-08-26 column-misread in another costume.
irqs(){ awk 'NR>1 {s=0; for(i=2;i<=NF-3;i++) if ($i ~ /^[0-9]+$/) s+=$i; print $1, s}' /proc/interrupts | sort; }

# ☠️ Per-round interrupt deltas, because the phenomenon this script found is a
# DECAY: the abort gets shorter the further from boot, so the waker is something
# that drains. A per-round diff shows which line shrinks WITH the abort instead
# of scaling with time asleep - the latter is scenery (the MPSS crystal churn was
# measured at a constant 2.4-2.5 shutdowns per second asleep, in both regimes).
# Normalise before comparing rounds: a round that slept 50 s and one that slept
# 356 s cannot have their raw totals compared.
IRQS=${IRQS:-1}

i=1
while [ "$i" -le "$N" ]; do
	x0=$(mf 'XO shutdown count'); t0=$(cut -d. -f1 /proc/uptime); st=$(mreg)
	[ "$IRQS" = 1 ] && irqs > /run/.sr_irq0
	rtcwake -m mem -s "$SECS" >/dev/null 2>&1
	t1=$(cut -d. -f1 /proc/uptime); x1=$(mf 'XO shutdown count')
	slept=$((t1 - t0))
	s "$i $t0 $slept $SECS ${st:-?} $(cat /sys/class/power_supply/pmi632-battery/capacity) $(( ${x1:-0} - ${x0:-0} )) $(wake_irq)"
	if [ "$IRQS" = 1 ]; then
		irqs > /run/.sr_irq1
		awk -v sl="$slept" 'NR==FNR{a[$1]=$2; next}
			{d=$2-a[$1]; if (d>0) printf "    irq %-12s +%-7d %.2f/s\n", $1, d, (sl>0 ? d/sl : 0)}' \
			/run/.sr_irq0 /run/.sr_irq1 | sort -t+ -k2 -rn | head -8 >> "$O"
	fi
	sleep "$GAP"
	i=$((i + 1))
done
s "# done"
