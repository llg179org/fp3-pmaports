#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# HOST side: deploy tools/wake-qmi.sh to the phone and run the census.
#
# Answers three questions in one window, because they need the same window:
#   * WHICH QMI messages are the ~60 s noise - if they are ones ModemManager
#     subscribed to, the fix is userspace and no kernel patch is needed
#     (leads/selective-smd-wakeup.md, "the cheaper fork in the road");
#   * WHICH message and port an incoming SMS arrives on - the wake list has the
#     call (Voice, port 39) measured and nothing else, so a filter built on
#     today's data would swallow SMS exactly as the low-power arm swallowed the
#     call;
#   * whether the application processor actually collapses while it sleeps, from
#     xo_accumulated_duration before and after - see `post` below.
#
# ☠️ TWO PHASES, AND THE SPLIT IS THE WHOLE POINT.
#   `start` deploys, takes the BEFORE snapshot, and fires the census as a
#   transient unit - then RETURNS. `post`, run after the census has had time to
#   finish, takes the AFTER snapshot and fetches the log.
#
#   The obvious single-phase version is wrong in a way that reads as a result.
#   `systemd-run --unit=... --collect` does NOT wait, so an AFTER snapshot taken
#   on the next line is taken seconds after the census STARTED: the delta is
#   ~zero and the honest-looking conclusion is "the AP never collapses". That is
#   the same shape as the `systemctl suspend` mistake that produced a withdrawn
#   "63 s -> 305 s" result on 2026-08-30 - a non-blocking call read as blocking.
#   And `--wait` is not the fix here: the suspend drops the USB link, the ssh
#   wrapper retries whole commands, and the census would restart.
#
# ☠️ Deliberately NOT combined with a ModemManager debug-log run. Raising the log
#    level changes the system while it is being measured, and the debug log can
#    only ever confirm a failed unregister, never clear one (see
#    leads/modemmanager-suspend-modes.md).
#
# ☠️ Do not poll the phone between the phases - a login is a wake, and the wake IS
#    the measurement. Watch progress with host-sleep-census.sh, which reads the
#    HOST's USB log and touches nothing.
#
#   run-wake-qmi.sh start [alarm_s] [rounds]     default 600 3
#   run-wake-qmi.sh post
set -eu
CMD=${1:-start}; S=${2:-600}; N=${3:-3}
D=$(dirname "$0")
STATE=${TMPDIR:-/tmp}/fp3-wake-qmi

# Two snapshots of an ACCUMULATING counter, readable only while awake, is the
# right instrument for time spent asleep - the difference is the integral, and
# nothing has to be sampled during the sleep (nothing can be: the battery
# attributes that look readable across a suspend are cached).
# ☠️ This debugfs is root-only; a BLANK row is not a zero. Say so if it is empty.
# ☠️ Runs a DEPLOYED script, never an inlined one. The inline version expanded
# $(basename $m) in the device's login shell, before sh -c saw it, and wrote
# busybox's usage text into the middle of the capture - a failure a host-side
# dry run cannot reproduce, because on the host the string passes through
# literally. See the header of rpm-xo-snapshot.sh.
rpm_snapshot() {
	fp3-ssh 'echo <pw> | sudo -S /usr/local/bin/rpm-xo-snapshot.sh 2>/dev/null'
}

case "$CMD" in
start)
	mkdir -p "$STATE"
	echo "=== deploy $(date '+%T')"
	for f in wake-qmi.sh qmi-msgids.txt rpm-xo-snapshot.sh; do
		fp3-ssh "cat > /tmp/$f" < "$D/$f"
	done
	fp3-ssh 'echo <pw> | sudo -S sh -c "install -m755 /tmp/wake-qmi.sh /usr/local/bin/wake-qmi.sh;
		install -m755 /tmp/rpm-xo-snapshot.sh /usr/local/bin/rpm-xo-snapshot.sh;
		install -m644 /tmp/qmi-msgids.txt /usr/local/bin/qmi-msgids.txt" 2>/dev/null'
	# ☠️ identity, not well-formedness: `sh -n` answers "is this well-formed",
	# never "is this the file I sent", and the two look identical when green.
	echo "--- checksums (host | device) - they must match"
	sha256sum "$D/wake-qmi.sh" | cut -c1-16
	fp3-ssh 'sha256sum /usr/local/bin/wake-qmi.sh | cut -c1-16'
	fp3-ssh 'sh -n /usr/local/bin/wake-qmi.sh && echo "syntax ok on device"'

	echo "=== state before the run (so a later reader can see what it described)"
	fp3-ssh 'systemctl show ModemManager -p ExecStart --value | sed "s/.*argv\[\]=//; s/ ;.*//";
		 mmcli -m any 2>/dev/null | sed -n "s/.*state: *//p" | head -1' | tee "$STATE/before-state.txt"

	# Free NAS reads, awake, before the census, so they cost nothing and cannot
	# disturb it. get-supported-messages returns the modem's OWN bitmask of NAS
	# message ids: a set with nothing beyond libqmi's closes the eDRX avenue at
	# the firmware rather than at our tooling, which is a real answer; a larger
	# set is a measured list of ids, still not a licence to name one eDRX.
	echo "=== NAS reads before the census"
	fp3-ssh 'qmicli -d qrtr://0 --nas-get-supported-messages 2>&1 | head -40' | tee "$STATE/nas-supported.txt" || true
	fp3-ssh 'qmicli -d qrtr://0 --nas-get-drx 2>&1 | head -10' | tee "$STATE/nas-drx.txt" || true

	echo "=== RPM master XO accumulation BEFORE (saved for the post phase)"
	rpm_snapshot | tee "$STATE/xo-before.txt"
	date +%s > "$STATE/t0"

	echo "=== census starts $(date '+%T'); ${N} rounds of ${S}s"
	echo "    >>> SEND THE SMS during round 2, i.e. roughly $(date -d "+$((S + 40)) seconds" '+%H:%M') <<<"
	fp3-ssh "echo <pw> | sudo -S systemd-run --unit=wakeqmi --collect \
		/usr/local/bin/wake-qmi.sh $S $N logind 2>/dev/null"
	echo "=== fired and RETURNING. Expected finish ~$(date -d "+$(( (S + 25) * N + 30 )) seconds" '+%H:%M')."
	echo "    Watch with host-sleep-census.sh; do NOT log in. Then: $0 post"
	;;

post)
	[ -f "$STATE/t0" ] || { echo "no start state in $STATE - was 'start' run?"; exit 1; }
	echo "=== $(( ($(date +%s) - $(cat "$STATE/t0")) )) s since the census started"
	echo "=== RPM master XO accumulation AFTER"
	rpm_snapshot | tee "$STATE/xo-after.txt"
	echo "--- BEFORE, for the same masters"
	cat "$STATE/xo-before.txt"
	echo "--- ☠️ Compare the APSS row's delta against the SUMMED sleep time the"
	echo "    census reports, not against the wall clock: the counter accumulates"
	echo "    whenever that master lets the XO go, asleep or not."
	echo "=== the census log"
	fp3-ssh 'cat /var/log/fp3/wake-qmi.log' | tee "$STATE/wake-qmi.log"
	;;
*) echo "usage: $0 start [alarm_s] [rounds] | $0 post"; exit 2;;
esac
