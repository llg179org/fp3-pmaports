#!/bin/sh
# vlow-ring.sh — read the vlow Client Votes ring immediately after a suspend
# window.  The four bytes are the same field sampled four times, so a read
# taken as the first thing after resume should carry values from inside the
# window, which an awake read never can.
#
# ☠️ Disarms the modem edge for the duration (the signal ring ends windows
# within seconds otherwise) and re-arms it at the end.

OUT=/run/vlow-ring.txt
S=/sys/kernel/debug/qcom_stats
M=/sys/kernel/debug/qcom_rpm_master_stats
EDGE=/sys/devices/platform/soc@0/4080000.remoteproc/remoteproc/remoteproc0/remoteproc0:smd-edge/power/wakeup
SECS=${1:-60}
ROUNDS=${2:-3}

modprobe qcom_stats 2>/dev/null
modprobe rpm_master_stats 2>/dev/null

: > $OUT
echo "== vlow-ring $(date) uptime=$(cut -d' ' -f1 /proc/uptime) secs=$SECS rounds=$ROUNDS" >> $OUT

WAS=$(cat $EDGE 2>/dev/null)
echo "== modem edge wakeup was: $WAS -> disabling" >> $OUT
echo disabled > $EDGE 2>>$OUT

masters() {
    for m in APSS LPASS MPSS PRONTO TZ; do
        printf '%s=%s ' "$m" "$(sed -n 's/.*XO shutdown count: //p' $M/$m)"
    done
}

r=1
while [ $r -le $ROUNDS ]; do
    echo "--- round $r" >> $OUT
    echo "pre  votes=$(sed -n 's/^Client Votes: //p' $S/vlow) count=$(sed -n 's/^Count: //p' $S/vlow) success=$(cat /sys/power/suspend_stats/success) xo: $(masters)" >> $OUT
    t0=$(cut -d' ' -f1 /proc/uptime)
    rtcwake -m mem -s $SECS >> $OUT 2>&1
    # first thing after resume: the ring
    V=$(sed -n 's/^Client Votes: //p' $S/vlow)
    C=$(sed -n 's/^Count: //p' $S/vlow)
    VM=$(sed -n 's/^Client Votes: //p' $S/vmin)
    t1=$(cut -d' ' -f1 /proc/uptime)
    echo "post votes=$V vmin_votes=$VM count=$C success=$(cat /sys/power/suspend_stats/success) elapsed=$(echo "$t0 $t1" | awk '{printf "%.0f", $2-$1}') xo: $(masters)" >> $OUT
    # and a second read a moment later, to see how fast the ring refills awake
    sleep 1
    echo "post+1s votes=$(sed -n 's/^Client Votes: //p' $S/vlow)" >> $OUT
    r=$((r + 1))
done

echo "== vlow node after:" >> $OUT
cat $S/vlow >> $OUT

if [ "$WAS" = enabled ]; then
    echo enabled > $EDGE 2>>$OUT
    echo "== modem edge re-armed: $(cat $EDGE)" >> $OUT
fi
echo "== done $(date)" >> $OUT
