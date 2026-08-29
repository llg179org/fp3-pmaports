#!/bin/sh
# Category: audio
# Detached: yes
# Description: playback survives a suspend, and nothing suspends the phone under it
#
# The user-visible question is "does the music stop when the screen goes dark".
# That is two questions wearing one sentence, and they have different fixes:
#
#   A. policy  - does the system suspend *while audio is playing*? It should
#      not: a player is expected to hold a logind sleep inhibitor for as long
#      as it has a stream. If nothing holds one, the phone sleeps mid-track and
#      the audio path is blameless.
#   B. survival - if the phone suspends anyway (an alarm, a forced suspend, a
#      caller that does not inhibit), does the stream come back? Freezing a
#      q6asm front-end and an ADSP across s2idle is not free, and a stream that
#      resumes dead looks identical from the outside to (A).
#
# So this check answers both, in that order, and refuses to answer either
# unless the phone demonstrably suspends at all in this boot - see part 0.
#
# ☠️ Two witnesses, on two layers, on purpose. The sound server's own opinion
# of its stream is not evidence that the hardware is still clocking data: it is
# the layer most likely to lie about exactly this. So the stream is watched at
# the kernel (the PCM substream's hw_ptr, which only advances when the DMA does)
# and the amplifier is read on its control bus afterwards (the i2c path that
# 24-speaker-amp exists for, because the ADSP has been seen resetting those pads
# behind the pinctrl framework's back - a resume is exactly when that recurs).
#
# Runs detached: resuming re-enumerates USB and drops the CDC-NCM link, so a
# check driven over the live session would die at the moment that matters.

. "$DEVICE_DIR/lib/audio-state.sh"

SLEEP_TIME=8			# RTC alarm for the forced-suspend leg
POLICY_WINDOW=90		# how long to watch for an *automatic* suspend
GENPD=/sys/kernel/debug/pm_genpd
SYSDOM=$GENPD/power-domain-system
TONE=/tmp/fp3-suspend-tone.raw

fail=0

# Sum the S2idle column across a domain's idle states - same accounting
# 99-suspend uses, and the only counter that separates a real suspend from the
# runtime idling that happens constantly anyway. "" when the column is absent.
s2idle_count() {
	awk '
		/^State/ { for (i = 1; i <= NF; i++) if ($i == "S2idle") col = i; next }
		col && NF >= col { n += $col; seen = 1 }
		END { if (seen) print n+0 }
	' "$1" 2>/dev/null
}

suspend_count() {
	cat /sys/power/suspend_stats/success 2>/dev/null || echo ""
}

# The playback substream's status file. Card and device are the ones the sound
# server actually opens; ask it rather than assume hw:0,0.
pcm_status() {
	cat /proc/asound/card0/pcm0p/sub0/status 2>/dev/null
}

pcm_field() {
	pcm_status | awk -v k="$1" '$1 == k":" { print $2 }'
}

# ---------------------------------------------------------------------------
# 0. the validity gate - can this phone suspend at all right now?
# ---------------------------------------------------------------------------
# Without this the whole check is unfalsifiable: on a boot where suspend never
# happens, "no automatic suspend during playback" passes for the wrong reason
# and "playback survived the suspend" never gets tested. A figure about a
# regime the system never enters is a correct number about the wrong thing.
if [ ! -e /sys/class/rtc/rtc0/wakealarm ]; then
	echo "SKIP: no RTC wakealarm - nothing can bring the phone back, so this"
	echo "      check must not suspend it"
	echo "      cmd: ls /sys/class/rtc/rtc0/"
	exit 0
fi

gate_before=$(cat /sys/class/rtc/rtc0/since_epoch)
echo 0 >/sys/class/rtc/rtc0/wakealarm
echo $((gate_before + 4)) >/sys/class/rtc/rtc0/wakealarm
sync
echo mem >/sys/power/state
gate_elapsed=$(( $(cat /sys/class/rtc/rtc0/since_epoch) - gate_before ))
echo 0 >/sys/class/rtc/rtc0/wakealarm 2>/dev/null

if [ "$gate_elapsed" -le 0 ]; then
	echo "SKIP: this boot does not suspend at all (control suspend elapsed"
	echo "      ${gate_elapsed}s), so neither half of this check can be answered."
	echo "      Fix that first - 99-suspend and the wakeup sources say why."
	echo "      cmd: grep -v '\\s0\\s*\$' /sys/kernel/debug/wakeup_sources"
	exit 0
fi
echo "PASS: control suspend worked (${gate_elapsed}s), so the regime exists"

# ---------------------------------------------------------------------------
# a tone to play, through the real path
# ---------------------------------------------------------------------------
# Generated rather than shipped: a few hundred kB of WAV in the repo would be
# the only binary asset here. 440 Hz, mono, 48 kHz, 16-bit, POLICY_WINDOW+60
# seconds long - it has to outlast both legs without a restart, because
# restarting the stream between them would hide the very failure being looked
# for. /tmp is tmpfs, so it costs RAM for the duration and nothing after.
tone_secs=$((POLICY_WINDOW + 60))
rate=48000
# Raw s16le, no WAV header: paplay takes --raw, and a header is one more thing
# that can be subtly wrong in a way that plays as noise instead of failing.
# busybox awk's printf "%c" writes the byte for a number, which is what this
# leans on - so the size is checked afterwards rather than assumed.
awk -v secs="$tone_secs" -v rate="$rate" 'BEGIN {
	n = rate * secs
	for (i = 0; i < n; i++) {
		v = int(6000 * sin(2 * 3.141592653589793 * 440 * i / rate))
		if (v < 0) v += 65536
		printf "%c%c", v % 256, int(v / 256) % 256
	}
}' >"$TONE" 2>/dev/null

want=$((tone_secs * rate * 2))
have=$(wc -c <"$TONE" 2>/dev/null || echo 0)
if [ "${have:-0}" -lt "$want" ]; then
	# awk could not write raw bytes here. Say so, and fall back to noise: the
	# question is whether the DMA keeps moving, and noise answers it as well as
	# a tone does. What must not happen is a short or malformed buffer that
	# ends the stream early and gets read as a suspend failure.
	echo "WARN: awk produced $have of $want bytes of tone; using noise instead"
	head -c "$want" /dev/urandom >"$TONE" 2>/dev/null
	have=$(wc -c <"$TONE" 2>/dev/null || echo 0)
fi

if [ "${have:-0}" -lt "$want" ]; then
	echo "FAIL: could not generate ${tone_secs}s of test audio at $TONE"
	echo "      cmd: wc -c $TONE"
	exit 1
fi

# Play it through the sound server, as the session user - the path a music app
# actually takes. Raw ALSA would answer a different question (and would not
# exercise the server's own suspend behaviour at all).
# shellcheck disable=SC2046 # want the two fields word-split
set -- $(_audio_client_env)
suser=$1
uid=$2
if [ -z "$suser" ]; then
	echo "SKIP: no reachable sound-server session, so the real playback path"
	echo "      cannot be exercised. This is a fact about the harness, not"
	echo "      about the device - a headless boot has no session to play in."
	echo "      cmd: ls /run/user/"
	rm -f "$TONE"
	exit 0
fi

# Which client exists depends on whether the server is pulseaudio or
# pipewire-pulse, and paplay is not guaranteed by either - pick one rather than
# report a missing binary as a broken audio path.
if command -v paplay >/dev/null 2>&1; then
	play_cmd="paplay --raw --rate=$rate --format=s16le --channels=1 $TONE"
elif command -v pw-play >/dev/null 2>&1; then
	play_cmd="pw-play --rate=$rate --format=s16 --channels=1 $TONE"
else
	echo "SKIP: neither paplay nor pw-play is installed, so the sound server"
	echo "      path cannot be driven from here"
	echo "      cmd: command -v paplay pw-play"
	rm -f "$TONE"
	exit 0
fi

chmod 644 "$TONE"
speaker_quiet
su "$suser" -c "XDG_RUNTIME_DIR=/run/user/$uid $play_cmd" >/dev/null 2>&1 &
player=$!
sleep 3

if ! kill -0 "$player" 2>/dev/null; then
	echo "FAIL: playback did not start at all"
	echo "      cmd: su $suser -c 'XDG_RUNTIME_DIR=/run/user/$uid $play_cmd'"
	speaker_restore
	rm -f "$TONE"
	exit 1
fi

hw0=$(pcm_field hw_ptr)
if [ -z "$hw0" ]; then
	echo "SKIP: no hw_ptr in the PCM status, so the kernel-side witness is"
	echo "      unavailable and only the sound server's own word would remain"
	echo "      cmd: cat /proc/asound/card0/pcm0p/sub0/status"
	kill "$player" 2>/dev/null
	speaker_restore
	rm -f "$TONE"
	exit 0
fi
echo "PASS: playback running through $suser's sound server (hw_ptr $hw0)"

cleanup() {
	kill "$player" 2>/dev/null
	speaker_restore
	rm -f "$TONE"
	echo 0 >/sys/class/rtc/rtc0/wakealarm 2>/dev/null
}
trap cleanup EXIT INT TERM

# ---------------------------------------------------------------------------
# A. policy - does anything suspend the phone while it is playing?
# ---------------------------------------------------------------------------
inhib=$(systemd-inhibit --list --no-pager 2>/dev/null | grep -c 'sleep')
susp_before=$(suspend_count)
sleep "$POLICY_WINDOW"
susp_after=$(suspend_count)

if [ -z "$susp_before" ] || [ -z "$susp_after" ]; then
	echo "SKIP: /sys/power/suspend_stats/success is unreadable, so an automatic"
	echo "      suspend during playback cannot be counted"
elif [ "$susp_after" -gt "$susp_before" ]; then
	echo "FAIL: the phone suspended $((susp_after - susp_before)) time(s) during"
	echo "      ${POLICY_WINDOW}s of playback - this is the reported symptom."
	if [ "$inhib" -eq 0 ]; then
		echo "      Nothing held a sleep inhibitor while the stream ran, so the"
		echo "      fault is policy, not the audio path: the player (or the"
		echo "      server on its behalf) must take one."
	else
		echo "      $inhib sleep inhibitor(s) were held and it suspended anyway."
	fi
	echo "      cmd: systemd-inhibit --list; loginctl show-session -p IdleAction"
	fail=1
else
	echo "PASS: no automatic suspend during ${POLICY_WINDOW}s of playback" \
		"($inhib sleep inhibitor(s) held)"
fi

# Still playing? A stream that died on its own during the window would make the
# line above true for the wrong reason.
if ! kill -0 "$player" 2>/dev/null; then
	echo "FAIL: playback stopped during the policy window, without a suspend"
	echo "      cmd: journalctl -b -u pipewire --user -n 50"
	exit 1
fi

# ---------------------------------------------------------------------------
# B. survival - force a suspend under the running stream
# ---------------------------------------------------------------------------
depth_before=""
[ -r "$SYSDOM/idle_states" ] && depth_before=$(s2idle_count "$SYSDOM/idle_states")
hw_pre=$(pcm_field hw_ptr)
rtc_before=$(cat /sys/class/rtc/rtc0/since_epoch)

echo 0 >/sys/class/rtc/rtc0/wakealarm
echo $((rtc_before + SLEEP_TIME)) >/sys/class/rtc/rtc0/wakealarm
sync
echo mem >/sys/power/state
rtc_after=$(cat /sys/class/rtc/rtc0/since_epoch)
echo 0 >/sys/class/rtc/rtc0/wakealarm 2>/dev/null
elapsed=$((rtc_after - rtc_before))

if [ "$elapsed" -le 0 ]; then
	echo "FAIL: the forced suspend did not happen under playback (elapsed"
	echo "      ${elapsed}s) even though the control suspend did. Something the"
	echo "      audio path takes is now blocking suspend outright."
	echo "      cmd: grep -v '\\s0\\s*\$' /sys/kernel/debug/wakeup_sources"
	exit 1
fi

if [ -n "$depth_before" ]; then
	depth_after=$(s2idle_count "$SYSDOM/idle_states")
	if [ "${depth_after:-0}" -gt "$depth_before" ]; then
		echo "PASS: suspended ${elapsed}s under playback, system domain collapsed"
	else
		echo "WARN: suspended ${elapsed}s under playback but the system power"
		echo "      domain did not collapse - the stream held something awake."
		echo "      cmd: cat /sys/kernel/debug/pm_genpd/pm_genpd_summary"
	fi
else
	echo "PASS: suspended ${elapsed}s under playback"
fi

# Give the resume a moment to finish before judging the stream.
sleep 3
hw_post=$(pcm_field hw_ptr)
state=$(pcm_field state)

if ! kill -0 "$player" 2>/dev/null; then
	echo "FAIL: the player died across the suspend"
	echo "      cmd: journalctl -b -k | grep -iE 'q6asm|xrun|pcm'"
	fail=1
elif [ -z "$hw_post" ]; then
	echo "FAIL: the PCM substream is gone after resume (it was $state before)"
	echo "      cmd: cat /proc/asound/card0/pcm0p/sub0/status"
	fail=1
elif [ "$hw_post" -gt "$hw_pre" ]; then
	echo "PASS: the DMA kept moving across the suspend" \
		"(hw_ptr $hw_pre -> $hw_post, state $state)"
else
	echo "FAIL: the stream is frozen after resume - hw_ptr stuck at $hw_post"
	echo "      (state $state). The player is alive and the server may well"
	echo "      report the stream as playing; the DMA is not advancing."
	echo "      cmd: journalctl -b -k | grep -iE 'q6asm|adsp|xrun'"
	fail=1
fi

# Second witness, on a layer the first one does not use: is the amplifier still
# answering on its control bus? A write that returns -EIO here is the failure
# 24-speaker-amp was written for, and a resume is a plausible new trigger.
if amixer -D "$AUDIO_CARD" -q cset "name=RX Volume" "$AW8898_VOL_QUIET" \
	>/dev/null 2>&1; then
	echo "PASS: the amplifier still answers on its control bus after resume"
else
	echo "FAIL: writing 'RX Volume' after resume failed - the amplifier's i2c"
	echo "      path is gone, which is silence regardless of what the DMA does"
	echo "      cmd: amixer -D $AUDIO_CARD cset name='RX Volume' $AW8898_VOL_QUIET"
	fail=1
fi

exit $fail
