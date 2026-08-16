#!/bin/sh
# Description: the system clock is a real date, and the bootstrap that makes it
# one is still installed
#
# This phone has no writable RTC. pm8xxx offers three ways to persist the time
# and the device tree enables none of them, so hwclock reads 1970 on every boot
# and ioctl(RTC_SET_TIME) answers ENODEV. A wrong clock is not cosmetic: TLS
# fails, apk refuses signatures, and every log line before the correction is
# stamped with a fiction - which is how a service that failed eleven hours ago
# came to be dated four weeks back.
#
# ☠️ Two arms, because the first one alone would be measuring the room. With
# WiFi in reach NTP sets the clock within seconds of boot, so "the date is
# right" says nothing about whether the phone can set its clock without WiFi -
# and the piece that does that, fp3-nitz-clock, could have been dropped by a
# reflash without a single check going red. The second arm asks the question
# the first one cannot: is it still there.

fail=0

# 1. Is the clock a date at all? 2025-01-01, comfortably after any plausible
# build date of this image and before any real use of it.
SANE_AFTER=1735689600
now=$(date -u +%s)

if [ "$now" -ge "$SANE_AFTER" ]; then
	echo "PASS: the clock reads $(date -u '+%Y-%m-%dT%H:%M:%SZ') (UTC)"
else
	echo "FAIL: the clock reads $(date -u '+%Y-%m-%dT%H:%M:%SZ'), which is not a"
	echo "      real date - TLS, apk and every timestamp in the journal are"
	echo "      unreliable until it is corrected"
	echo "      cmd: timedatectl; hwclock -r; sudo mmcli -m 0 --time"
	fail=1
fi

# What corrected it, so a pass is readable. Both sources are legitimate; the
# point is to say which one is carrying the phone.
if [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = yes ]; then
	echo "      corrected by NTP (a network is in reach)"
else
	echo "      NTP has not synchronised, so the clock is whatever the"
	echo "      cellular bootstrap left it at"
fi

# 2. Is the bootstrap still installed? This is the arm that survives a reflash
# with WiFi in reach, where arm 1 passes on NTP alone.
if [ ! -x /usr/local/bin/fp3-nitz-clock ]; then
	echo "FAIL: /usr/local/bin/fp3-nitz-clock is missing, so a boot without"
	echo "      WiFi has no way to set the clock at all"
	echo "      cmd: see fp3-pmaports/userspace-system/README.md for the install"
	fail=1
elif ! systemctl is-enabled fp3-nitz-clock.service >/dev/null 2>&1; then
	echo "FAIL: fp3-nitz-clock is installed but not enabled, so it never runs"
	echo "      cmd: sudo systemctl enable fp3-nitz-clock.service"
	fail=1
else
	echo "PASS: fp3-nitz-clock is installed and enabled"
	last=$(journalctl -b -u fp3-nitz-clock --no-pager -o cat 2>/dev/null | tail -1)
	[ -n "$last" ] && echo "      last run this boot: $last"
fi

exit $fail
