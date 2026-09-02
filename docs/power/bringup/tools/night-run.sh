#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# THE OVERNIGHT REPLICATION: three boots, one OCV pair around the whole night.
#
# What it answers. The cheap state's current, 40.1 mA, comes from ONE leg of ONE
# boot; the dominant unknown is boot-to-boot variation, which no single leg can
# see. And every current number in this project rides on one PMI632 calibration
# whose offset is uncertified. Both are addressed by the same night:
#
#   rest + OCV  →  { boot, converge, B-leg } x3  →  rest + OCV
#
#   * the three leg means give the boot-to-boot spread (NEVER the pooled windows,
#     which would hide exactly the term being estimated)
#   * the outer OCV pair integrates the whole night, and comparing that mAh with
#     the QG's own integral bounds the calibration offset without a shunt:
#     the QG carries eps directly, the OCV route only through a capacity axis
#     itself integrated at ~110 mA, so agreement to delta gives |eps| <= 1.6 delta
#
# ☠️ ONE OCV PAIR AROUND THE NIGHT, NOT ONE PER LEG. A rest draws less than the
# leg it brackets, so per-leg pairs measure a mixture: 90 min at 40 mA plus two
# 30 min rests at ~30 mA is 90 mAh over 2.5 h = 36 mA, a 10 % pull downward. Over
# a whole night the same rests are a 9 % correction with under 3 % residual error.
#
# ☠️ IT REBOOTS, SO IT CANNOT BE A SHELL LOOP. The script dies at each reboot, so
# the sequence lives in a STATE FILE and the service re-runs at every boot. That
# is also the danger: a state file that fails to advance is a boot loop on a phone
# that has to keep ringing. Hence MAXSTEP, an advance-before-act order (the step
# is written BEFORE the reboot, never after), and a hard disable on anything
# unexpected.
#
# ☠️ NEVER REBOOT WITH THE USB INPUT SUSPENDED. That bit lives in the PMIC and
# survives a warm reboot, so the phone would come back unable to charge, silently.
# Restore it before every reboot - checked here, not remembered.
set -u

D=/var/log/fp3/night
S=$D/state
LOG=$D/run.log
MAXSTEP=40

mkdir -p "$D"
s() { echo "$(date '+%F %T') $*" >> "$LOG"; }

# --- configuration, written once by `arm` ------------------------------------
[ -f "$D/conf" ] && . "$D/conf"
BOOTS=${BOOTS:-3}
LEGMIN=${LEGMIN:-75}
RESTMIN=${RESTMIN:-30}
ALARM=${ALARM:-90}

give_up() {
	s "GIVE UP: $*"
	systemctl disable fp3-night.service 2>/dev/null
	echo Charging > /sys/class/power_supply/pmi632-charger/status 2>/dev/null
	mmcli -m any --enable >/dev/null 2>&1
	systemctl start fp3-ims-reconcile.timer 2>/dev/null
	exit 1
}

step=$(cat "$S" 2>/dev/null || echo 0)
case "$step" in ''|*[!0-9]*) give_up "unreadable state '$step'" ;; esac
[ "$step" -le "$MAXSTEP" ] || give_up "step $step over MAXSTEP $MAXSTEP - refusing to loop"

# ☠️ ADVANCE FIRST. If the step were written after the work, a crash anywhere in
# the work would repeat it for ever. A repeated step is a lost measurement; a
# repeated REBOOT is a brick-shaped afternoon.
echo $((step + 1)) > "$S"

ocv() {   # ocv <tag> - radio off, rest, read, radio back
	s "OCV $1: radio off, resting ${RESTMIN} min"
	mmcli -m any --disable >/dev/null 2>&1 || s "  (mmcli --disable failed, continuing)"
	sleep $((RESTMIN * 60))
	# several reads: a single one cannot show whether the pack has settled
	for i in 1 2 3 4 5; do
		printf '%s %s %s %s\n' "$1" "$(date +%s)" \
			"$(cat /sys/class/power_supply/*battery*/voltage_now)" \
			"$(cat /sys/class/power_supply/*battery*/capacity)" >> "$D/ocv.txt"
		sleep 20
	done
	s "OCV $1 done: $(tail -1 "$D/ocv.txt")"
	mmcli -m any --enable >/dev/null 2>&1
	sleep 30
}

converged() {   # wait for the reconciler to prove the vector, from its own log
	i=0
	while [ $i -lt 30 ]; do
		if journalctl -u fp3-ims-reconcile --since "-10 min" 2>/dev/null \
			| grep -q "fp3-ims-reconcile:"; then
			s "reconciler spoke: $(journalctl -u fp3-ims-reconcile --since '-10 min' -o cat | tail -1)"
			return 0
		fi
		i=$((i + 1)); sleep 20
	done
	s "reconciler said nothing in 10 min - forcing one run"
	systemctl start fp3-ims-reconcile.service 2>/dev/null
	sleep 10
	return 0
}

reboot_now() {
	# the trap that survives a warm boot, checked rather than remembered
	st=$(cat /sys/class/power_supply/pmi632-charger/status 2>/dev/null)
	if [ "$st" != Charging ] && [ "$st" != Full ] && [ "$st" != "Not charging" ]; then
		s "restoring USB input before reboot (was '$st')"
		echo Charging > /sys/class/power_supply/pmi632-charger/status
	fi
	sync
	s "rebooting (next step $(cat $S))"
	systemctl reboot
	exit 0
}

s "=== step $step  (boots=$BOOTS leg=${LEGMIN}min rest=${RESTMIN}min alarm=${ALARM}s) ==="
s "battery $(cat /sys/class/power_supply/*battery*/capacity)% $(cat /sys/class/power_supply/*battery*/voltage_now)uV $(cat /sys/class/power_supply/pmi632-charger/status)"

if [ "$step" -eq 0 ]; then
	ocv start
	reboot_now
fi

leg=$(( (step + 1) / 2 ))
if [ "$leg" -le "$BOOTS" ] && [ $((step % 2)) -eq 1 ]; then
	s "--- leg $leg of $BOOTS, after boot $(cut -d. -f1 /proc/uptime)s ago ---"
	converged
	python3 /usr/local/bin/ims-toggle.py read 2>&1 | sed 's/^/  /' >> "$LOG"
	# USB input off so the leg measures the phone, not the charger
	echo Unknown > /sys/class/power_supply/pmi632-charger/status
	sh /usr/local/bin/ims-ma3-leg.sh "$LEGMIN" "$ALARM" "$D/leg$leg" >> "$LOG" 2>&1
	echo Charging > /sys/class/power_supply/pmi632-charger/status
	s "--- leg $leg done ---"
	if [ "$leg" -lt "$BOOTS" ]; then reboot_now; fi
	# last leg: fall through to the closing OCV in this same run
	echo $((step + 2)) > "$S"
fi

ocv end
s "=== NIGHT COMPLETE ==="
systemctl disable fp3-night.service 2>/dev/null
systemctl start fp3-ims-reconcile.timer 2>/dev/null
