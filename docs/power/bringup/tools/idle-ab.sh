#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Fable 5) under the direction of Lajosházi, László Gergely.
#
# The same idle measurement on BOTH operating systems, so the two numbers are a
# comparison rather than two measurements.
#
# The goal this serves (stated 2026-08-24): bring pmOS's consumption down to the
# UT level or below. The gap is idle depth — the oracle idles at ~22 mA where
# pmOS idles at 58-63, and does it awake, not asleep. Closing it needs the two
# sides measured by one instrument on one protocol; until 2026-08-24 the pmOS
# number came from medianed `current_now` and the UT number from a different day
# and a different method, which is not a comparison.
#
# THE PROTOCOL (identical on both, and every clause of it cost something):
#   * panel OFF, not backlight 0. ☠️ A panel at zero brightness is still powered
#     and was worth +24.5 mA on every floor measured before 2026-08-19.
#   * on battery, with the cable left plugged in: the charger input is suspended
#     in software so the sample is the phone, not the cable. ☠️ On both PMICs
#     that bit survives a warm reboot; it is restored on every exit path here.
#   * WiFi associated, one ssh session, radio up — the state the phone is
#     actually in. ☠️ Do not poll it over that session while it runs: every
#     packet is a wakeup, and on the UT side the wakeups ARE the phenomenon.
#
# TWO INSTRUMENTS, and the second is the one that makes it honest:
#   * `current_now`, sampled. ☠️ One read scatters ±138 mA and the distribution
#     is a quiet floor plus bursts, so this reports the FLOOR (p10) and the
#     median, never a mean, and never a single sample.
#   * `bms/cc_soc` where it exists (the downstream QG gauge, UT side only): a
#     real coulomb counter, validated both directions 2026-08-24 — implied
#     97.3 mA against a medianed 103.4 discharging, 1.079 against delivered
#     charge charging. It integrates, so it sees the bursts the sampler misses.
#     ☠️ `bms/charge_counter` is NOT one: it did not move at all over 453 s at
#     ~103 mA and steps in exactly 1 % of `charge_full` — the same OCV-lookup
#     trap as pmOS's `charge_now`. Never price anything with it on either system.
#
#   idle-ab.sh [window_s]            (default 3600)
set -u

WINDOW=${1:-3600}
OUT=/tmp/idle-ab-$(date +%s 2>/dev/null || echo run).txt

# --- which phone are we on -----------------------------------------------
if [ -d /sys/class/power_supply/pmi632-battery ]; then
	OS=pmos
	BAT=/sys/class/power_supply/pmi632-battery
	CHG=/sys/class/power_supply/pmi632-charger
	CC=
else
	OS=ut
	BAT=/sys/class/power_supply/battery
	CHG=
	CC=/sys/class/power_supply/bms/cc_soc
	FULL_UAH=$(cat /sys/class/power_supply/bms/charge_full 2>/dev/null)
fi
exec > "$OUT" 2>&1

input_off() { [ "$OS" = pmos ] && echo Unknown > "$CHG/status" || echo 1 > "$BAT/input_suspend"; }
input_on()  { [ "$OS" = pmos ] && echo Charging > "$CHG/status" || echo 0 > "$BAT/input_suspend"; }
input_state() { [ "$OS" = pmos ] && cat "$CHG/online" || cat "$BAT/input_suspend"; }

BLANKED=
COMPOSITOR=
restore() {
	input_on 2>/dev/null
	for fb in $BLANKED; do echo 0 > "$fb" 2>/dev/null; done
	for c in $COMPOSITOR; do systemctl start "$c" 2>/dev/null; done
	echo "# restored: input=$(input_state) status=$(cat $BAT/status) compositor:${COMPOSITOR:-none}"
}
trap restore EXIT INT TERM

echo "# idle-ab $(date) os=$OS window=${WINDOW}s"
echo "# kernel=$(uname -r) $(uname -v)"

# ☠️ Refuse rather than measure through a state we did not set: an input that is
# already suspended is a leftover from an earlier leg, and its cause matters
# more than this run does.
[ "$OS" = pmos ] && pre=$(cat "$CHG/online") || pre=$(cat "$BAT/input_suspend")
if { [ "$OS" = pmos ] && [ "$pre" != 1 ]; } || { [ "$OS" = ut ] && [ "$pre" != 0 ]; }; then
	echo "# ABORT: charger input is not in its normal state (read '$pre') - investigate, do not measure"
	exit 1
fi

# ☠️ Blanking the framebuffer is not turning the panel off, and the difference
# was worth +24.5 mA on every floor measured before 2026-08-19. On pmOS the
# COMPOSITOR holds DRM master and re-enables the panel behind you: writing dpms
# under it fails with EACCES and `blank` is undone, so the run measures a lit
# screen while believing it measured a dark one. Measured 2026-08-25: exactly
# that, a whole wasted hour reading 157 mA median against an expected 58-63.
#
# So: stop the compositor first, then blank, then PROVE it went off — and abort
# if it cannot be proven. A gate that cannot fail is not a gate.
COMPOSITOR=
for c in greetd lightdm sddm gdm unity8 lomiri; do
	if systemctl is-active --quiet "$c" 2>/dev/null; then
		systemctl stop "$c" 2>/dev/null && COMPOSITOR="$COMPOSITOR $c"
	fi
done
echo "# stopped compositor:${COMPOSITOR:- (none running)}"
sleep 3

i=0
while [ "$i" -lt 10 ]; do
	for fb in /sys/class/graphics/fb*/blank; do
		[ -w "$fb" ] && { echo 4 > "$fb" 2>/dev/null; case " $BLANKED " in *" $fb "*) ;; *) BLANKED="$BLANKED $fb";; esac; }
	done
	for d in /sys/class/drm/*/dpms; do [ -w "$d" ] && echo off > "$d" 2>/dev/null; done
	sleep 2
	i=$((i + 1))
	DPMS=$(cat /sys/class/drm/*/dpms 2>/dev/null | head -1)
	BL=$(cat /sys/class/backlight/*/brightness /sys/class/leds/lcd-backlight/brightness 2>/dev/null | head -1)
	# proof accepted from EITHER stack: the DRM connector says Off, or the
	# panel's own backlight reads 0 on a kernel with no DRM dpms node (UT 4.9).
	[ "$DPMS" = Off ] && break
	{ [ -z "$DPMS" ] && [ "${BL:-x}" = 0 ]; } && break
done
echo "# panel: dpms='${DPMS:-<no drm dpms node>}' backlight='${BL:-?}' blanked:$BLANKED"
if [ "$DPMS" != Off ] && ! { [ -z "$DPMS" ] && [ "${BL:-x}" = 0 ]; }; then
	echo "# ABORT: could not prove the panel is off. A lit panel is worth ~24.5 mA"
	echo "#        and would be read as a difference between the two systems."
	exit 1
fi

input_off
sleep 20
[ "$(cat "$BAT/status")" = Discharging ] || { echo "# ABORT: still $(cat $BAT/status) - every sample would read the cable"; exit 1; }
echo "# on battery: v=$(cat $BAT/voltage_now)"

c0=$([ -n "$CC" ] && cat "$CC" || echo -); v0=$(cat "$BAT/voltage_now"); t0=$(date +%s)
echo "# t_s current_uA voltage_uV${CC:+ cc_soc}"
while [ $(( $(date +%s) - t0 )) -lt "$WINDOW" ]; do
	printf '%s %s %s %s\n' "$(( $(date +%s) - t0 ))" \
		"$(cat "$BAT/current_now")" "$(cat "$BAT/voltage_now")" \
		"$([ -n "$CC" ] && cat "$CC" || echo -)"
	sleep 5
done
t1=$(date +%s); v1=$(cat "$BAT/voltage_now"); c1=$([ -n "$CC" ] && cat "$CC" || echo -)
W=$((t1-t0))
echo "# WINDOW=${W}s v $v0 -> $v1"
if [ -n "$CC" ]; then
	# cc_soc is 0..10000 for 0..100 % of charge_full
	echo "# cc_soc $c0 -> $c1 d=$((c0-c1)) full_uAh=${FULL_UAH:-?}"
	echo "# integrated mA = (d/10000)*full_uAh/1000 * 3600/W  -- compute offline"
fi
echo "# DONE $(date)"
echo "# output: $OUT"
