#!/bin/sh
# Category: touch
# ☠️ Was "power" until 2026-09-05, and correctly so: the #142 i2c stall was
# investigated under the power work before it had a category. It now has its own
# topic branch (wip/<base>/touch), and the coverage guard - rightly - refused to
# run anything until the branch and this check agreed on where it belongs.
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

# --- 2. the active arm is DISABLED HERE, but it is not useless - it was aimed
# wrong. Sorted by the idle before each probe, 2026-09-04:
#
#     idle    probes  stalls          idle    probes  stalls
#     0.02 s   52688       0          10-60 s     20       1   (5.0 %)
#     0.5  s    1392       0          15 s        60       1   (1.7 %)
#     2    s     300       0          45 s         3       1
#     3    s      40       0
#
# The fault has a threshold between 3 s and 10 s of idle. The long null above it
# came from raising the probe rate, which drops the idle below that threshold;
# at the 15 s rate those 52 688 fast probes would have produced ~878 stalls.
#
# It is disabled in the selftest for a different reason: reproducing it needs
# the screen OFF as well (5/5 against 0/5 at an identical 12 s idle), so the
# check would have to blank the user's screen, unbind the driver, and rebind it
# - and while the screen is off the Himax probe returns -5, which cost five
# reboots in one afternoon before the rebind was moved to the screen-on state.
#
# The working reproducer, with that ordering baked in, is
# docs/power/bringup/captures/2026-09-04_142-touch-after-resume/142-trigger.sh
# Read TRIGGER-screen-gates-it.md beside it first: it lists the three measured
# gates (idle >= 10 s, screen off, not a fresh boot) and why the 15 s duration
# is not a fingerprint but the QUP timeout constant.
if [ -n "$FP3_TOUCH_PROBE" ]; then
	say SKIP "FP3_TOUCH_PROBE is disabled here - reproducing the fault needs the"
	say SKIP "  screen off and >=10 s idle, so it blanks the screen and unbinds the"
	say SKIP "  driver. Use 142-trigger.sh from the capture instead."
fi

exit $fail
