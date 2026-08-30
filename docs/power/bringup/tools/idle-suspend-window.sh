#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# DOES THE PHONE SUSPEND ON ITS OWN, AND WHAT DOES IT COST WHEN IT DOES?
#
# Everything measured on this front so far used an EXPLICIT `systemctl suspend`.
# Nothing on this system asks for a suspend by itself:
#   * `sleep-inactive-ac-type='nothing'` (postmarketos-base-ui-gnome), so on a
#     cable the session never requests one - and this phone is always on a cable,
#     because the cable is the link;
#   * `IdleAction=ignore` in logind;
#   * `/etc/sleep-inhibitor.conf` makes an ssh session a sleep inhibitor.
# The third is the sharp one: **the measurement's own connection forbids the
# thing being measured.** So this script must be started and then abandoned - the
# witness is the HOST's USB log (`host-sleep-census.sh`), which needs no
# connection and cannot perturb what it watches.
#
# ☠️ DEAD-MAN SWITCH, AND IT IS THE PATH, NOT THE TRAP. Enabling an idle-suspend
# policy on a phone whose only two links both need userspace is a way to lose the
# phone: once it suspends, ssh is gone, and if nothing wakes it the next move is a
# held power button. An EXIT trap is not enough - it does not run on SIGKILL and
# it does not run across a reboot, and "persistence is a property of the whole
# chain" cuts both ways: a change you want to be temporary must be written
# somewhere that cannot persist. So the drop-in goes in **/run**, which systemd
# reads exactly like /etc and which is tmpfs: a reboot undoes this experiment
# whether or not anything ran. The trap is the fast path, the tmpfs is the
# guarantee. Verify the restore by reading the log line, never by assuming a
# clean exit.
#
# ☠️ This does NOT touch the modem edge arming. The edge stays armed on purpose:
# an idle-suspend policy that also drops incoming calls answers a question nobody
# asked (leads/selective-smd-wakeup.md, and the low-power arm that died of
# exactly this).
#
#   idle-suspend-window.sh [window_s] [idle_s]      default 1800 60
set -u
W=${1:-1800}; I=${2:-60}
O=/var/log/fp3/idle-suspend.log
mkdir -p /var/log/fp3
say(){ echo "$*" >> "$O"; }
: > "$O"

say "# idle-suspend-window $(date '+%F %T') window=${W}s idle=${I}s"
say "#   the witness is the HOST usb log; nothing here polls the phone"

# --- record the state we are about to change, and the restore, BEFORE changing it
OLD_ACTION=$(sed -n 's/^ *IdleAction *= *//p' /etc/systemd/logind.conf 2>/dev/null | tail -1)
OLD_SEC=$(sed -n 's/^ *IdleActionSec *= *//p' /etc/systemd/logind.conf 2>/dev/null | tail -1)
say "#   before: IdleAction=${OLD_ACTION:-<unset>} IdleActionSec=${OLD_SEC:-<unset>}"
say "#   edge arming is NOT touched: $(cat /sys/devices/platform/soc@0/4080000.remoteproc/remoteproc/*/*:smd-edge/power/wakeup 2>/dev/null | head -1)"

DROPIN=/run/systemd/logind.conf.d/zz-fp3-idle-window.conf   # /run on purpose: see above
reload_logind() {
	# ☠️ Prefer reload: restarting logind can take the graphical session with it,
	# and a session that died mid-window changes what is being measured into
	# something else. Fall back to a restart only if reload is refused, and SAY
	# which one happened - the two are not the same experiment.
	if systemctl reload systemd-logind 2>/dev/null; then say "#   (logind reloaded)"
	else systemctl restart systemd-logind 2>/dev/null; say "#   ☠️ (logind RESTARTED - reload refused; the session may have been recreated)"
	fi
}
restore() {
	rm -f "$DROPIN"
	reload_logind
	say "# RESTORED $(date '+%F %T') - drop-in removed; IdleAction back to ${OLD_ACTION:-the file default}"
	say "#   verify: $(systemctl show systemd-logind -p IdleAction --value 2>/dev/null)"
}
trap restore EXIT HUP INT TERM

# ☠️ THE COUNTER MUST BE READ BEFORE, OR THE ANSWER IS NOT A NUMBER. This
# script used to print /sys/power/suspend_stats/success only at the end, as an
# absolute value - which cannot say how many suspends happened IN the window,
# only how many have happened since boot. On a phone that has already suspended
# 75 times today, "success=75" afterwards is compatible with the window
# containing zero suspends, which is the exact outcome this exists to detect.
# --- WHICH POLICY BRANCH IS THIS PHONE IN? (added 2026-08-30)
# pmaports overrides sleep-inactive-ac-type only; the battery branch keeps
# GNOME's default 'suspend' at 1200 s. Which branch applies depends on what
# UPower thinks the phone is running on, which is NOT the same question as
# whether a cable is plugged in - the PMIC input-suspend bit can make a cabled
# phone report as discharging. These are RECORDED, never acted on: a wrong read
# here must not be able to change what the window measures.
for k in sleep-inactive-ac-type sleep-inactive-ac-timeout \
         sleep-inactive-battery-type sleep-inactive-battery-timeout; do
	v=$(gsettings get org.gnome.settings-daemon.plugins.power "$k" 2>/dev/null)
	say "#   gsettings $k = ${v:-<unreadable: no session bus from here>}"
done
say "#   power supply: online=$(cat /sys/class/power_supply/*/online 2>/dev/null | tr '\n' ' ')"
say "#   charger status=$(cat /sys/class/power_supply/pmi632-charger/status 2>/dev/null)"
say "#   upower on-battery=$(upower -i /org/freedesktop/UPower/devices/DisplayDevice 2>/dev/null | sed -n 's/.*state: *//p' | head -1)"

S0=$(cat /sys/power/suspend_stats/success 2>/dev/null)
F0=$(cat /sys/power/suspend_stats/fail 2>/dev/null)
say "#   BEFORE: suspend_stats success=${S0:-?} fail=${F0:-?}"

mkdir -p "$(dirname $DROPIN)"
printf '[Login]\nIdleAction=suspend\nIdleActionSec=%s\n' "$I" > "$DROPIN"
reload_logind
say "# enabled $(date '+%F %T'): IdleAction=suspend after ${I}s idle"
say "#   ☠️ an ssh session inhibits sleep (/etc/sleep-inhibitor.conf), so LOG OUT now"
say "#   inhibitors currently held:"
systemd-inhibit --list --no-pager 2>/dev/null | sed 's/^/   /' | head -20 >> "$O"

sleep "$W"

say "# window closed $(date '+%F %T')"
say "-- inhibitors held AT THE END (an ssh session here invalidates the run)"
systemd-inhibit --list --no-pager 2>/dev/null | sed 's/^/   /' | head -20 >> "$O"
S1=$(cat /sys/power/suspend_stats/success 2>/dev/null)
F1=$(cat /sys/power/suspend_stats/fail 2>/dev/null)
say "-- suspends completed IN THIS WINDOW (delta, which is the answer)"
say "   success ${S0:-?} -> ${S1:-?}  = $(( ${S1:-0} - ${S0:-0} ))"
say "   fail    ${F0:-?} -> ${F1:-?}  = $(( ${F1:-0} - ${F0:-0} ))"
if [ "$(( ${S1:-0} - ${S0:-0} ))" -eq 0 ]; then
	say "   ⇒ THE PHONE NEVER ASKED FOR A SUSPEND in ${W}s with IdleAction=suspend"
	say "     and a ${I}s idle threshold. That is a result, not a failed run -"
	say "     but check the inhibitor list below before believing it: an ssh"
	say "     session left open would have produced exactly this."
fi
say "-- kernel's view of each sleep"
journalctl -k --since "-${W}s" --no-pager 2>/dev/null \
	| grep -E "PM: suspend (entry|exit)|Timekeeping suspended" | tail -30 | sed 's/^/   /' >> "$O"
