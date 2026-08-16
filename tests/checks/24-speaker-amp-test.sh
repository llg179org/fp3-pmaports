#!/bin/sh
# Category: audio
# Description: the loudspeaker amplifier answers on I2C and starts its clock
#
# This exists because the battery was green on a phone whose loudspeaker is
# silent. 20-audio proves the codec enumerated and the PCMs open, which is the
# whole digital path and none of the analogue one; the only check that would
# have noticed was 21-audio-acoustic, and that one is behind --acoustic because
# an over-the-air measurement is too environment-dependent to gate on. Between
# them the amplifier had no check at all.
#
# ☠️ And "the room was noisy" is exactly what a dead amplifier looks like from
# the acoustic check. Measured 2026-08-16 on 7.1.3-r57: with a 1 kHz tone
# playing at full scale, the handset mic saw peak 95 out of 32768 against a peak
# of 38 in silence - a rise of about 8 dB where a working speaker a hand's width
# away is tens of dB. The acoustic check reported "detected at least 10 signals"
# and the honest reading of that was not "arrange the phone better", it was
# "nothing is coming out". Every acoustic run ever logged on this device, back
# to 2026-07-29, failed the same way.
#
# So measure the amplifier where it cannot be confused with the room: on its
# control bus, and in its own log lines. Both are digital and neither depends on
# where the phone is lying.
#
# ☠️ The fault it reports is not permanent, which is the whole reason it belongs
# in the default battery. Measured 2026-08-16: after a cold boot the amp answers
# normally (RX Volume readable and writable at 255, no clock complaint) and the
# speaker is loud - a 1 kHz tone put the handset mic's peak at 1466 against 58
# in silence. After three hours of use and audio testing on the same boot, the
# same checks fail and the same tone reaches 95. So this check measures a
# transition, not a constant, and its value is being run on every boot rather
# than once somebody suspects something. What kills the amp mid-session is open
# (docs/TODO.md).

. "$DEVICE_DIR/lib/audio-state.sh"

fail=0

# Match on the device name, not on the bus address: 3-0034 is where it sits
# today, and an i2c bus number is assigned in probe order like the IIO indices.
amp=""
for d in /sys/bus/i2c/devices/*/; do
	[ "$(cat "$d/name" 2>/dev/null)" = aw8898 ] && amp=${d%/} && break
done

if [ -z "$amp" ]; then
	echo "FAIL: no aw8898 on any i2c bus - the amplifier did not probe"
	echo "      cmd: grep -r . /sys/bus/i2c/devices/*/name"
	exit 1
fi
echo "PASS: aw8898 present at $(basename "$amp")"

audio_grab

# 1. Does it answer? "RX Volume" is the amp's own register, so a write to it is
# a round trip over I2C to the chip. Write back the value that is already there:
# the check must not change how loud the phone is, only find out whether the
# chip is reachable.
vol=$(amixer -D "$AUDIO_CARD" cget "name=RX Volume" 2>/dev/null |
	sed -n 's/^ *: values=//p' | head -1)

if [ -z "$vol" ]; then
	echo "FAIL: no 'RX Volume' control - the amp's component did not register"
	echo "      cmd: amixer -D hw:0 controls | grep 'RX Volume'"
	exit 1
fi

if amixer -D "$AUDIO_CARD" -q cset "name=RX Volume" "$vol" >/dev/null 2>&1; then
	echo "PASS: the amp answers on I2C (RX Volume readable and writable, now $vol)"
else
	echo "FAIL: writing 'RX Volume' back its own value ($vol) failed, so the amp"
	echo "      is not answering on I2C - every gain and enable the driver sets"
	echo "      is being dropped, which is why nothing comes out of the speaker"
	echo "      cmd: amixer -D hw:0 cset name='RX Volume' $vol"
	fail=1
fi

# 2. Does its clock come up? The driver waits for the I2S bit clock at startup
# and says so when it does not arrive; without it the amp has nothing to
# amplify. Take a cursor first so this reads only the lines this check caused -
# the log from earlier in the boot would make the verdict depend on history.
cur=$(journalctl -k -n0 --show-cursor --no-pager 2>/dev/null |
	sed -n 's/^-- cursor: *//p')

# One second of /dev/zero: silent, and still drives the whole DAPM path down to
# the amp's startup callback, which is the code that reports the clock.
timeout 5 aplay -D hw:0,0 -d 1 -f S16_LE -r 48000 -c 2 /dev/zero >/dev/null 2>&1
sleep 1

# ☠️ Match the device prefix, not the bare string. Every WARNING on this device
# prints a module list that contains snd_soc_aw8898, so a plain grep for the
# name pulls in a 1.5kB line that has nothing to do with the amplifier and
# buries the one line that does.
amp_lines() { grep -E 'aw8898 [0-9]+-[0-9a-f]+:' | sed 's/^.*aw8898 /aw8898 /'; }

if [ -n "$cur" ]; then
	new=$(journalctl -k --after-cursor "$cur" --no-pager 2>/dev/null | amp_lines)
else
	new=$(dmesg | amp_lines | tail -20)
	echo "INFO: no journal cursor available, read the whole ring buffer instead"
fi

if printf '%s\n' "$new" | grep -q 'iis clock not detected'; then
	echo "FAIL: the amp never saw its I2S clock during playback, so it has no"
	echo "      input to amplify - the speaker is silent whatever the volume is"
	echo "      cmd: aplay -D hw:0,0 -d 1 -f S16_LE -r 48000 -c 2 /dev/zero;"
	echo "           journalctl -k -b | grep aw8898"
	fail=1
elif printf '%s\n' "$new" | grep -q 'ASoC error'; then
	echo "FAIL: the amp logged bus errors during playback"
	fail=1
else
	echo "PASS: playback produced no aw8898 clock or bus complaint"
fi

printf '%s\n' "$new" | grep . | tail -4 | sed 's/^/      /'

exit $fail
