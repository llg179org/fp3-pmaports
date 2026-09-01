#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# WHY DOES THE MODEM NOT DROP ITS DUTY WHILE EVERYTHING ELSE SLEEPS?
# Eight hours, no USB cable, no WiFi, ModemManager RUNNING.
#
#   modem-night.sh [hours] [alarm_s] [floor_pct] [mm]   defaults 8 600 35 running
#
# `mm` is `running` or `stopped`, and it is the ONLY thing the control arm may
# change. The 2026-08-31 run gave 86 mA at 33.6 % modem duty; the step-0 night
# gave 48 mA at 5.0 %; the line through them has slope 133 mA per unit duty and
# an intercept of 41.4 mA, which says the oracle's 6.1 % duty would land at
# 49.5 mA - the goal, from the modem track alone. But those two points differ in
# WiFi and cable state as well as duty, so the line is drawn across two
# configurations. `mm stopped` repeats THIS census with only the daemon moved,
# and that is what turns it into a controlled measurement.
#
# ☠️ READ THIS BEFORE CHANGING THE PREMISE. "The modem does not drop its duty"
# is true only with ModemManager RUNNING. Measured 2026-08-31 across a clean
# 602 s alarm-ended suspend with the daemon STOPPED, MPSS was 5.0% awake - the
# same as an awake window. The one across-suspend number with the daemon running
# is 45% (2026-08-30) and is n=1. So this run does not re-ask whether the modem
# stays awake; it asks WHAT KEEPS IT awake, with the daemon running, over enough
# rounds that n=1 stops being the answer.
#
# THE THREE CANDIDATES, and the column that separates them:
#   (a) the AP keeps talking to it - our own stack polls, or ModemManager's
#       sleep handshake runs on every logind suspend  -> REQ/RSP traffic in the
#       census, and a duty gap between the two suspend paths (see below);
#   (b) the network keeps waking it - paging/NAS/DSD indications -> IND traffic
#       from those ports, correlated round by round with a high MPSS duty;
#   (c) neither - the modem simply never sleeps deeply on its own configuration
#       -> high duty in rounds with ZERO QMI in either direction.
# (c) is the uncomfortable one and it is the one the plan currently has no lever
# for, which is exactly why it must be able to win here.
#
# ☠️ TWO SUSPEND PATHS, ALTERNATED, AND THAT IS THE INTERNAL A/B.
#   odd rounds  rtcwake -m mem : the kernel freezes directly. logind never runs,
#                                so ModemManager's sleep handshake never runs.
#   even rounds logind         : the realistic path a phone actually takes, with
#                                the handshake and every inhibitor in it.
# The difference between the two sets IS the handshake's contribution, measured
# on the same night, the same cell and the same firmware. Nothing else this run
# does can be confounded by the network drifting between days, because both arms
# are interleaved inside it.
#
# ☠️ THE PHONE IS UNREACHABLE FOR THE WHOLE RUN. No cable and no WiFi means no
# dev link at all. Everything therefore restores itself on every exit path, and
# a SEPARATE dead-man timer restores WiFi even if this script is SIGKILLed.
# Nothing here may leave the phone needing hands.
#
# ☠️ NEVER LEAVE THE PMIC INPUT SUSPENDED. This script never sets that bit - the
# cable is out, so there is no input to suspend - but it clears it on exit
# anyway, because the bit survives a warm reboot and has wedged the bootloader
# before.
#
# ☠️ /var/log/fp3, NOT /tmp. /tmp is tmpfs here and an eight-hour run that ends
# in a reboot would leave nothing behind. This has cost a capture before.
set -u
HOURS=${1:-8}
ALARM=${2:-600}
FLOOR=${3:-35}
MM=${4:-running}
case "$MM" in running|stopped) ;; *) echo "mm must be running or stopped"; exit 2;; esac
WIFI=${5:-down}
case "$WIFI" in down|up) ;; *) echo "wifi must be down or up"; exit 2;; esac

BAT=/sys/class/power_supply/pmi632-battery
CHG=/sys/class/power_supply/pmi632-charger
O=/var/log/fp3/modem-night-$(date +%s)
mkdir -p "$O"
LOG=$O/run.log
say(){ echo "$*" | tee -a "$LOG"; }

# ---------------------------------------------------------------- restore
# Runs on EVERY exit path. Idempotent: each action is safe to repeat.
restored=0
restore() {
	[ "$restored" = 1 ] && return
	restored=1
	echo Charging > $CHG/status 2>/dev/null
	[ "${MM:-running}" = stopped ] && systemctl start ModemManager 2>/dev/null
	nmcli radio wifi on 2>/dev/null
	ip link set wlan0 up 2>/dev/null
	rfkill unblock all 2>/dev/null
	# leave the instrument disarmed - a left-armed kprobe blocks the NEXT run
	for e in /sys/kernel/tracing/events/kprobes/*/enable; do
		[ -e "$e" ] && echo 0 > "$e" 2>/dev/null
	done
	echo -n > /sys/kernel/tracing/kprobe_events 2>/dev/null
	# ☠️ Take the dead-man down too. It has already done its job by existing,
	# and a stale timer both fires pointlessly in eight hours and blocks the
	# next run from arming a unit of the same name.
	systemctl stop fp3-modemnight-deadman.timer 2>/dev/null
	systemctl stop fp3-modemnight-deadman.service 2>/dev/null
	echo "# RESTORED $(date '+%F %T') wifi=$(nmcli radio wifi 2>/dev/null) charger=$(cat $CHG/status 2>/dev/null)" >> "$LOG"
	echo DONE > "$O/DONE"
}
trap 'restore; exit 0' EXIT INT TERM

# ---------------------------------------------------------------- dead man
# ☠️ An escape route that depends on the thing it is rescuing is not an escape
# route. This timer is a SEPARATE transient unit: if this script is SIGKILLed,
# panics, or the loop wedges, WiFi still comes back and the phone is reachable.
DEADMAN=$(( HOURS * 3600 + 1800 ))
systemd-run --unit=fp3-modemnight-deadman --collect \
	--on-active="${DEADMAN}s" \
	/bin/sh -c "nmcli radio wifi on; ip link set wlan0 up; rfkill unblock all;
	            echo Charging > $CHG/status;
	            systemctl stop fp3-modemnight 2>/dev/null || true" >/dev/null 2>&1 \
	&& say "# dead-man armed: WiFi returns unconditionally in $((DEADMAN/60)) min" \
	|| { say "☠️ COULD NOT ARM THE DEAD-MAN TIMER - refusing to cut the only remaining link"; exit 1; }

say "# modem-night $(date '+%F %T') hours=$HOURS alarm=${ALARM}s floor=${FLOOR}% mm=$MM wifi=$WIFI"
say "# kernel=$(uname -v)"

# ---------------------------------------------------------------- gates
# Each one is a hard exit. The point of a gate is that the data's existence
# proves the condition held; a warning does not.
gate_fail(){ say "☠️ GATE FAILED: $*"; exit 1; }

[ "$(id -u)" = 0 ] || gate_fail "not root"
[ -d /sys/kernel/tracing ] || gate_fail "no tracefs - the census cannot arm"
[ -x /usr/local/bin/wake-qmi.sh ] || gate_fail "wake-qmi.sh not installed"
[ -x /usr/local/bin/rpm-xo-snapshot.sh ] || gate_fail "rpm-xo-snapshot.sh not installed"
[ -x /usr/lib/systemd/system-sleep/zz-fp3-trace-marker ] ||
	gate_fail "the system-sleep marker hook is missing - without it no round has a sleep window"
modprobe rpm_master_stats 2>/dev/null
[ -d /sys/kernel/debug/qcom_rpm_master_stats ] || gate_fail "no RPM master stats - the duty column would be blank"

# ☠️ The daemon's state is the instrument here, in BOTH directions, so the gate
# checks the one that was asked for rather than assuming.
#
# The modem must be REGISTERED either way, and that has to be read while the
# daemon is still up - with it stopped there is no mmcli answer, and "no answer"
# is indistinguishable from "not registered". So: read first, stop second.
[ "$(systemctl is-active ModemManager)" = active ] ||
	gate_fail "ModemManager is not running, so the modem's state cannot be read before the run"
MMSTATE=$(mmcli -m any 2>/dev/null | sed -n 's/.*state: *//p' | head -1)
case "$MMSTATE" in
	*registered*|*connected*) : ;;
	*) gate_fail "modem is '$MMSTATE', not registered - an unregistered modem is a different question" ;;
esac
say "# modem before the run: $MMSTATE  (daemon will be: $MM)"
if [ "$MM" = stopped ]; then
	systemctl stop ModemManager
	sleep 5
	[ "$(systemctl is-active ModemManager)" = active ] &&
		gate_fail "ModemManager refused to stop - the control arm would measure the wrong thing"
	# ☠️ Verify the PROCESS, not the label: a daemon can ignore SIGTERM while
	# systemd reports it stopping.
	pgrep -x ModemManager >/dev/null 2>&1 &&
		gate_fail "systemd says stopped but a ModemManager process is still alive"
	say "# ModemManager STOPPED for this run; restore() starts it again on every exit path"
fi

cap=$(cat $BAT/capacity)
[ "$cap" -gt $((FLOOR + 30)) ] || gate_fail "battery $cap% is too close to the $FLOOR% floor for $HOURS h"
say "# battery at start: $cap%  v=$(cat $BAT/voltage_now)uV"

# panel dark - a lit panel is the largest confound there is and it is free to close
for b in /sys/class/backlight/*/bl_power; do [ -w "$b" ] && echo 4 > "$b"; done
say "# panel: bl_power=$(cat /sys/class/backlight/*/bl_power 2>/dev/null | head -1)"

# ---------------------------------------------------------------- WiFi
# Two arms. `down` is the default and the one every census so far has used. `up`
# exists to separate the Wi-Fi link from the USB link: with the cable out either
# way, an up/down pair at the same duty prices Wi-Fi on its own, and the two have
# only ever moved together.
#
# ☠️ With WIFI=up the phone is REACHABLE for the whole run. Do not use that
# to look at it. Every ssh login wakes the AP, and the rounds are the
# measurement; a single poll costs the round it lands in and is invisible
# afterwards in the numbers it corrupted.
if [ "$WIFI" = down ]; then
	say "# taking WiFi down (it is a dev link - the dead-man above is why this is safe)"
	nmcli radio wifi off 2>/dev/null
	ip link set wlan0 down 2>/dev/null
	sleep 3
else
	say "# leaving WiFi UP - this arm prices the Wi-Fi link itself"
	nmcli radio wifi on 2>/dev/null
	ip link set wlan0 up 2>/dev/null
	sleep 5
	# An arm that claims to measure an associated link has to show it is
	# associated. A wlan0 that is up but unassociated draws a different
	# current and would be reported as "Wi-Fi up".
	ip -br addr show wlan0 2>/dev/null | grep -q 'UP.*[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+' ||
		gate_fail "WIFI=up but wlan0 has no address - an unassociated link is not the arm asked for"
	say "# wlan0: $(ip -br addr show wlan0 2>/dev/null)"
fi
say "# wifi radio now: $(nmcli radio wifi 2>/dev/null)  wlan0: $(ip -br link show wlan0 2>/dev/null | awk '{print $2}')"

# ---------------------------------------------------------------- cable out
# ☠️ Wait for the HUMAN to unplug rather than assuming it happened. A run that
# starts with the cable in measures a charging phone and looks identical to one
# that does not.
say "# waiting for the cable to come out (up to 30 min) - UNPLUG NOW"
w=0
while [ "$(cat $CHG/online 2>/dev/null || echo 1)" != 0 ] && [ $w -lt 1800 ]; do
	sleep 10; w=$((w + 10))
done
[ "$(cat $CHG/online 2>/dev/null || echo 1)" = 0 ] || gate_fail "cable still in after 30 min - nothing was measured"
say "# cable out at $(date '+%T') after ${w}s"

# ☠️ Let the surface charge decay before the first round. Measured on this
# device: fitting from 0/150/300/600 s after a wake gives -142/+141/+156/+25
# mV/h - the sign itself flips. The battery column of an unsettled round is not
# a small error, it is noise with a plausible magnitude.
say "# settling 300 s before the first round"
sleep 300

# ---------------------------------------------------------------- the loop
snap(){ /usr/local/bin/rpm-xo-snapshot.sh; }
END=$(( $(date +%s) + HOURS * 3600 ))
r=1
while [ "$(date +%s)" -lt $END ]; do
	cap=$(cat $BAT/capacity)
	if [ "$cap" -le "$FLOOR" ]; then
		say "# STOPPING at round $r: battery $cap% reached the $FLOOR% floor"
		break
	fi
	# alternate the two suspend paths - this is the internal A/B
	case $((r % 2)) in 1) P=rtcwake ;; *) P=logind ;; esac
	D=$O/round-$(printf '%03d' $r)-$P
	mkdir -p "$D"
	{
		echo "# round=$r path=$P t=$(date '+%F %T') cap=${cap}% v=$(cat $BAT/voltage_now)uV"
		echo "=== BEFORE"; snap
	} > "$D/masters.txt" 2>&1

	WAKE_QMI_LOG=$D/qmi.log /usr/local/bin/wake-qmi.sh "$ALARM" 1 "$P" >/dev/null 2>&1

	{
		echo "=== AFTER"; snap
		echo "# after: cap=$(cat $BAT/capacity)% v=$(cat $BAT/voltage_now)uV"
		echo "# suspend_stats: ok=$(cat /sys/power/suspend_stats/success) fail=$(cat /sys/power/suspend_stats/fail)"
		echo "# wakeup_irq=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)"
	} >> "$D/masters.txt" 2>&1

	say "# round $r ($P) done $(date '+%T') cap=$(cat $BAT/capacity)%"
	r=$((r + 1))
done

say "# loop ended after $((r - 1)) rounds, $(date '+%F %T'), battery $(cat $BAT/capacity)%"
restore
