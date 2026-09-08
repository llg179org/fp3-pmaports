#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# Log every call with its wall-clock time and the RADIO TECHNOLOGY it used.
#
#   fp3-callwatch.sh [logfile]        (on the device, as the session user)
#
# WHY THIS EXISTS AND THE OTHERS DO NOT ANSWER IT
# ===============================================
# terse-call.sh, call-wake-test.sh and lowpower-call2.sh all ask whether a call
# SURVIVES a power state. None of them is a continuous record of ordinary use.
# One HU are measuring this number's radio traffic 2026-09-08 to 09-10 and asked
# for the times at which trouble occurred, so they can line their trace up
# against ours. A minute of resolution is enough for them; what they cannot get
# from their own side is what the HANDSET thought was happening.
#
# ☠️ THE MEASUREMENT THAT MATTERS IS THE ACCESS TECHNOLOGY ACROSS THE CALL.
# This phone registers on LTE. If a call keeps `lte` throughout it went over
# IMS/VoLTE; if the tech drops to umts or gsm when the call starts and returns
# afterwards, that is CSFB - the fallback this whole investigation is about.
# Sampling it only once, at the start, cannot tell those apart, so it is sampled
# throughout the call and the WHOLE SET is logged, not just the first value.
#
# ☠️ EVENT-DRIVEN AT REST, ON PURPOSE. `gdbus monitor` blocks on the bus and
# costs nothing until ModemManager says something. A polling loop would keep the
# phone awake, which on this device is both a power cost and a confound - the
# port has already lost a night's measurement to its own poller.
#
# ☠️ THE NUMBER IS WRITTEN TO THE DEVICE-LOCAL LOG ONLY. It is what the operator
# needs for their own report; it is NOT what goes into a capture. Scrub before
# committing anything derived from this file - see fp3-porting-debug, "A capture
# is a paste from the device".
LOG="${1:-/home/fp3/callwatch.log}"
M=$(mmcli -L 2>/dev/null | grep -oE '/Modem/[0-9]+' | grep -oE '[0-9]+$' | head -1)
[ -n "$M" ] || { echo "no modem found" >&2; exit 1; }

stamp() { date '+%Y-%m-%d %H:%M:%S'; }
tech()  { mmcli -m "$M" 2>/dev/null | sed -n 's/.*access tech: *//p' | head -1; }
sig()   { mmcli -m "$M" 2>/dev/null | sed -n 's/.*signal quality: *//p' | head -1 | cut -d' ' -f1; }

say() { printf '%s  %s\n' "$(stamp)" "$*" >> "$LOG"; }

say "== callwatch start, modem $M, tech=$(tech) signal=$(sig)"

# ☠️ Sample the tech for the LIFE of the call, in the background, so a CSFB
# drop that happens a second after the call appears is not missed. Started per
# call and stopped with it, so nothing samples while the phone is idle.
watch_tech() {
  last=""
  while [ -f /tmp/.callwatch-active ]; do
    t=$(tech)
    [ "$t" != "$last" ] && { say "   tech -> $t  (signal $(sig))"; last="$t"; }
    sleep 1
  done
}

gdbus monitor --system --dest org.freedesktop.ModemManager1 2>/dev/null | while read -r line; do
  case "$line" in
    *"/Call/"*)
      # A call object appeared, changed state, or went away.
      st=$(printf '%s' "$line" | grep -oE "'State': <[a-z0-9]+>|StateChanged \([0-9]+, [0-9]+" | head -1)
      say "CALL  $line"
      if [ ! -f /tmp/.callwatch-active ]; then
        : > /tmp/.callwatch-active
        say "   call active: tech=$(tech) signal=$(sig)"
        watch_tech &
      fi
      case "$line" in
        *CallDeleted*|*"'terminated'"*)
          rm -f /tmp/.callwatch-active
          say "   call ended: tech=$(tech) signal=$(sig)"
          ;;
      esac
      ;;
    *Modem.Signal*)
      # ★ The handset's own view of the radio at that instant - rsrp, rsrq,
      # snr. This is the column One HU can line up against their trace, and
      # the one thing their side cannot see. Kept for the whole window, not
      # only during calls, so a problem has a before and an after.
      say "SIG   $line"
      ;;
    *AccessTechnologies*|*"'State': <"*|*Registration*)
      say "MODEM $line"
      ;;
  esac
done
