#!/bin/sh
# Category: power
# Description: the modem actually behaves like a camped idle UE - low duty at the paging DRX rate
#
# THE BEHAVIOUR HALF of the IMS lever, and the partner of 56-ims-config-test.sh.
# That one reads what the modem SAYS; this one measures what it DOES, which is
# the only half that can fail while the configuration looks correct.
#
# The signature of the cheap state is not just "low duty" - it is low duty AT THE
# PAGING RATE. Measured, three independent runs: 4.4-4.8 % awake at 3.13-3.15
# wakes/s, and 1/3.14 = 318 ms is the LTE paging DRX cycle. The expensive state
# is 31-52 % at 2.5/s. So the two are separated on both axes, and requiring both
# makes the check hard to pass by accident.
#
# ☠️ ITS MEDIUM IS THE NETWORK. The band alone moves duty by ~17 pp in this
# repo's own ladder, so the thresholds sit well inside the measured spread and
# the band and cell are printed with every result - a FAIL that is really a band
# change should be readable as one rather than blamed on the configuration.
#
# ☠️ THE ZERO-DELTA TRAP. The RPM updates XO total duration on EXIT, so a master
# that stays down for the whole window contributes zero and reads as "100 % awake"
# unless the shutdown COUNT is consulted too. That reading once produced a
# five-star finding that was exactly backwards, so this check defers to the
# canonical reader rather than parsing the counters itself.

WINDOW=${FP3_IMS_DUTY_WINDOW:-180}
READER=/usr/local/bin/rpm_master_stats.py
STATS=/sys/kernel/debug/qcom_rpm_master_stats/MPSS

[ -r "$STATS" ] || { echo "SKIP: $STATS not readable (need root, or no RPM master stats)"; exit 0; }
[ -x "$READER" ] || { echo "SKIP: $READER not installed - the canonical RPM reader is part of the power work"; exit 0; }
mmcli -m any >/dev/null 2>&1 || { echo "SKIP: no modem present"; exit 0; }

band=$(qmicli -d qrtr://0 --nas-get-rf-band-info 2>/dev/null | sed -n "s/.*Active Band Class: *//p" | head -1)
cell=$(qmicli -d qrtr://0 --nas-get-cell-location-info 2>/dev/null | sed -n "s/.*Global Cell ID: *//p" | head -1)

tmp=$(mktemp) || exit 1
sed 's/^/BEFORE /' "$STATS" > "$tmp"
sleep "$WINDOW"
sed 's/^/AFTER /' "$STATS" >> "$tmp"

line=$(python3 "$READER" --tagged "$tmp" "$WINDOW" 2>&1 | grep '^MPSS')
rm -f "$tmp"
echo "      window ${WINDOW}s  band=${band:-?}  cell=${cell:-?}"
echo "      $line"

duty=$(echo "$line" | sed -n 's/.*  *\([0-9][0-9]*\)\.[0-9]* % awake.*/\1/p')
rate=$(echo "$line" | sed -n 's/.*% awake  *\([0-9][0-9]*\)\.\([0-9]\).*wakes\/s.*/\1\2/p')

if [ -z "$duty" ] || [ -z "$rate" ]; then
	echo "FAIL: could not read a duty and a wake rate out of the canonical reader"
	echo "      (a zero delta is ambiguous by design and the reader refuses to guess - see its output above)"
	exit 1
fi

fail=0
# duty well under the cheap/expensive gap: measured 4.4-4.8 cheap, 31-52 expensive
if [ "$duty" -lt 15 ]; then
	echo "PASS: modem duty ${duty} % - camped, not holding a connection"
else
	echo "FAIL: modem duty ${duty} % - the UE is holding an RRC connection"
	echo "      if 56-ims-config-test.sh passed, the configuration is right and the"
	echo "      behaviour is not: check the band above before blaming IMS"
	fail=1
fi
# rate x10; the paging DRX cycle is 3.13-3.15/s, the connected state 2.4-2.6/s
if [ "$rate" -ge 29 ]; then
	echo "PASS: wake rate $(( rate / 10 )).$(( rate % 10 ))/s - the paging DRX cycle"
else
	echo "FAIL: wake rate $(( rate / 10 )).$(( rate % 10 ))/s - below the paging cycle, so the"
	echo "      wakes are connection housekeeping rather than paging occasions"
	fail=1
fi

exit $fail
