#!/bin/sh
# Requires: bt
# Description: the bluetooth controller is present and can be powered up
#
# ☠️ "not powered" is a symptom with two entirely different causes, and this
# check used to print only the symptom. Measured 2026-08-16 in the first full
# run that did not pass --no-bt: hci0 was rfkill soft-blocked, which is a
# setting somebody made, not a controller that failed to come up. The verdict
# was the same either way, so the message could not be acted on.
#
# So do here what 52-fuel-gauge does with the charger: put the device into the
# state the measurement needs, measure, and put it back. A soft block and a
# powered-down adapter are both restored on every exit path, because a check
# that leaves the radio on is a check that changes the phone it measures.

fail=0

if [ ! -d /sys/class/bluetooth/hci0 ]; then
	echo "FAIL: no hci0 - the bluetooth controller did not come up"
	echo "      cmd: dmesg | grep -i -e btqca -e hci_qca -e 'Bluetooth'"
	exit 1
fi
echo "PASS: hci0 present"

# Match on the type, not on an rfkill index: the numbering depends on probe
# order and moves between boots, the same way the IIO indices do.
rf=""
for r in /sys/class/rfkill/rfkill*; do
	[ "$(cat "$r/type" 2>/dev/null)" = bluetooth ] && rf=$r && break
done

unblocked=0
powered_on=0
restore() {
	[ "$powered_on" = 1 ] && bluetoothctl power off >/dev/null 2>&1
	powered_on=0
	[ "$unblocked" = 1 ] && [ -n "$rf" ] && echo 1 > "$rf/soft" 2>/dev/null
	unblocked=0
}
trap 'restore' EXIT INT TERM

if [ -n "$rf" ] && [ "$(cat "$rf/hard" 2>/dev/null)" = 1 ]; then
	echo "FAIL: hci0 is hard-blocked, which no software here can clear"
	echo "      cmd: rfkill list bluetooth"
	exit 1
fi

if [ -n "$rf" ] && [ "$(cat "$rf/soft" 2>/dev/null)" = 1 ]; then
	echo "INFO: hci0 was rfkill soft-blocked - unblocking it for the check"
	if ! echo 0 > "$rf/soft" 2>/dev/null; then
		echo "FAIL: could not clear the soft block, so the controller was"
		echo "      never asked to come up and nothing about it was measured"
		echo "      cmd: echo 0 > $rf/soft"
		exit 1
	fi
	unblocked=1
	sleep 2
fi

powered() { bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; }

if ! powered; then
	bluetoothctl power on >/dev/null 2>&1
	powered_on=1
	waited=0
	while [ "$waited" -lt 10 ] && ! powered; do
		sleep 1
		waited=$((waited + 1))
	done
fi

if powered; then
	echo "PASS: controller powers up (address $(bluetoothctl show 2>/dev/null |
		awk '/^Controller/ { print $2; exit }'))"
else
	echo "FAIL: hci0 exists but will not power up"
	echo "      cmd: bluetoothctl show; rfkill list bluetooth; dmesg | tail"
	echo "      A firmware load that failed shows in dmesg as btqca/hci_qca;"
	echo "      a controller that answers nothing does not."
	fail=1
fi

exit $fail
