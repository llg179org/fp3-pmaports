#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# ONE trip after the R1b window closes, doing the three things that all need the
# phone awake, so it is woken once rather than three times:
#
#   1. read everything (r1b-close-probe.sh) - the log, whether the sessions ever
#      reported idle, who set the idle policy, and the restore state
#   2. verify the idle-suspend policy is GONE
#   3. re-arm the step-0 sleep run for the night
#
# ☠️ Order matters. R1b's EXIT trap removes its logind drop-in, but step 0 must
# not be armed while an IdleAction=suspend policy could still be live: a
# residency measurement running underneath one is measuring two things at once.
# So the arming is conditional on the readback, and refuses loudly otherwise.
#
# ☠️ Everything complicated lives in the deployed scripts, NOT inside this ssh
# command string. Nested quoting is how a probe silently reports nothing.
#
# ☠️ step 0 cuts the PMIC charge input; its own trap restores it. Never reboot
# while it is set - see the standing gates.
#
#   close-r1b-and-restart-step0.sh [floor_pct] [sleep_s] [gap_s]
# floor stays at 55 to match the pre-registered protocol: it is a safety stop,
# not a finish line, and changing it mid-run changes the experiment.
set -u
PW=${FP3_PW:-<pw>}
FLOOR=${1:-55}; SECS=${2:-600}; GAP=${3:-20}
here=$(dirname "$(readlink -f "$0")")

probe=$(base64 -w0 "$here/r1b-close-probe.sh")
night=$(base64 -w0 "$here/sleep-night.sh")

FP3_SSH_TRIES=${FP3_SSH_TRIES:-150} fp3-ssh "echo $PW | sudo -S sh -c '
  echo $probe | base64 -d > /usr/local/bin/r1b-close-probe.sh
  echo $night | base64 -d > /usr/local/bin/sleep-night.sh
  chmod 755 /usr/local/bin/r1b-close-probe.sh /usr/local/bin/sleep-night.sh
  /usr/local/bin/r1b-close-probe.sh
  echo \"===== ARMING STEP 0 =====\"
  if [ \"\$(systemctl show systemd-logind -p IdleAction --value)\" != ignore ]; then
    echo \"REFUSED: IdleAction is not back to ignore - step 0 NOT armed\"
    exit 0
  fi
  systemctl reset-failed step0sleep 2>/dev/null
  systemd-run --unit=step0sleep --collect /usr/local/bin/sleep-night.sh $FLOOR $SECS $GAP
  sleep 3
  echo \"STEP0-ARMED unit=\$(systemctl is-active step0sleep) floor=$FLOOR% sleep=${SECS}s\"
  ls -t /var/log/fp3/ | head -2 | sed \"s/^/  logdir: /\"
' 2>/dev/null"
