#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# votes-pr-v2 — read the RPM Client Votes mask right after a real suspend window.
#
# v1 printed EMPTY xo: rows for a whole run. The cause was not a missing module
# but plain permissions: /sys/kernel/debug/qcom_rpm_master_stats is root-only and
# the sampler ran as the user. A blank row read as "nothing to see". This version
# refuses to start unless it can read both the vote file and the master stats,
# and it carries two sanity rows that must move: the suspend success counter and
# the APSS XO shutdown count.
set -u
TAG="${1:-run}"; N="${2:-4}"; SLEEP="${3:-30}"
V=/sys/kernel/debug/qcom_stats
MS=/sys/kernel/debug/qcom_rpm_master_stats
[ "$(id -u)" -eq 0 ] || { echo "ABORT: must run as root"; exit 1; }
modprobe rpm_master_stats 2>/dev/null

votes() { cat "$V/vlow" 2>/dev/null | awk '/Client Votes/{print $NF}'; }
cnt()   { awk '/Count/{print $NF}' "$V/$1" 2>/dev/null; }
xo()    { for m in APSS LPASS MPSS PRONTO TZ; do
            v=$(awk '/Shutdown count/{print $NF}' "$MS/$m" 2>/dev/null)
            printf '%s=%s ' "$m" "${v:-ERR}"; done; echo; }
succ()  { cat /sys/power/suspend_stats/success 2>/dev/null; }

# --- instrument gates: show each one able to fail before believing any row ---
[ -n "$(votes)" ]  || { echo "ABORT: no Client Votes line in $V/vlow"; exit 1; }
case "$(xo)" in *ERR*) echo "ABORT: master stats unreadable: $(xo)"; exit 1;; esac
[ -n "$(succ)" ]   || { echo "ABORT: no suspend success counter"; exit 1; }
grep -qw 'clk_smd_rpm.xo_sleep_off=1' /proc/cmdline || \
  { echo "ABORT: not the xo label; cmdline=$(cat /proc/cmdline)"; exit 1; }

echo "== votes-pr-v2 $TAG  N=$N sleep=${SLEEP}s  uptime=$(cut -d. -f1 /proc/uptime)s"
echo "gates: votes=ok masterstats=ok suspend_stats=ok xo=ok"
S0=$(succ); echo "suspend success at start: $S0"
echo "xo at start: $(xo)"

echo "-- CONTROL (awake, no suspend)"
i=0; while [ $i -lt 10 ]; do
  echo "CTRL j=$i votes=$(votes) vlow=$(cnt vlow) vmin=$(cnt vmin)"
  i=$((i+1)); sleep 1
done
echo "xo after control: $(xo)"

w=1
while [ $w -le "$N" ]; do
  echo "-- WINDOW $w: suspending ${SLEEP}s"
  echo "w$w-pre  xo: $(xo)"
  echo +$SLEEP > /sys/class/rtc/rtc0/wakealarm
  systemctl suspend
  sleep 3
  # first sample as early as we can get it after resume
  j=0; while [ $j -lt 8 ]; do
    echo "POST$w j=$j votes=$(votes) vlow=$(cnt vlow) vmin=$(cnt vmin)"
    j=$((j+1)); sleep 1
  done
  echo "w$w-post xo: $(xo)"
  w=$((w+1))
done

S1=$(succ)
echo "-- SANITY"
echo "suspend success $S0 -> $S1 (delta $((S1-S0)), expected $N)"
echo "xo at end: $(xo)"
echo "== DONE"
