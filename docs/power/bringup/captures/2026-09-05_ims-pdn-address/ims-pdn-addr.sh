#!/bin/sh
# Does the IMS PDN get a GLOBAL IPv6? imsd auto-detects its LOCAL address from
# one, and if there is none the value has to be supplied another way.
#
# Read-mostly and reversible: the bearer is raised, read, and torn down again.
# ☠️ Does NOT touch the IMS service switches - fp3-ims-reconcile keeps those off
# and this test does not need them; an IMS APN bearer is a data call.
set -u
echo "=== before ==="
mmcli -m any 2>/dev/null | grep -iE "bearer|state:" | head -5
echo "=== raise the ims APN ==="
timeout 60 mmcli -m any --create-bearer='apn=ims,ip-type=ipv4v6' 2>&1 | tail -2
B=$(mmcli -m any 2>/dev/null | sed -n 's#.*\(/org/freedesktop/ModemManager1/Bearer/[0-9]*\).*#\1#p' | tail -1)
echo "bearer: ${B:-none}"
[ -n "$B" ] || { echo "no bearer object; nothing to connect"; exit 1; }
timeout 60 mmcli -b "$B" --connect 2>&1 | tail -2
sleep 5
echo "=== what it got ==="
timeout 30 mmcli -b "$B" 2>&1 | grep -iE "interface|address|prefix|method|ipv6|ipv4" | head -20
echo "=== kernel view of that interface ==="
IF=$(timeout 30 mmcli -b "$B" 2>/dev/null | sed -n 's/.*interface: *//p' | head -1)
echo "iface: ${IF:-unknown}"
[ -n "$IF" ] && ip -6 addr show dev "$IF" 2>/dev/null | sed 's/^/  /'
echo "=== tear down ==="
timeout 60 mmcli -b "$B" --disconnect 2>&1 | tail -1
timeout 60 mmcli -m any --delete-bearer="$B" 2>&1 | tail -1
echo "=== after ==="
mmcli -m any 2>/dev/null | grep -iE "state:" | head -3
