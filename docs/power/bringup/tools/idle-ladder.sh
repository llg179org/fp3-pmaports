#!/bin/sh
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# The idle decomposition: what actually makes up the awake-idle draw, measured
# as a cumulative subtraction ladder inside ONE boot.
#
# ☠️ Why one boot and not four reboot-matched legs. The XO A/B of 2026-08-18
# put the same phone in the same state twice, eight hours apart, and its awake
# reference came out 150.1 mA one time and 161.0 mA the other - 7 % of
# boot-to-boot variance against terms we are trying to resolve at 10 mA. A
# ladder inside one boot pays no boot-to-boot variance at all; what it pays
# instead is drift with time and state of charge, and stage R at the end
# measures exactly that by restoring everything and re-running the baseline.
# If R comes back to S0, the ladder is sound. If it does not, the gap IS the
# error bar and must be quoted.
#
# ☠️ Cumulative, so each stage's number is a MARGINAL cost: S2-S1 is what the
# sensors cost given the desktop junk is already gone. That is the useful
# quantity for deciding what to fix, and it is not the same as each item's
# cost in isolation - two things that keep the same rail up look free
# individually and expensive together.
#
# ☠️ The prior idleleg.sh (2026-08-15) never took the charger off. Both of its
# captures read current_now = 0 for all 50 samples with a frozen voltage: the
# pack was full, on the cable, and the gauge had nothing to report. They
# measured nothing. This one suspends USBIN and refuses to start on a reading
# that says it did not take.
set -u

B=/sys/class/power_supply/pmi632-battery
CHG=/sys/class/power_supply/pmi632-charger
OUT=/run/idle-ladder.txt
SETTLE0=600
SETTLE=240
N=60
STEP=20

say() { echo "$*" >> "$OUT"; }

# ☠️ USBIN suspend lives in the PMIC and survives a warm reboot. Restore it on
# every exit path, and put the phone back the way it was found.

# ☠️☠️ `systemctl start rmtfs` DOES NOT UNDO `systemctl stop rmtfs`: stopping it
# powers the MODEM DOWN (rmtfs -P), and only an explicit remoteproc start brings
# it back. Recorded in the findings log 2026-08-21; not put into any tool until
# 2026-08-26, by which time it had destroyed an overnight control leg. Verify the
# thing, not the service that provides it.
modem_up_guard() {
	for rp in /sys/class/remoteproc/remoteproc*; do
		[ "$(cat "$rp/name" 2>/dev/null)" = 4080000.remoteproc ] || continue
		[ "$(cat "$rp/state" 2>/dev/null)" = offline ] || continue
		echo start > "$rp/state" 2>/dev/null
		sleep 15
		systemctl restart ModemManager 2>/dev/null
	done
	i=0
	while [ "$i" -lt 12 ]; do
		mmcli -L 2>/dev/null | grep -q 'Modem/' && return 0
		i=$((i + 1)); sleep 10
	done
	return 1
}

restore_all() {
	echo Charging > $CHG/status 2>/dev/null
	nmcli radio wifi on 2>/dev/null
	for s in cups avahi-daemon bluetooth udisks2 tuned tuned-ppd \
	         snsregd iio-sensor-proxy spkwatch ringwatch fp3-voiced \
	         ModemManager rmtfs tqftpserv greetd; do
		systemctl start "$s" 2>/dev/null
	done
	if ! modem_up_guard; then
		# ☠️ Say it where the reader of this run will see it. A ladder stage
		# that cut rmtfs priced MODEM-OFF, not "those services stopped", and
		# every stage after it inherited that state.
		say "# ☠️ NO MODEM after restore - a reboot is needed, and every stage"
		say "# ☠️ from the rmtfs one onward measured the modem POWERED OFF."
	fi
}
trap 'restore_all' EXIT INT TERM

: > "$OUT"
say "# idle-ladder start uptime=$(cut -d. -f1 /proc/uptime) boot_id=$(cat /proc/sys/kernel/random/boot_id)"
say "# kernel=$(uname -r) cmdline=$(tr '\0' ' ' < /proc/cmdline)"

# Screen and session off for every stage - this measures the system, not the UI.
systemctl stop greetd 2>/dev/null
sleep 5
for bl in /sys/class/backlight/*; do [ -w "$bl/brightness" ] && echo 0 > "$bl/brightness"; done
say "# greetd stopped, dpms=$(cat /sys/class/drm/card0/card0-DSI-1/dpms 2>/dev/null || echo '?')"

# ☠️ Off the charger, or every sample reads the cable.
echo Unknown > $CHG/status
sleep 15
say "# charger online=$(cat $CHG/online) batt_status=$(cat $B/status) v=$(cat $B/voltage_now) cap=$(cat $B/capacity)%"
if [ "$(cat $B/status)" = Charging ] || [ "$(cat $CHG/online)" = 1 ]; then
	say "# ABORT: USBIN suspend did not take - this is the failure that made the 2026-08-15 legs empty"
	exit 1
fi
c=$(cat $B/current_now)
if [ "$c" = 0 ]; then
	say "# ABORT: current_now reads 0 - the gauge is not reporting, nothing below would mean anything"
	exit 1
fi

stop() {
	for s in "$@"; do systemctl stop "$s" 2>/dev/null; done
	for s in "$@"; do say "#   $s -> $(systemctl is-active "$s" 2>/dev/null)"; done
}

stage() {
	tag=$1; settle=$2
	say "# --- stage $tag settling ${settle}s ---"
	sleep "$settle"
	say "# stage $tag sampling $N x ${STEP}s v=$(cat $B/voltage_now) cap=$(cat $B/capacity)%"
	i=0
	while [ "$i" -lt "$N" ]; do
		say "$tag $(cut -d. -f1 /proc/uptime) $(cat $B/current_now) $(cat $B/voltage_now) $(cat $B/capacity)"
		i=$((i + 1))
		sleep "$STEP"
	done
	say "# stage $tag done v=$(cat $B/voltage_now) cap=$(cat $B/capacity)%"
	cp "$OUT" /home/fp3/ 2>/dev/null || true
}

say "# === S0 baseline: everything as it boots, minus the session ==="
stage S0 "$SETTLE0"

say "# === S1 minus desktop services that no phone needs ==="
stop cups avahi-daemon bluetooth udisks2 tuned tuned-ppd
stage S1 "$SETTLE"

say "# === S2 minus the sensor stack (snsregd holds the ADSP) ==="
stop snsregd iio-sensor-proxy
stage S2 "$SETTLE"

say "# === S3 minus our own audio watchers ==="
stop spkwatch ringwatch fp3-voiced
stage S3 "$SETTLE"

say "# === S4 minus the modem stack ==="
stop ModemManager rmtfs tqftpserv
stage S4 "$SETTLE"

# ☠️ From here the wifi link is gone; reach the phone over USB (172.16.42.1).
# nmcli rather than stopping NetworkManager, because NM also owns usb0 and
# stopping it would take the last way in with it.
say "# === S5 minus wifi (USB access only from here) ==="
nmcli radio wifi off 2>/dev/null
say "#   wifi radio -> $(nmcli radio wifi 2>/dev/null)"
say "#   wlan0 -> $(ip -o link show wlan0 2>/dev/null | sed 's/.*state \([A-Z]*\).*/\1/')"
stage S5 "$SETTLE"

say "# === R restore everything: the drift control ==="
restore_all
sleep 20
say "#   wifi radio -> $(nmcli radio wifi 2>/dev/null)"
for s in cups avahi-daemon bluetooth udisks2 tuned tuned-ppd snsregd \
         iio-sensor-proxy spkwatch ringwatch fp3-voiced ModemManager \
         rmtfs tqftpserv; do
	say "#   $s -> $(systemctl is-active "$s" 2>/dev/null)"
done
# ☠️ greetd back up would light the panel and wreck the comparison; the drift
# control has to match S0, which had greetd stopped.
systemctl stop greetd 2>/dev/null
for bl in /sys/class/backlight/*; do [ -w "$bl/brightness" ] && echo 0 > "$bl/brightness"; done
echo Unknown > $CHG/status
sleep 10
stage R "$SETTLE"

say "# === done ==="
restore_all
say "# charger restored online=$(cat $CHG/online) status=$(cat $B/status)"
say "# DONE"
cp "$OUT" /home/fp3/ 2>/dev/null || true
