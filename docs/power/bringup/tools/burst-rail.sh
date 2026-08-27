#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Which RAIL is up when the current is up.
#
# ☠️ THE INSTRUMENT OF LAST RESORT, AND ONLY BECAUSE EVERY PROFILER IS SPENT.
# The awake burst has now been excluded from software (the trace: 313 events per
# burst bin against 316 per quiet bin), from the CPU (`burst-attrib`: cores in
# power-collapse 99 % of the time DURING the burst, both cpufreq policies pinned),
# from the modem (A-B-A': 2 mA against a 3 mA baseline spread) and from the panel
# (proven dark on every sample). It is nonetheless real power: the pack sags
# 16-20 mV for the extra ~100 mA, at a consistent 156-196 mOhm on three legs.
# Something is powered that is not running code, and rails are what "powered"
# means on this SoC.
#
# What it records, every sample, alongside the current: for all ~57 regulators,
# `state` (enabled/disabled) and `opmode` (fast/normal/idle). ☠️ opmode is the
# interesting one - a rail does not have to switch OFF to stop costing, it drops
# to idle/LPM, and a census that only looked at enabled/disabled would call a
# rail that never turns off "constant" while it swings between LPM and NPM.
#
# ☠️ AND IT IS TWO `grep -H .` CALLS PER SAMPLE, NOT A LOOP. The first version
# looped over the 57 directories with two `cat`s each - 114 forks per sample. It
# was measured at 156 samples where 180 were due, i.e. the sweep itself took over
# two seconds and the instrument was loading the thing it was measuring. "One
# sweep costs under 1 ms" had been measured with a single globbed `cat`, which is
# not what the loop did. Measure the loop you wrote, not the one you meant.
#
# ☠️ AND EVERY VALUE CARRIES ITS OWN PATH. The first version wrote a bare vector
# and a name list in the header, and the two silently disagreed: three regulators
# have no readable `state`, so the vector was 54 long against 57 names and every
# label after the first gap was wrong. `grep -H .` makes each reading
# self-describing, which is the only version of this that cannot drift. (Names are
# not unique either - this phone has two PMICs and so two `l1`, `l2`, `l3`; the
# `regulator.N` directory is the identity, the name is a label.)
#
# ☠️ NO CURRENT PER RAIL EXISTS. `requested_microamps` is what a consumer ASKED
# for, not what flows; on this SoC it is almost always 0. The output of this tool
# is a correlation - which rails are up when the current is up - and never an
# attribution of milliamps. Read it as a shortlist for a scope, not as a bill.
#
#   burst-rail.sh [seconds]        (default 360)
set -u
W=${1:-360}
IV=2
OUT=/var/log/fp3/burst-rail-$(date +%s)
mkdir -p "$OUT"
BAT=$(dirname "$(ls /sys/class/power_supply/*/capacity 2>/dev/null | head -1)")

say(){ echo "$*" | tee -a "$OUT/log"; }
say "# burst-rail $(date '+%F %T') window=${W}s interval=${IV}s bat=$BAT"
say "# kernel=$(uname -r) $(uname -v)"

say "# rails=$(ls -d /sys/class/regulator/regulator.* 2>/dev/null | wc -l)"

sampler(){
	{
		echo "# t_s cur_mA v_mV then one token per rail as regulator.N=<E|D><f|n|i|?>"
		for d in /sys/class/regulator/regulator.*; do
			[ -r "$d/name" ] && echo "# name $(basename "$d") $(cat "$d/name")"
		done
	} > "$OUT/rails.txt"
	t=0
	while [ $t -lt "$((W + 300))" ]; do
		sleep $IV
		t=$((t + IV))
		cur=$(cat "$BAT/current_now" 2>/dev/null || echo 0)
		vol=$(cat "$BAT/voltage_now" 2>/dev/null || echo 0)
		# ☠️ state and opmode must stay DISTINCT keys. Collapsing both to
		# `regulator.N=<x>` would give every rail two tokens with the same
		# name and silently keep whichever the parser saw last.
		vec=$(grep -H . /sys/class/regulator/*/state /sys/class/regulator/*/opmode 2>/dev/null |
			sed -e 's#/sys/class/regulator/##' -e 's#:#=#' |
			sed -e 's#=enabled$#=E#' -e 's#=disabled$#=D#' \
			    -e 's#=fast$#=f#'    -e 's#=normal$#=n#' -e 's#=idle$#=i#' |
			tr '\n' ' ')
		echo "$t $(( (cur<0 ? -cur : cur) / 1000 )) $((vol/1000)) $vec" >> "$OUT/rails.txt"
	done
}

sampler &
spid=$!
say "# sampler pid=$spid, handing the window to idle-ab.sh"
/usr/local/bin/idle-ab.sh "$W" >/dev/null 2>&1
rc=$?
kill $spid 2>/dev/null
wait $spid 2>/dev/null

src=$(ls -t /tmp/idle-ab-*.txt 2>/dev/null | head -1)
[ -n "$src" ] && cp "$src" "$OUT/current.txt"
waited=0
[ -n "$src" ] && waited=$(sed -n 's/.*waited=\([0-9]*\)s.*/\1/p' "$src" | head -1)
[ -z "$waited" ] && waited=0
echo "# window_from=$((waited + IV))  # samples before this mark saw a lit panel" >> "$OUT/rails.txt"
say "# idle-ab rc=$rc panel-wait=${waited}s -> window_from=$((waited + IV))"
[ -n "$src" ] && say "# $(grep '^# panel' "$src" | tr '\n' '|')"
say "# done: $(grep -vc '^#' "$OUT/rails.txt") rail samples"
say "# $OUT"
