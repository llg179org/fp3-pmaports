#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated. Written by Claude under the direction of Lajosházi, László
# Gergely, who reviewed every measurement it rests on.
#
# ssr-repro.sh - one controlled ADSP subsystem restart, with the WCD9335's
# health measured before it and at +20 s and +90 s after it, followed by a
# verdict table of the named failure symptoms.
#
# Run it on the device as root and detached, so the ssh session cannot
# contaminate the result:
#
#     systemd-run --collect --unit=ssr-repro /bin/sh /tmp/ssr-repro.sh
#     # then wait for "=== DONE" in /tmp/ssr-repro.log
#
# The remoteproc is addressed by NAME, never by index - the indices move
# between boots. The sanity rows at the end of the verdict must be non-zero:
# a verdict of all zeros with zero sanity rows means the counter read nothing,
# not that the kernel was quiet. That is not hypothetical; the first version of
# this script filtered dmesg by timestamp and printed an empty section while
# dmesg itself held 225 codec lines and a WARNING.
# One controlled ADSP restart, with the codec's health measured before and after.
# Addresses the remoteproc by name, never by index.
set -u
OUT=/tmp/ssr-repro.log
exec >"$OUT" 2>&1

RP=
for d in /sys/class/remoteproc/*/; do
	n=$(cat "$d/name" 2>/dev/null)
	case "$n" in adsp|*4080000*) RP="$d" ;; esac
done
[ -n "$RP" ] || { echo "FATAL: no adsp remoteproc"; exit 1; }
echo "adsp = $RP (name=$(cat "$RP/name"), state=$(cat "$RP/state"))"

health() {
	echo "--- health($1) t=$(cut -d' ' -f1 /proc/uptime)"
	echo "cards: $(grep -c . /proc/asound/cards)"
	amixer -c F3 cget name='RX INT7_1 MIX1 INP0' >/dev/null 2>&1 && echo "amixer-read: ok" || echo "amixer-read: FAIL"
	amixer -c F3 sset 'RX7 Digital Volume' 80 >/dev/null 2>&1 && echo "amixer-write: ok" || echo "amixer-write: FAIL"
	timeout 6 speaker-test -c2 -twav -l1 -D hw:F3,0 >/dev/null 2>&1 && echo "playback: ok" || echo "playback: FAIL"
	echo "irq142: $(grep wcd9335_pin1 /proc/interrupts | tr -s ' ')"
}

health before
MARK=$(cut -d' ' -f1 /proc/uptime)
echo "=== MARK $MARK: stopping adsp"
echo stop > "$RP/state"; sleep 5
echo "=== starting adsp t=$(cut -d' ' -f1 /proc/uptime)"
echo start > "$RP/state"
sleep 20
health after-20s
sleep 70
health after-90s
# Read dmesg directly and count the named symptoms. An earlier version of this
# filtered by timestamp with awk and printed nothing at all while dmesg itself
# held 225 codec lines - so the counts below come from grep over the whole
# buffer, and the raw window is printed unfiltered underneath.
echo "=== VERDICT (0 for every row is the pass)"
for pat in "CODEC version detection fail" "Failed to bringup WCD9335" \
           "already exists in 'regmap'" "Flags mismatch" \
           "Failed to register IRQ chip" "remove_proc_entry" \
           "WARNING:" "Failed to write config" "Failed to sync masks"; do
	printf '%-32s %s\n' "$pat" "$(dmesg | grep -c "$pat")"
done
echo "=== sanity: the restart really happened (must be non-zero)"
printf '%-32s %s\n' "remoteproc adsp lines" "$(dmesg | grep -c 'remoteproc2\|adsp is now up')"
printf '%-32s %s\n' "wcd9335/slim lines" "$(dmesg | grep -ci 'wcd9335\|slim')"
echo "=== raw dmesg from the MARK onwards"
dmesg | sed -n "/\[ *${MARK%%.*}\./,\$p"
echo "=== DONE"
