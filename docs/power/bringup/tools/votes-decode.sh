#!/bin/sh
# votes-decode.sh — empirical decode of the RPM vlow "Client Votes" mask.
#
# Hypothesis under test: the four bytes of the mask are four voting clients
# (plausibly APSS/MPSS/PRONTO/LPASS). If so, changing exactly one master's
# state must move exactly one byte (or byte pair).
#
# Awake sampling only: no suspend, so the modem wake edge is irrelevant here.
# Every leg is reversible; the ADSP is restarted at the end.

OUT=/run/votes-decode.txt
S=/sys/kernel/debug/qcom_stats
M=/sys/kernel/debug/qcom_rpm_master_stats
N=${1:-20}

log() { echo "$@" >> $OUT; }

sample() {   # sample <leg> <n>
    _leg=$1; _n=$2
    _j=0
    while [ $_j -lt $_n ]; do
        _vlow=$(sed -n 's/^Client Votes: //p' $S/vlow)
        _vmin=$(sed -n 's/^Client Votes: //p' $S/vmin)
        _cnt=$(sed -n 's/^Count: //p' $S/vlow)
        _xo=""
        for _m in LPASS MPSS PRONTO TZ APSS; do
            [ -r $M/$_m ] || continue
            _v=$(sed -n 's/.*XO shutdown count: //p' $M/$_m)
            _xo="$_xo $_m=$_v"
        done
        log "$_leg t=$_j vlow_votes=$_vlow vmin_votes=$_vmin vlow_count=$_cnt xo:$_xo"
        _j=$((_j + 1))
        sleep 1
    done
}

: > $OUT
log "== votes-decode $(date) uptime=$(cut -d' ' -f1 /proc/uptime) N=$N"
log "== masters present: $(ls $M)"

log "--- LEG 0: baseline (wlan0 up, adsp running, modem up)"
sample L0 $N

log "--- LEG 1: wlan0 down"
ip link set wlan0 down
sleep 3
sample L1 $N

log "--- LEG 2: wlan0 up again (recovery control)"
ip link set wlan0 up
sleep 5
sample L2 $N

log "--- LEG 3: ADSP stopped"
echo stop > /sys/class/remoteproc/remoteproc2/state 2>>$OUT
sleep 3
log "adsp state now: $(cat /sys/class/remoteproc/remoteproc2/state)"
sample L3 $N

log "--- LEG 4: ADSP started again"
echo start > /sys/class/remoteproc/remoteproc2/state 2>>$OUT
sleep 5
log "adsp state now: $(cat /sys/class/remoteproc/remoteproc2/state)"
sample L4 $N

log "== done $(date)"
