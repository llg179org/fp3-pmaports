#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Find what produces the awake current bursts, by recording the current AND the
# kernel's own wakeup events on one clock so they can be laid against each other.
#
# The ladders showed pmOS bursts on two thirds of its samples with ~81 s of period
# that the oracle does not have. Counting interrupts cannot answer "what runs every
# 81 s" - that is a question about WHICH work, not HOW MUCH.
#
# ☠️ THE TRACER IS NOT FREE. Tracepoints cost time on every wakeup, so the current
# recorded here is NOT comparable to an idle-ab figure and must never be quoted as
# an idle number. What survives the overhead is the STRUCTURE: which work repeats,
# and with what period.
#
# ☠️ AND THE PANEL MUST BE DOWN. A lit panel is worth ~24.5 mA and would swamp
# what is being looked for. This refuses to run rather than measure a lit screen.
#
#   burst-source.sh [seconds]        (default 360)
set -u
W=${1:-360}
T=/sys/kernel/debug/tracing
OUT=/var/log/fp3/burst-source-$(date +%s)
mkdir -p "$OUT"
BAT=$(dirname "$(ls /sys/class/power_supply/*/capacity 2>/dev/null | head -1)")

say(){ echo "$*" | tee -a "$OUT/log"; }
say "# burst-source $(date '+%F %T') window=${W}s bat=$BAT"
say "# kernel=$(uname -r) $(uname -v)"

# ☠️ THE PANEL IS NOT HANDLED HERE, AND THAT IS THE POINT. A first version of this
# script wrote /sys/class/graphics/fb*/blank and gated on bl_power, and it aborted
# on a phone where idle-ab.sh took the panel down in the same minute with waited=0s
# - because idle-ab also writes the DRM dpms property, and the gate needs both.
# Duplicating a working instrument to save one exec is how you get two instruments
# that disagree. So the tracer wraps idle-ab.sh: it owns the panel, the charge
# input, the sampling and the proof, and this script owns only the tracer.
T=/sys/kernel/debug/tracing
echo 0 > $T/tracing_on
echo > $T/trace
echo 16384 > $T/buffer_size_kb 2>/dev/null
echo nop > $T/current_tracer
for e in workqueue/workqueue_execute_start timer/timer_expire_entry; do
	[ -e "$T/events/$e/enable" ] && echo 1 > "$T/events/$e/enable" || say "# no such event: $e"
done
echo 1 > $T/tracing_on
say "# tracing armed at $(date '+%T'), handing the window to idle-ab.sh"

/usr/local/bin/idle-ab.sh "$W" >/dev/null 2>&1
rc=$?
echo 0 > $T/tracing_on
for e in workqueue/workqueue_execute_start timer/timer_expire_entry; do
	[ -e "$T/events/$e/enable" ] && echo 0 > "$T/events/$e/enable"
done
cp $T/trace "$OUT/trace.txt"

src=$(ls -t /tmp/idle-ab-*.txt 2>/dev/null | head -1)
[ -n "$src" ] && cp "$src" "$OUT/current.txt"
say "# idle-ab rc=$rc"
say "# $(grep -E '^# (panel|ABORT|on battery)' "$OUT/current.txt" 2>/dev/null | tr '\n' '|')"
say "# done: $(wc -l < "$OUT/trace.txt") trace lines, $(grep -c '^[0-9]' "$OUT/current.txt" 2>/dev/null) current samples"
say "# $OUT"
echo "$OUT"
