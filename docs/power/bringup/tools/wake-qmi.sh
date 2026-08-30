#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# WHICH QMI MESSAGE ends the sleep? - one layer below wake-service.sh.
#
# wake-service.sh named the SERVICE (the QRTR src_port: NAS=40, DSD=52, Voice=39
# on the run of 2026-08-30). That was enough to show call and noise are
# separable, and it is NOT enough to decide what to do about the noise, because
# the two possible causes need opposite fixes:
#
#   * the modem sends the indication unsolicited  -> only a kernel-side filter
#     can stop it waking us (leads/selective-smd-wakeup.md);
#   * ModemManager SUBSCRIBED to it (NAS 0x0003 "Register Indications",
#     WMS 0x0047 "Indication Register") -> unregistering is a USERSPACE fix,
#     needs no kernel patch at all, and is reversible over ssh.
#
# The message id is what separates those, so fetch it.
#
# LAYOUT, read from source, not from memory:
#   struct qrtr_hdr_v1 (net/qrtr/af_qrtr.c:39) is 8 x __le32 = 32 bytes = 0x20,
#   so the QMI SDU begins at +0x20 of `data` (= %x1, the 2nd arg of
#   qrtr_endpoint_post). Over QRTR there is no QMUX header - libqmi says so in
#   as many words at src/libqmi-glib/qmi-message.c:82 ("This is not a real
#   header in QRTR messages") - so the SDU starts directly with
#   struct service_header (same file, :99):
#       +0x20 flags (u8)   +0x21 transaction (u16 LE)
#       +0x23 message (u16 LE)   +0x25 tlv_length (u16 LE)
#   flags bit 2 (0x04) = indication (QMI_SERVICE_FLAG_INDICATION,
#   qmi-enums-private.h:83); 0x02 = response; 0x00 = request.
#
# ☠️ The offsets above are valid for the v1 header ONLY, so the probe also reads
#    `ver`. If any line shows ver!=1 the message decode in that round is garbage
#    and must be thrown away, not interpreted - the v2 header is a different
#    size (af_qrtr.c:51). Do not assume v1 because a previous run looked sane.
#
# ☠️ Do not poll the phone while this runs - a login is a wake, and the wake IS
#    the measurement.
#
# VALIDATED before first use, against a synthetic trace in the kprobe's own
# output format (legitimate here: the format string is fixed by this script, and
# the part under test is the decode, not the capture). It caught a real bug -
# the first table stored ids as hex only while the kprobe prints decimal, so
# EVERY line read "<not in libqmi>". That failure is indistinguishable from
# "libqmi has no definition for these" and would have been believed.
#
#   wake-qmi.sh [alarm_s] [rounds] [rtcwake|logind]     default 600 3 logind
set -u
S=${1:-600}; N=${2:-3}; P=${3:-logind}
O=/var/log/fp3/wake-qmi.log
IDS=$(dirname "$0")/qmi-msgids.txt
T=/sys/kernel/tracing
mkdir -p /var/log/fp3
say(){ echo "$*" >> "$O"; }
: > "$O"
EDGE=$(awk '/smd-edge/ && $(NF-2)==57 {l=$1; sub(":","",l); print l}' /proc/interrupts | head -1)
say "# wake-qmi $(date '+%F %T') alarm=${S}s rounds=$N path=$P edge=${EDGE:-?}"
say "#   ExecStart: $(systemctl show ModemManager -p ExecStart --value | sed 's/.*argv\[\]=//; s/ ;.*//')"
say "#   modem: $(mmcli -m any 2>/dev/null | sed -n 's/.*state: *//p' | head -1)"
[ -r "$IDS" ] && say "#   msgid table: $IDS ($(grep -c . "$IDS") lines)" \
              || say "#   ☠️ no msgid table at $IDS - ids stay numeric"

[ -d "$T" ] || { say "☠️ no tracefs"; exit 1; }
echo 0 > $T/tracing_on; echo > $T/trace
echo 16384 > $T/buffer_size_kb 2>/dev/null
echo -n > $T/kprobe_events 2>/dev/null

ARMED=""
if echo 'p:qmi qrtr_endpoint_post ver=+0x0(%x1):u32 ty=+0x4(%x1):u32 src_port=+0xc(%x1):u32 dst_port=+0x1c(%x1):u32 fl=+0x20(%x1):u8 msg=+0x23(%x1):u16' >> $T/kprobe_events 2>/dev/null; then
	echo 1 > $T/events/kprobes/qmi/enable; ARMED="$ARMED qmi"; fi
say "# probes armed:${ARMED:- NONE - the rest of this file is meaningless}"
[ -n "$ARMED" ] || exit 1

# port -> service, so a number can be resolved afterwards instead of guessed
say "-- qrtr services at start (service:instance node:port)"
qrtr-lookup 2>/dev/null | sed 's/^/   /' | head -40 >> "$O"

# stdin: "count src_port msgid flags". The id is unique only WITHIN a service,
# so print EVERY service that defines it and let the port (via qrtr-lookup
# above) disambiguate - picking one silently would be a guess dressed as a
# decode. ☠️ Field 2 of the table is the DECIMAL id because the kprobe prints
# decimal; matching against the hex column instead makes every line read
# "<not in libqmi>", which looks like missing definitions and is a units bug.
decode() {
	while read -r c sp msg fl; do
		case $((fl & 4)) in 4) k=IND;; *) case $((fl & 2)) in 2) k=RSP;; *) k=REQ;; esac;; esac
		# an id repeats across services, so narrow by what the flags already
		# settled - an IND can only be an Indication - and leave the rest of the
		# disambiguation to the port, using the qrtr-lookup block above.
		[ "$k" = IND ] && want=Indication || want=Message
		nm=""
		[ -r "$IDS" ] && nm=$(awk -v m="$msg" -v w="$want" '$2==m && $4==w {
			printf "%s%s:", (n++?" | ":""), $1; for(i=5;i<=NF;i++) printf " %s", $i} END{print ""}' "$IDS")
		printf '   %5d  src_port=%-6s %s  msg=%s  %s\n' "$c" "$sp" "$k" "$msg" "${nm:-<not in libqmi>}"
	done
}

r=1
while [ $r -le $N ]; do
	echo > $T/trace; echo 1 > $T/tracing_on
	t0=$(date +%s)
	if [ "$P" = logind ]; then
		rtcwake -m no -s "$S" >/dev/null 2>&1
		s0=$(cat /sys/power/suspend_stats/success)
		systemctl suspend
		_w=0; while [ "$(cat /sys/power/suspend_stats/success)" = "$s0" ] && [ $_w -lt 45 ]; do sleep 1; _w=$((_w + 1)); done
		sleep 8
	else
		rtcwake -m mem -s "$S" >/dev/null 2>&1
	fi
	# ☠️ THE MARKER IS WHAT MAKES THIS A MEASUREMENT OF THE SLEEP.
	# Tracing stays on across the resume, so everything the buffer holds is
	# "during the sleep OR just after it" - and the just-after part is not small
	# (a resume produces hundreds of rpm_requests within a second). A census that
	# does not split there will report post-wake traffic as the traffic that
	# arrived while asleep, which is the opposite of what it is for. Write the
	# marker before anything else, then cut the trace at it.
	echo RESUMED > $T/trace_marker 2>/dev/null
	echo 0 > $T/tracing_on
	d=$(journalctl -k --since "@$t0" --no-pager 2>/dev/null | grep -E "PM: suspend (entry|exit)" \
	    | awk '{t=$3; m=$0; sub(/.*PM: /,"",m); split(t,c,":"); s=c[1]*3600+c[2]*60+c[3];
	            if (m ~ /entry/) e=s; else if (e) {print s-e; exit}}')
	w=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)
	say ""
	say "== round $r: slept ${d:-?}s of ${S}s  pm_wakeup_irq=${w:-?}$([ "${w:-}" = "${EDGE:-x}" ] && echo '  <= modem edge')"
	bad=$(grep -c 'ver=[^1]' $T/trace 2>/dev/null || echo 0)
	[ "${bad:-0}" -gt 0 ] && say "   ☠️ $bad lines with ver!=1 - their decode is GARBAGE, do not interpret"
	ctl=$(grep -c 'ver=1 ty=[^1]' $T/trace 2>/dev/null || echo 0)
	say "   (QRTR control packets excluded from the decode: ${ctl:-0}; they carry no QMI SDU)"
	# everything up to the marker is the sleep; everything after it is the resume
	# ☠️ /tmp, NOT under $T - tracefs is not a writable filesystem.
	SLEPT=/tmp/fp3-trace-slept.$$
	awk '/tracing_mark_write: RESUMED/{exit} {print}' $T/trace > "$SLEPT" 2>/dev/null || cp $T/trace "$SLEPT"
	if ! grep -q 'RESUMED' $T/trace 2>/dev/null; then
		say "   ☠️ no RESUMED marker in the trace - the split did not happen, so the"
		say "      counts below include post-wake traffic and must NOT be read as"
		say "      'what arrived while asleep'."
	else
		say "   (trace split at the resume marker: $(grep -c . "$SLEPT") of $(grep -c . $T/trace) lines are from the sleep)"
	fi
	say "-- QMI messages seen WHILE ASLEEP (count / port / kind / id / name)"
	# require ver=1 AND ty=1: the offsets are v1-only, and only QRTR_TYPE_DATA
	# (include/uapi/linux/qrtr.h:18) carries a QMI SDU - a control packet's
	# payload is a router command, so decoding it as a QMI header yields a
	# plausible-looking message id for a message that was never sent.
	sed -n 's/.*ver=1 ty=1 src_port=\([0-9]*\).*fl=\([0-9]*\) msg=\([0-9]*\).*/\1 \3 \2/p' "$SLEPT" \
		| sort | uniq -c | sort -rn | head -14 | decode >> "$O"
	say "-- terse lines this round: $(journalctl -u ModemManager --since "@$t0" --no-pager 2>/dev/null | grep -ci terse)"
	rm -f "$SLEPT"
	sleep 15
	r=$((r + 1))
done
echo 0 > $T/events/kprobes/qmi/enable 2>/dev/null
echo -n > $T/kprobe_events 2>/dev/null
say "# done $(date '+%F %T')"
