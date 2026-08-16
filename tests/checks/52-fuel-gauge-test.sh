#!/bin/sh
# Category: charger
# Description: the reported capacity tracks the battery, not the CPU load
#
# The property worth checking here is not whether the percentage is right -
# nothing on the phone can say that - but whether it is a percentage at all.
# Reading the terminal voltage into the OCV table produced a number that fell
# by tens of points under a CPU burn and climbed back when it ended, because the
# table maps an open-circuit voltage and a loaded terminal voltage is not one.
# So the test is a load step: put the phone under load, and require that what
# the gauge reports barely moves. A gauge that integrates current passes; one
# that looks up a loaded voltage cannot.
#
# Needs no cable, so it is separate from 50-charger for the same reason
# 51-battery-temp is.
#
# ☠️ It needs more than "no cable required": it needs the charger not to be
# holding the rail. Measured 2026-08-16 with a cable attached, the load step
# moved the terminal voltage by 0mV - vbat read 4335539uV before and after, to
# the microvolt - because the input FET was sourcing the whole burn. The check
# skipped, and a skip in a passing battery is easy to read as "nothing to see".
# So take the phone off VBUS electrically for the duration instead of asking a
# human to unplug it: qcom_smbx maps the charger supply's writable STATUS onto
# USBIN_SUSPEND_BIT in USBIN_CMD_IL, which opens the PMIC's input FET while the
# cable, the PHY and this SSH session stay up.

fail=0
ps=/sys/class/power_supply/pmi632-battery
chg=/sys/class/power_supply/pmi632-charger

read_prop() { cat "$ps/$1" 2>/dev/null; }

# ☠️☠️ USBIN_SUSPEND_BIT lives in the PMIC and survives a warm reboot. Left set
# through a restart it has wedged the bootloader - fastboot enumerated and
# answered nothing, and only a held power button recovered it. So the release
# is armed before the first suspend and runs on every exit path, and nothing
# here reboots.
suspended_input=0
suspended_run=0
release_input() {
	[ "$suspended_input" = 1 ] || return 0
	echo Charging > "$chg/status" 2>/dev/null
	suspended_input=0
}
trap 'release_input' EXIT INT TERM

suspend_input() {
	[ -w "$chg/status" ] || return 1
	echo Unknown > "$chg/status" 2>/dev/null || return 1
	suspended_input=1
	sleep 2
	# Two gates here, because each can be fooled alone: online asks the PMIC
	# and status asks the charger state machine.
	#
	# ☠️ The third gate the power runbook uses - a negative current_now - does
	# NOT belong at this point. Measured 2026-08-16: with the FET open on a
	# battery at 100%, online read 0 and status read Discharging while
	# current_now read exactly 0, because an idle full pack really is drawing
	# nothing. Gating on it here rejected a disconnection that had in fact
	# happened. The ADC is asked below instead, under the load, where a
	# non-negative reading means something is wrong.
	[ "$(cat "$chg/online" 2>/dev/null)" = 0 ] || return 1
	[ "$(read_prop status)" = Discharging ] || return 1
	return 0
}

cap0=$(read_prop capacity)
if [ -z "$cap0" ]; then
	echo "FAIL: no capacity - is the battery power supply registered?"
	exit 1
fi

# The gauge's inputs. Both come from the PMIC's QG peripheral, and both are new
# with the integrating gauge; without them the capacity above can only be the
# old voltage lookup, whatever it happens to read at this instant.
inow=$(read_prop current_now)
ocv=$(read_prop voltage_ocv)
vnow=$(read_prop voltage_now)
if [ -z "$inow" ] || [ -z "$ocv" ]; then
	echo "FAIL: no current_now/voltage_ocv - the QG fuel gauge is not being read"
	echo "      (needs smb_variant.qg_base for this PMIC in qcom_smbx)"
	exit 1
fi
echo "cmd: cat $ps/{capacity,current_now,voltage_now,voltage_ocv}"
echo "INFO: start ${cap0}% ibat=${inow}uA vbat=${vnow}uV ocv=${ocv}uV"

# Off VBUS before the baseline is taken, so both readings come from the same
# electrical situation - a baseline on the charger and a loaded reading off it
# would show a "sag" that is only the disconnection.
if [ "$(cat "$chg/online" 2>/dev/null)" = 1 ]; then
	if suspend_input; then
		suspended_run=1
		echo "INFO: charger input suspended for the load step (cable still in)"
		cap0=$(read_prop capacity)
		vnow=$(read_prop voltage_now)
		echo "INFO: off VBUS ${cap0}% ibat=$(read_prop current_now)uA vbat=${vnow}uV"
	else
		release_input
		echo "SKIP: the charger is online and its input could not be suspended,"
		echo "      so a load step would be sourced by the charger and measure"
		echo "      nothing - unplug the cable and re-run"
		echo "      cmd: echo Unknown > $chg/status   # then check online/status/current_now"
		exit 0
	fi
fi

temp0=$(read_prop temp)
if [ -n "$temp0" ] && [ "$temp0" -gt 430 ]; then
	echo "SKIP: battery already at $((temp0 / 10))C, not adding a load to it"
	exit 0
fi

# ~30s of every core busy. On this phone that swings the terminal voltage by
# roughly a quarter of a volt, which is what used to move the reported
# percentage; the battery-side sensor barely notices it.
echo "cmd: $(nproc) x sha256sum /dev/zero for 30s"
i=0
while [ "$i" -lt "$(nproc)" ]; do
	sha256sum /dev/zero &
	i=$((i + 1))
done
sleep 30

cap1=$(read_prop capacity)
inow1=$(read_prop current_now)
vnow1=$(read_prop voltage_now)
ocv1=$(read_prop voltage_ocv)
temp1=$(read_prop temp)

kill $(pgrep sha256sum) 2>/dev/null
wait 2>/dev/null

# Put the phone back on the charger the moment the measurement is over - the
# bit must not outlive the burn any longer than it has to.
release_input

echo "INFO: loaded ${cap1}% ibat=${inow1}uA vbat=${vnow1}uV ocv=${ocv1}uV"

# The ADC gate, now that there is a load for it to see. Under a full-core burn
# off VBUS the pack must be delivering current; a non-negative reading means
# either the input never opened or the gauge is not reading the shunt.
if [ "$suspended_run" = 1 ] && [ "${inow1:-0}" -ge 0 ] 2>/dev/null; then
	echo "FAIL: current_now is ${inow1}uA under load with the charger input"
	echo "      suspended - the pack must be sourcing the burn"
	echo "      cmd: cat $ps/current_now"
	fail=1
fi

# The load has to have actually reached the battery, or the rest proves nothing:
# a gauge that survives a load step it never saw has survived nothing.
sag=$((vnow - vnow1))
[ "$sag" -lt 0 ] && sag=$((-sag))
if [ "$sag" -lt 50000 ]; then
	echo "SKIP: terminal voltage moved only $((sag / 1000))mV - no real load step,"
	echo "      so this run cannot tell a good gauge from a bad one"
	exit 0
fi
echo "PASS: load step reached the battery ($((sag / 1000))mV of sag)"

# Thirty seconds at well under an amp is a fraction of a percent of a 3000 mAh
# pack, so anything past two points is the meter following the load.
delta=$((cap0 - cap1))
[ "$delta" -lt 0 ] && delta=$((-delta))
if [ "$delta" -le 2 ]; then
	echo "PASS: capacity moved $delta point(s) across the load step"
else
	echo "FAIL: capacity moved $delta points (${cap0}% -> ${cap1}%) under load"
	echo "      - the gauge is reading the load, not the charge"
	fail=1
fi

# And the compensation has to be doing something: under load the open-circuit
# estimate must stand off the terminal voltage, in the direction the current
# says. Equal values mean nothing is being corrected.
if [ "$ocv1" -eq "$vnow1" ]; then
	echo "FAIL: voltage_ocv equals voltage_now under load - no IR correction"
	echo "      (is factory-internal-resistance-micro-ohms set on the battery?)"
	fail=1
else
	echo "PASS: ocv stands $(( (ocv1 - vnow1) / 1000 ))mV off the terminal voltage"
fi

if [ -n "$temp1" ]; then
	echo "INFO: battery $((temp0 / 10))C -> $((temp1 / 10))C over the burn"
fi

exit $fail
