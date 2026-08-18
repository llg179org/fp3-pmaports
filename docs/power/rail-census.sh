#!/bin/sh
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Name the rails that vote active and never vote sleep.
#
# The tracepoint qcom_rpm_smd_write already carries the resource type ("ldoa",
# "smpa", ...), the resource id and the raw KVP payload, so the census is a
# capture and a parse rather than new kernel code. Counts were taken before -
# 14 LDO votes active, 0 sleep - but a count cannot be acted on. This produces
# names and values.
#
# Usage: rail-census.sh [seconds-of-idle-after-resume]
#
# ☠️ Run it as a transient unit. It suspends the phone, so an ssh session
# hosting it is gone by the time it matters.
set -u

SECS=${1:-60}
TR=/sys/kernel/tracing
OUT=/run/rail-census.txt

[ -d "$TR" ] || TR=/sys/kernel/debug/tracing
if [ ! -d "$TR" ]; then
	echo "ABORT: no tracefs" >&2
	exit 1
fi
if [ ! -d "$TR/events/qcom_smd_rpm/qcom_rpm_smd_write" ]; then
	echo "ABORT: tracepoint qcom_smd_rpm:qcom_rpm_smd_write not present - wrong kernel" >&2
	exit 1
fi

say() { echo "$*" >> "$OUT"; }

: > "$OUT"
say "# rail-census kernel=$(uname -r) boot_id=$(cat /proc/sys/kernel/random/boot_id)"

echo 0 > "$TR/tracing_on"
echo > "$TR/trace"
echo 8192 > "$TR/buffer_size_kb" 2>/dev/null
echo 1 > "$TR/events/qcom_smd_rpm/qcom_rpm_smd_write/enable"
echo 1 > "$TR/tracing_on"
say "# tracing on, arming suspend"

# ☠️ The votes that matter are the ones sent on the way down, so the capture
# has to span the suspend itself, not the idle before it. rtcwake gives a
# bounded sleep that comes back without anyone touching the phone.
if command -v rtcwake >/dev/null 2>&1; then
	rtcwake -m mem -s 30 >> "$OUT" 2>&1
	say "# rtcwake returned rc=$?"
else
	# ☠️ The RTC on this device reads 1970; rtc-based wake has failed here
	# before. If it is missing entirely, fall back to a plain s2idle with a
	# timer alarm set by systemd.
	say "# rtcwake absent - falling back to systemd timer suspend"
	(sleep 30; systemctl start suspend.target) &
	systemctl start suspend.target
fi

sleep "$SECS"
echo 0 > "$TR/tracing_on"
say "# tracing off"

say "# ---- trace begins ----"
cat "$TR/trace" >> "$OUT"
echo 0 > "$TR/events/qcom_smd_rpm/qcom_rpm_smd_write/enable"
cp "$OUT" /home/fp3/ 2>/dev/null || true
say "# DONE"
