#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# A-B-A' on ANY one knob, measured with burst-attrib.sh.
#
# ☠️ THIS EXISTS TO STOP THE THIRD COPY. burst-modem-ab.sh and burst-wlan-ab.sh
# are the same twenty lines with a different verb, and the moment a third
# candidate appeared (NFC) it was going to be a third copy. Duplication is how
# this directory got two panel-blanking implementations that disagreed, one of
# them worse. Anything after wlan goes through here.
#
#   burst-knob-ab.sh <label> <off-cmd> <on-cmd> <state-cmd> <expected-off-state> [window_s]
#
# e.g.
#   burst-knob-ab.sh nfc 'rfkill block nfc' 'rfkill unblock nfc' \
#       'rfkill list nfc | sed -n "s/.*Soft blocked: //p" | head -1' yes 360
#
# The state command must print something; the run refuses to continue unless it
# prints <expected-off-state> after the off command, so a leg is never labelled
# "off" on the strength of a command that silently failed.
#
# ☠️ AND IT IS A-B-A', NOT A-B. The pack's floor drifts with state of charge, so
# a two-leg subtraction cannot tell an effect from that drift. If A and A' do not
# agree, the run says nothing.
set -u
[ $# -ge 5 ] || { echo "usage: $0 <label> <off-cmd> <on-cmd> <state-cmd> <expected-off> [window_s]" >&2; exit 2; }
LABEL=$1; OFFCMD=$2; ONCMD=$3; STATECMD=$4; EXPECT=$5; W=${6:-360}

OUT=/var/log/fp3/burst-${LABEL}-ab-$(date +%s)
mkdir -p "$OUT"
say(){ echo "$*" | tee -a "$OUT/log"; }
state(){ eval "$STATECMD" 2>/dev/null | head -1; }
restore(){ eval "$ONCMD" >/dev/null 2>&1; }
trap 'say "# signal caught - restoring $LABEL"; restore; exit 143' INT TERM HUP
trap 'restore' EXIT

say "# burst-knob-ab $(date '+%F %T') knob=$LABEL window=${W}s"
say "# kernel=$(uname -r) $(uname -v)"
say "# off='$OFFCMD' on='$ONCMD' state='$STATECMD' expect-off='$EXPECT'"

s0=$(state)
[ -n "$s0" ] || { say "# STOP: the state command printed nothing - refusing to run blind"; exit 1; }
say "# initial state=$s0"

leg(){
	say "# $1 begin: $LABEL=$(state) $(date '+%T')"
	/usr/local/bin/burst-attrib.sh "$W" >/dev/null 2>&1 || true
	d=$(ls -td /var/log/fp3/burst-attrib-* 2>/dev/null | head -1)
	if [ -n "$d" ]; then
		mkdir -p "$OUT/$1"
		cp "$d/attrib.txt" "$d/current.txt" "$d/log" "$OUT/$1/" 2>/dev/null
		say "# $1 done: $(grep -vc '^#' "$OUT/$1/attrib.txt") samples <- $d"
	else
		say "# $1 produced nothing"
	fi
	say "# $1 end:   $LABEL=$(state)"
}

leg A
eval "$OFFCMD" >/dev/null 2>&1
sleep 10
st=$(state)
say "# $LABEL off -> state=$st"
case "$st" in
*"$EXPECT"*) ;;
*) say "# STOP: $LABEL did not reach '$EXPECT' (state=$st) - refusing to call the next leg 'off'"; exit 1 ;;
esac
leg B
eval "$ONCMD" >/dev/null 2>&1
sleep 20
say "# $LABEL back on -> state=$(state)"
leg Ap
say "# done: $OUT"
