#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# Two guards on the RPM per-master XO counter, the single most misread number in
# this tree. Run it from anywhere; it needs only python3 and the repository.
#
#   ./selftest-rpm-readers.sh
#
# GUARD 1 - GOLDEN FILES. Four recorded captures, each with the answer written
# down when it was derived and reviewed by hand. If a change to
# `rpm_master_stats.py` moves any of these numbers, the run fails. The four are
# chosen to cover the ways this counter has actually been misread:
#
#   cheap     2026-08-31 leg A - the ~5 % modem state
#   expensive 2026-09-01       - the ~36 % modem state, the one under study
#   oracle    2026-08-24       - the DOWNSTREAM hex format, from Ubuntu Touch
#   trap      (inside both pmOS files) - LPASS with a FROZEN counter, which four
#             separate ad-hoc readers printed as "100 % awake" when it was in
#             fact asleep for the whole window
#
# GUARD 2 - NO SECOND READER. Any tool that parses the counter's FIELD NAMES
# instead of calling the canonical reader is a place the next inversion bug can
# live. 29 of them exist today and rewriting them all at once is not the point;
# the list is frozen in `rpm-reader-allowlist.txt` and this guard fails when the
# list GROWS. Referring to the debugfs PATH is fine - dumping the file verbatim
# is the recommended thing to do.
set -u
cd "$(dirname "$0")" || exit 1
C=../captures
R=./rpm_master_stats.py
fail=0
ok() { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fail=1; }

check() { # check <label> <expected-substring> <args...>
	label=$1; want=$2; shift 2
	got=$(python3 "$R" "$@" 2>&1)
	case "$got" in
	*"$want"*) ok "$label" ;;
	*) bad "$label"; echo "    want: $want"; echo "    got:"; echo "$got" | sed 's/^/      /' ;;
	esac
}

echo "GUARD 1 - golden files"
check "cheap  MPSS 5.1 %"      "MPSS      5.1 % awake    3.14 wakes/s  16.2 ms/wake" \
	--tagged "$C/2026-08-31_mm-duty-ab/leg-A-mm-stopped.txt" 600
check "cheap  LPASS asleep"    "LPASS   asleep for the whole window" \
	--tagged "$C/2026-08-31_mm-duty-ab/leg-A-mm-stopped.txt" 600
check "expensive MPSS 35.8 %"  "MPSS     35.8 % awake    2.46 wakes/s  145.5 ms/wake" \
	--tagged "$C/2026-09-01_four-master/raw/four-master-2026-09-01_2010.txt" 600
check "expensive LPASS asleep" "LPASS   asleep for the whole window" \
	--tagged "$C/2026-09-01_four-master/raw/four-master-2026-09-01_2010.txt" 600
check "expensive APSS awake"   "APSS    awake for the whole window" \
	--tagged "$C/2026-09-01_four-master/raw/four-master-2026-09-01_2010.txt" 600
check "oracle MPSS 6.3 %"      "MPSS      6.3 % awake    3.15 wakes/s  20.0 ms/wake" \
	--window "$C/2026-08-24_ut-master-stats-idle-before.txt" \
	         "$C/2026-08-24_ut-master-stats-idle-after.txt" 565
check "oracle LPASS 2.9 %"     "LPASS     2.9 % awake   13.71 wakes/s  2.1 ms/wake" \
	--window "$C/2026-08-24_ut-master-stats-idle-before.txt" \
	         "$C/2026-08-24_ut-master-stats-idle-after.txt" 565

# The trap, stated as its own case so the intent survives: the pmOS LPASS and
# the oracle LPASS have the SAME zero-ish signature in the accumulators and
# OPPOSITE meanings. Getting one of these right and the other wrong is the bug.
echo "GUARD 1b - the inversion trap, both directions in one comparison"
a=$(python3 "$R" --tagged "$C/2026-09-01_four-master/raw/four-master-2026-09-01_2010.txt" 600 | grep '^LPASS')
b=$(python3 "$R" --window "$C/2026-08-24_ut-master-stats-idle-before.txt" \
	"$C/2026-08-24_ut-master-stats-idle-after.txt" 565 | grep '^LPASS')
case "$a$b" in
*asleep*2.9*) ok "pmOS LPASS asleep, oracle LPASS 2.9 % awake - not the reverse" ;;
*) bad "the LPASS pair reads the wrong way round"; echo "    pmOS:   $a"; echo "    oracle: $b" ;;
esac

echo "GUARD 2 - no second reader"
# The scan is a function so it can be pointed at a throwaway directory and SHOWN
# FAILING. A verifier that has never been demonstrated to fire has proved
# nothing - this tree has already shipped one such check (a `curl -sI` that
# returned 302 for every hash, including a bogus one, and so passed
# unconditionally for weeks).
scan() {
	grep -lE 'xo_accumulated_duration|XO total duration|XO shutdown count|xo_count|Last XO shutdown|xo_last_ent|xo_last_exit' \
		"$1"/*.sh "$1"/*.py 2>/dev/null \
		| sed 's#.*/##' \
		| grep -vxE 'rpm_master_stats.py|selftest-rpm-readers.sh' \
		| LC_ALL=C sort
}

# ☠️ POSIX sh, not bash: no process substitution here. The first version of
# this line used <(...) and died with "Syntax error: \"(\" unexpected".
allow=$(mktemp) || exit 1
LC_ALL=C sort rpm-reader-allowlist.txt > "$allow"
now=$(scan .)
new_files=$(printf '%s\n' "$now" | LC_ALL=C comm -23 - "$allow")
rm -f "$allow"
if [ -n "$new_files" ]; then
	bad "a NEW tool parses the counter directly:"
	printf '%s\n' "$new_files" | sed 's/^/      /'
	echo "      Call rpm_master_stats.py instead, or - if the tool only needs the"
	echo "      raw bytes - dump the file verbatim and parse on the host."
else
	ok "no new direct parser ($(printf '%s\n' "$now" | grep -c .) known, frozen in rpm-reader-allowlist.txt)"
fi

echo "GUARD 2b - the guard, shown firing"
t=$(mktemp -d) || exit 1
trap 'rm -rf "$t"' EXIT INT TERM
printf '#!/bin/sh\nawk "/XO total duration/ {print}" x\n' > "$t/fake-offender.sh"
if [ -n "$(scan "$t")" ]; then
	ok "the scan detects a planted direct parser"
else
	bad "the scan did NOT detect a planted direct parser - guard 2 proves nothing"
fi
rm -rf "$t"; trap - EXIT INT TERM

echo "GUARD 1c - the golden check, shown firing"
gotbad=$(python3 "$R" --tagged "$C/2026-09-01_four-master/raw/four-master-2026-09-01_2010.txt" 60 2>&1)
case "$gotbad" in
*"35.8 % awake"*) bad "the golden check is insensitive to the window length - it proves nothing" ;;
*) ok "a wrong window length changes the golden answer, so the check can fail" ;;
esac

[ "$fail" = 0 ] && echo "PASS" || echo "FAILED"
exit "$fail"
