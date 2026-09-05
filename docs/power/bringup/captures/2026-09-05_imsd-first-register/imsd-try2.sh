#!/bin/sh
# Attempt 2. Attempt 1 sent the REGISTER out over wlan0 and got no 401, because
# the P-CSCF sits outside the ims PDN's on-link /28 and nothing routed it there.
#
# ☠️ ims-pdn-up.sh never had to solve this: on an IPv6 PDN the P-CSCF is reached
# through the same /64 the bearer hands out. With an IPv4 /28 and an off-subnet
# P-CSCF, an explicit host route via the bearer's gateway is required.
set -u
: "${PCSCF:?}"; : "${PCSCF2:=}"
LOG=/tmp/imsd-try2.log; : > "$LOG"
say() { echo "$*" | tee -a "$LOG"; }
mask() { sed -E 's/\b(10|80|172|192)\.[0-9]+\.[0-9]+\.[0-9]+\b/<addr>/g; s/IMSI=[0-9]{10,20}/IMSI=<redacted>/g'; }

B=/org/freedesktop/ModemManager1/Bearer/1
I=$(mmcli -b "$B" -K 2>/dev/null)
IFACE=$(echo "$I" | sed -n 's/^bearer\.status\.interface *: *//p')
GW=$(echo "$I" | sed -n 's/^bearer\.ipv4-config\.gateway *: *//p')
ADDR=$(echo "$I" | sed -n 's/^bearer\.ipv4-config\.address *: *//p')
say "iface=$IFACE gw-len=${#GW} addr-len=${#ADDR}"
[ -n "$IFACE" ] && [ -n "$GW" ] || { say "FATAL: no interface/gateway"; exit 1; }

say "=== host routes to the P-CSCF via the ims PDN ==="
ip route replace "$PCSCF/32" via "$GW" dev "$IFACE" && say "  primary route added"
[ -n "$PCSCF2" ] && { ip route replace "$PCSCF2/32" via "$GW" dev "$IFACE" && say "  secondary route added"; }
say "  verify: $(ip route get "$PCSCF" 2>&1 | head -1 | sed -E 's/\b(10|80|172|192)\.[0-9]+\.[0-9]+\.[0-9]+\b/<addr>/g')"

say "=== one run, 90 s ==="
set +e
timeout 90 env $(cat /etc/imsd.env | tr '\n' ' ') /usr/bin/imsd 2>&1 | mask >> "$LOG"
say "--- exited ---"
