#!/bin/sh
# v3: tcpdump runs INSIDE the Android container.
# ☠️ v1 and v2 reported "0 packets" from a tool that never started: the Android
# binary cannot be linked from the UT side ("library libc.so ... not accessible
# for the namespace (default)"), and its stderr did not reach the log. Two
# readings of zero were a dead instrument, not a measurement. Validated first on
# a known positive: 5 real packets on wlan0 inside the container.
set -u
A() { lxc-attach -n android -- "$@"; }
P=/data/local/tmp/ims.pcap
prop() { dbus-send --system --print-reply --dest=org.ofono /ril_0 "org.ofono.$1.GetProperties" 2>/dev/null | grep -A1 "\"$2\"" | tail -1 | grep -o 'true\|false'; }

echo "elotte: Online=$(prop Modem Online)  IMS=$(prop IpMultimediaSystem Registered)"
echo "=== modem offline ==="
dbus-send --system --print-reply --dest=org.ofono /ril_0 org.ofono.Modem.SetProperty string:Online variant:boolean:false >/dev/null 2>&1
sleep 10
echo "  Online=$(prop Modem Online)  IMS=$(prop IpMultimediaSystem Registered)"

A rm -f $P
echo "=== tcpdump a konteneren belul, minden interfesz, szuro nelkul ==="
A /system/bin/tcpdump -i any -s 0 -w $P >/tmp/td3.log 2>&1 &
sleep 5
A /system/bin/tcpdump -r $P 2>/dev/null | wc -l | sed 's/^/  indulaskor csomag: /'

echo "=== modem vissza online ==="
dbus-send --system --print-reply --dest=org.ofono /ril_0 org.ofono.Modem.SetProperty string:Online variant:boolean:true >/dev/null 2>&1
for i in $(seq 1 15); do
    sleep 10
    n=$(A /system/bin/tcpdump -r $P 2>/dev/null | wc -l)
    echo "  +$((i*10))s  Online=$(prop Modem Online)  IMS=$(prop IpMultimediaSystem Registered)  csomag=$n"
    [ "$(prop IpMultimediaSystem Registered)" = true ] && [ "$i" -ge 5 ] && break
done
pkill -x tcpdump 2>/dev/null; A pkill tcpdump 2>/dev/null; sleep 3

echo "=== a felvetel ==="
A /system/bin/tcpdump -r $P 2>/dev/null | wc -l | sed 's/^/  osszes csomag: /'
for f in "port 5060 or port 5061" "proto 50" "port 3868"; do
  printf "  %-24s %s\n" "$f" "$(A /system/bin/tcpdump -r $P "$f" 2>/dev/null | wc -l)"
done
echo "=== interfesz szerint (elso 12) ==="
A /system/bin/tcpdump -r $P -c 12 -nn 2>/dev/null | sed -E 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<addr>/g'
