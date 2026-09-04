#!/bin/sh
# #142 automated A/B, v2 - the driver is UNBOUND for the duration.
#
# ☠️ v1 probed the bus with I2C_SLAVE_FORCE while the touchscreen driver was
# using it. The two collided and wedged the QUP controller: 1824 EIO in a row,
# touch functionally dead until an unbind/rebind. I2C_SLAVE_FORCE exists to
# reach a claimed address, i.e. it deliberately bypasses the protection that
# keeps two users apart. On a shared bus, take the other user off it instead.
#
# The rebind is unconditional (trap), so a crash or a kill still gives the phone
# its touchscreen back.
D=/sys/bus/i2c/drivers/Himax-hx83112b-TS
P=/sys/devices/platform/soc@0/78b7000.i2c/power
OUT=/home/fp3/142-ab.txt
IDLE=45

restore() {
    echo auto > $P/control 2>/dev/null
    echo 2-0048 > $D/bind 2>/dev/null
    echo "== restored $(date '+%H:%M:%S'): driver bound, control=auto" >> $OUT
}
trap restore EXIT INT TERM

: > $OUT
echo "== A/B v2 start $(date '+%F %H:%M:%S')  idle=${IDLE}s, driver UNBOUND, interleaved arms" >> $OUT
echo 2-0048 > $D/unbind 2>/dev/null; sleep 2
echo "   driver unbound: $(ls /sys/bus/i2c/devices/2-0048/driver 2>&1 | tail -1)" >> $OUT

i=1
while [ $i -le 3 ]; do
    for arm in on auto; do
        echo $arm > $P/control; sleep 1
        sleep $IDLE
        st=$(cat $P/runtime_status)
        r=$(python3 /home/fp3/142-i2cprobe.py 2 0x50 0 1 2>&1 | sed -n 's/^  duration  //p')
        echo "round $i  control=$arm  status_before_probe=$st  $r" >> $OUT
    done
    i=$((i+1))
done
