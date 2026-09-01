#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# The XO counter, sampled once a second, as a TIME SERIES instead of a total.
#
# Every modem measurement in this tree so far divides one accumulated counter by
# one window and calls the result a duty. That number cannot tell apart the two
# mechanisms that would explain the same 38%:
#
#   per-occasion work  - the modem does ~150 ms of something every paging cycle,
#                        so nearly every second looks the same
#   acquisition scans  - the modem is idle for tens of seconds and then burns
#                        several SECONDS in one stretch scanning for a system
#                        that is not there (a RAT in the preference list with no
#                        coverage will do this)
#
# The mean is identical; the series is not, and the two want opposite fixes. So
# sample the counter every second and keep the deltas.
#
# It also does something the totals cannot: it TIMESTAMPS a state transition.
# This system has twice moved between a ~5% and a ~35% regime on its own and no
# capture has ever caught the moment, because every instrument integrated over
# it. A per-second series turns every leg into a transition detector after the
# fact, at no extra cost.
#
# ☠️ A 1 Hz SAMPLER KEEPS THE AP AWAKE. That is fine inside an awake leg - which
# is what every ladder here runs - and WRONG inside a sleep census: it would
# suppress the suspend it is meant to observe. Do not put it in modem-night.sh.
#
# ☠️ THE TICK IS THE 19.2 MHz XO, not the sleep clock: duration/19200 is ms.
# Getting that wrong yields a plausible-looking nonsense, which is the dangerous
# kind.
#
# ☠️ A ZERO DELTA IS TWO DIFFERENT WORLDS, AND THIS TOOL SHIPPED WITHOUT SAYING
# WHICH. The counter is EDGE-UPDATED - measured, 2026-08-31, captures/
# 2026-08-31_xo-dur-semantics: it advances when a master EXITS XO shutdown. So a
# master that stayed DOWN for the whole window accumulates delta 0 and count 0 -
# byte-identical to a master that stayed AWAKE for the whole window. Reading the
# first as the second is exactly the inversion that had three days of write-ups
# claiming "LPASS awake 100 %" while it was in fact down for 1.68 h, and it is
# the same signature an ADSP A/B of ours carried on 2026-09-01.
#
# The disambiguators are `Last XO shutdown enter` vs `exit` (enter later => it is
# down right now) and `Active cores bitmask`. This samples them every second and
# prints the state, so a zero row can never be silently read as "awake". For MPSS
# in the states measured so far the counter does accumulate - 375 toggles in
# 120 s - so the series is meaningful there; the guard is for every other master
# and for the day MPSS itself parks.
#
# ☠️ THE FIELD IS SPELLED DIFFERENTLY ON THE TWO SYSTEMS and a miss prints a
# blank, which reads as a zero - and zero is a meaningful value for this counter.
# Mainline writes `XO total duration: 407012504635` (decimal, space); the Ubuntu
# Touch oracle writes `xo_accumulated_duration:0xAE0147EB` (hex, colon). Accept
# both, and SAY SO when neither matched, so the same instrument runs on both
# slots. rpm-xo-snapshot.sh learned this the hard way.
#
# ☠️ THE RTC ON THIS DEVICE READS 1970. Wall-clock timestamps are meaningless
# and differences across them can go backwards; the clock here is /proc/uptime,
# which is monotonic. And a sample that arrives late must be divided by the time
# that ACTUALLY elapsed, not by the 1 s that was intended - otherwise a
# descheduled sampler invents a duty spike.
#
#   xo-series.sh <seconds> [master]        default master MPSS
#
# Output: one line per sample, plus a `#` header. Feed it to xo-series-fit.py.
set -u
SECS=${1:-600}
MASTER=${2:-MPSS}
MS=/sys/kernel/debug/qcom_rpm_master_stats
TICK=19200000

modprobe rpm_master_stats 2>/dev/null
F="$MS/$MASTER"
[ -e "$F" ] || { echo "☠️ $F absent - module missing, or not root. NOT a zero." >&2; exit 1; }

# One awk, both spellings. Prints "<xo_duration_ticks> <xo_shutdown_count>", or
# nothing at all if neither spelling matched - the caller checks for that.
snap() {
	awk '
	  /XO total duration:/            { d=$4 }
	  /XO shutdown count:/            { c=$4 }
	  /Last XO shutdown enter:/       { en=$5 }
	  /Last XO shutdown exit:/        { ex=$5 }
	  /Active cores bitmask:/         { ac=$4 }
	  /xo_accumulated_duration/       { s=$0; sub(/.*:[[:space:]]*/,"",s); d=strtonum(s) }
	  /xo_count/                      { s=$0; sub(/.*:[[:space:]]*/,"",s); c=strtonum(s) }
	  /xo_last_entered_at/            { s=$0; sub(/.*:[[:space:]]*/,"",s); en=strtonum(s) }
	  /xo_last_exited_at/             { s=$0; sub(/.*:[[:space:]]*/,"",s); ex=strtonum(s) }
	  END { if (d != "") printf "%d %d %s %s %s\n", d, c+0, en+0, ex+0, (ac == "" ? "?" : ac) }' "$F"
}

now() { awk '{printf "%.3f\n", $1}' /proc/uptime; }

first=$(snap)
[ -n "$first" ] || { echo "☠️ neither field spelling matched in $F - NOT a zero." >&2; exit 1; }
# state: DOWN if it entered shutdown more recently than it exited one.
state(){ awk -v en="$1" -v ex="$2" -v ac="$3" 'BEGIN{
	  print (en+0 > ex+0 ? "down" : "up") (ac == "0x0" || ac == "" ? "" : "+cores")}'; }

echo "# xo-series master=$MASTER window=${SECS}s tick=$TICK sampled at 1 Hz"
echo "# kernel=$(uname -v 2>/dev/null)"
echo "# t_s  awake_ms  xo_off_ms  dt_s  xo_shutdowns  state"
echo "# ☠️ state=down with awake_ms=1000 means the master was ASLEEP THE WHOLE SECOND"
echo "#    and the edge-updated counter simply did not advance - NOT 100% awake."
set -- $first; pd=$1; pc=$2; pen=$3; pex=$4; pac=$5
pt=$(now); t0=$pt
while :; do
	sleep 1
	s=$(snap); t=$(now)
	[ -n "$s" ] || continue
	set -- $s; d=$1; c=$2; en=$3; ex=$4; ac=$5
	st=$(state "$en" "$ex" "$ac")
	awk -v d="$d" -v pd="$pd" -v c="$c" -v pc="$pc" -v t="$t" -v pt="$pt" -v t0="$t0" -v tick="$TICK" -v st="$st" '
	  BEGIN {
	    dt = t - pt; if (dt <= 0) exit
	    off = (d - pd) / tick * 1000            # ms the XO was OFF in this sample
	    win = dt * 1000
	    aw  = win - off; if (aw < 0) aw = 0     # clamp: counter and clock are not the same source
	    printf "%.1f %.1f %.1f %.3f %d %s\n", t - t0, aw, off, dt, c - pc, st
	  }' 
	pd=$d; pc=$c; pen=$en; pex=$ex; pac=$ac; pt=$t
	awk -v t="$t" -v t0="$t0" -v s="$SECS" 'BEGIN{exit !(t-t0 >= s)}' && break
done
