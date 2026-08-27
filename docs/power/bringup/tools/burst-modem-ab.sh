#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# A-B-A' on the modem's RF, to test whether the awake current burst is the radio.
#
# ☠️ WHY THE MODEM AND WHY NOW. Two instruments have already answered "not me".
# burst-source.sh traced every workqueue and timer while the current swung 7x and
# found the SAME event rate in burst bins and quiet bins (313 vs 316 per 5 s).
# burst-attrib.sh then measured the machine itself and found, across a 9x swing:
# CPU-busy 1 % vs 1 %, power-collapse residency 99 % vs 100 %, wake rate 77/s vs
# 77/s, both cpufreq policies pinned identically, wlan 2 pps vs 2 pps. Whatever
# spends the power is not running code and is not the CPU. On this phone the
# things that can draw hundreds of milliamps without waking a CPU are short: the
# panel (proven dark and re-proven every sample), wlan (flat above), and the
# MODEM, which is also already known as the thing that terminates every suspend
# (IRQ 141, the SMD edge). That is the candidate this tests.
#
# ☠️ THE MODEM IS DISABLED, NOT RESTARTED. Stopping or restarting the modem
# remoteproc costs audio until the next reboot on this device, and a mixer write
# afterwards oopses the kernel. `mmcli --disable` powers the RF down and leaves
# the remoteproc running, and `--enable` puts it back. Nothing here writes to
# /sys/class/remoteproc.
#
# ☠️ AND IT IS A-B-A', NOT A-B. Three legs, because this pack's floor drifts with
# state of charge and a two-leg subtraction cannot tell a real effect from that
# drift. If A and A' do not agree, the run says nothing and must be repeated.
#
#   burst-modem-ab.sh [window_s]        (default 360)
set -u
W=${1:-360}
OUT=/var/log/fp3/burst-modem-ab-$(date +%s)
mkdir -p "$OUT"
say(){ echo "$*" | tee -a "$OUT/log"; }

command -v mmcli >/dev/null || { say "# STOP: no mmcli"; exit 1; }
M=$(mmcli -L 2>/dev/null | sed -n 's#.*/Modem/\([0-9]*\).*#\1#p' | head -1)
[ -n "$M" ] || { say "# STOP: ModemManager lists no modem - nothing to A/B"; exit 1; }

state(){ mmcli -m "$M" 2>/dev/null | sed -n 's/.*state: *\([a-z-]*\).*/\1/p' | head -1; }
restore(){ mmcli -m "$M" --enable >/dev/null 2>&1; }
trap 'say "# signal caught - re-enabling the modem"; restore; exit 143' INT TERM HUP
trap 'restore' EXIT

say "# burst-modem-ab $(date '+%F %T') window=${W}s modem=$M"
say "# kernel=$(uname -r) $(uname -v)"

leg(){ # leg <name> <label>
	say "# $1 begin: modem-state=$(state) $(date '+%T')"
	/usr/local/bin/burst-attrib.sh "$W" >/dev/null 2>&1 || true
	d=$(ls -td /var/log/fp3/burst-attrib-* 2>/dev/null | head -1)
	if [ -n "$d" ]; then
		mkdir -p "$OUT/$1"
		cp "$d/attrib.txt" "$d/current.txt" "$d/log" "$OUT/$1/" 2>/dev/null
		say "# $1 done: $(grep -vc '^#' "$OUT/$1/attrib.txt") samples <- $d"
	else
		say "# $1 produced nothing"
	fi
	say "# $1 end:   modem-state=$(state)"
}

leg A
mmcli -m "$M" --disable >/dev/null 2>&1
sleep 10
st=$(state)
say "# modem disabled -> state=$st"
case "$st" in
disabled|disabling) ;;
*) say "# STOP: the modem did not disable (state=$st) - refusing to call the next leg 'off'"; exit 1 ;;
esac
leg B
mmcli -m "$M" --enable >/dev/null 2>&1
sleep 20
say "# modem re-enabled -> state=$(state)"
leg Ap
say "# done: $OUT"
