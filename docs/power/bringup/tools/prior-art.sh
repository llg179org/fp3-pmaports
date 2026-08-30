#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# HAS THIS ALREADY BEEN MEASURED? Ask before spending a window, not after.
#
# ☠️ THIS EXISTS BECAUSE THE PROSE VERSION FAILED. On 2026-08-30 two rules went
# into /fp3-kernel-test - "grep the captures for the FIELD, not the topic" and
# "read the closed leads before spending a window" - and four hours later the
# same session measured `APSS XO shutdown count` across a fresh suspend, wrote a
# conclusion from it, and only then found that the repository had CLOSED that
# branch eleven days earlier with an A/B: the counter was driven 0 -> 1952 and
# the discharge slope moved by 0.4%. One grep would have surfaced it.
#
# A rule in prose is a wish. A rule you can run is a rule.
#
# Search by the FIELD or COUNTER NAME, never by the topic: captures are indexed
# by date and by the question that prompted them, never by what they contain.
#
#   prior-art.sh 'XO shutdown count'
#   prior-art.sh xo_accumulated_duration
#   prior-art.sh 'src_port=51'
set -u
[ $# -ge 1 ] || { echo "usage: $0 <field or counter name>"; exit 2; }
Q=$1
D=$(cd "$(dirname "$0")/.." && pwd)      # docs/power/bringup

hits=0
for area in captures leads findings-log.md; do
	p="$D/$area"
	[ -e "$p" ] || continue
	n=$(grep -rl -- "$Q" "$p" 2>/dev/null | wc -l)
	hits=$((hits + n))
	[ "$n" -gt 0 ] || continue
	echo "== $area ($n file(s))"
	grep -rn -- "$Q" "$p" 2>/dev/null | head -12 | sed 's|'"$D"'/||' | sed 's/^/   /'
done

echo
if [ "$hits" -eq 0 ]; then
	echo "no prior art for '$Q'."
	echo "☠️ That is not the same as 'nobody has measured this'. Try the other"
	echo "   spellings this device uses - downstream and mainline disagree on"
	echo "   several field names (xo_accumulated_duration vs 'XO total duration')"
	echo "   - and try the counter rather than the concept."
else
	echo "☠️ $hits file(s) mention it. Read the LATEST one before measuring:"
	echo "   a capture is true as of its date, and the retraction lives elsewhere."
	echo "   Check specifically for a closing verdict:"
	echo "     grep -rn -i 'do not spend\\|closes\\|retract\\|withdraw' <the files above>"
fi
