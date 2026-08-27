#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Name the remote processor that is up during an awake current burst.
#
# ☠️ THIS IS THE FOURTH INSTRUMENT ON THE SAME BURST, AND THE FIRST THREE ALL SAID
# "NOT ME". A trace said the burst is not code (the event rate is flat across a 9x
# current swing), burst-attrib said it is not the application CPU (the cores are
# power-collapsed 99 % of the time *during* the burst), and an A-B-A' said it is not
# the modem RF. What is left runs on a processor Linux does not schedule, so the
# question is no longer "what code" but "which master is awake".
#
# The RPM keeps that answer per master in debugfs. Per sample, for each of
# APSS / LPASS / MPSS / PRONTO:
#   - Shutdown count      delta -> how often it went down in this interval
#   - XO shutdown count   delta -> how often it released the crystal
#   - XO total duration   delta -> how long it was off the crystal, as % of wall
#                                  clock; this is the one that carries the answer
#   - Active cores bitmask      -> whether any of its cores is up right now
# A master that holds the XO through the burst and releases it through the quiet
# stretch is the owner of the burst, whatever its shutdown count says.
#
# ☠️ THE TICK IS THE 19.2 MHz XO, NOT THE SLEEP CLOCK. Measured: XO total duration
# / 19.2e6 lands inside uptime, /32768 is three orders out. Everything derived from
# a duration here divides by 19200 for ms - get that wrong and the duty cycle is
# nonsense in a plausible-looking way.
#
# ☠️ IT DOES NOT TOUCH /sys/class/remoteproc. Restarting the modem there costs
# audio until the next reboot and a mixer write afterwards oopses the kernel. This
# instrument only reads.
#
# ☠️ THE PANEL, THE CHARGE CUT AND THE WINDOW BELONG TO idle-ab.sh, as in
# burst-attrib.sh - and so does the same trap: idle-ab waits for the panel before
# its window opens, so the sampler runs long and writes `# window_from=<t>` at the
# END of the file. Any reader needs two passes; a mark that is written but not
# honoured is worse than no mark, because the file then looks filtered.
#
#   burst-master.sh [seconds]        (default 360)
set -u
W=${1:-360}
IV=2
# ☠️ The mainline module and the downstream 4.9 driver put this in different
# places AND spell the keys differently. Take the first that exists; the raw text
# of one file is copied into the capture at both ends of the run, so a capture
# whose parse came out empty still carries the format that defeated it. A capture
# is worth more than the parser that read it.
D=/sys/kernel/debug/qcom_rpm_master_stats
[ -d "$D" ] || D=/sys/kernel/debug/rpm_master_stats
OUT=/var/log/fp3/burst-master-$(date +%s)
mkdir -p "$OUT"
BAT=$(dirname "$(ls /sys/class/power_supply/*/capacity 2>/dev/null | head -1)")

say(){ echo "$*" | tee -a "$OUT/log"; }
say "# burst-master $(date '+%F %T') window=${W}s interval=${IV}s bat=$BAT"
say "# kernel=$(uname -r) $(uname -v)"

modprobe rpm_master_stats 2>/dev/null
[ -d "$D" ] || { say "☠️ no $D - the rpm_master_stats module is not loaded and would not load"; exit 1; }
MASTERS="APSS LPASS MPSS PRONTO"
FILES=""
for m in $MASTERS; do
	[ -r "$D/$m" ] && FILES="$FILES $D/$m" || say "☠️ $m unreadable - it will be a hole, not a zero"
done
say "# masters:$FILES"

# ☠️ WHO TALKS TO THE MODEM IS NOT THE SAME QUESTION AS WHETHER THE MODEM IS UP,
# and only one of the two is visible from this side. The AP sees the modem's
# messages as interrupts on the SMD/smp2p/glink edges - the same family as IRQ 141,
# which terminates every suspend on this phone. Sampling those counters next to
# the master state separates "the MSS core woke because the AP poked it" from "the
# MSS core woke on its own and the AP never heard about it". Neither answer was
# reachable before, and they lead to opposite fixes.
# ☠️ THE MODEM EDGE IS IDENTIFIED BY ITS HARDWARE IRQ, NOT ITS LINUX NUMBER. It
# was 141 on the boot where it was first named, and a Linux irq number is an
# allocation - it moves. hwirq 57 (GIC_SPI 25) on an `smd-edge` row is the modem's,
# and that is the line that terminates every suspend on this phone.
MODEM_IRQ=$(awk '/smd-edge/ && $(NF-2) == 57 {l=$1; sub(":","",l); print l}' /proc/interrupts | head -1)
IRQS=$(awk -F: '/smd|smp2p|glink|qcom-ipcc|ipa/ {gsub(/ /,"",$1); print $1}' /proc/interrupts | tr '\n' ' ')
for m in $MASTERS; do
	[ -r "$D/$m" ] && { echo "=== $m (raw, at start)"; cat "$D/$m"; } >> "$OUT/masters-raw.txt" 2>/dev/null
done

say "# modem edge irq=${MODEM_IRQ:-?}  all edge irqs:${IRQS:- none found}"
irq_row(){   # total over the listed irqs, then the modem edge alone
	awk -v want="$IRQS" -v one="${MODEM_IRQ:--1}" \
	    'BEGIN{n=split(want,w," "); for(i=1;i<=n;i++) k[w[i]]=1}
	     {l=$1; sub(":","",l); s=0; for(i=2;i<=NF;i++) if($i ~ /^[0-9]+$/) s+=$i;
	      if(l in k) t+=s; if(l == one) m=s}
	     END{print t+0, m+0}' /proc/interrupts
}

# one awk over all four files; four cats per sample was the cost that broke
# burst-rail.sh's first version, and this reads more per file than that did
snap(){
	awk 'FNR==1{m=$1; sub(":","",m); ms[n++]=m}
	     /XO total duration:/   {xo[m]=$4}
	     /XO shutdown count:/   {xc[m]=$4}
	     /Shutdown count:/      {sc[m]=$3}
	     /Active cores bitmask:/{ac[m]=$4}
	     END{for(i=0;i<n;i++){k=ms[i];
	         printf "%s %s %s %s ", sc[k]+0, xc[k]+0, xo[k]+0, ac[k]}}' $FILES
}

sampler(){
	hdr="# t_s cur_mA v_mV"
	for m in $MASTERS; do hdr="$hdr ${m}_sd ${m}_xosd ${m}_xopct ${m}_cores"; done
	hdr="$hdr edge_irq_per_s modem_irq_per_s"
	echo "$hdr" > "$OUT/master.txt"
	prev=$(snap)
	set -- $(irq_row); pirq=$1; pmirq=$2
	t=0
	while [ $t -lt "$((W + 300))" ]; do
		sleep $IV
		t=$((t + IV))
		cur=$(cat "$BAT/current_now" 2>/dev/null || echo 0)
		vol=$(cat "$BAT/voltage_now" 2>/dev/null || echo 0)
		now=$(snap)
		set -- $(irq_row); nirq=$1; nmirq=$2
		echo "$t $(( (cur<0 ? -cur : cur) / 1000 )) $((vol/1000)) $(
			echo "$prev|$now" | awk -v iv="$IV" -F'|' '{
				np=split($1,p," "); nn=split($2,c," ");
				for(i=1;i<=nn;i+=4){
					# duration ticks are the 19.2 MHz XO: /19200 = ms, /(192000*iv) = %
					printf "%d %d %d %s ", c[i]-p[i], c[i+1]-p[i+1],
					       (c[i+2]-p[i+2])/(192000*iv), c[i+3];
				}}') $(( (nirq - pirq) / IV )) $(( nmirq - pmirq ))" >> "$OUT/master.txt"
		prev=$now; pirq=$nirq; pmirq=$nmirq
	done
}

sampler &
spid=$!
say "# sampler pid=$spid, handing the window to idle-ab.sh"
/usr/local/bin/idle-ab.sh "$W" >/dev/null 2>&1
rc=$?
kill $spid 2>/dev/null
wait $spid 2>/dev/null

src=$(ls -t /tmp/idle-ab-*.txt 2>/dev/null | head -1)
[ -n "$src" ] && cp "$src" "$OUT/current.txt"
waited=0
[ -n "$src" ] && waited=$(sed -n 's/.*waited=\([0-9]*\)s.*/\1/p' "$src" | head -1)
[ -z "$waited" ] && waited=0
echo "# window_from=$((waited + IV))  # samples before this mark saw a lit panel" \
	>> "$OUT/master.txt"
say "# idle-ab rc=$rc panel-wait=${waited}s -> window_from=$((waited + IV))"
[ -n "$src" ] && say "# $(grep '^# panel:' "$src" | tr '\n' '|')"
for m in $MASTERS; do
	[ -r "$D/$m" ] && { echo "=== $m (raw, at end)"; cat "$D/$m"; } >> "$OUT/masters-raw.txt" 2>/dev/null
done
say "# done: $(grep -vc '^#' "$OUT/master.txt") master samples"
say "# $OUT"
