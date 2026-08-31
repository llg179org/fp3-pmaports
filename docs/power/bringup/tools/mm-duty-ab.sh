#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# IS THE MODEM'S 35 % AWAKE DUTY CAUSED BY ModemManager?
#
# Measured 2026-08-31: with ModemManager stopped the MPSS is awake 5.1 % of a
# 600 s window - the oracle's range. With it running the figure on record is
# 34.8 %. That looks decisive and is not, because the daemon had been stopped for
# ELEVEN HOURS before the window: 5.1 % could be the daemon's absence, or it could
# be the modem settling after a long spell with nothing asking it anything.
# `duty-vs-uptime.sh` exists because that decay is a real effect on this device.
#
# So: A-B-A' in ONE boot, the daemon as the only deliberate variable, and each leg
# given the same settle time so "how long since the last change" is held constant.
#
#   mm-duty-ab.sh [window_s] [settle_s]        default 600 120
#
# ☠️ Restores ModemManager to whatever state it was in on every exit path. The
# device needs its modem back; a measurement that leaves the phone unable to
# receive a call has changed the thing the goal is measured against.
set -u
W=${1:-600}; S=${2:-120}
O=/var/log/fp3/mm-duty-ab-$(date +%s)
mkdir -p "$O"
L=$O/log
say(){ echo "$(date '+%F %T') $*" | tee -a "$L"; }

WAS=$(systemctl is-enabled ModemManager 2>/dev/null || echo unknown)
RUN=$(systemctl is-active ModemManager 2>/dev/null || echo unknown)
say "# ModemManager on entry: active=$RUN enabled=$WAS"

restore() {
	if [ "$RUN" = active ]; then systemctl start ModemManager 2>/dev/null
	else systemctl stop ModemManager 2>/dev/null; fi
	say "# RESTORED ModemManager to active=$(systemctl is-active ModemManager 2>/dev/null)"
}
trap 'say "signal - restoring"; restore; exit 143' INT TERM HUP
trap restore EXIT

leg() {
	name=$1; want=$2
	if [ "$want" = up ]; then systemctl start ModemManager 2>/dev/null
	else systemctl stop ModemManager 2>/dev/null; fi
	say "-- leg $name: ModemManager=$(systemctl is-active ModemManager 2>/dev/null), settling ${S}s"
	sleep "$S"
	/usr/local/bin/modem-window.sh "$W" >/dev/null 2>&1
	cp /tmp/modem-window.txt "$O/$name.txt" 2>/dev/null
	say "-- leg $name done"
}

# ☠️ A first, B second, A' third. The daemon CHANGES STATE, so the third leg is a
# real return: stopping it again is the same operation as leg A, not a different
# one. That is what makes this an A-B-A' rather than a gated before/after.
leg A-mm-stopped  down
leg B-mm-running  up
leg A2-mm-stopped down

say "# all three legs in $O"
