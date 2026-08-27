#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Decide whether an awake current burst is the CPU being awake at all, or something
# that costs power without running code.
#
# ☠️ THIS EXISTS BECAUSE THE TRACER ANSWERED "NO". burst-source.sh recorded every
# workqueue and timer for six minutes while the current swung 57 -> 409 mA, and the
# event rate in the burst bins and in the quiet bins was the same to within 1 %
# (313 vs 316 events per 5 s bin, and every single top function at the same
# per-bin rate). A carpet of software wakeups that does not change cannot be what
# makes the current change. So counting work is finished as a line of attack, and
# the question becomes: during a burst, is the CPU even out of its idle state?
#
# What it samples, all of it cheap sysfs/procfs, none of it a tracepoint:
#   - current + voltage (the same gauge idle-ab reads)
#   - busy CPU time from /proc/stat        -> is code running?
#   - cpuidle state1 (power-collapse) residency and state0 (WFI) usage deltas
#                                          -> is the cluster reaching its deep state?
#   - both cpufreq policies                -> is it running fast when it runs?
#   - wlan packet counters                 -> is the radio being fed?
# If the burst has no CPU-busy and no residency signature, the power is going
# somewhere that is not a running instruction, and the next instrument is a rail.
#
# ☠️ THE PANEL AND THE CHARGE INPUT ARE NOT HANDLED HERE, DELIBERATELY. idle-ab.sh
# owns the panel proof, the charge cut and the window; this samples alongside it.
# Duplicating the panel logic is how burst-source.sh got a worse copy of it.
#
#   burst-attrib.sh [seconds]        (default 360)
set -u
W=${1:-360}
IV=2
OUT=/var/log/fp3/burst-attrib-$(date +%s)
mkdir -p "$OUT"
BAT=$(dirname "$(ls /sys/class/power_supply/*/capacity 2>/dev/null | head -1)")

say(){ echo "$*" | tee -a "$OUT/log"; }
say "# burst-attrib $(date '+%F %T') window=${W}s interval=${IV}s bat=$BAT"
say "# kernel=$(uname -r) $(uname -v)"

ncpu=$(grep -c ^processor /proc/cpuinfo)
say "# cpus=$ncpu idle-states=$(ls -d /sys/devices/system/cpu/cpu0/cpuidle/state* 2>/dev/null | wc -l)"

sum_idle_time(){   # microseconds spent in the named state, summed over all cpus
	s=$1; t=0
	for f in /sys/devices/system/cpu/cpu*/cpuidle/state$s/time; do
		[ -e "$f" ] || continue
		t=$((t + $(cat "$f")))
	done
	echo $t
}
sum_idle_usage(){
	s=$1; t=0
	for f in /sys/devices/system/cpu/cpu*/cpuidle/state$s/usage; do
		[ -e "$f" ] || continue
		t=$((t + $(cat "$f")))
	done
	echo $t
}
cpu_jiffies(){ awk '/^cpu /{busy=$2+$3+$4+$7+$8+$9; idle=$5+$6; print busy, busy+idle}' /proc/stat; }
netcnt(){ cat /sys/class/net/wlan0/statistics/rx_packets /sys/class/net/wlan0/statistics/tx_packets 2>/dev/null | tr '\n' ' '; }

# the sampler runs in the background for the whole window; idle-ab owns the window
sampler(){
	echo "# t_s cur_mA v_mV busy_pct pc_res_pct wfi_per_s pc_per_s f0_kHz f4_kHz wlan_pps" > "$OUT/attrib.txt"
	set -- $(cpu_jiffies); pb=$1; pt=$2
	pres=$(sum_idle_time 1); pwfi=$(sum_idle_usage 0); ppc=$(sum_idle_usage 1)
	set -- $(netcnt); pnet=$(( ${1:-0} + ${2:-0} ))
	t=0
	while [ $t -lt "$W" ]; do
		sleep $IV
		t=$((t + IV))
		cur=$(cat "$BAT/current_now" 2>/dev/null || echo 0)
		vol=$(cat "$BAT/voltage_now" 2>/dev/null || echo 0)
		set -- $(cpu_jiffies); nb=$1; nt=$2
		res=$(sum_idle_time 1); wfi=$(sum_idle_usage 0); pc=$(sum_idle_usage 1)
		set -- $(netcnt); nnet=$(( ${1:-0} + ${2:-0} ))
		f0=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq 2>/dev/null || echo 0)
		f4=$(cat /sys/devices/system/cpu/cpufreq/policy4/scaling_cur_freq 2>/dev/null || echo 0)
		dt=$((nt - pt)); [ "$dt" -le 0 ] && dt=1
		# residency is summed over ncpu cpus, so 100 % means every cpu was collapsed
		echo "$t $(( (cur<0 ? -cur : cur) / 1000 )) $((vol/1000))" \
		     "$(( (nb - pb) * 100 / dt ))" \
		     "$(( (res - pres) / (IV * ncpu * 10000) ))" \
		     "$(( (wfi - pwfi) / IV ))" \
		     "$(( (pc - ppc) / IV ))" \
		     "$f0 $f4 $(( (nnet - pnet) / IV ))" >> "$OUT/attrib.txt"
		pb=$nb; pt=$nt; pres=$res; pwfi=$wfi; ppc=$pc; pnet=$nnet
	done
}

sampler &
spid=$!
say "# sampler pid=$spid, handing the window to idle-ab.sh"
/usr/local/bin/idle-ab.sh "$W" >/dev/null 2>&1
rc=$?
wait $spid 2>/dev/null

src=$(ls -t /tmp/idle-ab-*.txt 2>/dev/null | head -1)
[ -n "$src" ] && cp "$src" "$OUT/current.txt"
say "# idle-ab rc=$rc"
[ -n "$src" ] && say "# $(grep '^# panel:' "$src" | tr '\n' '|')"
say "# done: $(grep -vc '^#' "$OUT/attrib.txt") attrib samples"
say "# $OUT"
