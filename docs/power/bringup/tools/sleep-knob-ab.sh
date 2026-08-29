#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# A-B-A' on one knob, measured in SUSPEND RESIDENCY rather than in duty or mA.
#
#   sleep-knob-ab.sh <label> <off-cmd> <on-cmd> <state-cmd> <expected-off> \
#                    [rounds] [seconds] [gap_s]        (defaults 3, 600, 150)
#
# ☠️ WHY A THIRD WRAPPER. burst-knob-ab compares currents and burst-master-knob
# compares a master's duty; neither can see the quantity that decides whether this
# phone sleeps at all. Residency and duty are DIFFERENT QUANTITIES and a null on
# one is not a null on the other - measured 2026-08-29: stopping ModemManager left
# the modem's duty flat (38/36/37 %) and took the suspend from 16-53 s to the full
# 602 s. A knob has to be asked both questions separately.
#
# THE QUESTION THIS WAS BUILT FOR. ModemManager's lifetime controls the wakes
# exactly, so the cost is something live in the daemon. Two mechanisms fit and they
# need opposite fixes:
#
#   (a) an indication subscription the MODEM services on its own schedule - the
#       fix is which NAS indications the QMI plugin registers, i.e. a change to
#       ModemManager;
#   (b) a POLL TIMER inside the daemon - s2idle does not stop hrtimers, so a timer
#       every N seconds wakes the AP, which then asks the modem and gets an
#       interrupt back. The fix is a setting.
#
# `mmcli -m 0 --disable` separates them with nothing patched: the daemon keeps
# running with all of its timers, and the modem's subscriptions go away with the
# disable. If the suspends hold, it is (a). If they still die, it is (b).
# ☠️ A disabled modem cannot receive a call either, so like every other leg here
# this is an instrument, not a candidate fix.
#
# ☠️ THE GAP IS A SAFETY PARAMETER (see suspend-rate.sh): the USB gadget does not
# re-enumerate within 30 s of a resume, so a short gap makes a healthy run
# indistinguishable from a wedged phone from the outside. Do not shorten it.
#
# ☠️ Do not poll the phone while this runs. Every ssh login is a wakeup and here
# the wakeups are the measurement. systemd-run it and read the log afterwards.
set -u
[ $# -ge 5 ] || { echo "usage: $0 <label> <off-cmd> <on-cmd> <state-cmd> <expected-off> [rounds] [secs] [gap]" >&2; exit 2; }
LABEL=$1; OFFCMD=$2; ONCMD=$3; STATECMD=$4; EXPECT=$5
N=${6:-3}; SECS=${7:-600}; GAP=${8:-150}

# ☠️ Same refusal as burst-master-knob.sh, matched on the PATH and not on the
# word: restarting the modem through /sys/class/remoteproc/N/state costs audio
# until the next reboot and a mixer write afterwards oopses the kernel.
case "$OFFCMD$ONCMD" in
	*/sys/class/remoteproc/*state*)
		echo "☠️ refusing: this must not drive the remoteproc state file" >&2; exit 2 ;;
esac

OUT=/var/log/fp3/sknob-${LABEL}-$(date +%s)
mkdir -p "$OUT"
say(){ echo "$*" | tee -a "$OUT/log"; }
state(){ eval "$STATECMD" 2>/dev/null | head -1; }
restore(){ eval "$ONCMD" >/dev/null 2>&1; }
trap 'say "# signal caught - restoring $LABEL"; restore; exit 143' INT TERM HUP
trap 'restore' EXIT

say "# sleep-knob-ab $(date '+%F %T') knob=$LABEL rounds=$N secs=$SECS gap=${GAP}s"
say "# kernel=$(uname -r) $(uname -v)"

leg(){
	name=$1
	say "# --- leg $name: state=$(state)"
	/usr/local/bin/suspend-rate.sh "$N" "$SECS" "$GAP" >/dev/null 2>&1
	cp /run/srate.txt "$OUT/$name.txt" 2>/dev/null
	# the summary line the reader actually wants, next to the raw file
	say "# leg $name slept: $(awk '!/^#/ && NF>3 {printf "%s ", $3}' "$OUT/$name.txt")of $SECS"
	say "# leg $name ended by: $(awk '!/^#/ && NF>3 {printf "%s ", $NF}' "$OUT/$name.txt")"
}

leg A
say "# applying off: $OFFCMD"
eval "$OFFCMD" >/dev/null 2>&1
sleep 10
st=$(state)
# ☠️ A leg is never labelled "off" on the strength of a command that returned 0.
# The state command has to SHOW the change - the ipacm A/B of 2026-08-28 was run
# against a `ctl.stop` property that reported "stopping" and never stopped.
case "$st" in
	*"$EXPECT"*) say "# state after off: $st" ;;
	*) say "☠️ STOP: state is '$st', expected '$EXPECT' - restoring and aborting"; exit 1 ;;
esac
leg B
say "# restoring: $ONCMD"
eval "$ONCMD" >/dev/null 2>&1
sleep 30
say "# state after restore: $(state)"
leg Ap
say "# $OUT"
