#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Does VBUS still carry the system load while the PMIC's input is SUSPENDED?
#
# ☠️ DEMOTED 2026-09-01, on the same morning it was written. It was built to test
# the suspicion that every "floor" current this project has published was taken
# with part of the load coming from the cable - which would make the OCV slope
# under-report silently, with every gate passing. Two minutes of reading killed
# that story before this ran:
#
#   - sleep-night.sh restores an `input_suspend` attribute that does not exist on
#     this device; that loop has always been a no-op.
#   - the cut that DOES happen, `echo Unknown > .../pmi632-charger/status`, is a
#     real input-path suspend: qcom_smbx.c's smb_set_property sets
#     USBIN_SUSPEND_BIT in USBIN_CMD_IL. The system then runs off the pack.
#
# And the 48-vs-100 mA discrepancy that prompted it turned out to have a duller
# cause: the 48 mA and the 5 % duty it was paired with came from different runs on
# different days (captures/2026-09-01_modem-night-control/, section 5).
#
# It is kept because source is not a measurement: this is the instrument that
# would CONFIRM the register reading on the live phone, and it costs a few
# minutes. It is no longer a lead.
#
# The instrument is the PMI632's own USBIN current-sense ADC channel,
# `in_voltage_usb_in_i_uv_input`, which the FP3 exposes on iio:device1.
#
# ☠️ IT DOES NOT READ ZERO AT ZERO CURRENT. Measured 2026-09-01 with the cable
# physically out: ~325000-355000 uV. So the channel carries a large offset and a
# single reading means nothing - only the difference between states does, and the
# charging state is what calibrates uV to mA.
#
# Three states, in this order:
#   1. cable OUT          - the true zero, and the run refuses to start without it
#   2. cable IN, charging - known current from the charger's own reporting: the scale
#   3. cable IN, SUSPENDED - the state every floor measurement was taken in
#
# ☠️ The USBIN suspend bit lives in the PMIC and SURVIVES A WARM REBOOT; a phone
# rebooted with it set has wedged the bootloader into a fastboot that answers
# nothing, and recovery needed a held power button. Every exit path here restores
# it.
#
#   usbin-load-probe.sh [samples_per_state]
set -u
N=${1:-20}
IIO=/sys/bus/iio/devices/iio:device1
CHG=/sys/class/power_supply/pmi632-charger
BAT=/sys/class/power_supply/pmi632-battery
O=/var/log/fp3/usbin-load-$(date +%s)
mkdir -p "$O"
LOG=$O/log.txt
say(){ echo "$*" | tee -a "$LOG"; }

restore(){
	echo Charging > $CHG/status 2>/dev/null
	for f in /sys/class/power_supply/*/input_suspend; do
		[ -w "$f" ] && echo 0 > "$f" 2>/dev/null
	done
	say "# RESTORED $(date '+%F %T') charger=$(cat $CHG/status 2>/dev/null) online=$(cat $CHG/online 2>/dev/null)"
}
trap restore EXIT INT TERM

[ "$(id -u)" = 0 ] || { echo "not root"; exit 1; }
[ -r $IIO/in_voltage_usb_in_i_uv_input ] || { echo "no usb_in_i_uv channel - wrong iio device?"; exit 1; }

sample(){	# $1 = state label
	i=0
	while [ $i -lt "$N" ]; do
		printf '%s %s %s %s %s %s\n' "$1" \
			"$(cat $IIO/in_voltage_usb_in_i_uv_input)" \
			"$(cat $IIO/in_voltage_usb_in_v_div_16_input)" \
			"$(cat $CHG/current_now 2>/dev/null || echo -)" \
			"$(cat $BAT/voltage_now)" \
			"$(cat $CHG/online)" >> "$O/samples.txt"
		i=$((i + 1))
		sleep 1
	done
	say "# state '$1' sampled $N times"
}

say "# usbin-load-probe $(date '+%F %T')  samples=$N"
say "# kernel=$(uname -v)"

# ---- state 1: cable out, the true zero
[ "$(cat $CHG/online)" = 0 ] || { say "☠️ GATE: cable is IN - unplug it, this run needs the zero first"; exit 1; }
say "# state 1: cable OUT"
sample cable-out

# ---- state 2: cable in, charging - the scale
say "# PLUG THE CABLE IN NOW (waiting up to 15 min)"
i=0
while [ "$(cat $CHG/online)" = 0 ] && [ $i -lt 900 ]; do sleep 1; i=$((i + 1)); done
[ "$(cat $CHG/online)" = 1 ] || { say "☠️ cable never appeared - nothing but the zero was measured"; exit 1; }
say "# cable in at $(date '+%T'); settling 30 s for APSD/AICL"
sleep 30
say "# state 2: cable IN, charging  (status=$(cat $CHG/status))"
sample cable-in-charging

# ---- state 3: cable in, input suspended - the state every floor was measured in
for f in /sys/class/power_supply/*/input_suspend; do [ -w "$f" ] && echo 1 > "$f"; done
sleep 5
st=$(cat $BAT/status)
say "# state 3: cable IN, input_suspend=1  battery status=$st"
[ "$st" = Discharging ] || say "☠️ battery says '$st', not Discharging - sleep-night.sh's own gate would have STOPPED here"
sample cable-in-suspended

say "# done $(date '+%F %T'); raw in $O/samples.txt"
