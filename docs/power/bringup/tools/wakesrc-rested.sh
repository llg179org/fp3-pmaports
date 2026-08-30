#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# NAME what ends a RESTED phone's sleep - the one sleep that is worth naming.
#
# ☠️ WHY THE REST PERIOD IS PART OF THE INSTRUMENT. The 2026-08-22 per-channel
# census ran on back-to-back short sleeps, i.e. entirely inside the disturbed
# regime (see leads/sleep-length-is-a-state.md), and answered "IPCRTR, and the
# ring is signal-level, not messages". That may describe only what a freshly
# woken phone does. The interesting sleep is the first one after the phone has
# been left alone, because that is the one a real idle phone takes - and it is
# also the only one long enough that whatever ends it had to arrive on its own
# schedule rather than being left over from the previous resume.
#
# So: rest, then ONE traced sleep on an alarm longer than any sleep observed, and
# name the channel that serviced the interrupt that ended it.
#
# ☠️ The channel name needs a DOUBLE deref: the argument is the channel pointer
# and `name` is a char* at +0x18. A single deref prints the pointer's own bytes
# as a string, which looks like data. Needs CONFIG_KPROBE_EVENTS (r67).
#
# ☠️ Do not poll the phone while this runs - a login is a wake, and here the wake
# IS the measurement.
#
#   wakesrc-rested.sh [rest_min] [alarm_s]      default 40 1800
set -u
R=${1:-40}; S=${2:-1800}
O=/var/log/fp3/wakesrc-rested.log
T=/sys/kernel/tracing
mkdir -p /var/log/fp3
say(){ echo "$*" >> "$O"; }
: > "$O"
EDGE=$(awk '/smd-edge/ && $(NF-2)==57 {l=$1; sub(":","",l); print l}' /proc/interrupts | head -1)
say "# wakesrc-rested $(date '+%F %T') rest=${R}min alarm=${S}s  modem edge irq=${EDGE:-?}"
say "#   the alarm is longer than any sleep yet observed, so an early end is the phone's"

say "# resting ${R} min - nothing touches the phone"
sleep $((R * 60))

if [ -d "$T" ]; then
	echo 0 > $T/tracing_on; echo > $T/trace
	echo 8192 > $T/buffer_size_kb 2>/dev/null
	echo -n > $T/kprobe_events 2>/dev/null
	if echo 'p:chan qcom_smd_channel_intr name=+0x0(+0x18(%x0)):string' > $T/kprobe_events 2>/dev/null; then
		echo 1 > $T/events/kprobes/chan/enable
		say "# kprobe armed on qcom_smd_channel_intr"
	else
		say "☠️ kprobe_events refused the probe - no per-channel census this run"; T=""
	fi
else say "☠️ no tracefs"; T=""; fi

irqs(){ awk 'NR>1 {s=0; for(i=2;i<=NF-3;i++) if ($i ~ /^[0-9]+$/) s+=$i;
	n=""; for(i=NF-2;i<=NF;i++) n=n" "$i; print $1, s, n}' /proc/interrupts | sort; }
irqs > /run/.wr0
t0=$(date +%s)
[ -n "$T" ] && { echo > $T/trace; echo 1 > $T/tracing_on; }
rtcwake -m mem -s "$S" >/dev/null 2>&1
[ -n "$T" ] && echo 0 > $T/tracing_on
irqs > /run/.wr1

d=$(journalctl -k --since "@$t0" --no-pager 2>/dev/null | grep -E "PM: suspend (entry|exit)" \
    | awk '{t=$3; m=$0; sub(/.*PM: /,"",m); split(t,c,":"); s=c[1]*3600+c[2]*60+c[3];
            if (m ~ /entry/) e=s; else if (e) {print s-e; exit}}')
w=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)
say ""
say "# slept ${d:-?}s of ${S}s   pm_wakeup_irq=${w:-?}$([ "${w:-}" = "${EDGE:-x}" ] && echo '  <= THE MODEM EDGE')"
[ "${d:-0}" -ge $((S - 5)) ] 2>/dev/null && say "# ☠️ it hit the alarm - this is a FLOOR, re-run with a longer one"
say "-- irq deltas over the sleep"
awk 'NR==FNR{a[$1]=$2; next} {v=$2-a[$1]; if (v>0) {n=""; for(k=3;k<=NF;k++) n=n" "$k; printf "   %-8s +%-6d%s\n", $1, v, n}}' \
	/run/.wr0 /run/.wr1 | sort -k2 -t+ -rn | head -12 >> "$O"
if [ -n "$T" ]; then
	say "-- channels serviced during the sleep (name=count)"
	sed -n 's/.*name="\([^"]*\)".*/\1/p' $T/trace | sort | uniq -c | sort -rn | head -15 >> "$O"
	say "-- the LAST few channel events before the wake (the tail is the wake itself)"
	grep -o 'name="[^"]*"' $T/trace | tail -8 | sed 's/^/   /' >> "$O"
	echo 0 > $T/events/kprobes/chan/enable 2>/dev/null; echo -n > $T/kprobe_events 2>/dev/null
fi
say "# done $(date '+%F %T')"
