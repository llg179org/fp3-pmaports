#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# WHAT DOES THE AP ASK THE MODEM WHILE NOTHING IS HAPPENING?
#
# wake-qmi.sh asks which QMI message ENDS A SLEEP. This asks a different
# question on the other side of the same probe: over a quiet AWAKE window, what
# QRTR traffic is there at all, in both directions, and does any of it recur at
# the rate the modem is waking?
#
# It exists because the radio-configuration fork closed: four different mode
# preferences on one cell give the same duty, so the modem's long wakes are not
# radio-side configuration. The remaining shape is that the modem's extra time
# per wake CONTAINS THE AP - it asks for something and waits. The candidate
# nobody here has ever looked at is rmtfs: on mainline the modem's EFS reads and
# writes are served by an AP daemon over QRTR, where the vendor stack has its
# own tuned rmt_storage. So this also prices rmtfs directly, from its own CPU
# time, which costs nothing and needs no probe at all.
#
# ☠️ DO NOT LOG IN WHILE IT RUNS. An ssh login is AP traffic and modem traffic,
# and the quiet is the measurement. Start it under systemd-run and leave.
#
# ☠️ THE RX DECODE IS VALIDATED, THE TX DECODE IS NOT, AND THE FILE SAYS WHICH.
# The +0x20/+0x23 offsets into `data` are read from net/qrtr/af_qrtr.c and
# libqmi's qmi-message.c and are checked here by reading `ver` - a line with
# ver!=1 is a different header size and its decode is garbage. For the transmit
# side, qrtr_node_enqueue's argument layout was NOT verified against source, so
# this arms it as a COUNTER ONLY. A count is honest; a decoded field from an
# unverified offset is a fabricated fact that looks like a measurement.
#
#   qmi-census-awake.sh [seconds]        default 300
set -u
S=${1:-300}
T=/sys/kernel/tracing
O=${QMI_CENSUS_LOG:-/var/log/fp3/qmi-census-awake.log}
IDS_SVC=$(dirname "$0")/qmi-service-ids.txt
IDS=$(dirname "$0")/qmi-msgids.txt
mkdir -p /var/log/fp3
say(){ echo "$*" >> "$O"; }
: > "$O"
say "# qmi-census-awake $(date '+%F %T') window=${S}s"
say "#   modem: $(mmcli -m any 2>/dev/null | sed -n 's/.*state: *//p' | head -1)"
say "#   band/cell: $(/usr/local/bin/leg-covariates.sh census 2>/dev/null | sed 's/^#   //')"

[ -d "$T" ] || { say "☠️ no tracefs"; exit 1; }
echo 0 > $T/tracing_on; echo > $T/trace
echo 16384 > $T/buffer_size_kb 2>/dev/null

# ☠️ A killed run leaves the instrument armed and kprobe_events cannot be cleared
# while anything in it is enabled (EBUSY), so a later run silently arms nothing
# and returns an empty capture that reads as a quiet phone. Disable, clear, and
# say whether the clear worked. This trap has fired here before.
for e in "$T"/events/kprobes/*/enable; do [ -e "$e" ] && echo 0 > "$e" 2>/dev/null; done
if echo -n > $T/kprobe_events 2>/dev/null; then
	say "# tracefs clean"
else
	say "☠️ COULD NOT CLEAR kprobe_events - aborting rather than measuring nothing:"
	say "   leftovers: $(tr '\n' ';' < $T/kprobe_events 2>/dev/null | cut -c1-200)"
	exit 1
fi

ARMED=""
# RX: modem -> AP. Offsets validated in wake-qmi.sh against af_qrtr.c/qmi-message.c.
if echo 'p:qmirx qrtr_endpoint_post ver=+0x0(%x1):u32 src_port=+0xc(%x1):u32 dst_port=+0x1c(%x1):u32 fl=+0x20(%x1):u8 msg=+0x23(%x1):u16' >> $T/kprobe_events 2>/dev/null; then
	echo 1 > $T/events/kprobes/qmirx/enable && ARMED="$ARMED rx"; fi
# TX: AP -> modem. COUNT ONLY - see the header. No fields, on purpose.
if echo 'p:qmitx qrtr_node_enqueue' >> $T/kprobe_events 2>/dev/null; then
	echo 1 > $T/events/kprobes/qmitx/enable && ARMED="$ARMED tx(count-only)"; fi
say "# probes armed:${ARMED:- NONE - the rest of this file is meaningless}"
[ -n "$ARMED" ] || exit 1

QL=/tmp/fp3-qrtr.$$; qrtr-lookup > "$QL" 2>/dev/null
PORTMAP=/tmp/fp3-portmap.$$; : > "$PORTMAP"
awk 'NR>1 && $1 ~ /^[0-9]+$/ && $5 ~ /^[0-9]+$/ {print $5, $1}' "$QL" 2>/dev/null |
while read -r port svc; do
	nm=$(awk -v s="$svc" '$1==s {print $2; exit}' "$IDS_SVC" 2>/dev/null)
	echo "$port ${nm:-svc$svc}" >> "$PORTMAP"
done
say "# ports mapped: $(grep -c . "$PORTMAP" 2>/dev/null || echo 0)"

# rmtfs, priced from its own CPU time - no probe, no perturbation
rm_pid=$(pgrep -x rmtfs 2>/dev/null | head -1)
rmcpu(){ [ -n "$rm_pid" ] && awk '{print $14+$15}' /proc/$rm_pid/stat 2>/dev/null || echo ""; }
HZ=$(getconf CLK_TCK 2>/dev/null || echo 100)
rm0=$(rmcpu)
xo0=$(awk '/XO total duration:/{printf "%.0f", $4}' /sys/kernel/debug/qcom_rpm_master_stats/MPSS)

echo 1 > $T/tracing_on
sleep "$S"
echo 0 > $T/tracing_on

rm1=$(rmcpu)
xo1=$(awk '/XO total duration:/{printf "%.0f", $4}' /sys/kernel/debug/qcom_rpm_master_stats/MPSS)
say ""
say "-- MPSS over the window: $(awk -v a="$xo1" -v b="$xo0" -v w="$S" 'BEGIN{printf "%.1f%% awake", 100*(1-(a-b)/19200000/w)}')"
if [ -n "$rm0" ] && [ -n "$rm1" ]; then
	say "-- rmtfs (pid $rm_pid) CPU over the window: $(awk -v a="$rm1" -v b="$rm0" -v h="$HZ" -v w="$S" 'BEGIN{printf "%.2f s (%.3f%% of one core)", (a-b)/h, 100*(a-b)/h/w}')"
else
	say "-- ☠️ rmtfs not found or /proc unreadable - NOT the same as 'rmtfs is idle'"
fi

say ""
say "-- RX (modem -> AP), by port/service, message id and kind"
awk '/qmirx:/ {
       for (i=1;i<=NF;i++) {
         if ($i ~ /^ver=/)      { split($i,a,"="); v=a[2] }
         if ($i ~ /^src_port=/) { split($i,a,"="); sp=a[2] }
         if ($i ~ /^fl=/)       { split($i,a,"="); f=a[2] }
         if ($i ~ /^msg=/)      { split($i,a,"="); m=a[2] }
       }
       if (v+0 != 1) { bad++; next }
       # ☠️ NO strtonum() ON THIS DEVICE. busybox/mawk here defines and() but not
       # strtonum, and an undefined function does not warn in the middle of a
       # pipeline - it aborts the whole awk, which printed an EMPTY table that
       # read exactly like "no QMI traffic". Measured: the smoke run reported
       # three RX messages and then listed none of them. The kprobe prints these
       # fields in DECIMAL anyway (ver=1 src_port=41 fl=4 msg=81), so no base
       # conversion was ever needed. Plain integer arithmetic, no extensions.
       k = (int(f/4) % 2 ? "ind" : (int(f/2) % 2 ? "resp" : "req"))
       n[sp" "m" "k]++
     }
     END { for (x in n) printf "%6d  %s\n", n[x], x
           if (bad) printf "☠️ %d lines with ver!=1 - DISCARDED, not decoded\n", bad }' \
    $T/trace | sort -rn |
while read -r cnt port msg kind; do
	svc=$(awk -v p="$port" '$1==p {print $2; exit}' "$PORTMAP")
	# the id is unique only WITHIN a service, so print every name that claims it
	# ☠️ Fields are "SERVICE DECIMAL HEX Name...": the decimal id is field 2, and
	# matching it against field 1 (the service name) matches nothing at all -
	# every line then reads "<not in libqmi>", which looks like a libqmi gap and
	# is a units bug. The id is unique only within a service, so print each
	# service that claims it and let the port say which one this was.
	nm=$(awk -v m="$msg" '$2==m { s=$4; for (i=5;i<=NF;i++) s=s" "$i;
	        printf "%s%s:%s", (n++ ? " | " : ""), $1, s } END{print ""}' "$IDS" 2>/dev/null)
	say "$(printf '%6s  %-28s msg=%-6s %-5s %s' "$cnt" "${svc:-port$port}" "$msg" "$kind" "${nm:-<not in libqmi>}")"
done

# ☠️ NOT `grep -c ... || echo 0`: grep exits 1 on zero matches, so the fallback
# APPENDS a second line and the variable becomes "0\n0", which then prints as a
# count split across two lines. It did exactly that on the smoke run.
txn=$(grep -c 'qmitx:' $T/trace 2>/dev/null); txn=${txn:-0}
rxn=$(grep -c 'qmirx:' $T/trace 2>/dev/null); rxn=${rxn:-0}
say ""
say "-- totals: RX $rxn ($(awk -v n="$rxn" -v w="$S" 'BEGIN{printf "%.2f", n/w}')/s), TX $txn ($(awk -v n="$txn" -v w="$S" 'BEGIN{printf "%.2f", n/w}')/s)"
say "☠️ TX is a raw probe-hit count: qrtr_node_enqueue's argument layout was not"
say "   verified against source, so no field of it is decoded and none is quoted."

for e in "$T"/events/kprobes/*/enable; do [ -e "$e" ] && echo 0 > "$e" 2>/dev/null; done
echo -n > $T/kprobe_events 2>/dev/null
rm -f "$QL" "$PORTMAP"
say "# done $(date '+%F %T'); probes disarmed"
