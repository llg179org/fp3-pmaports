#!/bin/sh
# #142 gate 3: does something accumulate per suspend, which a reboot clears?
#
# Evidence so far, two observations one way and one the other:
#   armB-clean-boot-trial2   1 suspend    0 stalls
#   today 16:54 boot         0 suspends   0 stalls in 59 probes at 15 s idle
#   armB-first-touch...    187 suspends   1 stall, on the first touch after a resume
#
# So: put this boot through many suspend/resume cycles, then run EXACTLY the
# 15 s probe that just returned 0/59 on the same boot. Same kernel, same boot,
# same script - the only thing that changed is the suspend count.
set -u
CYC=${CYC:-50}
echo "=== gate-3 accumulation test, $(date '+%F %T')"
echo "before: uptime $(cut -d. -f1 /proc/uptime) s, suspend success $(cat /sys/power/suspend_stats/success)"
i=1
while [ "$i" -le "$CYC" ]; do
    rtcwake -m mem -s 5 >/dev/null 2>&1
    [ $((i % 10)) -eq 0 ] && echo "  ...$i cycles, suspend success now $(cat /sys/power/suspend_stats/success)"
    sleep 2
    i=$((i+1))
done
echo "after:  uptime $(cut -d. -f1 /proc/uptime) s, suspend success $(cat /sys/power/suspend_stats/success)"
echo
echo "=== now the identical 15 s probe that gave 0/59 on this same boot ==="
N=60 IDLE=15 sh /home/fp3/142-idle15.sh
