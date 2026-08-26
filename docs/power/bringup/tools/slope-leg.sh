#!/bin/sh
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# A slope leg with an arbitrary cut applied - the generalisation of leg3.sh and
# leg3-control.sh, which differed from each other only in a guard and a tag.
#
# Usage: slope-leg.sh <tag> [service ...]
#   tag        names the run: the log, the archived slope file, the samples
#   service    zero or more systemd units stopped for the whole leg, and
#              restarted on every exit path
#
# Examples:
#   slope-leg.sh baseline-20260819
#   slope-leg.sh nomodem-20260819 ModemManager rmtfs tqftpserv
#
# ☠️ The cut is applied AFTER the descent and BEFORE the slope instrument, so
# that phase A and phase B see exactly the same system. A cut applied halfway
# through would show up as a slope change in one phase and be read as a result.
#
# ☠️ The pack must be in the flat part of the discharge curve before phase A
# starts, or the two phases sit on different slopes - that is what withdrew the
# leg of 2026-08-17, and what still inflates every ratio taken since. Compare
# phase-A slopes BETWEEN legs; the derived mA is for scale only.
set -u

TAG=${1:?usage: slope-leg.sh <tag> [service ...]}
shift
CUTS="$*"

BATT=/sys/class/power_supply/pmi632-battery
CHG=/sys/class/power_supply/pmi632-charger
LOG=/var/log/slope-leg-$TAG.txt
SLOPE=/home/fp3/suspend-slope.txt
PIDS=/run/slope-leg-$TAG.pids
TARGET=4030000
FLOOR=3800000
START_MIN=4200000
START_CAP=${START_CAP:-95}

say() { echo "$(cut -d. -f1 /proc/uptime) $TAG: $*" >> "$LOG"; }

# ☠️ USBIN suspend lives in the PMIC and survives a warm reboot; a leg that
# dies without restoring it leaves a phone that will not charge. The cut
# services come back on the same path, for the same reason.
#
# ☠️☠️ AND STARTING A SERVICE IS NOT ALWAYS RESTORING WHAT IT PROVIDED.
# Measured 2026-08-26, and it cost a whole night's control leg: `systemctl stop
# rmtfs` POWERS THE MODEM DOWN, and `systemctl start rmtfs` does NOT bring it
# back - that needs an explicit remoteproc start. The old version of this
# function looped `systemctl start` over $CUTS with 2>/dev/null and reported
# nothing, so leg B left the modem off, leg A' ran with it still off, and the
# A-B-A's control leg was a second TREATMENT leg wearing the control's name.
# The failure was invisible in the leg log; what exposed it afterwards was A''s
# own sleep durations matching B rather than A.
#
# So this now (1) restarts the modem remoteproc when the modem stack was cut,
# (2) VERIFIES the thing itself rather than the service that provides it, and
# (3) SAYS SO IN THE LOG either way. A restore whose outcome is not recorded is
# indistinguishable from one that did not happen.
restore() {
	echo Charging > "$CHG/status" 2>/dev/null
	for s in $CUTS; do systemctl start "$s" 2>/dev/null; done
	systemctl start greetd 2>/dev/null

	# Only when this leg cut the modem stack. Addressed by platform address,
	# never by index: remoteproc numbering moves between boots.
	case " $CUTS " in *" rmtfs "*|*" ModemManager "*)
		for r in /sys/class/remoteproc/remoteproc*; do
			[ "$(cat "$r/name" 2>/dev/null)" = 4080000.remoteproc ] || continue
			[ "$(cat "$r/state" 2>/dev/null)" = offline ] || continue
			say "modem remoteproc is offline after restore - starting it"
			echo start > "$r/state" 2>/dev/null
			sleep 15
			systemctl restart ModemManager 2>/dev/null
		done
		# The verification, and it is allowed to report failure. A leg that
		# followed this one must not be believed if this line says NO MODEM.
		i=0
		while [ $i -lt 12 ]; do
			mmcli -L 2>/dev/null | grep -q 'Modem/' && break
			i=$((i + 1)); sleep 5
		done
		if mmcli -L 2>/dev/null | grep -q 'Modem/'; then
			say "restore OK: modem enumerated"
		else
			say "☠️ RESTORE FAILED: no modem after $((i * 5))s."
			say "☠️ ANY LEG THAT RAN AFTER THIS ONE IS NOT A CONTROL - it ran"
			say "☠️ with the modem down. A reboot is needed to recover it."
		fi
	;; esac
}
trap restore EXIT INT TERM

v0=$(cat "$BATT/voltage_now")
c0=$(cat "$BATT/capacity")
say "start v=$v0 cap=$c0% cuts='${CUTS:-none}'"
say "kernel=$(uname -r) boot_id=$(cat /proc/sys/kernel/random/boot_id)"
say "cmdline=$(tr '\0' ' ' < /proc/cmdline)"

# ☠️ voltage_now is inflated while the charger is pushing, so it alone cannot
# say the pack is full; capacity is the second opinion.
#
# START_CAP was 99 on the reasoning that legs starting from different amounts of
# charge cover different parts of the curve. ☠️ Measured 2026-08-19, that
# reasoning is already satisfied twice over: the leg DESCENDS to a fixed TARGET
# (4.03 V) under CPU load before it measures anything, so every leg's phases land
# in the same window whatever it started from - and START_MIN is the guard that
# actually matters. The 99 % it demanded cost one to three hours of charge wait
# per leg for no measurement benefit.
#
# Worse, it could not be satisfied at all in the state it usually found: with the
# charger attached and the pack terminated, current_now reads 0 and charge_now
# does not move, because the system runs off USB. The pack never falls to the
# 4.30 V recharge threshold, so "wait for 99 %" waits forever.
if [ "$v0" -lt "$START_MIN" ]; then
	say "ABORT: starting at $v0, below START_MIN=$START_MIN - charge first"
	exit 1
fi
if [ "$c0" -lt "$START_CAP" ]; then
	say "ABORT: capacity $c0% below START_CAP=$START_CAP% - charge first"
	exit 1
fi

# ☠️ suspend-slope.txt is append-only across runs. Move the previous leg aside
# before writing a line, or two legs end up in one file and the fitter reads
# the union as one run.
if [ -s "$SLOPE" ]; then
	mv "$SLOPE" "$SLOPE.pre-$TAG"
	say "moved previous slope file aside as $SLOPE.pre-$TAG"
fi

# ☠️ This used to `systemctl stop greetd`, and that had two costs, both paid.
#
#   1. It leaves the phone with NO user interface for the whole leg: a powered
#      panel with nothing drawing on it, a power button nobody handles, and an
#      incoming call that ModemManager sees and nothing rings. Measured
#      2026-08-25: the operator found the phone black and unresponsive, and it
#      was this. Worse, greetd only comes back through restore(), so a leg
#      killed from outside leaves the phone that way indefinitely.
#   2. It is not even necessary. Measured the same day, one boot, panel proven
#      dark both ways: the floor with the full GUI and the floor with phosh and
#      greetd gone are BOTH 52.9 mA. The compositor is worth nothing at idle,
#      so stopping it buys no accuracy - it only breaks the phone.
#
# What does take the panel down with the compositor alive is locking the
# session; phosh then blanks it itself and bl_power goes to 4. So: lock, prove,
# and leave the phone able to ring.
for sess in $(loginctl list-sessions --no-legend 2>/dev/null | awk '$4 != "-" {print $1}'); do
	loginctl lock-session "$sess" 2>/dev/null && say "locked session $sess"
done
i=0
while [ "$i" -lt 30 ]; do
	for fb in /sys/class/graphics/fb*/blank; do [ -w "$fb" ] && echo 4 > "$fb"; done
	sleep 2
	[ "$(cat /sys/class/backlight/*/bl_power 2>/dev/null | head -1)" = 4 ] && break
	[ "$(cat /sys/class/drm/card0/card0-DSI-1/dpms 2>/dev/null)" = Off ] && break
	i=$((i + 1))
done
say "panel bl_power=$(cat /sys/class/backlight/*/bl_power 2>/dev/null | head -1) dpms=$(cat /sys/class/drm/card0/card0-DSI-1/dpms 2>/dev/null) waited=$((i * 2))s"
# ☠️ A gate that cannot fail is not a gate: a lit panel is worth ~24.5 mA and
# would be read as a difference between legs.
if [ "$(cat /sys/class/backlight/*/bl_power 2>/dev/null | head -1)" != 4 ] &&
   [ "$(cat /sys/class/drm/card0/card0-DSI-1/dpms 2>/dev/null)" != Off ]; then
	say "ABORT: could not prove the panel is off"
	exit 1
fi

echo Unknown > "$CHG/status"
sleep 10
say "off VBUS online=$(cat $CHG/online) status=$(cat $BATT/status)"
if [ "$(cat $BATT/status)" = Charging ]; then
	say "ABORT: still charging after USBIN suspend - every sample would read the cable"
	exit 1
fi

load_start() {
	_n=$(nproc 2>/dev/null || echo 4)
	_i=0
	while [ "$_i" -lt "$_n" ]; do
		( while :; do :; done ) &
		echo $! >> "$PIDS"
		_i=$((_i + 1))
	done
	say "load started on $_n cores"
}

load_stop() {
	[ -f "$PIDS" ] || return 0
	while read -r pid; do kill "$pid" 2>/dev/null; done < "$PIDS"
	rm -f "$PIDS"
	say "load stopped"
}

rm -f "$PIDS"
trap 'load_stop; restore' EXIT INT TERM
load_start

# ☠️ NEVER TEST THE THRESHOLD UNDER LOAD. Measured 2026-08-18: eight busy cores
# pull the terminal voltage down by about 360 mV, so a check taken under load
# declared a 4.030 V target reached while the pack was resting at 4.238 V -
# deep in the steep region the target exists to avoid. Shed the load and let it
# recover before every comparison.
while :; do
	load_stop
	sleep 30
	v=$(cat "$BATT/voltage_now")
	say "rested v=$v t=$(cat $BATT/temp 2>/dev/null)"
	[ "$v" -le "$TARGET" ] && { say "reached target v=$v"; break; }
	[ "$v" -le "$FLOOR" ] && { say "ABORT: below floor at v=$v"; exit 1; }
	load_start
	sleep 90
done

# The cut goes on here: after the descent, before a single sample.
for s in $CUTS; do systemctl stop "$s" 2>/dev/null; done
for s in $CUTS; do say "cut $s -> $(systemctl is-active "$s" 2>/dev/null)"; done

say "cooling before the leg; temp=$(cat $BATT/temp 2>/dev/null)"
say "launching slope leg"
# ☠️ Parameterised 2026-08-25. These were hardcoded 900/6/1800, which with the
# descent and a charge wait made one leg a half-night and an A-B-A a night and
# a half. The defaults are unchanged, so every earlier leg is reproduced
# exactly; shorten them per run when the question is a comparison between legs
# rather than an absolute number, and say in the tag that you did.
/root/suspend-slope.sh "$TAG" "${SLOPE_SLEEP:-900}" "${SLOPE_CYCLES:-6}" "${SLOPE_SETTLE:-1800}"
say "slope leg exited rc=$? v=$(cat $BATT/voltage_now)"
restore
say "done"
