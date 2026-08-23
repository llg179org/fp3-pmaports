#!/bin/sh
# mpss-leg.sh — two things at once.
#
# 1. A prediction of the teardown diagnosis: the modem edge oopsed when it was
#    stopped *armed*.  Disarm it first and the same stop should be clean, on
#    the same unfixed kernel, because a disarmed edge owns no wakeup device.
# 2. The MPSS subtraction leg the oops cost us: with the modem actually down,
#    which bit of the Client Votes mask moves?
#
# ☠️ Stopping the modem is undone by writing "start" back to the same node
#    (as root) and restarting ModemManager -- a reboot is not needed.

OUT=/run/mpss-leg.txt
S=/sys/kernel/debug/qcom_stats
M=/sys/kernel/debug/qcom_rpm_master_stats
EDGE=/sys/devices/platform/soc@0/4080000.remoteproc/remoteproc/remoteproc0/remoteproc0:smd-edge/power/wakeup

modprobe qcom_stats 2>/dev/null
modprobe rpm_master_stats 2>/dev/null

log() { echo "$@" >> $OUT; }

sample() {
    _leg=$1; _n=$2; _j=0
    while [ $_j -lt $_n ]; do
        _x=""
        for _m in APSS LPASS MPSS PRONTO TZ; do
            _x="$_x $_m=$(sed -n 's/.*XO shutdown count: //p' $M/$_m)"
        done
        log "$_leg t=$_j votes=$(sed -n 's/^Client Votes: //p' $S/vlow) count=$(sed -n 's/^Count: //p' $S/vlow) xo:$_x"
        _j=$((_j + 1)); sleep 1
    done
}

: > $OUT
log "== mpss-leg $(date) uptime=$(cut -d' ' -f1 /proc/uptime)"
log "== kernel: $(uname -v)"
log "== modem edge wakeup at start: $(cat $EDGE)"

log "--- M0: baseline, edge still armed"
sample M0 10

log "--- disarming the modem edge"
echo disabled > $EDGE 2>>$OUT
log "== modem edge wakeup now: $(cat $EDGE)"
log "== wakeup child dir present: $(ls -d /sys/devices/platform/soc@0/4080000.remoteproc/remoteproc/remoteproc0/remoteproc0:smd-edge/wakeup 2>/dev/null || echo NONE)"

log "--- M1: disarmed, modem still running"
sample M1 10

log "--- stopping remoteproc0 (modem) with the edge DISARMED"
dmesg -C 2>/dev/null
echo stop > /sys/class/remoteproc/remoteproc0/state 2>>$OUT
log "== write returned $?; rproc0 state: $(cat /sys/class/remoteproc/remoteproc0/state)"
log "== oops in dmesg since the write: $(dmesg | grep -c 'Unable to handle kernel')"
sleep 3

log "--- M2: modem stopped"
sample M2 20

log "== dmesg tail"
dmesg | tail -15 >> $OUT
log "== done $(date) — restore with: echo start > /sys/class/remoteproc/remoteproc0/state; systemctl restart ModemManager"
