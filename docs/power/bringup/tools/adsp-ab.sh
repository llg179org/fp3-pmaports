#!/bin/sh
# ADSP A/B: does a running ModemManager stop the LPASS entering XO shutdown?
# ☠️ GATE EVERY LEG on the daemon state it claims. The first attempt at this
# measured "MM running" and "MM stopped" as the same thing because the unit name
# was wrong and the stop was a no-op, and both legs printed a number.
set -u
L=/sys/kernel/debug/qcom_rpm_master_stats/LPASS
W=${1:-90}
xo(){ awk '/XO total duration/{d=$4} /XO shutdown count/{n=$4} END{print d, n}' $L; }
leg(){ # leg NAME WANT
	st=$(systemctl is-active ModemManager.service)
	if [ "$st" != "$2" ]; then
		echo "☠️ LEG $1 GATE FAILED: ModemManager is '$st', wanted '$2' - NOT a measurement"
		return 1
	fi
	echo "--- leg $1 (ModemManager=$st)"
	echo "    qrtr node1: $(qrtr-lookup 2>/dev/null | awk '$4==1' | wc -l) services"
	set -- $(xo); b=$1; bn=$2
	sleep "$W"
	set -- $(xo); a=$1; an=$2
	echo "    LPASS XO-off $(awk -v a="$a" -v b="$b" -v w="$W" 'BEGIN{printf "%.1f", (a-b)/19200000}')s of ${W}s  shutdowns +$((an - bn))"
}
leg A active || exit 1
systemctl stop ModemManager.service; sleep 20
leg B inactive
systemctl start ModemManager.service; sleep 20
leg Ap active
echo "final: ModemManager=$(systemctl is-active ModemManager.service)"
