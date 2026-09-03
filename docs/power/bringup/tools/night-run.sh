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
#     itself integrated at the discharge's MEAN 121.8 mA (2185 mAh / 17.94 h - NOT
#     the median 108, which an earlier version of this line quoted), so agreement
#     to delta gives |eps| <= 1.49 delta
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
# ☠️ THE WALL CLOCK IS WRONG AFTER EVERY BOOT UNTIL NTP LANDS - this device's RTC
# starts at 1970. Three boots' legs cannot be lined up against each other on a
# clock that jumps, so every line carries monotonic uptime and the boot id too.
BOOT_ID=$(cut -c1-8 /proc/sys/kernel/random/boot_id 2>/dev/null || echo ????????)
s() { echo "$(date '+%F %T') [+$(cut -d. -f1 /proc/uptime)s $BOOT_ID] $*" >> "$LOG"; }

# --- configuration, written once by `arm` ------------------------------------
[ -f "$D/conf" ] && . "$D/conf"
BOOTS=${BOOTS:-3}
LEGMIN=${LEGMIN:-75}
RESTMIN=${RESTMIN:-30}
ALARM=${ALARM:-90}
BAND=${BAND:-eutran-1}

give_up() {
	s "GIVE UP: $*"
	systemctl disable fp3-night.service 2>/dev/null
	echo Charging > /sys/class/power_supply/pmi632-charger/status 2>/dev/null
	mmcli -m any --set-current-bands=any >/dev/null 2>&1
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

# ☠️ RE-ASSERT THE DEVICE-SIDE LOCK AT EVERY STEP, because /run is tmpfs and this
# script's whole point is that it reboots. A lock written once at 19:08 is gone by
# the first reboot, and the two legs after it would take logins unstamped - which
# is precisely the failure mode this lock exists for. Cheap enough to redo.
printf 'night-run step %s, pid %s, started %s\n' "$step" "$$" "$(date '+%F %T')" \
	> /run/fp3-measuring 2>/dev/null || true

# ☠️☠️ A REST THAT DOES NOT SLEEP IS NOT A REST, AND OURS DID NOT. Measured on
# 2026-09-02: ZERO "PM: suspend entry" in the whole 101-minute opening rest and
# the whole 40-minute closing rest. Both used plain `sleep`, which keeps the AP
# awake - so the endpoints were an AWAKE phone relaxing, the slope never came
# under 0.2 mV/min, and BOTH OCVs were marked suspect by the run's own criterion.
# The criterion was right and unreachable: at an awake phone's draw the pack
# simply cannot settle that far inside a ceiling.
# ☠️ The fix is not a longer ceiling - that was the tempting reading and it would
# have cost hours per night for nothing. It is to make the waiting itself a
# suspend. `nap` replaces every `sleep` inside the OCV routine.
nap() {   # nap <seconds> - suspend if we can, sleep if we cannot, never fail
	rtcwake -m mem -s "$1" >/dev/null 2>&1 || sleep "$1"
}

ocv() {   # ocv <tag> [maxmin] - radio off, USB input off, rest, read, both back
	# ☠️ AN OCV TAKEN ON THE CHARGER IS THE CHARGER'S VOLTAGE, NOT THE PACK'S. The
	# rehearsal read 4.413 V at the start with status "Charging" - that is the
	# float voltage of the charger, and the entire offset-bounding argument needs a
	# RESTED PACK. The radio was switched off and the charger was not; both have to
	# go, and the state has to be verified rather than assumed.
	s "OCV $1: radio off, USB input suspended, resting ${RESTMIN} min"
	mmcli -m any --disable >/dev/null 2>&1 || s "  (mmcli --disable failed, continuing)"
	echo Unknown > /sys/class/power_supply/pmi632-charger/status
	sleep 5
	st=$(cat /sys/class/power_supply/pmi632-charger/status)
	[ "$st" = Discharging ] || s "  ☠️ charger status is '$st', not Discharging - this OCV is suspect"
	# ☠️ THE ACCEPTANCE CRITERION IS ALSO THE CONTROLLER. A fixed rest is either
	# too long or too short and cannot know which: relaxation after CHARGING is
	# slower and of the opposite sign to relaxation after discharge, so the opening
	# rest has to be told by the pack, not by us. Rest until the slope passes, with
	# a hard ceiling so a pack that never settles cannot eat the night.
	CAP=${2:-$RESTMIN}
	waited=0
	while [ "$waited" -lt "$((CAP * 60))" ]; do
		nap 300; waited=$((waited + 300))
		v1=$(cat /sys/class/power_supply/*battery*/voltage_now); nap 120
		v2=$(cat /sys/class/power_supply/*battery*/voltage_now)
		mv=$(( (v2 - v1) / 1000 )); waited=$((waited + 120))
		s "  rest $1: ${waited}s, ${mv} mV over the last 2 min"
		[ "$mv" -lt 1 ] && [ "$mv" -gt -1 ] && { s "  rest $1: settled after ${waited}s"; break; }
	done
	[ "$waited" -lt "$((CAP * 60))" ] || s "  ☠️ rest $1 hit its ${CAP} min ceiling without settling - this endpoint is suspect"
	# ☠️ SETTLING IS AN ACCEPTANCE CRITERION, NOT AN AFTERTHOUGHT. The rehearsal's
	# closing read was still climbing and only said so in hindsight. Take a ten
	# minute series and judge the LAST FIVE MINUTES: under 0.2 mV/min the pack is
	# rested, above it the number is a relaxation curve wearing an OCV's clothes.
	# ☠️ THE ACCEPTANCE SERIES HAS TO SLEEP TOO, and ten minutes of it used to be
	# ten minutes of an awake phone. Sparse sleeping samples: 10 x 60 s.
	for i in $(seq 1 10); do
		printf '%s %s %s %s\n' "$1" "$(date +%s)" \
			"$(cat /sys/class/power_supply/*battery*/voltage_now)" \
			"$(cat /sys/class/power_supply/*battery*/capacity)" >> "$D/ocv.txt"
		nap 60
	done
	slope=$(grep "^$1 " "$D/ocv.txt" | tail -6 | awk '
		NR==1{t0=$2; v0=$3} END{if (NR>1 && $2>t0) printf "%.2f", ($3-v0)/1000/(($2-t0)/60); else print "0"}')
	s "OCV $1 slope over the last 5 min: ${slope} mV/min $(awk -v x="$slope" 'BEGIN{print (x<0.2 && x>-0.2) ? "(rested)" : "☠️ NOT RESTED - treat this endpoint as suspect"}')"
	# ☠️ SAY WHETHER IT HAD SETTLED. Five reads twenty seconds apart still climbing
	# means the pack is relaxing and the number is not an OCV yet; the rehearsal's
	# closing read rose 1.2 mV across its five samples on a 3 min rest. Print the
	# drift so a reader can discount it instead of trusting a single last value.
	first=$(grep "^$1 " "$D/ocv.txt" | head -1 | awk '{print $3}')
	last=$(grep "^$1 " "$D/ocv.txt" | tail -1 | awk '{print $3}')
	s "OCV $1 done: ${last}uV, drift over the last 80 s: $(( (last - first) / 1000 )) mV"
	echo Charging > /sys/class/power_supply/pmi632-charger/status
	mmcli -m any --enable >/dev/null 2>&1
	sleep 30
}

# ☠️ A LOG LINE IS NOT A STATE. The first version waited for the string
# "fp3-ims-reconcile:" in the journal and treated it as proof - and it matched the
# unit's own DESCRIPTION ("Finished Hold the modem's IMS service switches off"),
# which systemd prints whether or not the reconciler achieved anything. Measured
# in the rehearsal: the line appeared, the run continued, and the leg then ran
# with voice/video/SMS/UT all TRUE - i.e. it measured the EXPENSIVE state for six
# minutes while believing it was the cheap one. A whole night would have been lost
# to a grep matching a description.
#
# So: read the VECTOR, not the log. Retry, force, and abort the leg rather than
# measure the wrong state - a missing leg is a gap, a mislabelled leg is a lie.
ims_off() {
	python3 /usr/local/bin/ims-toggle.py read 2>/dev/null \
		| awk '/voice|VoWiFi|video|SMS|UT/{if ($2 != "False" && $2 != "telephony") bad=1}
		       END{exit bad}'
}
converged() {
	i=0
	while [ $i -lt 12 ]; do
		if ims_off; then
			s "vector verified off: $(python3 /usr/local/bin/ims-toggle.py read 2>/dev/null | awk '/voice|VoWiFi|video|SMS|UT/{printf "%s=%s ", $1, $2}')"
			return 0
		fi
		s "vector NOT off yet (attempt $i) - starting the reconciler"
		systemctl start fp3-ims-reconcile.service 2>/dev/null
		i=$((i + 1)); sleep 20
	done
	# ☠️ ERROR POLICY, BECAUSE THIS RUNS UNSUPERVISED AT 3 AM. A failed vector gate
	# drops THIS LEG and moves on to the next boot; it does not kill the night. Two
	# legs are worth more than none, and the boot-to-boot spread - the whole point
	# of the night - survives losing one. `give_up` is reserved for what endangers
	# the phone: a corrupt state file, or a step count that would loop reboots.
	s "☠️ the IMS vector would not go off in 4 minutes - DROPPING THIS LEG and moving on"
	return 1
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
	ocv start 90        # opening rest is adaptive: the pack is coming off the charger
	reboot_now
fi

leg=$(( (step + 1) / 2 ))
if [ "$leg" -le "$BOOTS" ] && [ $((step % 2)) -eq 1 ]; then
	s "--- leg $leg of $BOOTS, after boot $(cut -d. -f1 /proc/uptime)s ago ---"
	if ! converged; then
		echo "leg $leg dropped: vector would not go off" >> "$D/dropped.txt"
		if [ "$leg" -lt "$BOOTS" ]; then reboot_now; fi
		echo $((step + 2)) > "$S"
		ocv end
		s "=== NIGHT COMPLETE (last leg dropped) ==="
		systemctl disable fp3-night.service 2>/dev/null
		exit 0
	fi
	python3 /usr/local/bin/ims-toggle.py read 2>&1 | sed 's/^/  /' >> "$LOG"
	# ☠️ PIN THE BAND, OR THE LEGS ARE NOT COMPARABLE. The band is worth ~17 pp of
	# duty and ~54 mA on this device, and the second rehearsal's six-minute leg
	# MOVED - eutran-3 at the start, eutran-1 at the end. Three legs on three boots
	# are meant to differ only by the boot; a leg that changes band mid-way differs
	# by the largest confounder this project has measured. Found because the leg
	# reads the band at BOTH ends, which the first rehearsal had shown was missing.
	mmcli -m any --set-current-bands="$BAND" >/dev/null 2>&1 \
		|| s "☠️ set-current-bands=$BAND FAILED - this leg is NOT band-pinned"
	sleep 10
	# USB input off so the leg measures the phone, not the charger
	echo Unknown > /sys/class/power_supply/pmi632-charger/status
	# ☠️☠️ AND TAKE wlan0 OUT OF NetworkManager'S HANDS FOR THE LEG. Measured on
	# 2026-09-02: with no DHCP server answering, NM retried a lease on wlan0 197
	# times inside a 77-minute leg - one every ~23 s - and the AP's median sleep
	# was 11 s against a 90 s alarm. The morning census on the same configuration
	# slept 62 s and shows ZERO such transactions, so this is the difference, not
	# a boot transient and not the band pinning: both of those were my hypotheses
	# and the journal named a third thing.
	# ☠️ `managed no` does NOT persist across a reboot, which is exactly why it is
	# safe here: a crash cannot leave this phone without its WiFi rescue path,
	# because the next boot restores it. The USB link is up throughout regardless.
	nmcli device set wlan0 managed no >/dev/null 2>&1 \
		|| s "☠️ could not unmanage wlan0 - a DHCP retry loop may wake the AP"
	sh /usr/local/bin/ims-ma3-leg.sh "$LEGMIN" "$ALARM" "$D/leg$leg" >> "$LOG" 2>&1
	nmcli device set wlan0 managed yes >/dev/null 2>&1
	echo Charging > /sys/class/power_supply/pmi632-charger/status
	mmcli -m any --set-current-bands=any >/dev/null 2>&1
	s "--- leg $leg done ---"
	# ☠️☠️ SET THE NEXT STATE BEFORE THE REBOOT, NOT AFTER IT. This line used to
	# sit BELOW the reboot, where it can never run: reboot_now does not return.
	# The advance-first write at the top had already left the state at step+1 -
	# an EVEN number - and the leg branch only fires on ODD steps, so the next
	# boot skipped straight to the closing OCV and declared the night complete.
	# ☠️ THE RUN COULD THEREFORE ONLY EVER PRODUCE ONE LEG, and it did exactly
	# that on 2026-09-02: leg 1 at 20:50, "NIGHT COMPLETE" at 22:54, three boots
	# requested and one delivered. Two rehearsals missed it because neither
	# rehearsed the multi-boot sequence - they rehearsed a leg.
	# ☠️ The advance-first invariant is preserved on purpose: if the LEG crashes,
	# the state stays even and the next boot ends the night gracefully instead of
	# repeating a reboot. Ending early is a lost measurement; looping is a brick.
	echo $((step + 2)) > "$S"
	if [ "$leg" -lt "$BOOTS" ]; then reboot_now; fi
	# last leg: fall through to the closing OCV in this same run
fi

ocv end
s "=== NIGHT COMPLETE ==="
systemctl disable fp3-night.service 2>/dev/null
systemctl start fp3-ims-reconcile.timer 2>/dev/null
