#!/bin/sh
# Category: power
# Detached: yes
# Description: the system suspends, wakes on an RTC alarm, and gets deep enough
#
# Runs last, and runs detached, because resuming re-enumerates USB and drops
# the CDC-NCM link every time. Driving this over a live SSH session would kill
# the measurement at the moment it matters, so the check writes its verdict to
# the rootfs and the runner reconnects afterwards to read it.
#
# Based on postmarketos-test's 90-suspend-test.sh, kept close to it on purpose:
# if this ever moves into a device-pmtest subpackage it should look familiar.
#
# Three separate properties, in increasing order of what they cost to break:
#
#   1. the sleep-state menu (/sys/power/mem_sleep) is what we recorded;
#   2. suspend happens and the RTC brings it back - and if something else
#      brings it back first, that is said in those words rather than reported
#      as "never suspended";
#   3. the SoC actually collapsed while it was down.
#
# (3) is the one worth having. A suspend that freezes userspace, holds a wakeup
# source somewhere and never lets the power domains go still passes (2) and
# still looks right from the outside - the phone is unresponsive, the screen is
# off, and it wakes on the alarm - while saving next to nothing. The only thing
# that separates the two is a counter inside genpd, so read it.

SLEEP_TIME=6
GENPD=/sys/kernel/debug/pm_genpd
SYSDOM=$GENPD/power-domain-system

fail=0

# ---------------------------------------------------------------------------
# 1. the sleep-state menu
# ---------------------------------------------------------------------------
# mem_sleep is written by the kernel at init and never by userspace, so a change
# here means the firmware or the kernel's suspend backend changed under us. See
# baseline/sleep-states.txt for why "deep" is absent and what its appearance
# would mean.
BASELINE="$DEVICE_DIR/baseline/sleep-states.txt"
if [ ! -s "$BASELINE" ]; then
	echo "FAIL: no baseline at baseline/sleep-states.txt"
	echo "      (mem_sleep currently reads: $(cat /sys/power/mem_sleep 2>&1))"
	fail=1
else
	want=$(grep -v '^[[:space:]]*#' "$BASELINE" | tr -s ' \t' '\n\n' \
		| grep . | sort | tr '\n' ' ')
	have=$(tr -d '[]' </sys/power/mem_sleep | tr -s ' \t' '\n\n' \
		| grep . | sort | tr '\n' ' ')
	if [ "$want" = "$have" ]; then
		echo "PASS: sleep states are '$(echo "$have" | sed 's/ $//')' as recorded"
	else
		echo "FAIL: sleep states changed - recorded '$(echo "$want" | sed 's/ $//')', found '$(echo "$have" | sed 's/ $//')'"
		case " $have " in
		*" deep "*)
			echo "      'deep' APPEARED. This is news, not a defect: the secure"
			echo "      firmware has started answering psci_features(SYSTEM_SUSPEND)."
			echo "      Re-run the depth measurement below under both states before"
			echo "      updating baseline/sleep-states.txt - s2idle already reaches"
			echo "      the system power collapse here, so 'deep' may buy nothing."
			;;
		*)
			echo "      A state was lost. Suspend depth is about to get worse;"
			echo "      check CONFIG_SUSPEND and the psci probe in the boot log."
			;;
		esac
		fail=1
	fi
fi

# ---------------------------------------------------------------------------
# 2 + 3. suspend, and how deep it went
# ---------------------------------------------------------------------------
if [ ! -e /sys/class/rtc/rtc0/wakealarm ]; then
	echo "FAIL: no RTC wakealarm - nothing can wake the device from suspend"
	exit 1
fi

# Sum the S2idle column across every idle state of a domain. genpd counts
# entries made from the s2idle path separately from runtime-idle ones, which is
# exactly the distinction this check needs: the domains collapse constantly
# during normal use, so a plain usage counter would rise no matter what suspend
# did. Returns "" if the column does not exist, so an older kernel skips rather
# than fails.
s2idle_count() {
	awk '
		/^State/ { for (i = 1; i <= NF; i++) if ($i == "S2idle") col = i; next }
		col && NF >= col { n += $col; seen = 1 }
		END { if (seen) print n+0 }
	' "$1" 2>/dev/null
}

depth_before=""
[ -r "$SYSDOM/idle_states" ] && depth_before=$(s2idle_count "$SYSDOM/idle_states")

before=$(cat /sys/class/rtc/rtc0/since_epoch)
target=$((before + SLEEP_TIME))

# Clear any stale alarm first: a leftover one in the past makes the write
# succeed and the wake never happen.
echo 0 >/sys/class/rtc/rtc0/wakealarm
echo "$target" >/sys/class/rtc/rtc0/wakealarm

sync
echo mem >/sys/power/state

after=$(cat /sys/class/rtc/rtc0/since_epoch)
elapsed=$((after - before))

# Two very different things used to be reported as one. "Woke before the alarm"
# was printed as "the system never suspended", which is false whenever the
# device suspended and something else brought it back early - and that is what
# actually happens inside the battery, where earlier checks leave wake sources
# armed. The discriminator is the alarm file itself: the RTC clears it when it
# fires, so an alarm that is still armed after resume means the wake came from
# somewhere else.
alarm_left=$(cat /sys/class/rtc/rtc0/wakealarm 2>/dev/null)
wake_irq=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)

if [ "$elapsed" -le 0 ]; then
	echo "FAIL: the system never suspended (elapsed ${elapsed}s, alarm was ${SLEEP_TIME}s out)"
	echo "      cmd: cat /sys/kernel/debug/wakeup_sources"
	exit 1
elif [ "$after" -lt "$target" ]; then
	# Still a suspend, so the depth measurement below is valid and worth
	# taking. Named, not swallowed: a device that cannot stay down for six
	# seconds is a real finding, just not this line's finding.
	echo "PASS: suspended for ${elapsed}s of ${SLEEP_TIME}s"
	echo "WARN: woke $((target - after))s early, not on the RTC alarm"
	[ -n "$alarm_left" ] && echo "      the alarm was still armed at $alarm_left"
	[ -n "$wake_irq" ] && echo "      last wakeup IRQ: $wake_irq" \
		"($(awk -v i="$wake_irq" '$1 ~ "^"i":" {for (j = NF; j > 0; j--) if ($j !~ /^[0-9]+$/) { print $j; break }}' /proc/interrupts 2>/dev/null))"
	echo "      cmd: grep -v '\s0\s*$' /sys/kernel/debug/wakeup_sources"
else
	echo "PASS: suspended and resumed on the RTC alarm after ${SLEEP_TIME}s"
fi

# Leave no armed alarm behind for the next check to trip over.
echo 0 >/sys/class/rtc/rtc0/wakealarm 2>/dev/null

# The other failure mode is not coming back at all, which shows up as the
# runner failing to reconnect rather than as a line here.

if [ -z "$depth_before" ]; then
	echo "SKIP: suspend depth (no S2idle column in $SYSDOM/idle_states)"
	echo "      cmd: cat $SYSDOM/idle_states"
else
	depth_after=$(s2idle_count "$SYSDOM/idle_states")
	if [ "${depth_after:-0}" -gt "$depth_before" ]; then
		echo "PASS: the system power domain collapsed while suspended" \
			"($depth_before -> $depth_after s2idle entries)"
	else
		echo "FAIL: suspend did not reach the system power collapse"
		echo "      power-domain-system s2idle entries stayed at $depth_before"
		echo "      The phone still froze and still woke up, so this is the"
		echo "      expensive failure: something kept a domain's child awake."
		echo "      Read the whole tree to find which one:"
		echo "      cmd: cat /sys/kernel/debug/pm_genpd/pm_genpd_summary"
		fail=1
	fi
fi

exit $fail
