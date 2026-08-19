#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Is it OUR UCM verb that keeps the audio DSP awake?
#
# The FP3 HiFi verb's EnableSequence leaves two q6routing paths permanently on,
# and its DisableSequence is empty:
#
#   QUIN_MI2S_RX Audio Mixer MultiMedia1 = 1     playback front-end -> speaker
#   MultiMedia2 Mixer SLIMBUS_0_TX       = 1     mic -> ADSP, pre-routed
#   AIF1_CAP Mixer SLIM TX0              = 1
#
# We put them there on purpose: pulseaudio probes a profile by opening the PCM
# after only the verb sequence, and a q6asm front-end cannot be opened until it
# is routed to a backend. The signature matches what was measured on 2026-08-19:
# applied once at boot, never re-applied, and gone after an ADSP restart - which
# is exactly when the DSP started power-collapsing through every suspend.
#
# ☠️ THIS NEEDS A FRESH BOOT. Once the ADSP has been restarted it collapses
# freely and every arm reads +1, which would look like a result and be noise.
# The first arm is therefore a GATE, not a measurement: if the DSP already
# collapses with everything in place, the phone is not in the held state and the
# probe refuses to run.
#
# ☠️ Run under systemd-run, over either link. It changes mixer settings and puts
# them back on every exit path.
#
#   audio-hold-probe.sh [suspend_s]        (default 30)

set -u

SECS=${1:-30}
RPM=/sys/kernel/debug/qcom_rpm_master_stats
CARD=0

PLAYBACK="QUIN_MI2S_RX Audio Mixer MultiMedia1"
CAP_MM2="MultiMedia2 Mixer SLIMBUS_0_TX"
CAP_AIF="AIF1_CAP Mixer SLIM TX0"

modprobe rpm_master_stats 2>/dev/null || true
say() { echo "$*"; }
mf() { sed -n "s/^[[:space:]]*$2[[:space:]]*:[[:space:]]*//p" "$RPM/$1" 2>/dev/null | head -1; }
get() { amixer -c $CARD cget name="$1" 2>/dev/null | sed -n 's/.*values=//p' | head -1; }
set_() { amixer -c $CARD -q cset name="$1" "$2" 2>/dev/null; }

P0=$(get "$PLAYBACK"); C0=$(get "$CAP_MM2"); A0=$(get "$CAP_AIF")

restore() {
	rc=$?
	set_ "$PLAYBACK" "${P0:-1}"
	set_ "$CAP_MM2" "${C0:-1}"
	set_ "$CAP_AIF" "${A0:-1}"
	say "# restored: playback=$(get "$PLAYBACK") mm2=$(get "$CAP_MM2") aif=$(get "$CAP_AIF") rc=$rc"
	say "# ☠️ check audio actually works again before trusting this line"
	exit $rc
}
trap restore EXIT INT TERM

# One arm: read, suspend, read. Reports the XO-off time as a fraction of the
# suspend, because a blink and a full collapse are different animals.
arm() {
	label=$1
	l0=$(mf LPASS 'Shutdown count'); d0=$(mf LPASS 'XO total duration')
	rtcwake -m mem -s "$SECS" > /dev/null 2>&1
	l1=$(mf LPASS 'Shutdown count'); d1=$(mf LPASS 'XO total duration')
	ms=$(( ( ${d1:-0} - ${d0:-0} ) / 19200 ))
	say "$label  LPASS +$(( ${l1:-0} - ${l0:-0} ))  XO off ${ms}ms of $(( SECS * 1000 ))ms"
	LAST_MS=$ms
}

say "# audio-hold-probe uptime=$(cut -d. -f1 /proc/uptime) suspend=${SECS}s"
say "# controls at start: playback=$P0 mm2=$C0 aif=$A0"
say "# LPASS at start: shutdowns=$(mf LPASS 'Shutdown count') xo_dur=$(mf LPASS 'XO total duration')"
say ""

LAST_MS=0
arm "  A  everything as booted "
if [ "$LAST_MS" -gt 5000 ]; then
	say ""
	say "# ABORT: the DSP already collapses with the verb in place."
	say "# This phone is not in the held state - it has been through an ADSP"
	say "# restart, or the holder is not the verb. Reboot and run this first."
	exit 1
fi

say ""
say "# B: dropping the capture pre-route only"
set_ "$CAP_MM2" 0
set_ "$CAP_AIF" 0
arm "  B  capture route off   "

say ""
say "# C: dropping the playback route as well"
set_ "$PLAYBACK" 0
arm "  C  both routes off     "

say ""
say "# D: capture back, playback still off"
set_ "$CAP_MM2" "${C0:-1}"
set_ "$CAP_AIF" "${A0:-1}"
arm "  D  playback route off  "

say ""
say "# audio-hold-probe done"
