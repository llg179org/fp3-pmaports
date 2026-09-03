#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# A-B-A' on the wlan radio, to test whether the awake current burst is WiFi
# sitting in receive.
#
# ☠️ WHY THIS AFTER THE PACKET COUNTER SAID NOTHING. burst-attrib records
# `wlan_pps` and it is flat across the burst - 2 vs 2. That excludes wlan TRAFFIC
# and excludes nothing else, because a radio with power-save off stays in receive
# whether or not a packet ever arrives. Packets are what the interface is asked to
# carry; power is what the radio spends listening. Reading the first as the second
# is exactly the kind of one-layer measurement that has already misled this
# investigation twice.
#
# The trace also put `ieee80211_dynamic_ps_timer` in the window, so the mac80211
# power-save machinery is at least running - which does not say it is winning.
#
# ☠️ CHECK WHICH LINK YOUR SESSION IS ON BEFORE RUNNING THIS. This phone has two
# (USB 172.16.42.1 and wlan 192.168.x.x) and taking the radio down over the
# wlan one strands the run. `ss -tnp | grep :22` answers it; this script refuses
# to start if it can see its own ssh session on the wlan address.
#
#   burst-wlan-ab.sh [window_s]        (default 360)
set -u
W=${1:-360}
OUT=/var/log/fp3/burst-wlan-ab-$(date +%s)
mkdir -p "$OUT"
say(){ echo "$*" | tee -a "$OUT/log"; }

command -v nmcli >/dev/null || { say "# STOP: no nmcli"; exit 1; }

WADDR=$(ip -4 -o addr show wlan0 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
if [ -n "$WADDR" ] && ss -tn 2>/dev/null | grep -q "$WADDR:22 "; then
	say "# STOP: this session is on the wlan link ($WADDR) - taking the radio down would strand the run"
	exit 1
fi

state(){ printf '%s/%s' "$(nmcli radio wifi 2>/dev/null)" "$(cat /sys/class/net/wlan0/operstate 2>/dev/null)"; }
restore(){ nmcli radio wifi on >/dev/null 2>&1; }
trap 'say "# signal caught - re-enabling wlan"; restore; exit 143' INT TERM HUP
trap 'restore' EXIT

say "# burst-wlan-ab $(date '+%F %T') window=${W}s wlan-addr=${WADDR:-none}"
say "# kernel=$(uname -r) $(uname -v)"

leg(){
	say "# $1 begin: wlan=$(state) $(date '+%T')"
	/usr/local/bin/burst-attrib.sh "$W" >/dev/null 2>&1 || true
	d=$(ls -td /var/log/fp3/burst-attrib-* 2>/dev/null | head -1)
	if [ -n "$d" ]; then
		mkdir -p "$OUT/$1"
		cp "$d/attrib.txt" "$d/current.txt" "$d/log" "$OUT/$1/" 2>/dev/null
		say "# $1 done: $(grep -vc '^#' "$OUT/$1/attrib.txt") samples <- $d"
	else
		say "# $1 produced nothing"
	fi
	say "# $1 end:   wlan=$(state)"
}

leg A
nmcli radio wifi off >/dev/null 2>&1
sleep 10
st=$(state)
say "# wlan disabled -> $st"
case "$st" in
disabled/*) ;;
*) say "# STOP: wlan did not go down ($st) - refusing to call the next leg 'off'"; exit 1 ;;
esac
leg B
nmcli radio wifi on >/dev/null 2>&1
sleep 20
say "# wlan re-enabled -> $(state)"
leg Ap
say "# done: $OUT"
