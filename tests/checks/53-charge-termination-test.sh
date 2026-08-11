#!/bin/sh
# Category: charger
# Description: the charger ends a charge at the current the battery node names
#
# A charge that never terminates is invisible from the outside: the phone stays
# on the cable, the pack stays at the float voltage, and the only symptom is a
# percentage that never reaches full. What decides it is a threshold in the
# PMIC, and the failure this guards against is not that the threshold is
# missing - the boot leaves one behind - but that it is the boot's rather than
# the battery's. Measured on this phone before the driver programmed it: the
# comparator held -101.8 mA while the pack's own profile asks for 100 mA, a
# value nothing in the kernel had chosen or could state.
#
# So the check compares what the hardware is comparing against with what the
# device tree says the cell wants. It needs no cable and no particular state of
# charge, which is why it is separate from 50-charger.

fail=0

# PMI632 is SPMI slave 2 (pmic@2 in the device tree), and its regmap carries
# the whole PMIC, charger base included.
rm=/sys/kernel/debug/regmap/0-02
dt=/sys/firmware/devicetree/base/battery
ps=/sys/class/power_supply/pmi632-battery

if [ ! -r "$rm/registers" ]; then
	echo "SKIP: no $rm/registers - CONFIG_REGMAP_DEBUGFS off, or the PMIC is not at slave 2"
	exit 0
fi

# The file is fixed width - "%04x: %02x\n", nine bytes per line - so it seeks,
# and one register is one 9-byte block. Reading it a byte at a time returns
# nothing at all, silently.
reg() {
	dd if="$rm/registers" bs=9 skip="$1" count=1 2>/dev/null |
		cut -d' ' -f2
}

# A device-tree u32 is four big-endian bytes with no newline.
dtu32() {
	[ -r "$1" ] || return 1
	od -An -tx1 "$1" 2>/dev/null | tr -d ' \n' | sed 's/^/0x/'
}

# ---------------------------------------------------------------------------
# Positive control: prove these offsets reach this PMIC's charger before
# believing anything read through them. The float voltage is programmed by the
# driver from the battery node, so the two must already agree - if they do not,
# the register window is wrong and every other read below is meaningless.
# ---------------------------------------------------------------------------
fv_raw=$(reg $((0x1070)))
fv_dt=$(dtu32 "$dt/constant-charge-voltage-max-microvolt")
if [ -z "$fv_raw" ] || [ -z "$fv_dt" ]; then
	echo "SKIP: cannot read the float voltage (reg=$fv_raw dt=$fv_dt)"
	exit 0
fi
# qpnp-smb5 float voltage: 3600000 uV + 10000 uV per LSB
fv_uv=$((3600000 + $((0x$fv_raw)) * 10000))
echo "cmd: dd if=$rm/registers bs=9 skip=$((0x1070)) count=1"
if [ "$fv_uv" != "$((fv_dt))" ]; then
	echo "FAIL: control read is wrong - float voltage reg says ${fv_uv}uV, device tree says $((fv_dt))uV"
	echo "      the register window does not describe this charger; not reading further"
	exit 1
fi
echo "INFO: control ok - float voltage ${fv_uv}uV matches the battery node"

# ---------------------------------------------------------------------------
# The termination threshold itself.
# ---------------------------------------------------------------------------
term_dt=$(dtu32 "$dt/charge-term-current-microamp")
if [ -z "$term_dt" ]; then
	echo "SKIP: the battery node names no charge-term-current-microamp"
	exit 0
fi
term_dt=$((term_dt))

msb=$(reg $((0x1067)))
lsb=$(reg $((0x1068)))
if [ -z "$msb" ] || [ -z "$lsb" ]; then
	echo "FAIL: could not read the ADC termination threshold"
	exit 1
fi
echo "cmd: dd if=$rm/registers bs=9 skip=$((0x1067)) count=2"

# Big-endian signed 16 bits, in the gauge's units and its sign convention:
# negative into the battery, so a termination current comes back negative.
raw=$(( $((0x$msb)) * 256 + $((0x$lsb)) ))
[ "$raw" -ge 32768 ] && raw=$((raw - 65536))
term_hw=$(( -raw * 152588 / 1000 ))

echo "INFO: threshold reg=0x$msb$lsb -> ${term_hw}uA, device tree asks ${term_dt}uA"

# One ADC LSB is ~152 uA, so the two can never be equal to the microamp; agree
# to within a single count of the comparator and no further.
diff=$((term_hw - term_dt))
[ "$diff" -lt 0 ] && diff=$((-diff))
if [ "$diff" -gt 153 ]; then
	echo "FAIL: the charger terminates at ${term_hw}uA, not the ${term_dt}uA this pack asks for"
	echo "      (a threshold left behind by the boot, not one this kernel chose)"
	fail=1
fi

# The ADC comparator has to be the one selected, or the threshold above is
# programmed into a comparator nothing consults.
eng=$(reg $((0x10C0)))
if [ -n "$eng" ]; then
	echo "cmd: dd if=$rm/registers bs=9 skip=$((0x10C0)) count=1"
	if [ $(( $((0x$eng)) & 0x08 )) -ne 0 ]; then
		echo "FAIL: CHGR_ENG_CHARGING_CFG=0x$eng selects the analog comparator, so the ADC threshold is unused"
		fail=1
	fi
fi

# ---------------------------------------------------------------------------
# What the charger is doing right now. Reported, not judged: which of the eight
# states it is in depends on the state of charge and on whether a cable is in,
# neither of which this check controls.
# ---------------------------------------------------------------------------
st1=$(reg $((0x1006)))
if [ -n "$st1" ]; then
	code=$(( $((0x$st1)) & 0x7 ))
	name=$(echo "inhibit trickle pre full-on taper terminate pause disable" |
		cut -d' ' -f$((code + 1)))
	echo "INFO: charger state $code ($name), psy says $(cat "$ps/status" 2>/dev/null) at $(cat "$ps/capacity" 2>/dev/null)%"
fi

[ "$fail" -eq 0 ] && echo "PASS: the charger terminates at the current the battery node names"
exit "$fail"
