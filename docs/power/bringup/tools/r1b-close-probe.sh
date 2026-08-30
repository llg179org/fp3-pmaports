#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# Everything the R1b closing trip needs to READ, in one plain script so that no
# part of it lives inside three layers of shell quoting. Runs on the phone as
# root. Reads only - it changes nothing, so a wrong line here cannot damage the
# experiment it is reporting on.
set -u

echo "===== R1B LOG ====="
cat /var/log/fp3/idle-suspend.log 2>/dev/null || echo "(no log)"
echo "===== r1b unit: $(systemctl is-active r1b 2>/dev/null) ====="

echo "===== DID THE SESSIONS EVER REPORT IDLE? ====="
# logind.conf(5): the action runs only "after all sessions report that they are
# idle, no idle inhibitor lock is active" and the delay has expired. The window
# script captured the inhibitor list; this is the missing first witness.
# The keys are printed rather than asked for with --value, because --value with
# several -p returns them in schema order, not the order requested.
for sid in $(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}'); do
	echo "  session $sid: $(loginctl show-session "$sid" -p Id -p Type -p State -p IdleHint -p IdleSinceHint 2>/dev/null | tr '\n' ' ')"
done
echo "  seat0: $(loginctl show-seat seat0 -p IdleHint 2>/dev/null)"

echo "===== WHO SET THE IDLE POLICY ====="
echo "  dconf(fp3): $(su fp3 -c 'dconf read /org/gnome/settings-daemon/plugins/power/sleep-inactive-battery-type' 2>/dev/null || echo '<unreadable>')"
echo "  schema override files naming the key:"
grep -rln sleep-inactive /usr/share/glib-2.0/schemas/ 2>/dev/null | sed 's/^/    /'
grep -rhn sleep-inactive /usr/share/glib-2.0/schemas/*.override 2>/dev/null | sed 's/^/    /'

echo "===== RESTORE CHECK ====="
echo "  logind IdleAction: $(systemctl show systemd-logind -p IdleAction --value 2>/dev/null)"
ls /run/systemd/logind.conf.d/ 2>/dev/null | sed 's/^/  leftover drop-in: /'
echo "  charger: $(cat /sys/class/power_supply/pmi632-charger/status 2>/dev/null)"
echo "  suspend_stats: success=$(cat /sys/power/suspend_stats/success 2>/dev/null) fail=$(cat /sys/power/suspend_stats/fail 2>/dev/null)"
