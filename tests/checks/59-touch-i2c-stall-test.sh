#!/bin/sh
# Category: power
# Description: the touchscreen's i2c controller does not hang on the first access after an idle
#
# The fault this exists to catch, measured 2026-09-04: a transaction on the
# touchscreen's QUP i2c bus hangs, and because the driver waits the controller's
# full transfer timeout, the panel is dead for ~15 s. It ends with the pair
#
#     Himax-hx83112b-TS N-0048: Failed to read input event: -110   (ETIMEDOUT)
#     Himax-hx83112b-TS N-0048: Failed to read input event: -6     (ENXIO)
#
# The 15 s is not arbitrary: i2c-qup computes xfer_timeout ONCE at probe from
# MX_DMA_TX_RX_LEN, the largest transfer the controller could ever do (128 KB),
# and applies it to every transfer. With no clock-frequency in the DT the driver
# defaults to 100 kHz, giving 2 s + 131072 x 99 us = 14.98 s - which is what the
# measured stalls last, to within the resolution of the log.
#
# ☠️ WHAT THE RATE MEANS, because it decides how to read a PASS. The fault is
# per *first access after the controller has been idle*, not per transaction:
#
#     measured over one 50-minute session of ordinary tapping
#       38 721 i2c reads, 15 stalls   ->  0.039 % per transaction
#       109 pauses >= 2 s             ->  13.8 % per resume
#
# The controller autosuspends after 1 s, so every pause longer than that creates
# one vulnerable moment. A phone that has been sitting untouched has had almost
# no vulnerable moments, so a clean log means "not exercised", NOT "not broken".
# This check says which of the two it is measuring.
#
# ☠️ HOW LONG THE ACTIVE RUN MUST BE - the number that decides whether a PASS is
# worth anything. The 15 stalls of that session were separated by
#
#     23  38  43  46  47  57  62  62  104  161  243  472  618  726   seconds
#     min 23   median 62   max 726
#
# so the floor has nothing to do with statistics: ANY run shorter than a few
# times 726 s can come back clean while the fault is fully present. Call it
# ~36 min = 730 probes at 3 s spacing as the shortest credible active run.
# Above that floor, a clean run of length T bounds the rate at 3/T (rule of
# three, 95 %); against the session rate of 1 stall per 200 s of active use
# that is
#
#     ~10 min  clean  ->  only rules out "worse than today"
#     ~100 min clean  ->  10x better than today
#     ~17 h    clean  ->  100x better, i.e. "gone"
#
# ☠️ And the per-probe rate quoted below is soft. Measured 2026-09-04 in one
# session: 200 probes at 0.5 s spacing produced exactly one stall - on trial 0,
# the first access after the setup idle - and 40 probes at 3 s spacing produced
# none at all. That 3 s arm was meant to be the known-positive control and came
# back empty, which is what 40 probes buys you (0/40 has a 13 % chance even at
# 5 %/probe). No two stalls were ever closer than 23 s, so there may be a
# refractory period, and if there is, "stalls per probe" is not even well
# defined - it falls with probe density. Size the run in TIME, not in probes.
#
# ☠️ IT DOES NOT PROVOKE THE FAULT BY DEFAULT, and that is deliberate. The
# obvious active probe - a userspace read on the same bus - collided with the
# touchscreen driver on 2026-09-04, wedged the controller into 1824 consecutive
# EIO, and cost two reboots to recover. A selftest must not do that to a phone.
# Set FP3_TOUCH_PROBE=<n> to run the active version, which unbinds the driver
# first so nothing can collide and verifies the rebind afterwards.

fail=0
say() { echo "$1: $2"; }

# --- locate the touchscreen BY NAME. ☠️ Never by index: the i2c bus number and
# the input node number are handed out in probe order and both moved on this
# device in one afternoon (2-0048 -> 3-0048 after a reboot, event4 -> event7
# after a rebind). A check hardcoding either reports a healthy panel as dead.
ts_dev=""
for d in /sys/bus/i2c/devices/*-00*; do
	[ -r "$d/name" ] || continue
	case "$(cat "$d/name" 2>/dev/null)" in
	hx83112b) ts_dev=$d ;;
	esac
done

if [ -z "$ts_dev" ]; then
	say FAIL "no hx83112b touchscreen on any i2c bus - the panel is not bound at all"
	exit 1
fi
say PASS "touchscreen at $(basename "$ts_dev"), driver $(basename "$(readlink "$ts_dev/driver" 2>/dev/null)" 2>/dev/null || echo NONE)"

# --- 1. passive: has the fault happened in this boot?
stalls=$(dmesg 2>/dev/null | grep -c -e 'Failed to read input event: -110')
irqs=$(awk '/hx83112b/{s=0; for(i=2;i<=NF-4;i++) s+=$i; print s+0; exit}' /proc/interrupts 2>/dev/null)
: "${irqs:=0}"

if [ "$stalls" -gt 0 ]; then
	say FAIL "$stalls i2c stalls this boot ($irqs touch interrupts): the panel was dead"
	say FAIL "  for ~15 s each time. dmesg | grep 'Failed to read input event'"
	fail=1
elif [ "$irqs" -lt 500 ]; then
	# ☠️ A clean log on an unexercised panel is not evidence. Say so rather than
	# banking a PASS the next reader will treat as one.
	say SKIP "no stalls, but only $irqs touch interrupts this boot - the panel has"
	say SKIP "  barely been used, so this measures that nobody touched it. Tap the"
	say SKIP "  screen for a minute with pauses, or run FP3_TOUCH_PROBE=20 for the"
	say SKIP "  active version."
else
	say PASS "no i2c stalls across $irqs touch interrupts this boot"
fi

# --- 2. active, only when asked for
if [ -n "$FP3_TOUCH_PROBE" ]; then
	# ships with the suite; the runner copies lib/ next to checks/
	probe="${DEVICE_DIR:-.}/lib/i2c-stall-probe.py"
	[ -r "$probe" ] || probe="$(dirname "$0")/../lib/i2c-stall-probe.py"
	if [ ! -r "$probe" ]; then
		say SKIP "FP3_TOUCH_PROBE set but the probe is not on the device ($probe)"
	elif [ "$(id -u)" != 0 ]; then
		say SKIP "FP3_TOUCH_PROBE needs root (it unbinds and rebinds the driver)"
	else
		drv=$(readlink "$ts_dev/driver" 2>/dev/null | sed 's|.*/||')
		unit=$(basename "$ts_dev")
		say PASS "active probe: unbinding $drv so the probe cannot collide with it"
		echo "$unit" > "/sys/bus/i2c/drivers/$drv/unbind" 2>/dev/null
		sleep 1
		hits=0; n=0
		while [ "$n" -lt "$FP3_TOUCH_PROBE" ]; do
			sleep 3                       # > 1 s, so the controller autosuspends
			d=$(python3 "$probe" 78b7000 0x50 0 1 2>/dev/null | sed -n 's/.*max \([0-9.]*\) s.*/\1/p')
			case "$d" in [1-9]*.*) hits=$((hits+1)); say FAIL "  probe $n hung for ${d}s" ;; esac
			n=$((n+1))
		done
		# ☠️ Rebind, then VERIFY. A restore that only reports success is how this
		# phone was twice left without a touchscreen: the bind failed with -5 and
		# the script said "bound" anyway.
		echo "$unit" > "/sys/bus/i2c/drivers/$drv/bind" 2>/dev/null; sleep 3
		if [ -e "$ts_dev/driver" ]; then
			say PASS "driver rebound and verified"
		else
			echo "$unit" > "/sys/bus/i2c/drivers/$drv/bind" 2>/dev/null; sleep 4
			if [ -e "$ts_dev/driver" ]; then
				say PASS "driver rebound on the second attempt"
			else
				say FAIL "☠️ the driver did NOT rebind - this phone has no touchscreen"
				say FAIL "  until it is rebooted. A stall can leave the chip unable to probe."
				fail=1
			fi
		fi
		if [ "$hits" -gt 0 ]; then
			say FAIL "active probe: $hits of $FP3_TOUCH_PROBE first-accesses-after-idle hung"
			fail=1
		else
			secs=$((FP3_TOUCH_PROBE * 3))
			if [ "$secs" -lt 2178 ]; then
				# below 3 x the longest observed gap (726 s): a clean run here
				# is compatible with the fault being fully present.
				say SKIP "active probe: 0 of $FP3_TOUCH_PROBE hung, but ${secs}s is under the"
				say SKIP "  ~2180 s floor (3 x the longest observed 726 s gap), so this"
				say SKIP "  proves nothing. Use FP3_TOUCH_PROBE=730 for the shortest"
				say SKIP "  credible run, 2000 to claim a real improvement."
			else
				say PASS "active probe: 0 of $FP3_TOUCH_PROBE hung over ${secs}s; 95 % upper bound"
				say PASS "  on the rate is 1 per $((secs / 3)) s, vs 1 per 200 s measured 2026-09-04"
			fi
		fi
	fi
fi

exit $fail
