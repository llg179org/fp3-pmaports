#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Does ofono bring this modem up over QRTR?
#
# The port question behind it: Sailfish's telephony is ofono, mainline msm8953
# reaches the modem over QRTR, and postmarketOS is running ModemManager over that
# same transport on this phone right now. So the oracle is on the same device.
#
# ☠️ REVERSIBLE BY CONSTRUCTION, and the restore is exercised on every exit path:
#   * ModemManager is STOPPED, never removed, and started again at the end;
#   * ofono is installed as a package and left installed (harmless, not enabled);
#   * nothing touches sshd, NetworkManager, wpa_supplicant or the USB gadget.
# ☠️ Mobile data is down while this runs. The SSH links are not.
#
# ☠️ apk resolves the whole `world`, so the install is simulated first and the
# output read for `Purging` - an unrelated half-finished upgrade has taken a
# session's shell out from under us before.
#
#   ofono-try.sh [seconds_to_watch]        (default 90)

set -u

WATCH=${1:-90}
OUT=/run/night/ofono-try.txt
CONF=/etc/ofono/modem.conf
mkdir -p /run/night
say() { echo "$*" | tee -a "$OUT"; }
: > "$OUT"

MM_WAS=""
CONF_SAVED=0

restore() {
	rc=$?
	say ""
	say "# restoring"
	systemctl stop ofono 2>/dev/null
	pkill -x ofonod 2>/dev/null
	sleep 2
	if [ "$CONF_SAVED" = 1 ]; then
		mv -f "$CONF.pre-try" "$CONF" 2>/dev/null && say "#   $CONF restored"
	else
		rm -f "$CONF" 2>/dev/null
	fi
	if [ "$MM_WAS" = active ]; then
		systemctl start ModemManager 2>/dev/null
		sleep 8
		say "#   ModemManager: $(systemctl is-active ModemManager 2>/dev/null), modems: $(mmcli -L 2>&1 | head -1)"
	fi
	say "# restore done rc=$rc"
	exit $rc
}
trap restore EXIT INT TERM

say "# ofono-try uptime=$(cut -d. -f1 /proc/uptime) watch=${WATCH}s"

# --- 0. the eMMC gate, because this is night work on a card that dropped once ---
if dmesg 2>/dev/null | grep -qE 'mmc0: (cache flush error|mmc_hs400_to_hs200)|mmcblk0: recovery failed'; then
	say "# ABORT: mmc error already in dmesg this boot"
	exit 1
fi

# --- 1. install, but look before ---
if ! apk info -e ofono >/dev/null 2>&1; then
	say "== apk add --simulate ofono =="
	apk add --simulate ofono 2>&1 | tee -a "$OUT" | grep -qi "Purging" && {
		say "# ABORT: the simulation wants to purge something - read $OUT before proceeding"
		exit 1
	}
	say "== installing =="
	apk add ofono ofono-scripts 2>&1 | tail -5 | tee -a "$OUT"
else
	say "# ofono already installed: $(apk info -e ofono)"
fi
command -v ofonod >/dev/null 2>&1 || { say "# ABORT: no ofonod after install"; exit 1; }
say "# ofonod: $(ofonod --version 2>&1 | head -1)"
say ""

# --- 2. what the driver needs, measured here rather than assumed ---
# qrtrqmi takes the data interfaces from modem properties. Find them.
MAIN=""
for cand in rmnet_ipa0 wwan0 rmnet0; do
	[ -e "/sys/class/net/$cand" ] && { MAIN=$cand; break; }
done
if [ -z "$MAIN" ]; then
	MAIN=$(ls /sys/class/net | grep -E '^(rmnet|wwan)' | head -1)
fi
say "== data path =="
say "  main interface: ${MAIN:-NONE FOUND}"
PREMUX=$(ls /sys/class/net | grep -E '^rmnet_data[0-9]+$|^rmnet[0-9]+$' | head -8 | tr '\n' ' ')
say "  premux candidates: ${PREMUX:-none}"
if [ -z "$MAIN" ]; then
	say ""
	say "# STOP: there is no rmnet/wwan interface for qrtrqmi to use."
	say "# That is a RESULT, not a failure of this script: on this kernel the"
	say "# modem's data path is not exposed as a netdev that ofono can be told"
	say "# about, and that is the gap to write up."
	exit 0
fi
IDX=$(cat "/sys/class/net/$MAIN/ifindex")
say "  ifindex: $IDX"
say ""

# --- 3. hand ModemManager off ---
MM_WAS=$(systemctl is-active ModemManager 2>/dev/null)
say "== stopping ModemManager (was: $MM_WAS) =="
systemctl stop ModemManager 2>/dev/null
sleep 5
say "  now: $(systemctl is-active ModemManager 2>/dev/null)"
say ""

# --- 4. declare the modem, because nothing else will ---
mkdir -p /etc/ofono
if [ -f "$CONF" ]; then cp "$CONF" "$CONF.pre-try"; CONF_SAVED=1; fi
{
	echo "[qrtrqmi]"
	echo "Driver=qrtrqmi"
	echo "NetworkInterface=$MAIN"
	echo "NetworkInterfaceIndex=$IDX"
	n=0
	for p in $PREMUX; do
		n=$((n + 1))
		echo "PremuxInterface${n}=$p"
		echo "${n}MuxId=$n"
	done
	echo "NumPremuxInterfaces=$n"
} > "$CONF"
say "== $CONF =="
sed 's/^/  /' "$CONF" | tee -a "$OUT" >/dev/null
cat "$CONF" | sed 's/^/  /' >> "$OUT"
say ""

# --- 5. run it in the foreground under this unit, with debug on ---
say "== starting ofonod -n -d =="
ofonod -n -d > /run/night/ofonod.log 2>&1 &
OFONO_PID=$!
sleep 10
if ! kill -0 "$OFONO_PID" 2>/dev/null; then
	say "# ofonod exited immediately - log tail:"
	tail -20 /run/night/ofonod.log | sed 's/^/  /' | tee -a "$OUT" >/dev/null
	tail -20 /run/night/ofonod.log | sed 's/^/  /' >> "$OUT"
	exit 1
fi
say "  running, pid $OFONO_PID"
say ""

# --- 6. watch ---
i=0
while [ "$i" -lt "$WATCH" ]; do
	sleep 15
	i=$((i + 15))
	mods=$(dbus-send --system --print-reply --dest=org.ofono / org.ofono.Manager.GetModems 2>&1 | grep -c 'object path' || true)
	say "  t=${i}s  modems=$mods  ofonod=$(kill -0 $OFONO_PID 2>/dev/null && echo alive || echo dead)"
	[ "$mods" -gt 0 ] && break
done
say ""

say "== ofono manager =="
dbus-send --system --print-reply --dest=org.ofono / org.ofono.Manager.GetModems 2>&1 | head -40 | sed 's/^/  /' >> "$OUT"
dbus-send --system --print-reply --dest=org.ofono / org.ofono.Manager.GetModems 2>&1 | head -20 | sed 's/^/  /'
say ""
say "== ofonod log, the interesting lines =="
grep -iE "qrtr|qmi|modem|service|error|fail|warn" /run/night/ofonod.log | tail -40 | sed 's/^/  /' >> "$OUT"
grep -iE "qrtr|qmi|error|fail" /run/night/ofonod.log | tail -20 | sed 's/^/  /'

kill "$OFONO_PID" 2>/dev/null
say ""
say "# ofono-try done - full daemon log in /run/night/ofonod.log"
