#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# Is the thing that ends every sleep coming FROM THE NETWORK, or from the modem
# itself?
#
# ☠️ WHY THIS IS THE CONTROL THAT MATTERS NOW. The recovery hypothesis is dead:
# resting 2/5/10/20/40 minutes gave 22/6/3/6/3 s, all ended by the modem edge, so
# leaving the phone alone changes nothing. What DOES differ is the time of day -
# at 02:30 and 05:15 this phone slept its full 300 s and 240 s alarms, and
# through the whole morning it never reached 43 s. Network-side traffic (paging,
# broadcast, neighbour activity) is diurnal; the modem's own housekeeping is not.
#
# One leg with the radio off separates them, and nothing else does:
#   radio off, still sleeps badly -> the modem generates it; the network is out
#   radio off, sleeps long        -> it comes from the network, and 3GPP power
#                                    save (PSM/eDRX) becomes the lever rather
#                                    than anything on our side
#
# ☠️ Not a modem restart: mmcli --disable leaves the processor up and the driver
# bound. Restarting the remoteproc costs audio until the next reboot and oopses
# the kernel on the next mixer write.
#
#   radio-off-sleep.sh [alarm_s]      default 1800
set -u
S=${1:-1800}
O=/var/log/fp3/radio-off-sleep.log
mkdir -p /var/log/fp3
say(){ echo "$*" >> "$O"; }
: > "$O"
EDGE=$(awk '/smd-edge/ && $(NF-2)==57 {l=$1; sub(":","",l); print l}' /proc/interrupts | head -1)
say "# radio-off-sleep $(date '+%F %T') alarm=${S}s edge=${EDGE:-?}"

leg(){ # $1 = label
	t0=$(date +%s)
	rtcwake -m mem -s "$S" >/dev/null 2>&1
	d=$(journalctl -k --since "@$t0" --no-pager 2>/dev/null | grep -E "PM: suspend (entry|exit)" \
	    | awk '{t=$3; m=$0; sub(/.*PM: /,"",m); split(t,c,":"); s=c[1]*3600+c[2]*60+c[3];
	            if (m ~ /entry/) e=s; else if (e) {print s-e; exit}}')
	w=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)
	if [ "${d:-0}" -ge $((S - 10)) ] 2>/dev/null; then by="THE ALARM - slept the whole window"
	elif [ "${w:-}" = "${EDGE:-x}" ];         then by="modem edge"
	else                                           by="irq ${w:-?}"; fi
	printf '%-12s %7ss of %ss   %s\n' "$1" "${d:-?}" "$S" "$by" >> "$O"
}

say "#   modem before: $(mmcli -m any 2>/dev/null | sed -n 's/.*state: *//p' | head -1)"
leg "A radio-on"

mmcli -m any --disable >/dev/null 2>&1
sleep 20
say "#   modem after disable: $(mmcli -m any 2>/dev/null | sed -n 's/.*state: *//p' | head -1)"
leg "B radio-off"

mmcli -m any --enable >/dev/null 2>&1
sleep 30
say "#   modem re-enabled: $(mmcli -m any 2>/dev/null | sed -n 's/.*state: *//p' | head -1)"
leg "A' radio-on"
say "# done $(date '+%F %T')"
