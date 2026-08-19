#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# The second ofono attempt: give it the interfaces it asked for.
#
# The first run got further than expected. ofono's udevng plugin has a `qrtrsoc`
# path, it found the modem by itself - no hand-written modem.conf needed - and it
# stopped at exactly one line:
#
#   plugins/udevng.c:setup_qrtrsoc() Not enough rmnet_data interfaces found
#
# Reading the source rather than guessing: `setup_qrtrsoc()` requires one
# `rmnet_ipa*` device (we have `rmnet_ipa0`) and **at least three** interfaces
# named `rmnet_dataN`, from which it derives `mux_id = N + 1`. On a downstream
# SoC kernel the IPA driver creates those; mainline's `ipa2_lite` does not - but
# `CONFIG_RMNET=m` is in this kernel, so they can be created by hand.
#
# ☠️ Fully reversible: the links are deleted and the module unloaded on every
# exit path, and ModemManager is stopped and started again, never removed.
#
#   ofono-rmnet-try.sh [seconds_to_watch]     (default 120)

set -u

WATCH=${1:-120}
OUT=/run/night/ofono-rmnet.txt
PARENT=rmnet_ipa0
N=3
mkdir -p /run/night
say() { echo "$*" | tee -a "$OUT"; }
: > "$OUT"

MM_WAS=""
MADE=""
LOADED=0

restore() {
	rc=$?
	say ""
	say "# restoring"
	pkill -x ofonod 2>/dev/null
	sleep 2
	for i in $MADE; do
		${IP:-ip} link del "$i" 2>/dev/null && say "#   deleted $i"
	done
	[ "$LOADED" = 1 ] && { sleep 1; modprobe -r rmnet 2>/dev/null && say "#   unloaded rmnet"; }
	if [ "$MM_WAS" = active ]; then
		systemctl start ModemManager 2>/dev/null
		sleep 10
		say "#   ModemManager: $(systemctl is-active ModemManager), $(mmcli -L 2>&1 | head -1)"
	fi
	say "#   interfaces now: $(ls /sys/class/net | tr '\n' ' ')"
	say "# restore done rc=$rc"
	exit $rc
}
trap restore EXIT INT TERM

say "# ofono-rmnet-try uptime=$(cut -d. -f1 /proc/uptime) watch=${WATCH}s"
say "# before: $(ls /sys/class/net | tr '\n' ' ')"

[ -e "/sys/class/net/$PARENT" ] || { say "# ABORT: no $PARENT"; exit 1; }

# ☠️ busybox's `ip` does not implement `type rmnet mux_id`. It sends the netlink
# message WITHOUT the IFLA_RMNET_MUX_ID attribute, the kernel's
# rmnet_rtnl_validate() answers -EINVAL ("MUX ID not specified"), and `ip` prints
# a bare "RTNETLINK answers: Invalid argument" - which reads exactly like the
# kernel refusing the operation. Measured 2026-08-20, and it cost a wrong
# conclusion for ten minutes. Find a real iproute2 and refuse to continue without
# one, because a negative from the wrong tool is worse than no result.
IP=""
for c in /sbin/ip /usr/sbin/ip /usr/bin/ip; do
	[ -x "$c" ] || continue
	case "$(readlink -f "$c")" in
	*busybox*) continue ;;
	esac
	IP=$c; break
done
if [ -z "$IP" ]; then
	say "# ABORT: only busybox ip is present, which cannot set mux_id."
	say "# Install iproute2 first: apk add --simulate iproute2, then apk add iproute2."
	exit 1
fi
say "# using ip: $IP ($($IP -V 2>&1 | head -1))"

if ! lsmod | grep -q '^rmnet '; then
	modprobe rmnet 2>&1 | tee -a "$OUT"
	lsmod | grep -q '^rmnet ' || { say "# ABORT: rmnet module would not load"; exit 1; }
	LOADED=1
	say "# loaded rmnet"
fi

# ☠️ mux_id = N + 1 is ofono's rule, read out of setup_gobi_qrtr_premux(), not a
# guess: it parses the digits after "rmnet_data" and adds one.
i=0
while [ "$i" -lt "$N" ]; do
	mux=$((i + 1))
	if "$IP" link add link "$PARENT" name "rmnet_data$i" type rmnet mux_id "$mux" 2>>"$OUT"; then
		"$IP" link set "rmnet_data$i" up 2>/dev/null
		MADE="$MADE rmnet_data$i"
		say "# created rmnet_data$i mux_id=$mux"
	else
		say "# ☠️ could not create rmnet_data$i - that is the result"
	fi
	i=$((i + 1))
done
say "# after: $(ls /sys/class/net | tr '\n' ' ')"
say ""

case "$MADE" in
*rmnet_data2*) : ;;
*) say "# STOP: fewer than three interfaces exist, ofono will refuse again."; exit 0 ;;
esac

MM_WAS=$(systemctl is-active ModemManager 2>/dev/null)
say "== stopping ModemManager (was: $MM_WAS) =="
systemctl stop ModemManager 2>/dev/null
sleep 5

say "== starting ofonod -n -d =="
ofonod -n -d > /run/night/ofonod-rmnet.log 2>&1 &
PID=$!
sleep 10
kill -0 "$PID" 2>/dev/null || { say "# ofonod died; tail:"; tail -20 /run/night/ofonod-rmnet.log >> "$OUT"; exit 1; }

i=0
mods=0
while [ "$i" -lt "$WATCH" ]; do
	sleep 15
	i=$((i + 15))
	mods=$(dbus-send --system --print-reply --dest=org.ofono / org.ofono.Manager.GetModems 2>/dev/null | grep -c 'object path' || true)
	say "  t=${i}s modems=$mods"
	[ "$mods" -gt 0 ] && break
done
say ""

say "== ofono modems =="
dbus-send --system --print-reply --dest=org.ofono / org.ofono.Manager.GetModems 2>&1 | head -60 >> "$OUT"

if [ "$mods" -gt 0 ]; then
	say ""
	say "== bringing the modem online =="
	m=$(dbus-send --system --print-reply --dest=org.ofono / org.ofono.Manager.GetModems 2>/dev/null | grep -oE '"/[a-z0-9_/]+"' | head -1 | tr -d '"')
	say "  modem path: $m"
	dbus-send --system --print-reply --dest=org.ofono "$m" org.ofono.Modem.SetProperty string:Powered variant:boolean:true 2>&1 | head -3 >> "$OUT"
	sleep 10
	dbus-send --system --print-reply --dest=org.ofono "$m" org.ofono.Modem.SetProperty string:Online variant:boolean:true 2>&1 | head -3 >> "$OUT"
	sleep 20
	say "== modem properties =="
	dbus-send --system --print-reply --dest=org.ofono "$m" org.ofono.Modem.GetProperties 2>&1 | head -60 >> "$OUT"
	say "== sim =="
	dbus-send --system --print-reply --dest=org.ofono "$m" org.ofono.SimManager.GetProperties 2>&1 | head -40 >> "$OUT"
	say "== netreg =="
	dbus-send --system --print-reply --dest=org.ofono "$m" org.ofono.NetworkRegistration.GetProperties 2>&1 | head -40 >> "$OUT"
fi

say ""
say "== ofonod log, qrtr/qmi lines =="
grep -iE "qrtr|qmi|premux|rmnet|sim|netreg|error|fail" /run/night/ofonod-rmnet.log | tail -60 >> "$OUT"

kill "$PID" 2>/dev/null
say "# done"
