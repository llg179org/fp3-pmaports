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
restore() {
	input_on 2>/dev/null
	for fb in $BLANKED; do echo 0 > "$fb" 2>/dev/null; done
	echo "# restored: input=$(input_state) status=$(cat $BAT/status)"
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
# ☠️☠️ Two further corrections, both measured 2026-08-25, both by this script
# failing at the job it exists for:
#
#   1. `systemctl stop greetd` does NOT stop the compositor. greetd reads
#      inactive while `phoc` and `phrog` keep running and keep DRM master, so
#      the clause that was supposed to release the panel silently did nothing
#      for two whole runs. A step whose effect is not checked is not a step.
#   2. The proof read `/sys/class/drm/*/dpms`, a property owned by the very
#      compositor we could not stop - and on that basis a perfectly good run
#      was declared INVALID. The panel's own `bl_power` read 4
#      (FB_BLANK_POWERDOWN) throughout. Read the hardware, never the software's
#      description of it.
#
# So the compositor is now left alone - it is running on both sides of the
# comparison anyway, and stopping it is not the configuration a phone is in
# during normal use. We ask for the panel off, then WAIT for the display stack
# (ours or the compositor's own idle blank) to actually take it down, and prove
# it from `bl_power` / the DRM CRTC's `active` flag. Abort if it cannot be
# proven. A gate that cannot fail is not a gate.
# The panel bias rails, where the hardware has them (the 4.9 oracle's PMI632
# qpnp-lcdb). ☠️ Read `state`/`enable`, NEVER `microvolts`: the voltage file
# reports the rail's CONFIGURED voltage and sits at 5500000 whether the rail is
# on or off. Measured 2026-08-26: across a blank=4 that demonstrably powered the
# panel down, `microvolts` did not move one digit while `enable` went 1 -> 0.
# Reading the voltage is very probably where "fb0/blank is only a half blank,
# the LCDB stays at 5500 mV" came from - a claim this file no longer accepts.
# ☠️ Resolved ONCE, not per sample. Walking every regulator to match a name is
# ~200 file opens, and at one sample every 5 s that is the instrument competing
# with the thing it measures - on a run whose whole subject is a few tens of mA.
# Empty on a system that has no such rail, which simply leaves the veto unarmed.
LCDB_FILES=
for d in /sys/class/regulator/*/; do
	n=$(cat "$d/name" 2>/dev/null) || continue
	case "$n" in
	*lcdb*|*lab*|*ibb*) LCDB_FILES="$LCDB_FILES $d/state" ;;
	esac
done

lcdb_state() {
	for f in $LCDB_FILES; do
		printf '%s=%s,' "$(basename "$(dirname "$f")")" "$(cat "$f" 2>/dev/null)"
	done
}
lcdb_says_on() {
	for f in $LCDB_FILES; do
		[ "$(cat "$f" 2>/dev/null)" = enabled ] && return 0
	done
	return 1
}

# --- the state the phone was in, not just how much it drew ------------------
# ☠️ Added 2026-08-26, after four windows of oracle data could not be compared
# with a fifth from another day. Every one of them recorded the state of charge
# and nothing else about the conditions, so when the numbers disagreed by 4.5x
# there was no way to tell a colder pack from a busier radio from a different
# WiFi state - the three explanations that outlive the state of charge. A
# measurement that cannot name what differed between two runs is not a
# comparison, however carefully the current itself was sampled.
#
# Everything here is best-effort and CROSS-OS, and each probe prints `?` rather
# than nothing when it finds no source: an absent line reads as "this did not
# apply", which is the failure this block exists to stop.

bat_temp() {
	# deci-degC. mainline exposes it on the charger (added by this port), the
	# downstream 4.9 gauge on the battery node.
	for f in "$BAT/temp" /sys/class/power_supply/*/temp; do
		[ -r "$f" ] && { cat "$f"; return; }
	done
	echo '?'
}

env_snapshot() {
	echo "# --- environment ($1) ---"
	echo "# uptime_s=$(cut -d' ' -f1 /proc/uptime 2>/dev/null || echo '?')" \
	     "loadavg=$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo '?')"
	echo "# battery: temp_dC=$(bat_temp)" \
	     "capacity=$(cat "$BAT/capacity" 2>/dev/null || echo '?')" \
	     "v=$(cat "$BAT/voltage_now" 2>/dev/null || echo '?')" \
	     "status=$(cat "$BAT/status" 2>/dev/null || echo '?')" \
	     "full_uAh=${FULL_UAH:-?}"

	# Thermal zones: the pack is one temperature, the SoC another, and a run
	# that idles hot is not the same run.
	printf '# thermal:'
	found=
	for z in /sys/class/thermal/thermal_zone*/; do
		[ -r "$z/temp" ] || continue
		printf ' %s=%s' "$(cat "$z/type" 2>/dev/null)" "$(cat "$z/temp" 2>/dev/null)"
		found=1
	done
	[ -n "$found" ] || printf ' ?'
	echo

	# WiFi: /proc/net/wireless is the one file both kernels have, and it
	# carries the signal level, not just "associated".
	# ☠️ The signal level, not just "associated": a weak link makes the radio
	# retransmit and transmit harder, so two runs at -84 and at -60 dBm are not
	# the same idle. Measured 2026-08-26: it moved 6 dB inside a 60 s window.
	# ☠️ And do NOT test /proc/net/wireless with `test -s` - procfs files report
	# size 0 whatever they contain, so the "nothing found" marker printed on top
	# of a perfectly good reading. Build the string first, then judge it.
	wl=$(sed -n '3,$p' /proc/net/wireless 2>/dev/null |
		while read -r ifc _ link level _; do
			printf ' %s link=%s level=%s' \
				"${ifc%:}" "${link%.}" "${level%.}"
		done)
	echo "# wifi:${wl:- ?}"

	# The modem. ☠️ This is the device's largest known waker (IRQ 141, the SMD
	# edge), so a run that does not record its state cannot rule it out. The
	# two kernels expose it under different names: mainline as a remoteproc,
	# downstream 4.9 as an msm_subsys device.
	printf '# remote processors:'
	found=
	for r in /sys/class/remoteproc/remoteproc*/; do
		[ -r "$r/state" ] || continue
		printf ' %s=%s' "$(cat "$r/name" 2>/dev/null)" "$(cat "$r/state" 2>/dev/null)"
		found=1
	done
	for s in /sys/bus/msm_subsys/devices/subsys*/; do
		[ -r "$s/state" ] || continue
		printf ' %s=%s' "$(cat "$s/name" 2>/dev/null)" "$(cat "$s/state" 2>/dev/null)"
		found=1
	done
	[ -n "$found" ] || printf ' ?'
	echo

	# Registration is userspace and neither OS answers it the same way. Say so
	# in the file: an unrecorded radio state is a named gap, not an absence.
	printf '# radio registration:'
	if command -v mmcli >/dev/null 2>&1; then
		printf ' %s' "$(mmcli -m 0 2>/dev/null |
			sed -n 's/.*state: *\([a-z]*\).*/\1/p' | head -1)"
		printf ' (mmcli; needs root - blank means it refused)'
	elif [ -d /sys/class/net/rmnet_data0 ]; then
		printf ' rmnet_data0=%s (link state only; not registration)' \
			"$(cat /sys/class/net/rmnet_data0/operstate 2>/dev/null)"
	else
		printf ' ? NOT RECORDED - no cross-OS source'
	fi
	echo
	echo "# --- end environment ($1) ---"
}

# One compact line of everything that claims to know, for the sample stream and
# for the end-of-window verdict.
panel_state() {
	printf 'ppo=%s,bl=%s,blp=%s,%s' \
		"$(sed -n 's/.*panel_power_on = \([0-9]*\).*/\1/p' \
			/sys/class/graphics/fb0/show_blank_event 2>/dev/null | head -1)" \
		"$(cat /sys/class/backlight/*/brightness /sys/class/leds/lcd-backlight/brightness \
			2>/dev/null | head -1)" \
		"$(cat /sys/class/backlight/*/bl_power 2>/dev/null | head -1)" \
		"$(lcdb_state)"
}

panel_is_off() {
	# ☠️ A powered bias rail vetoes every other witness. This is the hardware
	# itself and nothing in userspace can make it read off while the panel is
	# lit, which is more than can be said for the backlight, for a DBus return
	# value, or for a DRM property owned by the compositor.
	lcdb_says_on && return 1
	# The panel's own power state: 4 = FB_BLANK_POWERDOWN. This is the
	# hardware, and it is not writable by the compositor's DRM lease.
	for p in /sys/class/backlight/*/bl_power; do
		[ -r "$p" ] || continue
		[ "$(cat "$p" 2>/dev/null)" = 4 ] && return 0
	done
	# Downstream mdss (the 4.9 oracle) has no bl_power and no DRM sysfs, and
	# ☠️ its backlight brightness is NOT a witness: measured 2026-08-25, the
	# panel was fully powered at brightness 37-38 for 25 minutes while nothing
	# held a "keep display on" request, and unity-system-compositor answered
	# setScreenPowerMode("off") with `true` while leaving it powered. The one
	# file that reports the panel itself is show_blank_event.
	if [ -r /sys/class/graphics/fb0/show_blank_event ]; then
		grep -q 'panel_power_on = 0' /sys/class/graphics/fb0/show_blank_event 2>/dev/null && return 0
		return 1
	fi
	# Fall back to the CRTC actually being off (mainline DRM), then to a zero
	# backlight on a kernel that has neither (UT 4.9).
	if [ -r /sys/kernel/debug/dri/0/state ] &&
	   grep -q 'active=0' /sys/kernel/debug/dri/0/state 2>/dev/null &&
	   ! grep -q 'active=1' /sys/kernel/debug/dri/0/state 2>/dev/null; then
		return 0
	fi
	BL=$(cat /sys/class/backlight/*/brightness /sys/class/leds/lcd-backlight/brightness 2>/dev/null | head -1)
	[ -z "$(cat /sys/class/drm/*/dpms 2>/dev/null | head -1)" ] && [ "${BL:-x}" = 0 ]
}

# ☠️ Neither writing `blank` nor writing `dpms` takes the panel down while a
# compositor holds DRM master - both are refused or undone, measured 2026-08-25.
# What does work, and is what a person does to a phone anyway, is locking the
# session: phosh then blanks the panel itself and `bl_power` goes to 4.
#
# The oracle is the other way round and needs both halves of this loop. On the
# 4.9 side, measured 2026-08-25:
#   * it never blanks on its own. powerd's inactivity action is not set to
#     display-off, so the panel stays lit indefinitely with NO inhibitor held
#     (`powerd-cli listsysrequests` lists nothing on any of its three lists).
#     Waiting is not a strategy there; 25 minutes bought nothing.
#   * `setScreenPowerMode("off", reason)` on com.canonical.Unity.Screen returns
#     `false` for most reasons and `true` for two of them - and the panel stays
#     powered either way. A DBus method returning success is not a measurement.
#   * writing 4 to /sys/class/graphics/fb0/blank DOES take it down, hwcomposer
#     notwithstanding: show_blank_event flips to `panel_power_on = 0`, the
#     backlight goes to 0 and all five MDSS/DSI clocks leave enabled_clocks.
# So the loop below - write, then prove - is what works on both, and it is the
# proof that had to change, not the write.
for s in $(loginctl list-sessions --no-legend 2>/dev/null | awk '$4 != "-" {print $1}'); do
	loginctl lock-session "$s" 2>/dev/null && echo "# locked session $s"
done

PANEL_WAIT=${PANEL_WAIT:-240}
echo "# asking for the panel off, then waiting up to ${PANEL_WAIT}s for the hardware to say it is"
i=0
while [ "$i" -lt "$PANEL_WAIT" ]; do
	for fb in /sys/class/graphics/fb*/blank; do
		[ -w "$fb" ] && { echo 4 > "$fb" 2>/dev/null; case " $BLANKED " in *" $fb "*) ;; *) BLANKED="$BLANKED $fb";; esac; }
	done
	for d in /sys/class/drm/*/dpms; do [ -w "$d" ] && echo off > "$d" 2>/dev/null; done
	panel_is_off && break
	sleep 5
	i=$((i + 5))
done
echo "# panel: bl_power='$(cat /sys/class/backlight/*/bl_power 2>/dev/null | head -1)'" \
     "dpms='$(cat /sys/class/drm/*/dpms 2>/dev/null | head -1)'" \
     "brightness='$(cat /sys/class/backlight/*/brightness 2>/dev/null | head -1)'" \
     "waited=${i}s blanked:$BLANKED"
if ! panel_is_off; then
	echo "# ABORT: could not prove the panel is off. A lit panel is worth ~24.5 mA"
	echo "#        and would be read as a difference between the two systems."
	echo "#        If the session is active, lock the screen or let it idle out first."
	exit 1
fi

input_off
sleep 20
[ "$(cat "$BAT/status")" = Discharging ] || { echo "# ABORT: still $(cat $BAT/status) - every sample would read the cable"; exit 1; }
echo "# on battery: v=$(cat $BAT/voltage_now)"

c0=$([ -n "$CC" ] && cat "$CC" || echo -); v0=$(cat "$BAT/voltage_now"); t0=$(date +%s)
# ☠️ The panel state is carried in every sample, not just checked at the start.
# Until 2026-08-26 this loop proved the panel dark once and then measured for an
# hour without looking again - so a panel that came back up mid-window would be
# read as the phone drawing more current, on the exact question ("was the screen
# really off") this instrument exists to settle. A gate at the door only.
env_snapshot "opening"

echo "# t_s current_uA voltage_uV${CC:+ cc_soc} panel temp_dC"
RELIT=
while [ $(( $(date +%s) - t0 )) -lt "$WINDOW" ]; do
	ps=$(panel_state)
	panel_is_off || RELIT="$RELIT $(( $(date +%s) - t0 ))"
	printf '%s %s %s %s %s %s\n' "$(( $(date +%s) - t0 ))" \
		"$(cat "$BAT/current_now")" "$(cat "$BAT/voltage_now")" \
		"$([ -n "$CC" ] && cat "$CC" || echo -)" "$ps" "$(bat_temp)"
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
# ☠️ The closing gate. An hour of samples taken behind a panel that relit is not
# a floor measurement, and the only honest thing to do with it is to say so in
# the file rather than to average it.
echo "# panel at end: $(panel_state)"
if [ -n "$RELIT" ]; then
	echo "# ☠️ INVALID: the panel was NOT off at t =$RELIT (seconds into the window)."
	echo "#    Do not quote a floor or a median from this run. A lit panel was"
	echo "#    worth +24.5 mA on every floor measured before 2026-08-19."
else
	echo "# panel: off for all $(( W / 5 + 1 )) samples of the window"
fi
env_snapshot "closing"
echo "# DONE $(date)"
echo "# output: $OUT"
