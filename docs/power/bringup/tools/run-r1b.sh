#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# HOST side for R1b: deploy idle-suspend-window.sh, arm it, and LET GO.
#
# One trip, because the awake window between sleep rounds is short. Everything
# after the arming is read afterwards - this script must not hold a connection
# open, since an ssh session is a sleep inhibitor and would forbid exactly the
# thing being measured.
#
# ☠️ FP3_SSH_TRIES is raised on purpose: the wrapper's default patience is about
# two minutes, shorter than one sleep cycle. The command below is idempotent
# (install, systemd-run --collect of a fixed unit name), which is what makes a
# long retry budget safe - the wrapper re-runs the WHOLE string on each attempt.
#
#   run-r1b.sh [window_s] [idle_s]        default 1800 60
set -u
W=${1:-1800}; I=${2:-60}
PW=${FP3_PW:-<pw>}
here=$(dirname "$(readlink -f "$0")")

b64=$(base64 -w0 "$here/idle-suspend-window.sh")

FP3_SSH_TRIES=${FP3_SSH_TRIES:-250} fp3-ssh "echo $PW | sudo -S sh -c '
  echo $b64 | base64 -d > /usr/local/bin/idle-suspend-window.sh
  chmod 755 /usr/local/bin/idle-suspend-window.sh
  systemctl reset-failed r1b 2>/dev/null
  systemd-run --unit=r1b --collect /usr/local/bin/idle-suspend-window.sh $W $I
  echo R1B-ARMED unit=\$(systemctl is-active r1b) window=${W}s idle=${I}s
  echo \"  suspend_stats success=\$(cat /sys/power/suspend_stats/success) fail=\$(cat /sys/power/suspend_stats/fail)\"
' 2>/dev/null"
