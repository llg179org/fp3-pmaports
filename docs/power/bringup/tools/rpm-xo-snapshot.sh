#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# One line per RPM master: how long it has let the XO go, cumulatively, since
# boot. Run it before and after a sleep - the DIFFERENCE is the time that master
# spent letting the crystal off, which is the integral the question wants and
# which cannot be sampled during a suspend (userspace is frozen, and the battery
# attributes that look readable across one are cached).
#
# ☠️ THIS EXISTS AS A FILE BECAUSE INLINING IT DOES NOT WORK. As
#   fp3-ssh 'echo pw | sudo -S sh -c "... $(basename $m) ..."'
# the device's LOGIN shell expands the double-quoted string before sh -c ever
# sees it, so $m is empty and `basename` prints its usage text into the middle of
# the capture. It looked right in a host-side dry run, because there the string
# passes through literally - the expansion happens one hop further along than the
# harness can see. A quoted snippet that survives the host is not a snippet that
# survives the device.
#
# ☠️ Root-only debugfs: a BLANK row is not a zero. This says so rather than
# printing an empty line, because empty lines next to real ones read as "nothing
# to see here" and have been believed before.
MS=/sys/kernel/debug/qcom_rpm_master_stats
modprobe rpm_master_stats 2>/dev/null
if [ ! -d "$MS" ]; then
	echo "☠️ $MS absent - module missing, or not root. NOT a zero."
	exit 1
fi
n=0
for m in "$MS"/*; do
	[ -e "$m" ] || continue
	v=$(sed -n 's/^[[:space:]]*xo_accumulated_duration[[:space:]]*:[[:space:]]*//p' "$m" 2>/dev/null | head -1)
	c=$(sed -n 's/^[[:space:]]*xo_count[[:space:]]*:[[:space:]]*//p' "$m" 2>/dev/null | head -1)
	printf '%-12s xo_accumulated_duration=%-22s xo_count=%s\n' \
		"$(basename "$m")" "${v:-<unreadable>}" "${c:-<unreadable>}"
	n=$((n + 1))
done
[ "$n" -gt 0 ] || echo "☠️ no master files under $MS - NOT a zero."
