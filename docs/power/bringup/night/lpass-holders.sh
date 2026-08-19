#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Step 1 of the deep-sleep chain: WHO HOLDS LPASS.
#
# The audio DSP has shut down twice since boot, for 0.12 s in total, against
# 4344 shutdowns on the vendor stack on the same hardware. A master that never
# shuts down is a sufficient explanation for qcom_stats/vlow reading 0 in every
# capture this investigation has ever taken - so before any patch, the question
# is which of the ADSP's clients keeps it up, and whether removing them moves
# the counter at all.
#
# ☠️ This is measurement, not a fix. The XO branch was mechanically plausible,
# moved its own counter from 0 to 1952, and changed the discharge slope by
# nothing. Nothing here is allowed to become a patch until the counter moves.
#
# ☠️ Every stage re-verifies that the counter is LIVE before believing a zero:
# at least two other masters must move during the same window. That check is
# what makes "LPASS +0" a measurement rather than a stuck file, and it is
# repeated per stage because a file can go stale halfway through a night.
#
# ☠️ Run under systemd-run. Run in the foreground over ssh and an ssh timeout
# kills it mid-stage, leaving the ADSP stopped and the sensor stack unloaded
# with nothing left to put them back.
#
#   lpass-holders.sh [dwell_s] [live_s]        (defaults 240, 30)
#
# Environment:
#   LPASS_STAGES="S0 S1 S2 S3 S4 S5"   which stages to run. "S0" alone is the
#                                      control: read the counter, remove nothing.

set -u

DWELL=${1:-240}
LIVE=${2:-30}
RPM=/sys/kernel/debug/qcom_rpm_master_stats
STATS=/sys/kernel/debug/qcom_stats
ADSP=/sys/class/remoteproc/remoteproc2      # name=adsp; verified below, not assumed

say() { echo "$*"; }
up() { cut -d. -f1 /proc/uptime; }

modprobe rpm_master_stats 2>/dev/null || true

mf() { sed -n "s/^[[:space:]]*$2[[:space:]]*:[[:space:]]*//p" "$RPM/$1" 2>/dev/null | head -1; }
cnt() { sed -n 's/^Count[[:space:]]*:[[:space:]]*//p' "$STATS/$1" 2>/dev/null | head -1; }

if [ ! -r "$RPM/LPASS" ]; then
	say "# ABORT: $RPM/LPASS is not readable - without it every reading below is '?'"
	exit 1
fi
if [ "$(cat $ADSP/name 2>/dev/null)" != adsp ]; then
	say "# ABORT: $ADSP is not the ADSP (name=$(cat $ADSP/name 2>/dev/null)) - the numbering moved"
	exit 1
fi

# --- restore ------------------------------------------------------------------
# Written before anything is removed, and armed on every exit path.
STOPPED_SVC=''
REMOVED_MOD=''
ADSP_STOPPED=0

restore() {
	rc=$?
	say ""
	say "# restoring"
	if [ "$ADSP_STOPPED" = 1 ]; then
		echo start > $ADSP/state 2>/dev/null || true
		sleep 5
		say "#   adsp -> $(cat $ADSP/state 2>/dev/null)"
	fi
	for m in $REMOVED_MOD; do
		modprobe "$m" 2>/dev/null && say "#   modprobe $m ok" || say "#   modprobe $m FAILED"
	done
	for s in $STOPPED_SVC; do
		systemctl start "$s" 2>/dev/null && say "#   started $s" || say "#   start $s FAILED"
	done
	say "# restore done rc=$rc uptime=$(up)"
	exit $rc
}
trap restore EXIT INT TERM

# --- the instrument -----------------------------------------------------------
# One stage: read all five masters, wait, read again. Print the deltas and a
# verdict on whether the counter could have moved at all.
stage() {
	label=$1; window=$2
	a0=$(mf APSS 'Shutdown count'); m0=$(mf MPSS 'Shutdown count')
	p0=$(mf PRONTO 'Shutdown count'); l0=$(mf LPASS 'Shutdown count')
	lx0=$(mf LPASS 'XO shutdown count'); lt0=$(mf LPASS 'Sleep Accumulated Duration')
	v0=$(cnt vlow); n0=$(cnt vmin)

	sleep "$window"

	a1=$(mf APSS 'Shutdown count'); m1=$(mf MPSS 'Shutdown count')
	p1=$(mf PRONTO 'Shutdown count'); l1=$(mf LPASS 'Shutdown count')
	lx1=$(mf LPASS 'XO shutdown count'); lt1=$(mf LPASS 'Sleep Accumulated Duration')
	v1=$(cnt vlow); n1=$(cnt vmin)

	d() { echo $(( ${2:-0} - ${1:-0} )); }
	moved=0
	[ "${a1:-0}" -gt "${a0:-0}" ] 2>/dev/null && moved=$((moved + 1))
	[ "${m1:-0}" -gt "${m0:-0}" ] 2>/dev/null && moved=$((moved + 1))
	[ "${p1:-0}" -gt "${p0:-0}" ] 2>/dev/null && moved=$((moved + 1))

	say "STAGE $label window=${window}s uptime=$(up)"
	say "  APSS +$(d "$a0" "$a1")  MPSS +$(d "$m0" "$m1")  PRONTO +$(d "$p0" "$p1")"
	say "  LPASS shutdowns +$(d "$l0" "$l1")  (total $l1)   XO +$(d "$lx0" "$lx1")  (total $lx1)"
	say "  LPASS sleep duration +$(d "$lt0" "$lt1")"
	say "  vlow $v0 -> $v1   vmin $n0 -> $n1"
	if [ "$moved" -ge 2 ]; then
		say "  counter-live: OK ($moved of 3 other masters moved)"
	else
		say "  counter-live: ☠️ ONLY $moved of 3 moved - this stage's LPASS reading proves nothing"
	fi
	say ""
}

stop_svc() {
	for s in "$@"; do
		if systemctl is-active --quiet "$s" 2>/dev/null; then
			systemctl stop "$s" 2>/dev/null && STOPPED_SVC="$STOPPED_SVC $s"
		fi
	done
	say "# stopped:$STOPPED_SVC"
}

# Remove modules by repeated passes rather than in a hand-written dependency
# order: the order is what breaks when the module set changes, and a pass loop
# reports honestly which ones would not go and why.
rmmod_deep() {
	want=$*
	pass=0
	while [ "$pass" -lt 6 ]; do
		pass=$((pass + 1)); progress=0
		for m in $want; do
			lsmod | grep -q "^$m " || continue
			if rmmod "$m" 2>/dev/null; then
				REMOVED_MOD="$m $REMOVED_MOD"   # reverse order for restore
				progress=1
			fi
		done
		[ "$progress" = 0 ] && break
	done
	left=''
	for m in $want; do
		if lsmod | grep -q "^$m "; then
			left="$left $m($(lsmod | awk -v M="$m" '$1==M {print $3" used by "$4}'))"
		fi
	done
	if [ -n "$left" ]; then say "# still loaded:$left"; else say "# all removed after $pass pass(es)"; fi
}

STAGES=${LPASS_STAGES:-S0 S1 S2 S3 S4 S5}
want() { case " $STAGES " in *" $1 "*) return 0 ;; esac; return 1; }

say "# lpass-holders start uptime=$(up) dwell=${DWELL}s live=${LIVE}s stages=\"$STAGES\""
say "# LPASS at start: shutdowns=$(mf LPASS 'Shutdown count') xo=$(mf LPASS 'XO shutdown count') sleep=$(mf LPASS 'Sleep Accumulated Duration')"
say ""

# S0: the control. Everything running, same window as every stage below.
want S0 && stage "S0 baseline (nothing removed)" "$DWELL"

# S1: the sensor userspace. Known NOT sufficient on its own over three minutes
# (2026-08-19); repeated here at full dwell so S2 has a clean predecessor.
if want S1; then
	say "# S1: stopping the sensor userspace"
	stop_svc snsregd iio-sensor-proxy
	stage "S1 sensor userspace stopped" "$DWELL"
fi

# S2: the SMGR client drivers. These are the QMI clients that talk to the DSP's
# sensor manager; if anything in our stack keeps a session open, it is here.
if want S2; then
	say "# S2: removing the SMGR client drivers"
	rmmod_deep smgr_prox smgr_accel smgr_gyro smgr_mag sns_smgr smgr
	stage "S2 SMGR drivers removed" "$DWELL"
fi

# S3: the audio userspace. No stream is playing, but a held PCM would keep an
# AFE port up, and an AFE port up is a reason for the DSP not to collapse.
if want S3; then
	say "# S3: stopping the audio userspace"
	stop_svc fp3-voiced spkwatch ringwatch
	stage "S3 audio userspace stopped" "$DWELL"
fi

# S4: the q6 stack itself, machine driver first (it holds the DAI links).
if want S4; then
	say "# S4: removing the q6 stack"
	rmmod_deep snd_soc_apq8016_sbc q6voice_dai q6voice q6mvm q6cvp q6cvs q6voice_common \
		q6asm_dai q6afe_dai q6routing q6afe_clocks q6adm q6asm q6afe q6core apr
	stage "S4 q6 stack removed" "$DWELL"
fi

# S5: stop the DSP outright. This does NOT answer "does LPASS sleep" - a stopped
# processor is off, not asleep - but it does answer the separate question of
# whether the RPM's own gate opens once nothing is holding LPASS at all. If vlow
# moves here and nowhere else, the mechanism is confirmed and the cost of the
# ADSP is bounded from above.
if want S5; then
say "# S5: stopping the ADSP remoteproc outright"
if echo stop > $ADSP/state 2>/dev/null; then
	ADSP_STOPPED=1
	sleep 5
	say "# adsp state=$(cat $ADSP/state 2>/dev/null)"
	stage "S5 ADSP stopped" "$DWELL"
else
	say "# S5 SKIPPED: could not write stop to $ADSP/state"
fi
fi

say "# lpass-holders done uptime=$(up)"
