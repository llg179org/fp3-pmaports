#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# ONE trip after the R1b window closes, doing three things that all need the
# phone awake, so the phone is woken once rather than three times:
#
#   1. fetch the R1b log (the on-phone witness; the host USB log is the other)
#   2. answer who set sleep-inactive-battery-type='nothing' - a dconf read and a
#      schema grep, which distinguish a user-level override from a package one
#   3. restart the step-0 sleep run for the night
#
# ☠️ Order matters. R1b's own EXIT trap removes its logind drop-in, but this
# script must not restart step 0 while an IdleAction=suspend policy could still
# be live - so it verifies the restore FIRST and refuses to arm step 0 if the
# policy is still in place. A residency measurement running underneath an
# idle-suspend policy is measuring two things at once.
#
# ☠️ step 0 cuts the PMIC charge input. Its own trap restores it, but the caller
# must never reboot while it is set - see the standing gates.
set -u
PW=${FP3_PW:-<pw>}
# floor stays at 55 to match the pre-registered protocol - it is a safety
# stop, not a finish line, and changing it mid-run changes the experiment.
FLOOR=${1:-55}; SECS=${2:-600}; GAP=${3:-20}
here=$(dirname "$(readlink -f "$0")")
# deploy rather than assume the tool is already at /usr/local/bin
b64=$(base64 -w0 "$here/sleep-night.sh")

FP3_SSH_TRIES=${FP3_SSH_TRIES:-120} fp3-ssh "echo $PW | sudo -S sh -c '
  echo \"===== R1B LOG =====\"
  cat /var/log/fp3/idle-suspend.log 2>/dev/null || echo \"(no log)\"
  echo \"===== r1b unit: \$(systemctl is-active r1b 2>/dev/null) =====\"

  echo \"===== WHO SET THE POLICY =====\"
  echo \"dconf(user fp3): \$(su fp3 -c \"dconf read /org/gnome/settings-daemon/plugins/power/sleep-inactive-battery-type\" 2>/dev/null || echo \"<unreadable>\")\"
  echo \"schema overrides naming the key:\"
  grep -rln sleep-inactive /usr/share/glib-2.0/schemas/ 2>/dev/null | sed \"s/^/  /\" || echo \"  (none)\"
  grep -rn sleep-inactive /usr/share/glib-2.0/schemas/*.override 2>/dev/null | sed \"s/^/  /\"

  echo \"===== RESTORE CHECK (before arming step 0) =====\"
  echo \"logind IdleAction now: \$(systemctl show systemd-logind -p IdleAction --value)\"
  ls /run/systemd/logind.conf.d/ 2>/dev/null | sed \"s/^/  leftover drop-in: /\"
  echo \"charger: \$(cat /sys/class/power_supply/pmi632-charger/status)\"

  if [ \"\$(systemctl show systemd-logind -p IdleAction --value)\" != \"ignore\" ]; then
    echo \"REFUSED: IdleAction is not back to ignore - not arming step 0\"
    exit 0
  fi

  echo \"===== ARMING STEP 0 =====\"
  echo $b64 | base64 -d > /usr/local/bin/sleep-night.sh
  chmod 755 /usr/local/bin/sleep-night.sh
  systemctl reset-failed step0sleep 2>/dev/null
  systemd-run --unit=step0sleep --collect /usr/local/bin/sleep-night.sh $FLOOR $SECS $GAP
  sleep 2
  echo \"STEP0-ARMED unit=\$(systemctl is-active step0sleep) floor=${FLOOR}% sleep=${SECS}s\"
  ls -t /var/log/fp3/ | head -3 | sed \"s/^/  logdir: /\"
' 2>/dev/null"
