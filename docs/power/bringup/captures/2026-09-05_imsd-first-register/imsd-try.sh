#!/bin/sh
# First registration attempt for imsd on the FP3. Deployed as a file.
#
# ☠️ Bypasses ims-pdn-up.sh deliberately: that script is IPv6-only (it reads
# bearer.ipv6-config.address and runs `ip -6 addr replace`) and this network's
# IMS PDN is IPv4-only. The DAEMON needs no patch - LOCAL is read from the
# environment first and only auto-detected when unset.
#
# ☠️ Runs ONCE, in the foreground, with a timeout. Repeated failed AKA attempts
# can trip the network's fresh-SA throttle the README warns about, so this does
# not loop and does not enable the systemd unit.
set -u
: "${PCSCF:?PCSCF must be passed in}"
IP_TYPE=ipv4
LOG=/tmp/imsd-try.log
: > "$LOG"
say() { echo "$*" | tee -a "$LOG"; }

say "=== 1. the modem's own IMS stack must stay out of the way ==="
/usr/local/bin/fp3-ims-reconcile.py off 2>&1 | tail -1 | tee -a "$LOG"

say "=== 2. raise the ims PDN (IPv4) ==="
MODEM=$(mmcli -L 2>/dev/null | sed -n 's,.*/Modem/\([0-9]*\).*,\1,p' | head -n1)
say "modem $MODEM"
B=""
for p in $(mmcli -m "$MODEM" -K 2>/dev/null | sed -n 's/^modem\.generic\.bearers\.value\[[0-9]*\] *: *//p'); do
    I=$(mmcli -b "$p" -K 2>/dev/null)
    echo "$I" | grep -q '^bearer\.properties\.apn *: *ims$' || continue
    B=$p
done
if [ -z "$B" ]; then
    OUT=$(mmcli -m "$MODEM" --create-bearer="apn=ims,ip-type=$IP_TYPE" 2>&1)
    B=$(printf '%s' "$OUT" | sed -n 's,.*\(/org/freedesktop/ModemManager1/Bearer/[0-9]*\).*,\1,p')
    say "created $B"
fi
[ -n "$B" ] || { say "FATAL: no ims bearer"; exit 1; }
mmcli -b "$B" --connect >/dev/null 2>&1
sleep 4
I=$(mmcli -b "$B" -K 2>/dev/null)
IFACE=$(echo "$I" | sed -n 's/^bearer\.status\.interface *: *//p')
ADDR=$(echo "$I" | sed -n 's/^bearer\.ipv4-config\.address *: *//p')
PFX=$(echo "$I" | sed -n 's/^bearer\.ipv4-config\.prefix *: *//p')
say "iface=$IFACE  addr-len=${#ADDR}  prefix=${PFX:-?}"
[ -n "$IFACE" ] && [ -n "$ADDR" ] || { say "FATAL: bearer up but no IPv4 interface/address"; exit 1; }
ip link set "$IFACE" up
ip addr replace "$ADDR/${PFX:-29}" dev "$IFACE"
say "netdev configured"

say "=== 3. open the protected ports (upstream says a policy-drop INPUT kills MT delivery) ==="
if nft list table inet filter >/dev/null 2>&1; then
    nft list chain inet filter input 2>/dev/null | grep -q imsd-protected-ports || {
        nft insert rule inet filter input iifname "qmapmux*" tcp dport 45061-45062 accept comment '"imsd-protected-ports"' 2>/dev/null
        nft insert rule inet filter input iifname "qmapmux*" udp dport 45061-45062 accept comment '"imsd-protected-ports"' 2>/dev/null
        say "nftables: rules inserted"; }
else
    say "nftables: no inet filter table (nothing to open)"
fi

say "=== 4. configuration ==="
umask 077
{ echo "PCSCF=$PCSCF"; echo "LOCAL=$ADDR"; echo "DEV=$IFACE"; echo "DUMP_SIP=1"; echo "DUMP_DIR=/tmp/imsd-sip"; } > /etc/imsd.env
mkdir -p /tmp/imsd-sip
say "wrote /etc/imsd.env ($(wc -l < /etc/imsd.env) lines; values not echoed)"

say "=== 5. ONE foreground run, 90 s ==="
set +e
timeout 90 env $(cat /etc/imsd.env | tr '\n' ' ') /usr/bin/imsd >>"$LOG" 2>&1
say "--- imsd exited rc=$? ---"
