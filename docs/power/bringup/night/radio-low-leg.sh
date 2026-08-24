#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Fable 5) under the direction of Lajosházi, László Gergely.
#
# What is the radio worth? — the mmcli power-state-low arm of the modem lead.
#
# Measured 2026-08-24 (modem-xo-duty, captures/2026-08-24_modem-xo-duty.txt):
# with the radio up, every s2idle suspend aborts early (11 s / 47 s of a
# requested 90) and the MPSS chops the crystal ~2.5 transitions/s; with
# `mmcli --set-power-state-low` the suspends run full-term and the MPSS holds
# XO-shutdown essentially the whole window. That mechanism has no mA price yet —
# this leg is the price, read as a phase-A slope against baseline-20260819
# (-35.77 mV/h) and nomodem-20260819 (-22.62 mV/h).
#
# It arms the radio low, verifies across ONE probe suspend that the arm actually
# took (full-term wall clock AND the MPSS crystal off for most of it) BEFORE
# spending hours, and only then hands over to the ordinary slope leg. ☠️ A leg
# that measures an intervention which silently did not take is the most
# expensive kind of null, and this project has already paid for one.
#
# ☠️ rtcwake exits 0 even when the suspend aborts early — the gate must
# wall-clock the window, never trust the rc (measured 2026-08-24).
# ☠️ After a power-state round trip the modem stays 'disabled':
# --set-power-state-on alone is not a restore, --enable is (measured
# 2026-08-24). Every exit path here does both.
#
#   radio-low-leg.sh [tag]

set -u

TAG=${1:-radiolow-20260824}
RPM=/sys/kernel/debug/qcom_rpm_master_stats

modprobe rpm_master_stats 2>/dev/null || true
mf() { sed -n "s/^[[:space:]]*$2[[:space:]]*:[[:space:]]*//p" "$RPM/$1" 2>/dev/null | head -1; }
say() { echo "$*"; }

restore_modem() {
	mmcli -m any --set-power-state-on >/dev/null 2>&1
	sleep 5
	mmcli -m any --enable >/dev/null 2>&1
	sleep 5
	say "# modem restored: $(mmcli -m any 2>/dev/null | grep -iE 'power state|state:' | tr -s ' ' | head -2 | tr '\n' ' ')"
}
trap restore_modem EXIT INT TERM

say "# radio-low-leg $TAG uptime=$(cut -d. -f1 /proc/uptime)"
say "# modem before: $(mmcli -m any 2>/dev/null | grep -iE 'power state|state:|signal quality' | tr -s ' ' | tr '\n' ' ')"

mmcli -m any --set-power-state-low >/dev/null 2>&1 || { say "# ABORT: set-power-state-low failed"; exit 1; }
sleep 10
pstate=$(mmcli -m any 2>/dev/null | sed -n 's/.*power state: *//p' | head -1)
[ "$pstate" = low ] || { say "# ABORT: power state is '$pstate', not low - the arm did not take"; exit 1; }
say "# radio armed low"

# The gate: one 90 s suspend; the wall clock has to cover most of it and the
# MPSS crystal has to be off for most of it.
x0=$(mf MPSS 'XO total duration'); t0=$(date +%s)
rtcwake -m mem -s 90 >/dev/null 2>&1
t1=$(date +%s); x1=$(mf MPSS 'XO total duration')
wall=$((t1 - t0)); ms=$(( ( ${x1:-0} - ${x0:-0} ) / 19200 ))
say "# probe suspend: wall ${wall}s of 90, MPSS XO off ${ms}ms"

if [ "$wall" -lt 75 ]; then
	say "# ABORT: the suspend aborted at ${wall}s - radio-low did not stop the modem's wakeups."
	exit 1
fi
if [ "$ms" -lt 60000 ]; then
	say "# ABORT: MPSS crystal off only ${ms}ms of the probe - the modem is still chopping."
	exit 1
fi

say "# gate passed - handing over to slope-leg.sh $TAG (modem restore stays on this shell's exit path)"
/root/slope-leg.sh "$TAG"
rc=$?
say "# slope-leg rc=$rc"
exit $rc
