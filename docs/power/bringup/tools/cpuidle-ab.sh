#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# DOES THE MODEM'S LONG WAKE CONTAIN THE AP'S OWN WAKE-UP LATENCY?
#
# The modem here wakes at the same rate as the vendor stack but stays awake
# about seven times longer. Radio configuration is excluded (four mode
# preferences on one cell give the same duty) and so is QMI: a 300 s census in
# this exact state counted eighteen QRTR messages against roughly 770 wakes, and
# rmtfs used no CPU at all. So the modem is not waiting for an ANSWER from the
# AP. What is still open is whether it waits for the AP to be THERE - every wake
# paying for an application processor climbing out of power collapse.
#
# Barring deep idle is the strongest form of "the AP responds instantly" that
# the hardware can offer. If the duty does not move, the hardware-latency
# flavour is FALSIFIED, not merely unsupported.
#
# ☠️ THE KNOB IS AN OPEN FILE DESCRIPTOR, NOT A WRITE. /dev/cpu_dma_latency
# holds the constraint only while the fd that wrote it stays open, and releases
# it on close - which is the good property here (nothing survives a crash) and
# the easy mistake (a write in a subshell that exits constrains nothing at all).
# Check the value is back to 2000000000 afterwards; this script does.
#
# ☠️ A KNOB WITHOUT A WITNESS PROVES NOTHING. This reads every CPU's cpuidle
# state usage on both sides of every arm. In the barred arm the deep state's
# usage delta must be ~0; if it is not, the knob did not take and the arm is not
# a measurement of anything. Say so and refuse the conclusion.
#
# ☠️ AND CHECK THE GATE FIRST. This kernel carries a global cpu_latency_qos
# mechanism from the PLL work. If something already holds the constraint, the
# barred arm equals the free arm by construction and a null result means
# nothing. Measured before writing this: the target read 2000000000, the
# unconstrained default.
#
#   cpuidle-ab.sh [seconds_per_arm]      default 600
set -u
W=${1:-600}
O=${CPUIDLE_AB_LOG:-/var/log/fp3/cpuidle-ab.log}
DEEP=state1                     # cpu-power-collapse; state0 is WFI
mkdir -p /var/log/fp3
say(){ echo "$*" | tee -a "$O"; }
: > "$O"
say "# cpuidle-ab $(date '+%F %T') arm=${W}s deep=$DEEP"

gate=$(od -An -td4 -N4 /dev/cpu_dma_latency 2>/dev/null | tr -d ' ')
say "# gate: /dev/cpu_dma_latency target = ${gate:-unreadable}"
if [ "$gate" != "2000000000" ]; then
	say "☠️ SOMETHING ALREADY CONSTRAINS CPU LATENCY (${gate}). The barred arm would"
	say "   equal the free arm by construction. Aborting rather than measuring nothing."
	exit 1
fi

deepuse(){ cat /sys/devices/system/cpu/cpu*/cpuidle/$DEEP/usage 2>/dev/null | tr '\n' ' '; }
sumdeep(){ awk '{s+=$1} END{print s+0}' /sys/devices/system/cpu/cpu*/cpuidle/$DEEP/usage 2>/dev/null; }
xo(){ awk '/XO total duration:/{printf "%.0f", $4}' /sys/kernel/debug/qcom_rpm_master_stats/MPSS; }

arm(){ # arm NAME BARRED
	say "--- arm $1 (deep idle $( [ "$2" = yes ] && echo BARRED || echo free ))"
	/usr/local/bin/leg-covariates.sh "$1 before" 2>/dev/null | tee -a "$O" >/dev/null
	d0=$(sumdeep); x0=$(xo)
	if [ "$2" = yes ]; then
		exec 3>/dev/cpu_dma_latency
		printf '\000\000\000\000' >&3
		now=$(od -An -td4 -N4 /dev/cpu_dma_latency 2>/dev/null | tr -d ' ')
		say "    constraint now: ${now:-?} (0 = deep idle barred)"
	fi
	sleep "$W"
	d1=$(sumdeep); x1=$(xo)
	if [ "$2" = yes ]; then
		exec 3>&-
		back=$(od -An -td4 -N4 /dev/cpu_dma_latency 2>/dev/null | tr -d ' ')
		say "    constraint released: ${back:-?}"
	fi
	/usr/local/bin/leg-covariates.sh "$1 after" 2>/dev/null | tee -a "$O" >/dev/null
	duty=$(awk -v a="$x1" -v b="$x0" -v w="$W" 'BEGIN{printf "%.1f", 100*(1-(a-b)/19200000/w)}')
	dd=$((d1 - d0))
	say "RESULT $1 mpss_up=${duty}%  ${DEEP}_entries=+$dd ($(awk -v n="$dd" -v w="$W" 'BEGIN{printf "%.1f", n/w}')/s)"
	# The witness, stated as a verdict rather than left for a reader to notice.
	# ☠️ RELATIVE TO THE FREE ARM, NOT AN ABSOLUTE COUNT. The first version
	# failed a knob that had worked: 20 s barred gave 22 entries against 2509
	# free - a 99.1 % cut - and an absolute threshold of W/10 = 2 called that
	# "did not take". A residue of a few entries is expected (the constraint is
	# applied per wakeup, and threads racing the open see the old target); what
	# matters is whether the RATE collapsed.
	if [ "$2" = no ]; then FREE_RATE=$(awk -v n="$dd" -v w="$W" 'BEGIN{printf "%.3f", n/w}'); fi
	if [ "$2" = yes ]; then
		br=$(awk -v n="$dd" -v w="$W" 'BEGIN{printf "%.3f", n/w}')
		if awk -v b="$br" -v f="${FREE_RATE:-0}" 'BEGIN{exit !(f > 0 && b < 0.05*f)}'; then
			say "    witness OK: deep idle really was barred ($br/s vs $FREE_RATE/s free, $(awk -v b="$br" -v f="$FREE_RATE" 'BEGIN{printf "%.1f", 100*(1-b/f)}')% cut)"
		else
			say "    ☠️ THE KNOB DID NOT TAKE: $br/s deep-idle entries vs $FREE_RATE/s in the free arm."
			say "       This arm is not a measurement of barred idle. Do not conclude from it."
		fi
	fi
	sleep 20
}

FREE_RATE=""
say "# deep-idle usage per cpu at start: $(deepuse)"
arm A-free   no
arm B-barred yes
arm C-free   no
say "# deep-idle usage per cpu at end:   $(deepuse)"
say "# done $(date '+%F %T')"
