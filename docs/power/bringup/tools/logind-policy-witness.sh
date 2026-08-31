#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# DOES A /run LOGIND DROP-IN ACTUALLY TAKE EFFECT?
#
# R1b enabled IdleAction=suspend through a /run/systemd/logind.conf.d drop-in and
# measured zero suspends in 1800 s. Two of the three conditions logind.conf(5)
# names were then shown to have HELD (every session whose class can idle reported
# idle; no block-mode sleep inhibitor). What was never checked is the simplest
# one: whether logind ever read the drop-in at all.
#
# ☠️ THE EARLIER INSTRUMENT ASKED THE WRONG OBJECT. `systemctl show
# systemd-logind -p IdleAction` asks for a property of the systemd UNIT, and
# IdleAction is a property of the logind D-BUS INTERFACE - so it returns an empty
# string whatever the setting is, silently. That empty string also made a gate
# refuse to arm a night's measurement. The witness below asks the bus.
#
# This takes seconds, not a window: the question is what logind BELIEVES, and it
# believes it the moment it reloads.
set -u
B="busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager"
D=/run/systemd/logind.conf.d/zz-fp3-policy-witness.conf

show() {
	echo "  IdleAction      = $($B IdleAction 2>&1)"
	echo "  IdleActionUSec  = $($B IdleActionUSec 2>&1)"
	echo "  IdleHint        = $($B IdleHint 2>&1)"
	echo "  IdleSinceHint   = $($B IdleSinceHint 2>&1)"
}

echo "=== BEFORE (no drop-in of ours) ==="
show
echo "  wrong tool, for the record: systemctl show -p IdleAction = '$(systemctl show systemd-logind -p IdleAction --value 2>&1)'"

echo "=== installing the drop-in in /run (tmpfs: a reboot undoes it) ==="
mkdir -p "$(dirname $D)"
printf '[Login]\nIdleAction=suspend\nIdleActionSec=60\n' > "$D"
if systemctl reload systemd-logind 2>/dev/null; then echo "  (reloaded)"
else systemctl restart systemd-logind 2>/dev/null; echo "  ☠️ (RESTARTED - reload refused; the session may have been recreated)"; fi
sleep 2

echo "=== AFTER ==="
show

echo "=== removing it again ==="
rm -f "$D"
systemctl reload systemd-logind 2>/dev/null || systemctl restart systemd-logind 2>/dev/null
sleep 2
echo "=== RESTORED ==="
show
