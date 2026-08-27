#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# One continuous discharge from a full pack to the phone switching itself off,
# logging current, voltage, capacity and temperature the whole way down.
#
# ☠️ WHY THIS IS WORTH KILLING A PACK CHARGE FOR. Three separate numbers that
# every power page on this device rests on are, today, assumptions:
#
#   1. THE PACK'S REAL CAPACITY. Both gauges compute against `charge_full`, which
#      on this phone is the 3 060 000 µAh NAMEPLATE. The pack is years old. Every
#      "points -> mAh" figure on both systems inherits that number.
#   2. THE OCV -> SoC CURVE, i.e. what a given resting voltage actually means. The
#      cross-system ladder comparison had to interpolate one from two anchors.
#   3. THE LOWER LEG OF THE MAPPING. Below 3.967 V the oracle ladder has no data
#      at all, and five of the eight pmOS rungs live entirely down there.
#
# Integrating `current_now` from a known-full pack to shutdown, against what
# `capacity` claims at every point, gives all three from one run. It is also the
# only thing that can settle the standing contradiction where the charge column
# says pmOS cost 2.12x and the current integral of the SAME RUN says 1.20x.
#
#   discharge-run.sh [interval_s]        (default 10)
#
# ☠️ THIS ONE DELIBERATELY HAS NO CAPACITY FLOOR, WHICH EVERY OTHER INSTRUMENT
# HERE DOES. night-ladder.sh stops at 20 % precisely so it never measures the pack
# flat - and that is right for it, because it is measuring the SYSTEM. This is
# measuring the PACK, and stopping early would leave the bottom of the curve, the
# part with no data, still missing. Gating it on `capacity` would be worse than
# useless: `capacity` is the instrument under test. Run this when you can afford
# a flat phone, and not otherwise.
#
# Safety that IS kept, unchanged from night-ladder.sh:
#   - the charge input is restored on every exit path including SIGTERM at
#     shutdown, because `input_suspend` lives in the PMIC and survives a reboot;
#   - state is on persistent storage, written as it goes, so the log survives the
#     power-off that ends the run - which here is the expected ending, not a
#     failure;
#   - a resume: if the phone is plugged in and rebooted, the previous log is kept.
set -u
IV=${1:-10}

for d in /var/log/fp3 /home/user/fp3 /home/phablet/fp3 /userdata/fp3; do
	mkdir -p "$d" 2>/dev/null && [ -w "$d" ] && OUTDIR="$d" && break
done
: "${OUTDIR:?no writable persistent directory found}"
OUT="$OUTDIR/discharge-$(date +%s)"
mkdir -p "$OUT"
LOG="$OUT/log"
say(){ echo "$*" | tee -a "$LOG"; }

BAT=/sys/class/power_supply/battery
[ -d "$BAT" ] || BAT=$(dirname "$(ls /sys/class/power_supply/*/capacity 2>/dev/null | head -1)")

restore_input() {
	# ☠️ Both writes, unconditionally. The suspend bit lives in the PMIC and
	# survives a warm reboot, so a run that dies having written only one of these
	# leaves a phone that will not charge and nobody watching.
	for f in /sys/class/power_supply/*/input_suspend; do
		[ -w "$f" ] && echo 0 > "$f" 2>/dev/null
	done
	for s in /sys/class/power_supply/*/status; do
		case "$s" in *pmi632*|*charger*) echo Charging > "$s" 2>/dev/null ;; esac
	done
}
trap 'say "# signal caught - restoring charge input"; restore_input; exit 143' INT TERM HUP
trap 'restore_input' EXIT

cap0=$(cat "$BAT/capacity" 2>/dev/null || echo "")
case "$cap0" in ""|*[!0-9]*) say "# STOP: capacity unreadable at $BAT/capacity - refusing to run blind"; exit 1 ;; esac
if [ "$cap0" -lt 97 ]; then
	say "# STOP: the pack reads ${cap0}% and this run is only meaningful from full."
	say "#       Charge it, let the charger TERMINATE, then start this again."
	exit 1
fi

say "# discharge-run $(date '+%F %T') interval=${IV}s bat=$BAT"
say "# kernel=$(uname -r) $(uname -v)"
say "# charge_full=$(cat "$BAT/charge_full" 2>/dev/null) charge_full_design=$(cat "$BAT/charge_full_design" 2>/dev/null)"
say "# start: cap=${cap0}% v=$(cat "$BAT/voltage_now") temp=$(cat "$BAT/temp") status=$(cat "$BAT/status")"

# ☠️ THE PANEL IS TAKEN DOWN BY idle-ab.sh AND NOT BY A COPY OF IT HERE. Neither
# writing `blank` nor writing `dpms` works while the compositor holds DRM master;
# what works is locking the session so the compositor blanks it itself, and the
# proof needs several witnesses because each one has already lied once. All of
# that is in idle-ab.sh, so this borrows a short window of it purely for the side
# effect - the session stays locked and the panel stays dark afterwards - and then
# runs its own loop. A twenty-hour discharge measured with a LIT PANEL is worth
# ~24.5 mA of pure garbage, which is most of the floor.
for c in "$(dirname "$0")/idle-ab.sh" /usr/local/bin/idle-ab.sh; do
	[ -x "$c" ] && IDLE_AB="$c" && break
done
: "${IDLE_AB:?idle-ab.sh not found - refusing to start, the panel would stay lit}"
say "# borrowing a 20 s idle-ab window to lock the session and take the panel down"
"$IDLE_AB" 20 >/dev/null 2>&1 || true
bl=$(cat /sys/class/backlight/*/bl_power 2>/dev/null | head -1)
say "# panel after that: bl_power='$bl' dpms='$(cat /sys/class/drm/*/dpms 2>/dev/null | head -1)'"
if [ "${bl:-x}" != 4 ]; then
	say "# STOP: the panel is not down (bl_power='$bl') - refusing to spend a pack charge on a lit screen"
	exit 1
fi

# ☠️ The charge input is cut ONCE and stays cut. idle-ab.sh cuts and restores it
# per window; a discharge that let it back in between samples would be measuring
# the charger.
#
# ☠️☠️ AND THE CUT IS NOT THE SAME ON BOTH SYSTEMS. `input_suspend` is the Ubuntu
# Touch path (`pmi632-battery/input_suspend`); on mainline that file DOES NOT
# EXIST, and the loop above wrote to nothing at all - a twenty-hour run that would
# have measured a phone on the charger and called it a discharge curve. On pmOS
# the input is cut through the charger node's `status`. Found by reading the node
# list on the device, 2026-08-27, before the run rather than after it.
cut_input() {
	done_any=0
	for f in /sys/class/power_supply/*/input_suspend; do
		[ -w "$f" ] && echo 1 > "$f" 2>/dev/null && done_any=1
	done
	for s in /sys/class/power_supply/*charger*/status; do
		[ -w "$s" ] && echo Unknown > "$s" 2>/dev/null && done_any=1
	done
	return $((1 - done_any))
}
cut_input || { say "# STOP: found nothing to cut the charge input with"; exit 1; }
sleep 5
st=$(cat "$BAT/status" 2>/dev/null || echo '?')
say "# charge input cut: status=$st"
# ☠️ Prove the cut, do not assume it. Every sample of a run that kept charging is
# a sample of the charger.
[ "$st" = Discharging ] || {
	say "# STOP: still '$st' after the cut - every sample would read the cable"
	exit 1
}

# ☠️ bl_power is in every row, not just at the start. The compositor re-enables
# the panel on any input, and over twenty hours something will touch it. A column
# that records it lets the analysis drop those rows; a one-off check at the door
# would silently average a lit screen into the curve.
echo "# uptime_s cap_pct v_uV cur_uA temp_dC bl_power status" > "$OUT/discharge.txt"
while :; do
	up=$(cut -d' ' -f1 /proc/uptime)
	cap=$(cat "$BAT/capacity" 2>/dev/null || echo -1)
	v=$(cat "$BAT/voltage_now" 2>/dev/null || echo -1)
	c=$(cat "$BAT/current_now" 2>/dev/null || echo 0)
	tp=$(cat "$BAT/temp" 2>/dev/null || echo -1)
	st=$(cat "$BAT/status" 2>/dev/null || echo ?)
	bl=$(cat /sys/class/backlight/*/bl_power 2>/dev/null | head -1)
	echo "$up $cap $v $c $tp ${bl:-?} $st" >> "$OUT/discharge.txt"
	# ☠️ sync every sample. The run ENDS with the power being cut; anything left
	# in the page cache at that moment is the part of the curve that matters most.
	sync
	sleep "$IV"
done
