#!/bin/sh
# Category: power
# Description: the modem SMD edge is wake-armed, so an incoming call ends s2idle
#
# Two layers, failed separately so the message names the broken one:
#   1. the knob exists   - the running kernel carries the r66 qcom_smd wake-IRQ
#                          patch (its absence means an old kernel, not a config);
#   2. the knob is armed - the fp3-modem-wake-arm oneshot ran at boot (the
#                          kernel default is 'disabled' on purpose, so a fresh
#                          kernel with the unit missing FAILS here).
#
# The live proof behind this check (2026-08-22): with the edge armed an incoming
# call woke the phone 15 s into a 300 s suspend window; disarmed, the same
# windows sleep to the alarm. Attribution counters stay blind in s2idle, so the
# check reads the knob, not wakeup_count.

fail=0

knob=$(ls /sys/devices/platform/soc@0/4080000.remoteproc/remoteproc/*/*:smd-edge/power/wakeup 2>/dev/null | head -1)
if [ -z "$knob" ]; then
	echo "FAIL: no wakeup knob on the modem smd-edge (kernel without the r66 qcom_smd wake patch?)"
	echo "      cmd: ls /sys/devices/platform/soc@0/4080000.remoteproc/remoteproc/*/*:smd-edge/power/wakeup"
	exit 1
fi
echo "PASS: modem smd-edge wakeup knob exists ($knob)"

state=$(cat "$knob")
if [ "$state" = enabled ]; then
	echo "PASS: modem edge is wake-armed (incoming call ends s2idle)"
else
	echo "FAIL: modem edge wakeup is '$state' - fp3-modem-wake-arm.service missing or not enabled"
	echo "      cmd: cat $knob; systemctl status fp3-modem-wake-arm"
	fail=1
fi

exit $fail
