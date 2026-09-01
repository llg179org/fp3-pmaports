#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# DOES THE EXPENSIVE MODEM STATE DECAY ON ITS OWN, AND ON WHAT SCHEDULE?
#
#   modem-decay-watch.sh [hours] [sample_s] [cov_s]      defaults 11 10 600
#
# The leading explanation for the two modem regimes this port keeps landing in
# - a cheap ~5 % XO duty and an expensive ~35 % one - is that something inside
# the modem is RETRYING a procedure with exponential backoff. That hypothesis
# makes a prediction no integrated window can test: left completely undisturbed,
# the duty must fall in STEPS whose spacing GROWS, because each retry is farther
# from the last. A flat 35 % for eight hours kills it.
#
# So this run does exactly one thing: it watches, for a whole night, and touches
# nothing. It is designed by the reviewer, not by the author of the hypothesis
# it tests, and the readings below were written down BEFORE it ran.
#
# PRE-REGISTERED READINGS (do not add a fifth one in the morning):
#   duty decays >=10 % with no cell change     -> backoff SURVIVES; the step
#                                                 timestamps are the prize, and
#                                                 geometric spacing is the
#                                                 retry schedule itself
#   flat +-3 pp for >=8 h on the same cell     -> backoff is DEAD
#   the change coincides with a cell/band move -> VOID, the network moved
#   sawtooth                                   -> a recurring trigger; check
#                                                 whether the resets line up
#                                                 with the 10-minute covariate
#                                                 reads. If they do, THE PROBE
#                                                 IS THE TRIGGER: re-run with
#                                                 covariates at start and end
#                                                 only.
#
# ☠️ NO PARSING HAPPENS ON THE DEVICE. The four master files are dumped
# VERBATIM. Four separate awk/grep readers of this same counter have now shipped
# with a bug of the same family - the tick, the INT_MAX clamp, the missing
# strtonum, and the `@` versus `:` in the static fields - and every one of them
# printed a confident, wrong number instead of failing. Raw bytes to disk cannot
# have that class of bug; the parse happens later, on the host, where it can be
# fixed without re-running the night.
#
# ☠️ IT WRITES TO DISK, NOT TO tmpfs. A night's worth of samples in /tmp is lost
# to a reboot, and a reboot is exactly what a bad night ends with.
#
# ☠️ THIS SAMPLER KEEPS THE AP AWAKE (a wake every sample_s). That is deliberate
# and it is a LIMIT: this window can say nothing about AP suspend residency. It
# is asking about MPSS, which - measured - does not care whether the AP sleeps.
#
# ☠️ NO RADIO WRITES. Not a band lock, not a mode preference, not a power-state
# change. The whole point is an undisturbed radio; the covariate reads are the
# only QMI this run issues, and the sawtooth reading above exists because even
# those may not be free.
set -u

H=${1:-11}; S=${2:-10}; C=${3:-600}
M=/sys/kernel/debug/qcom_rpm_master_stats
[ -r "$M/MPSS" ] || { echo "no rpm master stats (need root)" >&2; exit 1; }

OUT=/var/log/fp3/decay-$(date +%s)
mkdir -p "$OUT" || exit 1
LOG=$OUT/samples.txt
COV=$OUT/covariates.txt
META=$OUT/meta.txt

secs=$(awk -v h="$H" 'BEGIN{printf "%d", h*3600}')   # H may be fractional, for a short self-test
now() { cut -d' ' -f1 /proc/uptime; }

{
  echo "# modem-decay-watch $(date -Iseconds) hours=$H sample_s=$S cov_s=$C"
  echo "# kernel: $(uname -a)"
  echo "# boot_id: $(cat /proc/sys/kernel/random/boot_id)"
  echo "# uptime_at_start: $(now)"
  echo "# journal cursor at start:"
  journalctl -n1 -o export 2>/dev/null | grep '^__CURSOR=' || echo "__CURSOR=unavailable"
  echo "# rmnet counters at start:"
  for i in /sys/class/net/rmnet_ipa0 /sys/class/net/rmnet_data0; do
    [ -d "$i" ] && echo "  $i oper=$(cat $i/operstate 2>/dev/null) rx=$(cat $i/statistics/rx_bytes 2>/dev/null) tx=$(cat $i/statistics/tx_bytes 2>/dev/null)"
  done
  echo "# disk free at start: $(df -h / | tail -1)"
  echo "# ModemManager: $(systemctl is-active ModemManager 2>/dev/null)"
  # ☠️ THE TRANSPORT IS A COVARIATE, NOT TRIVIA. A Wi-Fi ssh session IS PRONTO
  # wake length, and an associated but unused wlan0 is still a Wi-Fi core
  # serving beacons. A four-master window that does not record these cannot
  # read its own PRONTO column - which is exactly how the 2026-09-01 window
  # lost that column.
  echo "# links:"
  for n in /sys/class/net/wlan0 /sys/class/net/usb0 /sys/class/net/rmnet_ipa0; do
    [ -d "$n" ] && echo "  $(basename $n): oper=$(cat $n/operstate 2>/dev/null) carrier=$(cat $n/carrier 2>/dev/null)"
  done
  echo "# addresses:"; ip -br addr 2>/dev/null | sed 's/^/  /'
  echo "# rfkill:"; rfkill list 2>/dev/null | sed 's/^/  /'
} > "$META"

cov() {
  {
    echo "== cov t=$(now) wall=$(date +%s)"
    timeout 25 qmicli -d qrtr://0 --nas-get-serving-system 2>&1 | sed 's/^/   /'
    timeout 25 qmicli -d qrtr://0 --nas-get-rf-band-info 2>&1 | sed 's/^/   /'
    timeout 25 qmicli -d qrtr://0 --nas-get-signal-info 2>&1 | sed 's/^/   /'
  } >> "$COV" 2>&1
}

cov
start=$(now)
next_cov=$C
i=0
while :; do
  t=$(now)
  # integer seconds since start, without floating point in the shell
  el=$(awk -v a="$t" -v b="$start" 'BEGIN{printf "%d", a-b}')
  [ "$el" -ge "$secs" ] && break

  {
    echo "== t=$t wall=$(date +%s) i=$i"
    for m in APSS MPSS LPASS PRONTO; do
      echo "-- $m"
      cat "$M/$m"
    done
  } >> "$LOG" 2>&1

  if [ "$el" -ge "$next_cov" ]; then
    cov
    next_cov=$(( next_cov + C ))
  fi
  i=$(( i + 1 ))
  sleep "$S"
done

cov
{
  echo "# uptime_at_end: $(now)  samples=$i"
  echo "# rmnet counters at end:"
  for n in /sys/class/net/rmnet_ipa0 /sys/class/net/rmnet_data0; do
    [ -d "$n" ] && echo "  $n oper=$(cat $n/operstate 2>/dev/null) rx=$(cat $n/statistics/rx_bytes 2>/dev/null) tx=$(cat $n/statistics/tx_bytes 2>/dev/null)"
  done
  echo "# disk free at end: $(df -h / | tail -1)"
  echo "# journal cursor at end:"
  journalctl -n1 -o export 2>/dev/null | grep '^__CURSOR=' || echo "__CURSOR=unavailable"
  echo "# done $(date -Iseconds)"
} >> "$META"
echo "$OUT"
