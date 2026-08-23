#!/bin/sh
# ring-source.sh — is the modem edge's ~one-per-2-s signal ring produced by an
# AP-side userspace client, or by the modem on its own?
#
# The channel census already showed the pokes carry no qrtr payload, which was
# read as "not the QMI services".  But a client holding an open channel can
# still earn flow-control interrupts without sending messages, so the question
# is worth asking directly: take the userspace qrtr consumers away one at a
# time and count the modem edge's interrupts.
#
# Awake measurement, no suspend, nothing persistent: every service is started
# again at the end.

OUT=/run/ring-source.txt
W=${1:-60}

log() { echo "$@" >> $OUT; }

# The modem edge's IRQ line, by the remoteproc it belongs to.
edge_irq_count() {
    awk '/smd-edge/ { gsub(/:/, "", $1); print $1, $2 }' /proc/interrupts
}

leg() {   # leg <name>
    _n=$1
    _a=$(edge_irq_count | tr '\n' ';')
    _qa=$(grep -c . /proc/net/qrtr 2>/dev/null || echo na)
    sleep $W
    _b=$(edge_irq_count | tr '\n' ';')
    log "$_n window=${W}s"
    log "  before: $_a"
    log "  after:  $_b"
    log "  delta:  $(echo "$_a|$_b" | awk -F'|' '{
        n=split($1,A,";"); m=split($2,B,";");
        for (i=1;i<=n;i++) { split(A[i],x," "); split(B[i],y," ");
            if (x[1] != "") printf "irq%s=+%d ", x[1], y[2]-x[2] }
        printf "\n" }')"
}

: > $OUT
log "== ring-source $(date) uptime=$(cut -d' ' -f1 /proc/uptime) window=${W}s"
log "== irq lines:"
grep smd-edge /proc/interrupts >> $OUT
log "== services: $(systemctl is-active ModemManager rmtfs 2>/dev/null | tr '\n' ' ')"

log "--- A: baseline (everything running)"
leg A

log "--- B: ModemManager stopped"
systemctl stop ModemManager >> $OUT 2>&1
sleep 3
leg B

log "--- C: rmtfs stopped as well"
systemctl stop rmtfs >> $OUT 2>&1
sleep 3
log "  rmtfs now: $(systemctl is-active rmtfs 2>/dev/null)"
leg C

log "--- D: both started again (recovery control)"
systemctl start rmtfs >> $OUT 2>&1
systemctl start ModemManager >> $OUT 2>&1
sleep 10
leg D

log "== services at the end: $(systemctl is-active ModemManager rmtfs 2>/dev/null | tr '\n' ' ')"
log "== done $(date)"
