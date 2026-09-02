#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# THE CURRENT METER THAT KEEPS RUNNING WHILE THE AP SLEEPS.
#
#   qg-accum.sh            one reading: average current over the accumulator window
#   qg-accum.sh N SECS     N readings SECS apart
#
# `current_now` can only be sampled with the AP awake, so it prices the system
# the observation itself created; a 30-minute leg at a 600 s alarm gave three
# samples whose scatter (A −148.0 mA against A′ −202.9 mA, the SAME configuration)
# was larger than the effect being measured. The PMI632's fuel gauge has a
# hardware accumulator that does better on both counts.
#
# WHAT IT IS. QG peripheral base 0x4800 on the PMI632 (the value our own
# qcom_smbx.c carries as `.qg_base`, and the vendor 4.9 DT confirms:
# `qcom,qgauge@4800`). Three registers, read over the SPMI regmap debugfs:
#
#   0x4888..0x488a  V_ACCUM_DATA0   24-bit, little endian
#   0x488b..0x488d  I_ACCUM_DATA0   24-bit, little endian, SIGNED
#   0x488e          ACCUM_CNT       how many samples are in the accumulator
#
# and the vendor's own conversion, from qg-defs.h:
#
#   V_RAW_TO_UV(x) = 194637 * x / 1000        I_RAW_TO_UA(x) = 152588 * x / 1000
#
# applied to acc/count — that is, the vendor reads it as the AVERAGE over the
# window, which is what this script prints.
#
# ☠️ THE SIGN IS INVERTED relative to `current_now`. Measured 2026-09-02 while
# charging: the accumulator said −157 mA where `current_now` said +156 mA. The
# magnitudes agree within a few mA, which is what makes the two a cross-check.
#
# ★ IT RUNS ACROSS SUSPEND, and that is the point. Measured: read, `rtcwake -m mem
# -s 60`, read again on wake — the count had rolled over during the sleep and the
# window it reported covered the sleeping phone. At the wake instant `current_now`
# read −9 mA (a transient); the accumulator read −148 mA, consistent with the
# −150 mA it read before and the +149 mA `current_now` gave three seconds later.
#
# ☠️ WHAT IT DOES NOT DO. ACCUM_CNT is 8 bits and samples arrive at ~3.35/s, so
# the window is at most ~76 s. It is not a charge counter over an hour and it
# cannot be differenced across a long sleep — it reports the average over the
# LAST ~minute. To make that minute the quiet part of a sleep, keep the wake
# interval short, or read it knowing it covers the tail.
set -u
N=${1:-1}
GAP=${2:-20}
REG=/sys/kernel/debug/regmap/0-02/registers
[ -r "$REG" ] || { echo "☠️ $REG not readable - run as root" >&2; exit 1; }

i=0
while [ "$i" -lt "$N" ]; do
	i=$((i+1))
	# ☠️ ONE grep, not four: the four bytes must come from one pass, or the
	# accumulator can roll over between reads and the count will not match the sum.
	R=$(grep -E '^488[b-e]:' "$REG")
	acc=$(echo "$R" | awk -F': ' '/^488b/{a=$2} /^488c/{b=$2} /^488d/{c=$2} END{print c b a}')
	cnt=$(echo "$R" | awk -F': ' '/^488e/{print $2}')
	# ☠️ NO awk strtonum HERE. busybox awk does not have it, and this repo has
	# already paid once for an instrument that used it: the function is simply
	# undefined and awk prints an error where a number should be. Shell
	# arithmetic understands 0x directly.
	v=$((0x$acc)); [ "$v" -ge 8388608 ] && v=$((v - 16777216))
	c=$((0x$cnt))
	if [ "$c" -eq 0 ]; then
		echo "$(date '+%F %T') ACCUM_CNT=0 - no samples yet, no average to report"
	else
		# -(v/c) * 152588 / 1e6 mA, in integer arithmetic scaled by 10
		ma10=$(( -v * 152588 / c / 100000 ))
		echo "$(date '+%F %T') I_acc=$v cnt=$c  avg = $((ma10/10)).$(( (ma10<0 ? -ma10 : ma10) %10 )) mA   (sign inverted vs current_now)"
	fi
	[ "$i" -lt "$N" ] && sleep "$GAP"
done
