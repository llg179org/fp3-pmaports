#!/bin/sh
# votes-decode2.sh — continue the Client Votes decode by subtraction.
#
# Entry state for this run: the ADSP has already been SSR'd this boot, so
# bit 4 is set and stays set. Now take the other co-processors away one at a
# time and watch which bits leave with them. Whatever bit is still set when
# every co-processor has released is the standing vote that keeps the RPM out
# of vlow.
#
# ☠️ This run stops the modem. Recovery is a reboot; nothing here is persistent.

OUT=/run/votes-decode2.txt
S=/sys/kernel/debug/qcom_stats
M=/sys/kernel/debug/qcom_rpm_master_stats
N=${1:-15}

log() { echo "$@" >> $OUT; }

sample() {
    _leg=$1; _n=$2; _j=0
    while [ $_j -lt $_n ]; do
        _vlow=$(sed -n 's/^Client Votes: //p' $S/vlow)
        _cnt=$(sed -n 's/^Count: //p' $S/vlow)
        _xo=""
        for _m in APSS LPASS MPSS PRONTO TZ; do
            [ -r $M/$_m ] || continue
            _xo="$_xo $_m=$(sed -n 's/.*XO shutdown count: //p' $M/$_m)"
        done
        log "$_leg t=$_j vlow_votes=$_vlow vlow_count=$_cnt xo:$_xo"
        _j=$((_j + 1)); sleep 1
    done
}

: > $OUT
log "== votes-decode2 $(date) uptime=$(cut -d' ' -f1 /proc/uptime)"
log "== rproc states: 0=$(cat /sys/class/remoteproc/remoteproc0/state) 1=$(cat /sys/class/remoteproc/remoteproc1/state) 2=$(cat /sys/class/remoteproc/remoteproc2/state)"

log "--- LEG 5: control (ADSP already SSR'd, wifi up, modem up)"
sample L5 $N

log "--- LEG 6: PRONTO down (wlan0 down, wcn36xx unloaded, remoteproc1 stopped)"
ip link set wlan0 down
rmmod wcn36xx 2>>$OUT
sleep 2
echo stop > /sys/class/remoteproc/remoteproc1/state 2>>$OUT
sleep 3
log "rproc1 state now: $(cat /sys/class/remoteproc/remoteproc1/state)"
sample L6 $N

log "--- LEG 7: MPSS down too (remoteproc0 stopped)"
systemctl stop ModemManager 2>>$OUT
sleep 2
echo stop > /sys/class/remoteproc/remoteproc0/state 2>>$OUT
sleep 5
log "rproc0 state now: $(cat /sys/class/remoteproc/remoteproc0/state)"
sample L7 $N

log "--- LEG 8: residue, longer look (everything released that can be)"
sample L8 30

log "== master stats at the end"
for m in APSS LPASS MPSS PRONTO TZ; do
    [ -r $M/$m ] && { echo "== $m" >> $OUT; cat $M/$m >> $OUT; }
done
log "== vlow node"
cat $S/vlow >> $OUT
log "== vmin node"
cat $S/vmin >> $OUT
log "== done $(date) — REBOOT REQUIRED to restore modem/wifi"
