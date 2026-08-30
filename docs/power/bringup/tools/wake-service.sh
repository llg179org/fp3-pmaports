#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# WHICH SERVICE's traffic ends the sleep?
#
# ☠️ THE QUESTION CHANGED, SO THE INSTRUMENT HAS TO. The 2026-08-22 census
# answered at the CHANNEL layer - "IPCRTR, and the ring is signal-level" - which
# was as far as that layer can see, and it closed several candidates on that
# basis. Two things have happened since: that census ran on back-to-back short
# sleeps, and the radio-off control (radio on 8 s, radio off 1802 s of 1800, radio
# on 33 s) established that what ends a sleep arrives FROM THE NETWORK. Both the
# noise and an incoming call come over IPCRTR, so naming the channel cannot
# separate them and naming the SERVICE might.
#
# Two probes, and the script says which of them actually armed - a probe that
# never attached is silence, and silence has been misread as data three times on
# this front:
#   1. qrtr_port_lookup(int port)  - the local port the packet is delivered to.
#      static, so it may be inlined; if kprobe_events refuses it, that is the
#      answer, not a failure to report.
#   2. qrtr_endpoint_post(ep, data, len) - the header, before delivery. From
#      struct qrtr_hdr_v1 (net/qrtr/af_qrtr.c:39), all __le32 and __packed:
#        +0x00 version  +0x04 type      +0x08 src_node  +0x0c src_port
#        +0x10 confirm  +0x14 size      +0x18 dst_node  +0x1c dst_port
#      `data` is the second argument, %x1.
#
# ☠️ Do not poll the phone while this runs - a login is a wake, and the wake IS
# the measurement.
#
# ☠️ THE SUSPEND PATH IS PART OF THE MEASUREMENT, NOT A DETAIL. `rtcwake -m mem`
# writes /sys/power/state directly and never reaches logind, so ModemManager is
# never told to go terse - which means a census taken that way describes the
# NON-terse state. The first run of this script did exactly that and its NAS/DSD
# result is therefore about a modem nobody had quieted. Running the same census
# down the logind path answers the sharper question: does terse actually remove
# those indications? If it does, the puzzle moves to why it bought no residency.
#
#   wake-service.sh [alarm_s] [rounds] [rtcwake|logind]   default 600 3 rtcwake
set -u
S=${1:-600}; N=${2:-3}; P=${3:-rtcwake}
O=/var/log/fp3/wake-service.log
T=/sys/kernel/tracing
mkdir -p /var/log/fp3
say(){ echo "$*" >> "$O"; }
: > "$O"
EDGE=$(awk '/smd-edge/ && $(NF-2)==57 {l=$1; sub(":","",l); print l}' /proc/interrupts | head -1)
say "# wake-service $(date '+%F %T') alarm=${S}s rounds=$N path=$P edge=${EDGE:-?}"
say "#   ExecStart: $(systemctl show ModemManager -p ExecStart --value | sed 's/.*argv\[\]=//; s/ ;.*//')"
say "#   modem: $(mmcli -m any 2>/dev/null | sed -n 's/.*state: *//p' | head -1)"

[ -d "$T" ] || { say "☠️ no tracefs"; exit 1; }
echo 0 > $T/tracing_on; echo > $T/trace
echo 16384 > $T/buffer_size_kb 2>/dev/null
echo -n > $T/kprobe_events 2>/dev/null

ARMED=""
if echo 'p:chan qcom_smd_channel_intr name=+0x0(+0x18(%x0)):string' >> $T/kprobe_events 2>/dev/null; then
	echo 1 > $T/events/kprobes/chan/enable; ARMED="$ARMED chan"; fi
if echo 'p:port qrtr_port_lookup port=%x0:u32' >> $T/kprobe_events 2>/dev/null; then
	echo 1 > $T/events/kprobes/port/enable; ARMED="$ARMED port"; fi
if echo 'p:hdr qrtr_endpoint_post type=+0x4(%x1):u32 src_node=+0x8(%x1):u32 src_port=+0xc(%x1):u32 dst_node=+0x18(%x1):u32 dst_port=+0x1c(%x1):u32' >> $T/kprobe_events 2>/dev/null; then
	echo 1 > $T/events/kprobes/hdr/enable; ARMED="$ARMED hdr"; fi
say "# probes armed:${ARMED:- NONE - the rest of this file is meaningless}"
[ -n "$ARMED" ] || exit 1

# the name service maps service ids to ports; capture it so a port number can be
# turned into a service afterwards rather than guessed
say "-- qrtr services at start (service:instance node:port)"
qrtr-lookup 2>/dev/null | sed 's/^/   /' | head -30 >> "$O"

r=1
while [ $r -le $N ]; do
	echo > $T/trace; echo 1 > $T/tracing_on
	t0=$(date +%s)
	if [ "$P" = logind ]; then
		rtcwake -m no -s "$S" >/dev/null 2>&1        # arm the alarm, do not suspend
		s0=$(cat /sys/power/suspend_stats/success)
		systemctl suspend
		_w=0; while [ "$(cat /sys/power/suspend_stats/success)" = "$s0" ] && [ $_w -lt 45 ]; do sleep 1; _w=$((_w + 1)); done
		sleep 8    # execution resumes when the phone is awake; give the resume a moment
	else
		rtcwake -m mem -s "$S" >/dev/null 2>&1
	fi
	echo 0 > $T/tracing_on
	d=$(journalctl -k --since "@$t0" --no-pager 2>/dev/null | grep -E "PM: suspend (entry|exit)" \
	    | awk '{t=$3; m=$0; sub(/.*PM: /,"",m); split(t,c,":"); s=c[1]*3600+c[2]*60+c[3];
	            if (m ~ /entry/) e=s; else if (e) {print s-e; exit}}')
	w=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)
	say ""
	say "== round $r: slept ${d:-?}s of ${S}s  pm_wakeup_irq=${w:-?}$([ "${w:-}" = "${EDGE:-x}" ] && echo '  <= modem edge')"
	say "-- channels serviced"
	sed -n 's/.*name="\([^"]*\)".*/\1/p' $T/trace | sort | uniq -c | sort -rn | head -8 >> "$O"
	say "-- QRTR headers seen (the answer, if any arrived)"
	grep -o 'type=[0-9]* src_node=[0-9]* src_port=[0-9]* dst_node=[0-9]* dst_port=[0-9]*' $T/trace \
		| sort | uniq -c | sort -rn | head -12 | sed 's/^/   /' >> "$O"
	say "-- terse lines in this round: $(journalctl -u ModemManager --since "@$t0" --no-pager 2>/dev/null | grep -ci terse)"
	say "-- local ports looked up"
	grep -o 'port=[0-9]*' $T/trace | sort | uniq -c | sort -rn | head -8 | sed 's/^/   /' >> "$O"
	# ☠️ NOT "the wake itself": tracing stays on across the resume, so this tail is
	# POST-wake traffic - which is why it reads as all rpm_requests, the RPM's edge
	# rather than the modem's. Kept as context only; the witnesses are
	# pm_wakeup_irq and the QRTR headers above.
	say "-- last trace lines (POST-wake traffic, context only - not the wake)"
	tail -6 $T/trace | sed 's/^/   /' >> "$O"
	sleep 15
	r=$((r + 1))
done

for p in chan port hdr; do echo 0 > $T/events/kprobes/$p/enable 2>/dev/null; done
echo -n > $T/kprobe_events 2>/dev/null
say "# done $(date '+%F %T')"
