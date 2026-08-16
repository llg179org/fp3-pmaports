#!/bin/sh
# Category: audio
# Requires: acoustic headset
# Description: a tone played on the speaker is heard by the headset mic
#
# Same acoustic method as 21, on the analogue headset input instead of the
# digital handset mic - so it exercises the ADC path rather than the DMIC one.
# Needs a headset actually plugged in, hence the extra requirement.
#
# ☠️ Mind which end is which. The tone comes out of the phone's SPEAKER and is
# recorded on the HEADSET's microphone, so the thing to arrange is the headset's
# mic in front of the phone's speaker - not the earbud next to the mic, which
# couples nothing.
#
# ☠️ But do not stop at the geometry, which is all this note said when it was
# first written and was not the reason the check failed. Both acoustic checks
# play through the loudspeaker, and on this device the loudspeaker is silent:
# measured the same day, the amplifier does not answer on I2C and never sees its
# I2S clock, so a 1 kHz tone at full scale moved the handset mic's peak from 38
# to 95 out of 32768. Every acoustic run ever logged here, back to 2026-07-29,
# failed the same way. The geometry explanation fitted the numbers and was still
# wrong, because a dead amplifier and an uncoupled microphone produce the same
# quiet-room reading - which is why 24-speaker-amp now measures the amplifier on
# its control bus, where the room cannot get in. Run that first: while it fails,
# nothing here is a statement about the microphone.

. "$DEVICE_DIR/lib/audio-state.sh"

fail=0
audio_grab

# Speaker out, headset mic in - the headset path from HiFi.conf.
audio_cset \
	'QUIN_MI2S_RX Audio Mixer MultiMedia1' 1 \
	'ADC MUX0' AMIC \
	'AMIC MUX0' ADC2 \
	'ADC2 Volume' 20 \
	'SLIM TX0 MUX' DEC0 \
	'AIF1_CAP Mixer SLIM TX0' 1 \
	'MultiMedia2 Mixer SLIMBUS_0_TX' 1 || fail=1

if [ "$fail" -ne 0 ]; then
	echo "FAIL: could not set the loopback routes"
	exit 1
fi

# alsabat plays a tone and FFTs what comes back; rc 0 means it found its own
# frequency in the capture. Quarter volume - loud enough to reach the mic, quiet
# enough not to be a nuisance.
speaker_quiet
out=$(alsabat -D "$AUDIO_CARD" -P hw:0,0 -C hw:0,1 -c 1 -r 48000 -F 1000 2>&1)
rc=$?
speaker_restore

if [ "$rc" -eq 0 ]; then
	echo "PASS: 1 kHz tone played on the speaker was detected on the headset mic"
	exit 0
fi

echo "FAIL: acoustic loopback failed (alsabat rc=$rc)"
printf '%s\n' "$out" | tail -8 | sed 's/^/  /'
echo "      Before believing this, check the obvious: is the volume up, is the"
echo "      phone face-down on a soft surface, is the room quiet?"
exit 1
