#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Did our IPA driver ever complete its handshake with the modem?
#
#   ipa-handshake-probe.sh          (read-only, safe on a phone in use)
#
# Background: leads/ipa-modem-handshake.md. Ten candidates for the modem's idle
# duty are dead, and what survives has to be something the AP tells the modem
# ONCE - not a daemon, not a setting, not traffic. Two observations point here:
# the modem offers an IPA control service (49) with nobody talking to it, and no
# IPA channel is ever brought up.
#
# ☠️ MAINLINE IS NOT MISSING THE CODE, so "add the handshake" is not the finding
# to go looking for. msm8953 uses drivers/net/ipa2-lite (NOT drivers/net/ipa,
# which is v3+), that driver has its own 1334-line ipa-qmi.c carrying
# ipa_init_modem_driver_req and a 60 s INIT_DRIVER timeout, CONFIG_QCOM_IPA2_LITE
# is =m, and it autoloads off `qcom,ipa-lite-v2.6`. The question is which of two
# different faults we have, and they need different fixes.
#
# ☠️ THE V2 PATH CAN STALL WITH NOTHING LOGGED. Its own comment: "With IPA v2
# modem is not required to send DRIVER_INIT_COMPLETE request to AP. We start
# operation as soon as IPA_UC_RESPONSE_INIT_COMPLETED irq is triggered." That is a
# hardware interrupt, not a message - if it never arrives, ipa_qmi_ready() is
# never called and no error appears anywhere. A silent stall is exactly the shape
# that survives ten eliminations.
#
# ☠️ What is NOT ambiguous any more: a failing probe. Up to 6.8.0 this driver did
#     ret = ipa_init_sram(ipa); if (ret) return 0;   /* error swallowed */
# and reported success. 7.1.3 returns the error, so on our kernel a probe that
# fails says so. If the probe is clean and service 49 is still unattended, the
# fault is in the QMI exchange or the uC interrupt, not in bring-up.
set -u
O=/var/log/fp3/ipa-probe-$(date +%s)
mkdir -p "$O"
say(){ echo "$*" | tee -a "$O/log"; }

say "# ipa-handshake-probe $(date '+%F %T')"
say "# kernel=$(uname -r) $(uname -v)"
say "# uptime=$(cut -d. -f1 /proc/uptime)s"

say ""
say "## 1. is the module loaded at all?"
lsmod | awk 'NR==1 || /ipa/' | tee -a "$O/log"
say "# (nothing but the header means it never loaded - that alone would explain everything)"

say ""
say "## 2. is the platform device bound to a driver?"
for d in /sys/bus/platform/devices/*ipa*; do
	[ -e "$d" ] || continue
	drv=$(readlink -f "$d/driver" 2>/dev/null)
	say "#   $(basename "$d") -> driver: ${drv:-NONE (unbound)}"
done
ls -d /sys/bus/platform/drivers/*ipa* 2>/dev/null | while read -r p; do
	say "#   driver $(basename "$p") claims: $(ls "$p" 2>/dev/null | grep -c '^[0-9a-f]*\.')"
done

say ""
say "## 3. what did the kernel say - probe, QMI, and any 60 s INIT_DRIVER timeout"
dmesg 2>/dev/null | grep -iE 'ipa|qmi' | tail -40 | tee -a "$O/log"

say ""
say "## 4. does the modem's IPA control service have a client?"
if command -v qrtr-lookup >/dev/null 2>&1; then
	qrtr-lookup 2>&1 | tee -a "$O/log"
else
	say "# qrtr-lookup not installed - skipped"
fi

say ""
say "## 5. the interfaces, and whether anything ever went through them"
for i in rmnet_ipa0 ipa_lan0 rmnet_data0; do
	[ -d "/sys/class/net/$i" ] || { say "#   $i: absent"; continue; }
	say "#   $i: state=$(cat /sys/class/net/$i/operstate 2>/dev/null) rx=$(cat /sys/class/net/$i/statistics/rx_bytes 2>/dev/null) tx=$(cat /sys/class/net/$i/statistics/tx_bytes 2>/dev/null)"
done

say ""
say "# $O"
