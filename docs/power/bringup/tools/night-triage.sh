#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# THE MORNING AFTER: read the night in the order that can invalidate it.
#
#   night-triage.sh [dir]          (default /var/log/fp3/night, run on the device)
#
# ☠️ THE ORDER IS THE POINT, and it is deliberately validity-first. A current
# number is meaningless until the leg that produced it is known to be what it
# claimed and undisturbed, so the mA come LAST:
#
#   1. audit labels   - was anything else awake during a leg (ssh, unexpected
#                       unit, incoming call)? An interfered leg is invalid, not
#                       noisy.
#   2. vector gates   - did every leg actually run with IMS off, and did any leg
#                       get dropped because it would not?
#   3. band log       - did a leg change band? The band is worth ~17 pp of duty
#                       and ~54 mA here; legs on different bands are not
#                       comparable and no statistic will rescue them.
#   4. OCV endpoints  - did both rests settle (< 0.2 mV/min), or is an endpoint
#                       suspect?
#   5. the numbers    - ma3-fit per leg, and only then the boot-to-boot spread.
#
# ☠️ AND THE SPREAD COMES FROM THE LEG MEANS, NEVER THE POOLED WINDOWS. Pooling
# hides exactly the term the night was run to estimate: the within-leg band is
# already known to be ~1 mA, and the question is how much a BOOT moves it.
set -u
D=${1:-/var/log/fp3/night}
[ -d "$D" ] || { echo "no such directory: $D"; exit 1; }

echo "=== 1. INTERFERENCE AUDIT ============================================"
grep -hE "audit:|DISTURBED|INTERFERED" "$D"/leg*/log.txt 2>/dev/null || echo "  no audit lines found - either no leg ran, or the legs predate the audit (which is itself worth knowing)"

echo
echo "=== 2. VECTOR GATES =================================================="
grep -hE "vector (verified|NOT)|DROPPING THIS LEG" "$D/run.log" 2>/dev/null || echo "  (nothing logged)"
[ -s "$D/dropped.txt" ] && { echo "  ☠️ dropped legs:"; cat "$D/dropped.txt"; }

echo
echo "=== 3. BAND / CELL ==================================================="
grep -hE "band/cell|THE BAND MOVED" "$D"/leg*/log.txt 2>/dev/null || echo "  (no band recorded)"

echo
echo "=== 4. OCV ENDPOINTS ================================================="
grep -hE "OCV .* (done|slope)|NOT RESTED|hit its" "$D/run.log" 2>/dev/null || echo "  (no OCV lines)"

echo
echo "=== 5. THE NUMBERS (validity first - read 1-4 before believing these) ="
for leg in "$D"/leg*/; do
	[ -d "$leg" ] || continue
	echo "--- $(basename "$leg")"
	ma3-fit.py "$leg" --alarm "${ALARM:-90}" 2>/dev/null | sed -n '2,6p'
done

echo
echo "=== 6. BOOT-TO-BOOT SPREAD (from the LEG MEANS, never the pooled windows)"
for leg in "$D"/leg*/; do
	ma3-fit.py "$leg" --alarm "${ALARM:-90}" 2>/dev/null | awk 'NR==2{print $6}'
done | awk '
	{n++; x[n]=$1; s+=$1}
	END{
		if (n < 2) { printf "  only %d usable leg - no boot-to-boot spread yet\n", n+0; exit }
		# ☠️ Written as a product rather than a power. The reason recorded here on
		# 2026-09-03 was WRONG: it claimed busybox awk on the phone lacks math
		# support, measured on the HOST busybox, which is a different build. The
		# phone has it - sqrt(4) = 2 and (3-1)^2 = 4, asked directly. The product
		# form is kept because it is portable and costs nothing, not because the
		# power operator was broken.
		# ☠️☠️ AND NO APOSTROPHES IN HERE. This block lives inside a SINGLE-QUOTED
		# awk program, so one apostrophe in a comment closes the program and the
		# shell then reads the next awk line as its own - which is exactly what
		# happened when the note above was first written with "phone-apostrophe-s"
		# in it: busybox ash answered "bad for loop variable" on line 70, blaming a
		# line that was never shell to begin with.
		m=s/n; for (i=1;i<=n;i++) v+=(x[i]-m)*(x[i]-m); sd=sqrt(v/(n-1))
		printf "  %d legs, means:", n; for (i=1;i<=n;i++) printf " %.1f", x[i]; print ""
		printf "  mean of leg means = %.1f mA, boot-to-boot sd = %.1f mA, sem = %.1f mA\n", m, sd, sd/sqrt(n)
		print "  ☠️ THIS sd is the number the night was run for. The within-leg band"
		print "     (~1 mA) was never the dominant error, and pooling the windows"
		print "     would have hidden this one entirely."
	}'
