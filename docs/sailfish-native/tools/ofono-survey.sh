#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# What would ofono's qrtrqmi driver need on THIS phone?
#
# ☠️ Read-only. It installs nothing, stops nothing and writes nothing outside
# /run. Run it before the ofono experiment, because qrtrqmi is a modem *driver*
# and not an auto-detecting plugin: it takes NetworkInterface,
# NetworkInterfaceIndex, the pre-multiplexed netdevs and their mux ids from modem
# properties, and on an integrated SoC modem nothing supplies those. This is how
# you find out what to write into /etc/ofono/modem.conf.
#
# The working oracle is on the same phone: ModemManager is talking to this modem
# over the same transport right now, so what it binds to is the answer.

set -u
OUT=/run/night/ofono-survey.txt
mkdir -p /run/night
say() { echo "$*" | tee -a "$OUT"; }
: > "$OUT"

say "# ofono-survey uptime=$(cut -d. -f1 /proc/uptime) kernel=$(uname -r)"
say ""

say "== network interfaces that could be the modem's data path =="
for d in /sys/class/net/*; do
	n=$(basename "$d")
	case "$n" in
	lo|wlan*|usb*|rndis*|bridge*|veth*) continue ;;
	esac
	say "  $n  ifindex=$(cat "$d/ifindex" 2>/dev/null) type=$(cat "$d/type" 2>/dev/null) oper=$(cat "$d/operstate" 2>/dev/null) driver=$(basename "$(readlink -f "$d/device/driver" 2>/dev/null)" 2>/dev/null)"
done
say ""

say "== all interfaces, for completeness =="
say "  $(ls /sys/class/net | tr '\n' ' ')"
say ""

say "== rmnet / IPA modules =="
say "  $(lsmod | grep -iE 'rmnet|ipa|qmi|qrtr|wwan' | awk '{print $1}' | tr '\n' ' ')"
say ""

say "== wwan subsystem (upstream path) =="
if [ -d /sys/class/wwan ]; then
	for w in /sys/class/wwan/*; do say "  $(basename "$w")"; done
	say "  char devices: $(ls /dev/wwan* 2>/dev/null | tr '\n' ' ')"
else
	say "  no /sys/class/wwan - this SoC uses the QRTR path, not the WWAN chardev path"
fi
say ""

say "== QRTR services (who is on the bus) =="
if command -v qrtr-lookup >/dev/null 2>&1; then
	qrtr-lookup 2>&1 | head -40 | while read -r l; do say "  $l"; done
else
	say "  qrtr-lookup not installed"
	say "  qrtr nodes: $(ls /sys/class/net/ 2>/dev/null | grep -c qrtr) (indirect)"
fi
say ""

say "== ModemManager, the oracle on the same transport =="
say "  unit: $(systemctl is-active ModemManager 2>/dev/null)"
if command -v mmcli >/dev/null 2>&1; then
	mmcli -L 2>&1 | while read -r l; do say "  $l"; done
	m=$(mmcli -L 2>/dev/null | grep -oE '/org/freedesktop/ModemManager1/Modem/[0-9]+' | head -1)
	if [ -n "$m" ]; then
		say "  --- modem detail ---"
		mmcli -m "$m" 2>&1 | grep -iE "primary port|ports|device |plugin|state|power state|equipment id|drivers" | while read -r l; do say "    $l"; done
		say "  --- bearer / data interface ---"
		mmcli -m "$m" --bearer 2>/dev/null | head -20 | while read -r l; do say "    $l"; done
	fi
else
	say "  mmcli not installed"
fi
say ""

say "== is ofono already present? =="
say "  ofonod: $(command -v ofonod || echo absent)"
say "  apk: $(apk info -e ofono 2>/dev/null || echo 'not installed')"
say ""

say "== eMMC health gate (the standing guardrail) =="
if dmesg 2>/dev/null | grep -qE 'mmc0: (cache flush error|mmc_hs400_to_hs200 failed)|mmcblk0: recovery failed'; then
	say "  ☠️ MMC ERROR IN DMESG - stop device work, save the log"
else
	say "  clean: no mmc error this boot"
fi
say "  root: $(awk '$2=="/" {print $4}' /proc/mounts | cut -d, -f1)"
say ""
say "# survey done"
