#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# IS THE MODEM SITTING IN RRC_CONNECTED WHEN IT SHOULD BE IDLE?
#
# The expensive state's microstructure is textbook connected-mode DRX: ~200 ms
# on-durations, a few per second, not one quiet second in ten minutes. The cheap
# state is 3.14/s at 16 ms - numerically the oracle. That is a discrete radio
# state change, not an analog slowdown.
#
# A camped RRC_IDLE UE transmits essentially never: a random-access burst for a
# tracking-area update or a paging response, nothing that would land in a tenth
# of snapshots. So `--nas-get-tx-rx-info=lte` sampled over a couple of minutes
# separates the two, with no diag and no kernel work.
#
# ☠️ ONE SAMPLE SET IS NOT AN EXPERIMENT. The first run measured 8/60 in the
# expensive state and had nothing to compare it against. This script supplies
# the pair: sample, force the radio down and back up so the UE must re-attach,
# let it settle, and sample again. If the second set is near zero the modem does
# release to idle and something re-establishes the connection later; if it is
# still ~13 % then whatever holds it is back within a minute.
#
# ☠️ EVERY QMI POLL WAKES THE MODEM, so the duty printed here is NOT comparable
# with a clean 600 s leg. It is reported to show the two sets ran in the same
# regime, not as a duty measurement.
#
# ☠️ It cycles the radio: `--set-power-state-low` then `--set-power-state-on`.
# That has been done on this device before without harm and it is not a reboot,
# but it does drop any call. Do not run it while the phone is in use.
#
#   rrc-probe.sh [samples] [interval_s]      default 60 2
set -u
N=${1:-60}; I=${2:-2}
O=${RRC_PROBE_LOG:-/var/log/fp3/rrc-probe.log}
D=qrtr://0
mkdir -p /var/log/fp3
say(){ echo "$*" | tee -a "$O"; }
: > "$O"
say "# rrc-probe $(date '+%F %T') samples=$N interval=${I}s"

xo(){ awk '/XO total duration:/{printf "%.0f", $4}' /sys/kernel/debug/qcom_rpm_master_stats/MPSS; }

sample(){ # sample LABEL
	yes=0; n=0; x0=$(xo)
	i=0
	while [ $i -lt "$N" ]; do
		r=$(qmicli -d $D --nas-get-tx-rx-info=lte 2>/dev/null |
		    sed -n "s/.*In traffic: *'\([a-z]*\)'.*/\1/p" | head -1)
		n=$((n + 1)); [ "$r" = yes ] && yes=$((yes + 1))
		sleep "$I"; i=$((i + 1))
	done
	x1=$(xo); w=$((N * I))
	say "$(printf 'RESULT %-12s TX-in-traffic %2d/%2d (%4.1f%%)  MPSS %4.1f%% awake over %ds' \
		"$1" "$yes" "$n" "$(awk -v y=$yes -v m=$n 'BEGIN{printf "%.1f", 100*y/m}')" \
		"$(awk -v a="$x1" -v b="$x0" -v w="$w" 'BEGIN{printf "%.1f", 100*(1-(a-b)/19200000/w)}')" "$w")"
	/usr/local/bin/leg-covariates.sh "$1" 2>/dev/null | tee -a "$O" >/dev/null
}

wait_reg(){
	i=0; while [ $i -lt 40 ]; do
		case "$(mmcli -m any 2>/dev/null | sed -n 's/.*  state: *//p' | head -1)" in
			registered|connected) return 0 ;;
		esac
		sleep 5; i=$((i + 1))
	done
	return 1
}

say "-- A: as found"
sample A-as-found

say "-- forcing the radio down and back up so the UE must re-attach"
mmcli -m any --set-power-state-low >/dev/null 2>&1 || say "   ☠️ power-state-low FAILED"
sleep 10
mmcli -m any --set-power-state-on  >/dev/null 2>&1 || say "   ☠️ power-state-on FAILED"
if wait_reg; then say "   re-registered after $(date '+%T')"; else
	say "   ☠️ DID NOT RE-REGISTER within 200 s - leg B is not a measurement"; fi
sleep 30   # let any attach-time signalling finish before sampling

say "-- B: after a fresh attach"
sample B-fresh-attach
say "# done $(date '+%F %T')"
