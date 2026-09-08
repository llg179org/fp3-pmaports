#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# imsd-leg.sh          -- root, on pmOS. PCSCF is read from /etc/imsd.env.
#
# ONE run of the userspace IMS daemon down the path that is known to reach the
# network: IPv4 ims PDN, netdev configured, protected ports opened, an explicit
# host route to the P-CSCF, then a single 90 s foreground imsd.
#
# This merges captures/2026-09-05_imsd-first-register/imsd-try.sh (steps 1-4)
# and imsd-try2.sh (the host route). They were two scripts on 2026-09-05 because
# the first attempt sent its REGISTER out over wlan0 and got no 401 - the P-CSCF
# sits outside the ims PDN's /28 and nothing routed it there. Merged here so the
# route exists BEFORE the daemon runs, which costs ONE AKA attempt instead of two.
#
# ☠️ WHY NOT systemctl start imsd.service. Its ExecStartPre is ims-pdn-up.sh,
# which asks for an ip-type=ipv6 bearer and reads bearer.ipv6-config.address.
# This network answers `Ipv4OnlyAllowed: ip-version-mismatch` to that request -
# measured again 2026-09-08 20:08, seven identical retries. That is NOT a carrier
# fault and NOT a change: the 2026-09-05 work already knew the IMS APN here is
# IPv4-only and went around ims-pdn-up.sh deliberately. The unit stays disabled.
#
# ☠️ RUNS ONCE. Repeated failed AKA attempts can trip the network's fresh-SA
# throttle, so there is no loop and this never enables the systemd unit.
#
# ☠️ LOCAL IS REWRITTEN EVERY RUN. The bearer's IPv4 address is not stable across
# bring-ups, and a stale LOCAL in /etc/imsd.env would have imsd bind an address it
# no longer holds - a failure that looks like a network refusal.
set -u
LOG=/tmp/imsd-leg-$(date +%s).log
: > "$LOG"
say() { echo "$*" | tee -a "$LOG"; }
mask() { sed -E 's/\b(10|80|172|192)\.[0-9]+\.[0-9]+\.[0-9]+\b/<addr>/g; s/IMSI=[0-9]{10,20}/IMSI=<redacted>/g'; }
# ☠ mmcli prints "--" for a field it has no value for, and "--" is NOT empty.
# Measured 2026-09-08 20:11: a disconnected bearer gave IFACE="--", the [ -n ... ]
# guard passed, and every later step ran against "--" - the host route landed on
# wlan0 and the whole leg measured nothing while reporting success.
bad() { [ -z "$1" ] || [ "$1" = "--" ]; }

PCSCF=$(sed -n 's/^PCSCF=//p' /etc/imsd.env 2>/dev/null | head -1)
[ -n "$PCSCF" ] || { say "FATAL: no PCSCF in /etc/imsd.env"; exit 1; }
say "# imsd-leg $(date '+%F %T')  (P-CSCF read from /etc/imsd.env, not echoed)"

say "=== 1. the modem's own IMS stack must stay out of the way ==="
/usr/local/bin/fp3-ims-reconcile.py off 2>&1 | tail -1 | tee -a "$LOG"

say "=== 2. raise the ims PDN (IPv4) ==="
MODEM=$(mmcli -L 2>/dev/null | sed -n 's,.*/Modem/\([0-9]*\).*,\1,p' | head -n1)
say "modem $MODEM"
B=""
for p in $(mmcli -m "$MODEM" -K 2>/dev/null | sed -n 's/^modem\.generic\.bearers\.value\[[0-9]*\] *: *//p'); do
	I=$(mmcli -b "$p" -K 2>/dev/null)
	echo "$I" | grep -q '^bearer\.properties\.apn *: *ims$' || continue
	# ☠ An ims bearer of the WRONG ip-type is worse than none: it is found,
	# reused, refused by the network (Ipv4OnlyAllowed) and leaves every field "--".
	# A leftover ipv6 one from imsd.service did exactly that. Delete, do not reuse.
	if echo "$I" | grep -q '^bearer\.properties\.ip-type *: *ipv4$'; then
		B=$p
	else
		say "  deleting stale non-ipv4 ims bearer $p"
		mmcli -m "$MODEM" --delete-bearer="$p" >/dev/null 2>&1
	fi
done
if [ -z "$B" ]; then
	OUT=$(mmcli -m "$MODEM" --create-bearer="apn=ims,ip-type=ipv4" 2>&1)
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
GW=$(echo "$I" | sed -n 's/^bearer\.ipv4-config\.gateway *: *//p')
say "iface=$IFACE  addr-len=${#ADDR}  prefix=${PFX:-?}  gw-len=${#GW}"
if bad "$IFACE" || bad "$ADDR"; then
	say "FATAL: bearer up but no IPv4 interface/address - the PDN did not come up"
	say "  bearer state: $(echo "$I" | sed -n 's/^bearer\.status\.connected *: *//p')"
	exit 1
fi
ip link set "$IFACE" up
ip addr replace "$ADDR/${PFX:-29}" dev "$IFACE"
say "netdev configured"

say "=== 3. open the protected ports ==="
if nft list table inet filter >/dev/null 2>&1; then
	nft list chain inet filter input 2>/dev/null | grep -q imsd-protected-ports || {
		nft insert rule inet filter input iifname "qmapmux*" tcp dport 45061-45062 accept comment '"imsd-protected-ports"' 2>/dev/null
		nft insert rule inet filter input iifname "qmapmux*" udp dport 45061-45062 accept comment '"imsd-protected-ports"' 2>/dev/null
		say "nftables: rules inserted"; }
	say "nftables: protected ports present"
else
	say "nftables: no inet filter table (nothing to open)"
fi

say "=== 4. host route to the P-CSCF via the ims PDN (this is what attempt 1 lacked) ==="
bad "$GW" && { say "FATAL: no gateway (got '\''$GW'\'') - cannot route to the P-CSCF"; exit 1; }
ip route replace "$PCSCF/32" via "$GW" dev "$IFACE" && say "  route added"
say "  verify: $(ip route get "$PCSCF" 2>&1 | head -1 | mask)"

say "=== 5. configuration (values not echoed) ==="
umask 077
{ echo "PCSCF=$PCSCF"; echo "LOCAL=$ADDR"; echo "DEV=$IFACE"; echo "DUMP_SIP=1"; echo "DUMP_DIR=/tmp/imsd-sip"; } > /etc/imsd.env
mkdir -p /tmp/imsd-sip
say "wrote /etc/imsd.env ($(wc -l < /etc/imsd.env) lines)"

say "=== 6. ONE foreground run, 90 s ==="
set +e
timeout 90 env $(cat /etc/imsd.env | tr '\n' ' ') /usr/bin/imsd 2>&1 | mask >> "$LOG"
say "--- imsd exited ---"
say "# log: $LOG   SIP dump: /tmp/imsd-sip"
