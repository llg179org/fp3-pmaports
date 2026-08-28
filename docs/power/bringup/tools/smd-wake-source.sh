#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# WHICH CHANNEL rings the modem's SMD edge and ends the suspend?
#
#   smd-wake-source.sh [cycles] [seconds] [gap_s]     (defaults 4, 300, 90)
#
# The trade this exists to break: with the modem edge armed
# (4080000.remoteproc/.../remoteproc0:smd-edge, power/wakeup = enabled) an
# incoming call raises the phone from s2idle and it rings - measured 2026-08-25,
# resume at 18:06:14 and the call object one second later. With it disarmed the
# suspends hold but calls do not arrive. Between those two the phone currently
# gets neither: the edge is armed, so every suspend dies in about a second, and
# the sleep it would buy is switched off at the policy layer anyway.
#
# ☠️ The trade is only forced if the thing ringing the edge is the SAME thing that
# delivers the call. Nobody has checked. A per-CHANNEL census across the suspend
# answers it: if the ~1-per-2-s ring is one service - a heartbeat, a QMI client
# retrying against a listener that does not exist on this port - then quieting
# that channel keeps the wake path for calls and gives the residency back, with
# no firmware involved.
#
# WHAT IS ALREADY KNOWN, so this does not rediscover it: the 2026-08-22 kprobe
# census put ~all ~35 of the modem edge's interrupts in a 120 s window on the
# **IPCRTR** channel, and the matching qrtr census found only 4 payloads - so the
# ring is signal-level (flow control / read-acks), not messages. The AP is not
# driving it either: a __qcom_smd_send census over the same window sent 2 IPCRTR
# frames against 276 rpm_requests and 31 WLAN_CTRL. ☠️ And IPCRTR is also how a
# call arrives, so quieting the channel is not a lever - which is why this script
# is now a BEFORE/AFTER instrument for the modem firmware swap rather than a
# search. Run it on 425464, swap, run it on 325768.
#
# ☠️ Do not read the 2026-08-22 census's 33-hit group as modem traffic: that is
# WCNSS_CTRL / APPS_RIVA_* / APPS_FM, i.e. the PRONTO edge (GIC 174) scanning all
# of its channels once per interrupt.
#
# ☠️ Do not poll the phone while this runs - every ssh login is a wake, and here
# the wakes ARE the measurement. systemd-run it and read /run/smdwake.txt after.
set -u
N=${1:-4}; SECS=${2:-300}; GAP=${3:-90}
O=/run/smdwake.txt
T=/sys/kernel/tracing
: > "$O"
s(){ echo "$*" >> "$O"; }

MODEM_EDGE=/sys/devices/platform/soc@0/4080000.remoteproc/remoteproc/remoteproc0/remoteproc0:smd-edge

s "# smd-wake-source n=$N secs=$SECS gap=${GAP}s uptime=$(cut -d. -f1 /proc/uptime)"
s "# kernel=$(uname -v)"
s "# modem edge wakeup: $(cat $MODEM_EDGE/power/wakeup 2>/dev/null)"
s "# other edges:"
for w in $(find /sys/devices -name wakeup -path '*smd-edge/power/*' 2>/dev/null); do
	s "#   $w = $(cat $w)"
done
s "# modem: $(mmcli -m 0 2>/dev/null | sed -n 's/.*state: *//p' | head -1)"
s "# suspend_stats success=$(cat /sys/power/suspend_stats/success) fail=$(cat /sys/power/suspend_stats/fail)"

# The tracepoint fires once per channel the edge's interrupt handler walks, so
# the count per channel is "how many times an interrupt on that channel's edge
# was serviced", not "how many messages arrived". That is the right granularity
# here: the question is which edge and which channel the wake belongs to.
# ☠️ The channel name needs a DOUBLE deref: the argument is the channel pointer
# and `name` is a char* at +0x18, so the string lives at +0x0(+0x18(%x0)). The
# 2026-08-22 first attempt used a single deref and printed the pointer's own
# bytes as a string. Needs CONFIG_KPROBE_EVENTS, which r67 turned on.
if [ -d "$T" ]; then
	echo 0 > $T/tracing_on
	echo > $T/trace
	echo 8192 > $T/buffer_size_kb 2>/dev/null
	echo -n > $T/kprobe_events 2>/dev/null
	if echo 'p:chan qcom_smd_channel_intr name=+0x0(+0x18(%x0)):string' > $T/kprobe_events 2>/dev/null; then
		echo 1 > $T/events/kprobes/chan/enable
		s "# kprobe: chan on qcom_smd_channel_intr, name=+0x0(+0x18(%x0)):string"
	else
		s "# kprobe_events refused the probe - no per-channel census this run"
		T=""
	fi
else
	s "# no tracefs - running without the per-channel census"
	T=""
fi

irqs(){ awk 'NR>1 {s=0; for(i=2;i<=NF-3;i++) if ($i ~ /^[0-9]+$/) s+=$i;
	name=""; for(i=NF-2;i<=NF;i++) name=name" "$i; print $1, s, name}' /proc/interrupts | sort; }

i=1
while [ "$i" -le "$N" ]; do
	t0=$(cut -d. -f1 /proc/uptime)
	irqs > /run/.sw_irq0
	[ -n "$T" ] && { echo > $T/trace; echo 1 > $T/tracing_on; }
	rtcwake -m mem -s "$SECS" >/dev/null 2>&1
	[ -n "$T" ] && echo 0 > $T/tracing_on
	t1=$(cut -d. -f1 /proc/uptime)
	irqs > /run/.sw_irq1
	slept=$((t1 - t0))
	s ""
	s "== round $i: slept ${slept}s of $SECS, pm_wakeup_irq=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)"
	s "-- irq deltas"
	awk 'NR==FNR{a[$1]=$2; next} {d=$2-a[$1]; if (d>0) {n=""; for(k=3;k<=NF;k++) n=n" "$k; printf "   %-8s +%-6d%s\n", $1, d, n}}' \
		/run/.sw_irq0 /run/.sw_irq1 | sort -k2 -t+ -rn | head -10 >> "$O"
	if [ -n "$T" ]; then
		s "-- channels serviced (name=count)"
		sed -n 's/.*name="\([^"]*\)".*/\1/p' $T/trace | sort | uniq -c | sort -rn | head -12 >> "$O"
	fi
	sleep "$GAP"
	i=$((i + 1))
done
[ -n "$T" ] && { echo 0 > $T/events/kprobes/chan/enable 2>/dev/null; echo -n > $T/kprobe_events 2>/dev/null; }
s ""
s "# done uptime=$(cut -d. -f1 /proc/uptime)"
