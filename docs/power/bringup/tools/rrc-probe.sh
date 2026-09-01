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
# ☠️ AND LOCK THE BAND, BECAUSE THE CYCLE MOVES IT. On the first run the radio
# came back on eutran-3 instead of eutran-1, and eutran-3's own ladder value
# (31.8 %) accounts for leg B's duty on its own. That was the third time in one
# day that a difference turned out to be the band. A and B are only comparable
# if the band is pinned across both, so this pins it and restores `any` at the
# end - through a trap, so an interrupted run does not leave the phone locked to
# one band.
#
#   rrc-probe.sh [samples] [interval_s] [band]   default 60 2 <current band>
set -u
N=${1:-60}; I=${2:-2}; BAND=${3:-}
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

# ☠️ ASK THE NETWORK, NOT THE DAEMON. The first version polled ModemManager's
# own state and declared "DID NOT RE-REGISTER within 200 s" while the modem was,
# at the NAS layer, registered with CS and PS both attached on LTE. What it had
# actually detected was that MM sat in `disabled` - which is a real problem, but
# a different one, and the wrong verdict masked it. Registration is a property of
# the radio; read it there.
wait_reg(){
	i=0; while [ $i -lt 40 ]; do
		case "$(qmicli -d $D --nas-get-serving-system 2>/dev/null |
		        sed -n "s/.*Registration state: *'\([a-z]*\)'.*/\1/p" | head -1)" in
			registered) return 0 ;;
		esac
		sleep 5; i=$((i + 1))
	done
	return 1
}

BAND=${BAND:-$(qmicli -d $D --nas-get-rf-band-info 2>/dev/null |
	sed -n "s/.*Active Band Class: *'\([a-z0-9-]*\)'.*/\1/p" | head -1)}
restore_band(){
	qmicli -d $D --nas-set-system-selection-preference=any >/dev/null 2>&1
	b=$(qmicli -d $D --nas-get-rf-band-info 2>/dev/null |
	    sed -n "s/.*Active Band Class: *'\([a-z0-9-]*\)'.*/\1/p" | head -1)
	say "# band preference restored to 'any' (now on ${b:-?})"
}
if [ -n "$BAND" ]; then
	# ☠️ trap FIRST, then lock: a lock with no restore path is how a phone ends
	# up pinned to one band after an interrupted measurement.
	trap 'restore_band' EXIT INT TERM
	qmicli -d $D --nas-set-system-selection-preference="$BAND" >/dev/null 2>&1 \
		&& say "# band pinned to $BAND for both arms" \
		|| say "☠️ could not pin the band - A and B may not be comparable"
	sleep 15
else
	say "☠️ could not read the current band - A and B may not be comparable"
fi

say "-- A: as found"
sample A-as-found

say "-- forcing the radio down and back up so the UE must re-attach"
# ☠️ THE CYCLE IS FOUR STEPS, NOT TWO, AND THE MISSING TWO LEAVE THE PHONE
# UNABLE TO TAKE A CALL. --set-power-state-low requires the modem disabled and
# leaves it that way; without the closing --enable, ModemManager stays in
# `disabled` and will not deliver an incoming call, even though the radio is
# registered and attached. This script did exactly that on its first run. The
# sequence is disable -> power-state-low -> power-state-on -> enable, which is
# what the repo's own modem-core-cycle item already said.
mmcli -m any --disable            >/dev/null 2>&1 || say "   ☠️ disable FAILED"
mmcli -m any --set-power-state-low >/dev/null 2>&1 || say "   ☠️ power-state-low FAILED"
sleep 10
mmcli -m any --set-power-state-on  >/dev/null 2>&1 || say "   ☠️ power-state-on FAILED"
mmcli -m any --enable              >/dev/null 2>&1 || say "   ☠️ enable FAILED"
if wait_reg; then say "   re-registered after $(date '+%T')"; else
	say "   ☠️ DID NOT RE-REGISTER within 200 s - leg B is not a measurement"; fi
sleep 30   # let any attach-time signalling finish before sampling

say "-- B: after a fresh attach"
sample B-fresh-attach

# ☠️ LEAVE THE PHONE ABLE TO RING. Whatever happened above, the last thing this
# does is check the two states a user cares about and say so plainly.
st=$(mmcli -m any 2>/dev/null | sed -n 's/.*  state: *//p' | head -1)
reg=$(qmicli -d $D --nas-get-serving-system 2>/dev/null | sed -n "s/.*Registration state: *'\([a-z]*\)'.*/\1/p" | head -1)
if [ "$st" = registered ] || [ "$st" = connected ]; then
	say "# final: ModemManager=$st, NAS=$reg - the phone can take a call"
else
	mmcli -m any --enable >/dev/null 2>&1
	st2=$(mmcli -m any 2>/dev/null | sed -n 's/.*  state: *//p' | head -1)
	say "☠️ final: ModemManager was '$st' (NAS=$reg) - re-enabled, now '$st2'."
	say "   A modem left disabled does NOT deliver incoming calls."
fi
say "# done $(date '+%F %T')"
