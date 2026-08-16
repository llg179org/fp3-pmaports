#!/bin/sh
# pll-sweep.sh - force N cpufreq transitions on one cluster and count how many
# of them fail to lock the cluster PLL.
#
# Why this exists. The overnight slope run of 2026-08-15 was spoiled by a storm
# of
#
#   apcs-cpu0-pll failed to enable!
#   WARNING: drivers/clk/qcom/clk-alpha-pll.c:421 at wait_for_pll+0xf4/0x108
#
# which ran through the whole of its control leg, and the phone then died
# mid-line with no shutdown sequence at all. The storm began at about 3.82 V,
# the lowest the battery had been that session, which makes "the PLL fails when
# the supply sags" the obvious hypothesis - and one more failure at 3.89 V while
# charging already weakens it. The RUNBOOK's next step is therefore to stop
# guessing and count: the same fixed sweep at a high battery and at a low one.
#
# ☠️ The point is the *rate*, not the presence of failures. A leg that reports
# zero is only meaningful next to the transition count, which is why this script
# reads the kernel's own total_trans rather than counting its own writes: a
# write to scaling_setspeed that the governor coalesces away exercises nothing,
# and would otherwise be counted as a transition that survived.
#
# Usage, on the device as root:
#   pll-sweep.sh [--rounds N] [--policy 0|4] [--settle-ms MS]
#
# Everything it prints is the measurement; redirect it to a file.

set -eu

ROUNDS=200
POLICY=0
SETTLE_MS=50

while [ $# -gt 0 ]; do
	case $1 in
	--rounds) ROUNDS=$2; shift 2 ;;
	--policy) POLICY=$2; shift 2 ;;
	--settle-ms) SETTLE_MS=$2; shift 2 ;;
	*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
done

POL=/sys/devices/system/cpu/cpufreq/policy$POLICY
[ -d "$POL" ] || { echo "no $POL" >&2; exit 1; }

BAT=$(echo /sys/class/power_supply/*battery* | cut -d' ' -f1)

bat_line() {
	printf '%s  cap=%s%%  V=%s  I=%s  status=%s\n' "$1" \
		"$(cat "$BAT/capacity" 2>/dev/null)" \
		"$(cat "$BAT/voltage_now" 2>/dev/null)" \
		"$(cat "$BAT/current_now" 2>/dev/null)" \
		"$(cat "$BAT/status" 2>/dev/null)"
}

# The failure is a kernel WARNING, so read the kernel log, and take a cursor
# first: counting from the start of the boot would make the answer depend on
# everything that happened before the sweep.
cursor=$(journalctl -k -n0 --show-cursor --no-pager 2>/dev/null |
	sed -n 's/^-- cursor: *//p')

gov_before=$(cat "$POL/scaling_governor")
freqs=$(cat "$POL/scaling_available_frequencies")
trans_before=$(cat "$POL/stats/total_trans")

# ☠️ Pin every other policy, or the measurement is about the wrong cluster.
# The first version of this script swept policy0 and reported its transition
# count next to a failure count that was 90 apcs-cpu4-pll against 1
# apcs-cpu0-pll: the big cluster was still on schedutil and was being driven by
# the sweep's own CPU load, so numerator and denominator described different
# hardware. Holding the others at one frequency under the userspace governor
# takes them out of the experiment instead of leaving them in it unmeasured.
others=""
for p in /sys/devices/system/cpu/cpufreq/policy*; do
	[ "$p" = "$POL" ] && continue
	[ -w "$p/scaling_governor" ] || continue
	others="$others $p"
	eval "gov_$(basename "$p")=\$(cat \"\$p/scaling_governor\")"
	echo userspace > "$p/scaling_governor" 2>/dev/null || true
	# Its lowest frequency: least heat, and no reason to prefer any other.
	pin=$(tr ' ' '\n' < "$p/scaling_available_frequencies" | grep . | sort -n | head -1)
	echo "$pin" > "$p/scaling_setspeed" 2>/dev/null || true
	echo "pinned $(basename "$p") at $pin (was $(eval echo "\$gov_$(basename "$p")"))"
done

echo "policy$POLICY  cpus=$(cat "$POL/affected_cpus")  governor=$gov_before"
echo "frequencies: $freqs"
echo "rounds=$ROUNDS settle=${SETTLE_MS}ms"
bat_line "before:"

restore() {
	echo "$gov_before" > "$POL/scaling_governor" 2>/dev/null || true
	for p in $others; do
		eval "g=\$gov_$(basename "$p")"
		echo "$g" > "$p/scaling_governor" 2>/dev/null || true
	done
}
trap restore EXIT INT TERM

echo userspace > "$POL/scaling_governor"

# Alternate lowest/highest before walking the ladder. The big jump is the one
# that has to re-lock the PLL rather than only re-divide, and doing it first
# means a sweep that is cut short still contains the interesting transition.
lo=$(echo "$freqs" | tr ' ' '\n' | grep . | sort -n | head -1)
hi=$(echo "$freqs" | tr ' ' '\n' | grep . | sort -n | tail -1)

r=0
while [ "$r" -lt "$ROUNDS" ]; do
	r=$((r + 1))
	for f in $lo $hi $freqs; do
		echo "$f" > "$POL/scaling_setspeed" 2>/dev/null || true
		# usleep is busybox; fall back to a whole second only if absent,
		# which would make the sweep much slower but never wrong.
		if command -v usleep >/dev/null 2>&1; then
			usleep $((SETTLE_MS * 1000))
		else
			sleep 1
		fi
	done
	# A progress line every 25 rounds, so a run that has to be killed still
	# says how far it got and what the battery was doing at the time.
	[ $((r % 25)) -eq 0 ] && bat_line "round $r:"
done

trans_after=$(cat "$POL/stats/total_trans")
restore
trap - EXIT INT TERM

bat_line "after: "

if [ -n "$cursor" ]; then
	log=$(journalctl -k --after-cursor "$cursor" --no-pager 2>/dev/null)
else
	echo "INFO: no journal cursor, reading the whole ring buffer instead"
	log=$(dmesg)
fi

fails=$(printf '%s\n' "$log" | grep -c 'pll failed to enable' || true)
# Per PLL, because "which cluster" is half the result: the same sweep can
# produce failures on the cluster it is not driving.
per_pll=$(printf '%s\n' "$log" | grep -o 'apcs-cpu[0-9]*-pll failed to enable' |
	sort | uniq -c || true)
warns=$(printf '%s\n' "$log" | grep -c 'wait_for_pll' || true)
trans=$((trans_after - trans_before))

echo
echo "transitions (kernel's own count): $trans"
echo "PLL enable failures:              $fails"
echo "wait_for_pll warnings:            $warns"
[ -n "$per_pll" ] && printf 'per PLL:\n%s\n' "$per_pll"
if [ "$trans" -gt 0 ]; then
	echo "failure rate:                     $((fails * 10000 / trans)) per 10000"
else
	echo "☠️ zero transitions - the sweep exercised nothing, so a zero failure"
	echo "   count here says nothing at all. Check that the userspace governor"
	echo "   took and that scaling_setspeed is writable."
fi

printf '%s\n' "$log" | grep 'pll failed to enable' | head -5
