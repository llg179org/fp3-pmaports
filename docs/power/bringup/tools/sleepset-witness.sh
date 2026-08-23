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
# The only witness available that early is boot-time ftrace printing into the
# kernel ring buffer, armed from the kernel command line:
#
#     trace_event=qcom_smd_rpm:qcom_rpm_smd_write tp_printk
#
# This script does not add that - editing extlinux is a deploy step with its own
# re-arm and md5 gates. It reports whether the current boot was armed, and if so
# what the probe-time votes were.
#
# Usage: sleepset-witness.sh
set -u

echo "# sleepset-witness kernel=$(uname -r) boot_id=$(cat /proc/sys/kernel/random/boot_id)"
echo "# uptime=$(cut -d. -f1 /proc/uptime)s"
echo

CMDLINE=$(cat /proc/cmdline)
case "$CMDLINE" in
*tp_printk*qcom_rpm_smd_write*|*qcom_rpm_smd_write*tp_printk*)
	echo "armed: yes" ;;
*)
	echo "armed: no"
	echo "FAIL: this boot was not armed, so the probe-time votes were never printed."
	echo "      Add to the kernel command line and reboot:"
	echo "        trace_event=qcom_smd_rpm:qcom_rpm_smd_write tp_printk"
	echo "      An unarmed boot proves nothing either way - do not read its"
	echo "      silence as 'no sleep votes'."
	exit 0 ;;
esac
echo

DM=$(dmesg 2>/dev/null) || { echo "FAIL: dmesg needs root"; exit 0; }

TOTAL=$(printf '%s\n' "$DM" | grep -c 'qcom_rpm_smd_write')
SLEEP=$(printf '%s\n' "$DM" | grep 'qcom_rpm_smd_write' | grep -c 'sleep')
LDOSLEEP=$(printf '%s\n' "$DM" | grep 'qcom_rpm_smd_write' | grep 'sleep' | grep -cE 'ldoa|smpa')

echo "qcom_rpm_smd_write lines in this boot's ring buffer: $TOTAL"
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
	echo "      'No configuration' warnings, which mean the node was parsed but"
	echo "      discarded for lacking regulator-on-in-suspend:"
	printf '%s\n' "$DM" | grep -i "No configuration" | head -5
fi
