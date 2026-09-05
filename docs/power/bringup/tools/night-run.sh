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

# ☠️ TELL THE QUEUE THE RUN STOPPED. Without this a timer-started measurement has
# nobody to report to: #85 finished 2026-09-04 01:15 and sat unclosed for two days
# with nine tasks behind it. The sentinel says only that the run STOPPED - judging
# it is night-triage.sh's job and a separate queue task - and it must be written on
# EVERY exit path, which is why it is a function and not a line.
done_sentinel() {
	# ☠️ FP3_TASK must be set by whoever arms the run. It used to default to 85,
	# which is now closed - a later night would have annotated a dead task and
	# released nothing, silently. Unset writes task 0, which queue-sync reports
	# as unattributed on every run instead of acting on the wrong entry.
	[ -n "${FP3_TASK:-}" ] || s "☠️ FP3_TASK not set - the completion will be unattributed"
	FP3_MEASURE_UNIT=fp3-night.service \
		fp3-measure-done "${FP3_TASK:-0}" "$1" "$2" "$D" >> "$LOG" 2>&1 \
		|| s "☠️ could not write the completion sentinel - the queue will not learn this ran"
}

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
	# ☠️ THE ABORT PATH NEEDS THE SENTINEL MOST. A run that gives up silently is
	# exactly the case that leaves the queue waiting for a night that will never
	# report - which is the failure #159 exists to remove.
	done_sentinel aborted "gave up: $*"
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
	# ☠️☠️ SAVE THE TAG FIRST: `set --` BELOW DESTROYS IT. The slope estimator
	# reads its two numbers with `set -- $(awk ...)`, which overwrites the
	# positional parameters - so from that line on, `$1` is the SLOPE, not
	# "start"/"end". Measured on the device 2026-09-03, before a night that would
	# have run on it: `grep "^0.10 "` matches nothing in ocv.txt, so `first` and
	# `last` come back EMPTY, and busybox arithmetic reads an empty operand as 0.
	# The run does not crash - it prints `OCV 0.10 done: uV, drift over the last
	# 80 s: 0 mV`. ☠️ A fabricated **0 mV drift reads as a perfectly rested pack**,
	# which is the worst shape a broken instrument can take: it reports the best
	# possible result precisely when it measured nothing. The raw ocv.txt survives,
	# so the endpoints are recoverable offline, but the run's own verdict is not.
	tag=$1
	# ☠️ AN OCV TAKEN ON THE CHARGER IS THE CHARGER'S VOLTAGE, NOT THE PACK'S. The
	# rehearsal read 4.413 V at the start with status "Charging" - that is the
	# float voltage of the charger, and the entire offset-bounding argument needs a
	# RESTED PACK. The radio was switched off and the charger was not; both have to
	# go, and the state has to be verified rather than assumed.
	s "OCV $tag: radio off, USB input suspended, resting ${RESTMIN} min"
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
		s "  rest $tag: ${waited}s, ${mv} mV over the last 2 min"
		[ "$mv" -lt 1 ] && [ "$mv" -gt -1 ] && { s "  rest $tag: settled after ${waited}s"; break; }
	done
	[ "$waited" -lt "$((CAP * 60))" ] || s "  ☠️ rest $tag hit its ${CAP} min ceiling without settling - this endpoint is suspect"
	# ☠️ SETTLING IS AN ACCEPTANCE CRITERION, NOT AN AFTERTHOUGHT. The rehearsal's
	# closing read was still climbing and only said so in hindsight. Take a ten
	# minute series and judge the LAST FIVE MINUTES: under 0.2 mV/min the pack is
	# rested, above it the number is a relaxation curve wearing an OCV's clothes.
	# ☠️ THE ACCEPTANCE SERIES HAS TO SLEEP TOO, and ten minutes of it used to be
	# ten minutes of an awake phone. Sparse sleeping samples: 10 x 60 s.
	for i in $(seq 1 10); do
		printf '%s %s %s %s\n' "$tag" "$(date +%s)" \
			"$(cat /sys/class/power_supply/*battery*/voltage_now)" \
			"$(cat /sys/class/power_supply/*battery*/capacity)" >> "$D/ocv.txt"
		nap 60
	done
	# ☠️☠️ FIRST-MINUS-LAST IS NOT A SLOPE, IT IS A TWO-SAMPLE DIFFERENCE, and one
	# outlier flips it. Measured 2026-09-03: a validation rest settled to +-1 mV
	# over its last three minutes - genuinely rested - and was declared NOT RESTED
	# at 5.39 mV/min, because a load spike had dipped two samples 30-90 mV nine
	# minutes in and one of them happened to be the FIRST of the window. The rest
	# was fine; the estimator was not, and it would have condemned good endpoints
	# all night.
	# ☠️ The fix is not smoothing. A load spike inside a rest IS a disturbance and
	# has to be named: drop samples further than 3 MAD from the median, fit the
	# slope on what is left, and SAY how many were dropped. A rest that needs many
	# drops is a rest that was disturbed, which is a different verdict from "still
	# relaxing" and must not be allowed to masquerade as one.
	# ☠️ THIS PRODUCED AN EMPTY SLOPE ON THE DEVICE AND THE CAUSE IS NOT YET KNOWN.
	# 2026-09-03, from the rehearsal's own log: "slope over the last 5 min:  mV/min
	# ☠️ NOT RESTED" - a blank where a number belongs, and the endpoint condemned
	# for the blank. My first diagnosis was the `read ... <<-EOF` here-doc, and a
	# side-by-side test on the same real data DISPROVED it: both the here-doc and
	# the positional form return 0.10 / 2 on the host. So the here-doc was not the
	# fault, and the fix below is NOT sold as one.
	# ☠️☠️ NOT A HERE-DOC, AND IT TOOK THREE DIAGNOSES TO EARN THAT SENTENCE.
	# The deployed version read the awk output through `read -r slope dropped
	# <<-EOF ... EOF` with the awk program written INSIDE the here-doc body. On the
	# device that produces:
	#     awk: cmd. line:15: Unexpected end of string
	# and an EMPTY slope - so the run log printed "slope over the last 5 min:
	# mV/min ☠️ NOT RESTED", a blank where a number belongs, and condemned a
	# perfectly good endpoint for it. An unquoted here-doc expands its body, and an
	# awk program is exactly the kind of text that does not survive being expanded.
	#
	# ☠️ THE TWO WRONG DIAGNOSES ARE THE LESSON, NOT THE BUG. First I blamed the
	# here-doc and "disproved" it with a test that put the awk program in a
	# VARIABLE - not inside the here-doc, so it tested a different construction and
	# passed. Then I blamed `^` because the HOST's busybox says "Math support is
	# not compiled in" - but the phone's busybox has math (sqrt(4) = 2, (3-1)^2 = 4),
	# so the host binary was not the target's. Both times the stand-in passed where
	# the real thing failed. The reproduction that finally settled it extracted the
	# deployed block from /usr/local/bin UNCHANGED and ran it on the phone.
	# ☠️ A repro that is easier to write than the original is usually a different
	# program. Run what runs.
	set -- $(grep "^$tag " "$D/ocv.txt" | tail -6 | awk '
		{t[NR]=$2; v[NR]=$3}
		END{
			n=NR; if (n<4) {print "0 0"; exit}
			for(i=1;i<=n;i++) w[i]=v[i]
			for(i=1;i<n;i++) for(j=i+1;j<=n;j++) if(w[j]<w[i]){x=w[i];w[i]=w[j];w[j]=x}
			med = (n%2) ? w[(n+1)/2] : (w[n/2]+w[n/2+1])/2
			for(i=1;i<=n;i++) d[i]=(v[i]>med)?v[i]-med:med-v[i]
			for(i=1;i<=n;i++) e[i]=d[i]
			for(i=1;i<n;i++) for(j=i+1;j<=n;j++) if(e[j]<e[i]){x=e[i];e[i]=e[j];e[j]=x}
			mad = (n%2) ? e[(n+1)/2] : (e[n/2]+e[n/2+1])/2
			if (mad < 1000) mad = 1000        # 1 mV floor: do not reject clean data
			k=0; st=0; sv=0; stt=0; stv=0
			for(i=1;i<=n;i++) if (d[i] <= 3*mad) { k++; st+=t[i]; sv+=v[i] }
			if (k<4) {printf "0 %d\n", n-k; exit}
			mt=st/k; mv=sv/k
			for(i=1;i<=n;i++) if (d[i] <= 3*mad) { stt+=(t[i]-mt)*(t[i]-mt); stv+=(t[i]-mt)*(v[i]-mv) }
			printf "%.2f %d\n", (stt>0? stv/stt : 0)/1000*60, n-k
		}')
	slope=${1:-}; dropped=${2:-0}
	if [ -z "$slope" ]; then
		s "  ☠️☠️ OCV $tag: THE SLOPE ESTIMATOR RETURNED NOTHING - this is a tool"
		s "     failure, NOT a verdict about the pack. Do not read the endpoint as"
		s "     'not rested': it has not been judged at all. Check that busybox awk"
		s "     accepts the program (it uses ^ and a hand-written sort)."
		slope=0
	fi
	[ "${dropped:-0}" -eq 0 ] || s "  ☠️ OCV $tag: ${dropped} sample(s) dropped as outliers - a load spike landed in the rest window; the slope below is fitted on the rest"
	s "OCV $tag slope over the last 5 min: ${slope} mV/min $(awk -v x="$slope" 'BEGIN{print (x<0.2 && x>-0.2) ? "(rested)" : "☠️ NOT RESTED - treat this endpoint as suspect"}')"
	# ☠️ SAY WHETHER IT HAD SETTLED. Five reads twenty seconds apart still climbing
	# means the pack is relaxing and the number is not an OCV yet; the rehearsal's
	# closing read rose 1.2 mV across its five samples on a 3 min rest. Print the
	# drift so a reader can discount it instead of trusting a single last value.
	first=$(grep "^$tag " "$D/ocv.txt" | head -1 | awk '{print $3}')
	last=$(grep "^$tag " "$D/ocv.txt" | tail -1 | awk '{print $3}')
	s "OCV $tag done: ${last}uV, drift over the last 80 s: $(( (last - first) / 1000 )) mV"
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
		done_sentinel aborted "last leg dropped: the vector would not go off"
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
done_sentinel finished "$BOOTS legs and both OCV blocks ran; validity is night-triage.sh's to judge"
systemctl disable fp3-night.service 2>/dev/null
systemctl start fp3-ims-reconcile.timer 2>/dev/null
