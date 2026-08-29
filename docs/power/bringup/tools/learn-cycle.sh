#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# One discharge span wide enough for the gauge to learn the pack from, and a
# witness on what it learned.
#
#   learn-cycle.sh [floor_pct] [interval_s]      (defaults 38 and 10)
#
# WHY IT IS NOT discharge-run.sh. That one deliberately has no floor, because it
# is measuring the pack and stopping early would leave the bottom of the curve
# missing. This is measuring the DRIVER: whether the learning added in r79 closes
# a span and moves `charge_full` toward what the pack actually holds. For that a
# span only has to be wider than the driver's threshold - half the pack - and
# stopping at the floor leaves a phone that can carry on working afterwards.
#
# ☠️ It has to START from a terminated charge. The upper anchor is the charger
# saying it finished; a run started at 91 % has no anchor at the top and the span
# begins wherever the first rest-OCV happens to land, which is not a controlled
# experiment. The check below refuses anything under 97 %.
#
# ☠️ `charge_full` is recorded in every row, not just at the ends. The learning
# fires inside an anchor, which can happen at any sample, and a value read only
# at the end cannot say when - or whether it moved once or three times.
#
# Safety is discharge-run.sh's, unchanged: the charge input is restored on every
# exit path including SIGTERM, because the suspend bit lives in the PMIC and
# survives a warm reboot.
set -u
FLOOR=${1:-38}
IV=${2:-10}

for d in /var/log/fp3 /home/user/fp3 /home/phablet/fp3 /userdata/fp3; do
	mkdir -p "$d" 2>/dev/null && [ -w "$d" ] && OUTDIR="$d" && break
done
: "${OUTDIR:?no writable persistent directory found}"
OUT="$OUTDIR/learn-cycle-$(date +%s)"
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

say "# learn-cycle $(date '+%F %T') floor=${FLOOR}% interval=${IV}s bat=$BAT"
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
cf0=$(cat "$BAT/charge_full" 2>/dev/null || echo -1)
cf_last=$cf0
say "# charge_full at the start of the span: $cf0"
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
echo "# uptime_s cap_pct v_uV cur_uA temp_dC bl_power status charge_full_uah" > "$OUT/discharge.txt"
while :; do
	up=$(cut -d' ' -f1 /proc/uptime)
	cap=$(cat "$BAT/capacity" 2>/dev/null || echo -1)
	v=$(cat "$BAT/voltage_now" 2>/dev/null || echo -1)
	c=$(cat "$BAT/current_now" 2>/dev/null || echo 0)
	tp=$(cat "$BAT/temp" 2>/dev/null || echo -1)
	st=$(cat "$BAT/status" 2>/dev/null || echo ?)
	bl=$(cat /sys/class/backlight/*/bl_power 2>/dev/null | head -1)
	cf=$(cat "$BAT/charge_full" 2>/dev/null || echo -1)
	echo "$up $cap $v $c $tp ${bl:-?} $st $cf" >> "$OUT/discharge.txt"
	if [ "$cf" != "$cf_last" ]; then
		say "# cap=${cap}% charge_full ${cf_last} -> ${cf}"
		cf_last=$cf
	fi
	# ☠️ sync every sample. The run ENDS with the power being cut; anything left
	# in the page cache at that moment is the part of the curve that matters most.
	sync
	case "$cap" in ''|*[!0-9]*) : ;; *)
		if [ "$cap" -le "$FLOOR" ]; then
			say "# reached the ${FLOOR}% floor at cap=${cap}%"
			break
		fi ;;
	esac
	sleep "$IV"
done

restore_input
say "# charge input restored: status=$(cat "$BAT/status" 2>/dev/null)"
say "# charge_full at start=$cf0 at end=$(cat "$BAT/charge_full" 2>/dev/null)"
say "# design=$(cat "$BAT/charge_full_design" 2>/dev/null)"
say "$OUT"
