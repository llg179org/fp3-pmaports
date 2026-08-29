#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# A-B-A' on the eMMC host's runtime-PM autosuspend delay, counting the RPM
# requests it produces.
#
#   rpm-write-ab.sh [leg_s] [rounds] [delay_b_ms]     (defaults 300, 3, 2000)
#
# ☠️ RUN IT DETACHED, WITH THE HOST QUIET. The quantity being counted is the RPM
# traffic caused by idle filesystem writes, and an SSH session is an idle
# filesystem write. The first attempt at this drove all three legs over SSH and
# produced an effect the same size as the drift between its own controls, which
# settles nothing. `systemd-run --unit=... --collect` and read the file afterwards.
#
# ☠️ IT COUNTS WITH THE FUNCTION PROFILER, NOT THE RING BUFFER. `function` tracing
# writes records, and the reader that drains them writes to disk - which is the
# very thing under measurement. `function_profile_enabled` keeps a per-CPU hit
# count and costs no I/O at all.
set -u
LEG=${1:-300}
ROUNDS=${2:-3}
DELAY_B=${3:-2000}
DELAY_A=50
T=/sys/kernel/tracing
O=/var/log/fp3/rpm-write-ab-$(date +%s).txt

[ -w "$T/function_profile_enabled" ] || { echo "no function profiler at $T" >&2; exit 1; }

set_delay(){ for d in /sys/class/mmc_host/*/device; do echo "$1" > "$d/power/autosuspend_delay_ms"; done; }
delays(){ cat /sys/class/mmc_host/*/device/power/autosuspend_delay_ms | tr '\n' ' '; }

count_leg(){   # count_leg <seconds> -> hits
	echo 0 > "$T/function_profile_enabled"
	echo qcom_rpm_smd_write > "$T/set_ftrace_filter"
	echo 1 > "$T/function_profile_enabled"
	sleep "$1"
	echo 0 > "$T/function_profile_enabled"
	awk '$1 == "qcom_rpm_smd_write" { s += $2 } END { print s + 0 }' "$T"/trace_stat/function*
}

{
	echo "# rpm-write-ab $(date '+%F %T') leg=${LEG}s rounds=$ROUNDS A=${DELAY_A}ms B=${DELAY_B}ms"
	echo "# kernel=$(uname -v)"
	echo "# ☠️ every number below is per leg, not per second; divide by $LEG"
	r=0
	while [ "$r" -lt "$ROUNDS" ]; do
		r=$((r + 1))
		set_delay "$DELAY_A"; a=$(count_leg "$LEG")
		set_delay "$DELAY_B"; b=$(count_leg "$LEG")
		set_delay "$DELAY_A"; c=$(count_leg "$LEG")
		echo "round $r  A=$a  B=$b  Ap=$c  (delays now: $(delays))"
	done
	set_delay "$DELAY_A"
	echo "# restored: $(delays)"
	echo 0 > "$T/function_profile_enabled"
	echo > "$T/set_ftrace_filter"
} > "$O" 2>&1
echo "$O"
