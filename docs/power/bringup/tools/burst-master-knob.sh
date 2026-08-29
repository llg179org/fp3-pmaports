#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# A-B-A' on one knob, measured with burst-master.sh instead of burst-attrib.sh.
#
# ☠️ WHY A SECOND WRAPPER AND NOT A FLAG ON burst-knob-ab.sh: what is under test
# here is not the current but a MASTER'S DUTY CYCLE. burst-knob-ab compares
# currents; this compares how often MPSS/PRONTO were up, which is the only way to
# ask whether a knob reaches the modem FIRMWARE or only its radio. mmcli --disable
# moved the current by 2 mA against a 3 mA baseline spread - a flat result that
# says nothing about whether the MSS core kept waking. This asks that directly.
#
#   burst-master-knob.sh <label> <off-cmd> <on-cmd> <state-cmd> <expected-off> [window_s]
#
# The state command must print <expected-off> after the off command or the run
# stops: a leg is never labelled "off" on the strength of a command that silently
# failed. And it is A-B-A', never A-B - the pack's floor drifts with charge.
#
# ☠️ It must never be pointed at /sys/class/remoteproc. Restarting the modem there
# costs audio until the next reboot and a mixer write afterwards oopses the kernel.
set -u
[ $# -ge 5 ] || { echo "usage: $0 <label> <off-cmd> <on-cmd> <state-cmd> <expected-off> [window_s]" >&2; exit 2; }
LABEL=$1; OFFCMD=$2; ONCMD=$3; STATECMD=$4; EXPECT=$5; W=${6:-360}

# ☠️ Refuse the ONE dangerous write - restarting the modem through
# /sys/class/remoteproc/N/state costs audio until the next reboot and a mixer
# write afterwards oopses the kernel.
#
# ☠️ Match the PATH, not the word. The first version of this guard matched
# *remoteproc* anywhere in either command, and on 2026-08-29 it refused a
# perfectly safe run whose knob was
#   echo remoteproc0:smd-edge.IPCRTR.-1.-1 > .../qcom_smd_qrtr/unbind
# - an rpmsg DEVICE NAME that merely contains the word. A guard that fires on
# the safe case is worse than none, because the next person in a hurry deletes
# it rather than narrowing it.
case "$OFFCMD$ONCMD" in
	*/sys/class/remoteproc/*state*|*/sys/class/remoteproc/*/state*)
		echo "☠️ refusing: this must not drive the remoteproc state file" >&2; exit 2 ;;
esac

OUT=/var/log/fp3/bmknob-${LABEL}-$(date +%s)
mkdir -p "$OUT"
say(){ echo "$*" | tee -a "$OUT/log"; }
state(){ eval "$STATECMD" 2>/dev/null | head -1; }
restore(){ eval "$ONCMD" >/dev/null 2>&1; }
trap 'say "# signal caught - restoring $LABEL"; restore; exit 143' INT TERM HUP
trap 'restore' EXIT

say "# burst-master-knob $(date '+%F %T') knob=$LABEL window=${W}s"
say "# kernel=$(uname -r) $(uname -v)"

leg(){
	name=$1
	say "# --- leg $name: state=$(state)"
	/usr/local/bin/burst-master.sh "$W" >/dev/null 2>&1
	d=$(ls -dt /var/log/fp3/burst-master-* | head -1)
	cp -r "$d" "$OUT/$name"
	say "# leg $name -> $OUT/$name ($(grep -vc '^#' "$OUT/$name/master.txt") samples)"
}

leg A
say "# applying off: $OFFCMD"
eval "$OFFCMD" >/dev/null 2>&1
sleep 10
got=$(state)
[ "$got" = "$EXPECT" ] || { say "☠️ after the off command the state is '$got', expected '$EXPECT' - refusing to label this leg off"; exit 1; }
leg B
say "# restoring: $ONCMD"
restore
sleep 20
say "# state after restore: $(state)"
leg Ap
say "# $OUT"
