#!/bin/sh
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Witness the probe-time RPM sleep-set votes.
#
# ☠️ The reason this exists rather than reusing rail-census.sh: the votes the
# regulator-state-mem device-tree change casts are sent from
# suspend_set_initial_state(), which runs inside regulator_register() at probe.
# That is long before userspace can enable a tracepoint, so the running-system
# census cannot see them and its silence would look exactly like a lever that
# did not work.
#
# The witness is boot-time ftrace, armed from the kernel command line:
#
#     trace_event=qcom_smd_rpm:qcom_rpm_smd_write trace_buf_size=8M
#
# ☠️ Do NOT add tp_printk to that. The cmdline on this device carries
# console=ttyMSM0,115200, and tp_printk routes every tracepoint hit through
# printk. At ~100 characters a line and 115200 baud that is ~9 ms per line of
# blocked boot; a boot's worth of RPM writes would run past the 20 s watchdog
# and boot-loop the phone. The trace buffer needs no console and costs nothing.
#
# This script does not edit extlinux - that is a deploy step with its own re-arm
# and md5 gates. It reports whether this boot was armed, and if so what the
# probe-time votes were.
#
# ☠️ Read it EARLY. The trace buffer is a ring: at a few dozen RPM writes a
# second, a long uptime overwrites the boot window. If the oldest timestamp in
# the buffer is not near zero, the probe-time votes are already gone and the
# answer is "unknown", not "none" - this script says so rather than guessing.
#
# Usage: sleepset-witness.sh
set -u

echo "# sleepset-witness kernel=$(uname -r) boot_id=$(cat /proc/sys/kernel/random/boot_id)"
echo "# uptime=$(cut -d. -f1 /proc/uptime)s"
echo

CMDLINE=$(cat /proc/cmdline)
case "$CMDLINE" in
*trace_event=*qcom_rpm_smd_write*)
	echo "armed: yes" ;;
*)
	echo "armed: no"
	echo "FAIL: this boot was not armed, so the probe-time votes were never traced."
	echo "      Add to the kernel command line and reboot:"
	echo "        trace_event=qcom_smd_rpm:qcom_rpm_smd_write trace_buf_size=8M"
	echo "      An unarmed boot proves nothing either way - do not read its"
	echo "      silence as 'no sleep votes'."
	exit 0 ;;
esac
echo

TR=/sys/kernel/tracing
[ -d "$TR" ] || TR=/sys/kernel/debug/tracing
if [ ! -r "$TR/trace" ]; then
	echo "FAIL: cannot read $TR/trace (needs root, or no tracefs)"
	exit 0
fi
DM=$(grep -v '^#' "$TR/trace")

# Is the boot window still in the ring, or has it been overwritten?
FIRST=$(printf '%s\n' "$DM" | head -1 | sed -n 's/.* \([0-9]*\)\.[0-9]*: .*/\1/p')
if [ -z "$FIRST" ]; then
	echo "FAIL: the trace buffer is empty - the event never fired, or something"
	echo "      cleared it. Check $TR/events/qcom_smd_rpm/qcom_rpm_smd_write/enable."
	exit 0
fi
echo "oldest event in the ring: ${FIRST}s after boot (uptime now $(cut -d. -f1 /proc/uptime)s)"
if [ "$FIRST" -gt 30 ]; then
	echo "FAIL: the ring no longer reaches the boot window - the probe-time votes"
	echo "      have been overwritten. This is UNKNOWN, not 'no votes'. Reboot and"
	echo "      read within the first minutes, or raise trace_buf_size."
	exit 0
fi
echo

TOTAL=$(printf '%s\n' "$DM" | grep -c 'qcom_rpm_smd_write')
SLEEP=$(printf '%s\n' "$DM" | grep 'qcom_rpm_smd_write' | grep -c 'sleep')
LDOSLEEP=$(printf '%s\n' "$DM" | grep 'qcom_rpm_smd_write' | grep 'sleep' | grep -cE 'ldoa|smpa')

echo "qcom_rpm_smd_write lines in the trace ring:       $TOTAL"
echo "  of them sleep-context:                            $SLEEP"
echo "  of those, ldoa/smpa (the regulators):             $LDOSLEEP"
echo
echo "-- distinct sleep-context resources:"
printf '%s\n' "$DM" | grep 'qcom_rpm_smd_write' | grep 'sleep' |
	sed 's/.*qcom_rpm_smd_write: *//' | awk '{print $1, $2}' | sort | uniq -c | sort -rn

echo
if [ "$LDOSLEEP" -gt 0 ]; then
	echo "PASS: the regulators cast $LDOSLEEP sleep-set votes at probe."
	echo "      The device-tree change reached the RPM. Whether that moves"
	echo "      vlow is a separate question - read qcom_stats next."
else
	echo "FAIL: zero ldoa/smpa sleep-set votes in an armed boot."
	echo "      The regulator-state-mem nodes did not produce votes. Check for"
	echo "      'No configuration' warnings in dmesg, which mean the node was"
	echo "      parsed but discarded for lacking regulator-on-in-suspend:"
	dmesg 2>/dev/null | grep -i "No configuration" | head -5
fi
