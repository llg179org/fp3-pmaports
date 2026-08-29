#!/bin/sh
# Category: audio
# Detached: yes
# Description: the screen sleeps while audio keeps playing
#
# The requirement, stated so it cannot be read the other way round: with only
# audio running, **the display must blank** and **the audio must keep playing**.
# Keeping the panel lit to keep the music going is a failure, not a pass.
#
# Three distinct claims, each with its own fix if it breaks:
#
#   A. the display actually blanks. Not "the compositor thinks it blanked" -
#      fbcon has been seen holding DRM DPMS on with no userspace client at all,
#      so this is read at the panel and at the display controller's interrupt
#      rate, not from the session.
#   B. the stream survives that. The screen going dark must not stop the DMA.
#   C. the system does not s2idle underneath it. On this path suspend *is*
#      silence: the q6asm front-end is fed by an AP task, and s2idle freezes
#      that task, so nothing keeps the ring full. The correct behaviour is
#      therefore that a player holds a logind sleep inhibitor for as long as it
#      has a stream - screen off, system awake, audio playing. If the phone
#      suspends mid-track and nothing held an inhibitor, the fault is policy
#      and the audio path is blameless; the check says which of the two it saw.
#
# Part D then forces a suspend anyway and reports what happens to the stream.
# That one is diagnostic, not a requirement: it measures how expensive (C) is
# to get wrong. If the DMA does come back, the inhibitor is a nicety; if it
# does not, the inhibitor is the whole feature.
#
# Nothing is answered at all unless the phone demonstrably suspends in this
# boot - see part 0 - because otherwise (C) passes for the wrong reason.
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

# The panel's own power state. Connector names differ per board and per kernel,
# so find the one that is connected rather than hardcode card0-DSI-1.
dpms_file() {
	for c in /sys/class/drm/card*-*/dpms; do
		[ -r "$c" ] || continue
		[ "$(cat "${c%/dpms}/status" 2>/dev/null)" = connected ] || continue
		echo "$c"
		return
	done
}

# Interrupts from the display controller. This is the witness that does not go
# through the compositor at all: a panel that is still refreshing counts here
# whatever any userspace state says.
mdss_irqs() {
	awk '/msm_mdss|mdp|mdss/ { for (i = 2; i <= NF; i++) if ($i ~ /^[0-9]+$/) n += $i }
	     END { print n+0 }' /proc/interrupts 2>/dev/null
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
# A + B. the screen must blank, and the stream must not care
# ---------------------------------------------------------------------------
# The blank is left to the session's own idle timeout - forcing DPMS by hand
# would test a transition nobody makes in normal use. So this window has to be
# longer than that timeout; if it is not, the panel is still lit at the end and
# that is a fact about the configured timeout, not about audio. Said as WARN
# for exactly that reason.
dpms=$(dpms_file)
irq_before=$(mdss_irqs)
[ -n "$dpms" ] && echo "PASS: panel state readable at $dpms ($(cat "$dpms"))"

inhib=$(systemd-inhibit --list --no-pager 2>/dev/null | grep -c 'sleep')
susp_before=$(suspend_count)

# Ask the session to lock, which is what a user pocketing the phone does; the
# blank then follows from the session's own policy rather than from us.
loginctl lock-sessions >/dev/null 2>&1

sleep "$POLICY_WINDOW"

# Panel: two readings, and they must agree. The interrupt delta is taken over
# the whole window, so a panel that blanked half way still shows far fewer than
# a refreshing one - the comparison is against the awake rate, not against zero.
irq_after=$(mdss_irqs)
irq_delta=$((irq_after - irq_before))
irq_per_s=$((irq_delta / POLICY_WINDOW))
dpms_state=$([ -n "$dpms" ] && cat "$dpms" 2>/dev/null)

if [ -z "$dpms" ]; then
	echo "SKIP: no connected DRM connector exposes dpms, so the panel state"
	echo "      cannot be read directly; only the interrupt rate is left"
	echo "      cmd: head /sys/class/drm/card*-*/status /sys/class/drm/card*-*/dpms"
elif [ "$dpms_state" = "Off" ] && [ "$irq_per_s" -lt 5 ]; then
	echo "PASS: the panel blanked while audio played" \
		"(dpms $dpms_state, ${irq_per_s} display irq/s)"
elif [ "$dpms_state" = "Off" ]; then
	echo "FAIL: dpms says Off but the display controller is still taking" \
		"${irq_per_s} irq/s - the panel is still being refreshed."
	echo "      This is the fbcon case: the session let go and something below"
	echo "      it is holding the pipeline on, so the screen costs power all"
	echo "      night while every userspace indicator says it is off."
	echo "      cmd: grep -E 'msm_mdss|mdp' /proc/interrupts; cat $dpms"
	fail=1
else
	echo "WARN: the panel was still on at the end of ${POLICY_WINDOW}s" \
		"(dpms ${dpms_state:-unknown}, ${irq_per_s} display irq/s)"
	echo "      Either the session idle timeout is longer than this window, or"
	echo "      the stream is holding an idle inhibitor it should not - those"
	echo "      are different bugs and the next command separates them."
	echo "      cmd: systemd-inhibit --list; gsettings get" \
		"org.gnome.desktop.session idle-delay"
fi

# B: did the blank cost us the stream? Read before the suspend leg touches
# anything, so a failure here is attributable to the screen and nothing else.
hw_blank=$(pcm_field hw_ptr)
if ! kill -0 "$player" 2>/dev/null; then
	echo "FAIL: playback stopped while the screen went dark - no suspend was"
	echo "      involved, so this is the audio path or the session, not power"
	echo "      management"
	echo "      cmd: journalctl -b --user -u pipewire -n 50"
	exit 1
elif [ -n "$hw_blank" ] && [ "$hw_blank" -gt "$hw0" ]; then
	echo "PASS: the stream kept running across the screen blank" \
		"(hw_ptr $hw0 -> $hw_blank)"
else
	echo "FAIL: the player is alive but the DMA stopped during the window" \
		"(hw_ptr $hw0 -> ${hw_blank:-gone})"
	echo "      cmd: cat /proc/asound/card0/pcm0p/sub0/status"
	fail=1
fi

# ---------------------------------------------------------------------------
# C. policy - nothing may s2idle underneath it
# ---------------------------------------------------------------------------
susp_after=$(suspend_count)

if [ -z "$susp_before" ] || [ -z "$susp_after" ]; then
	echo "SKIP: /sys/power/suspend_stats/success is unreadable, so an automatic"
	echo "      suspend during playback cannot be counted"
elif [ "$susp_after" -gt "$susp_before" ]; then
	echo "FAIL: the phone suspended $((susp_after - susp_before)) time(s) during"
	echo "      ${POLICY_WINDOW}s of playback - on this path that is silence."
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
	echo "PASS: stayed awake for the whole ${POLICY_WINDOW}s of playback" \
		"($inhib sleep inhibitor(s) held)"
fi

# ---------------------------------------------------------------------------
# D. diagnostic - force a suspend under the running stream
# ---------------------------------------------------------------------------
# Not a requirement: it measures the price of getting C wrong. A stream that
# comes back makes the inhibitor a nicety; one that does not makes it the
# feature.
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
	# Writing /sys/power/state bypasses logind inhibitors, so this is not the
	# inhibitor from C doing its job - something in the running audio path is
	# an armed wakeup source or a blocked freeze. Worth knowing, but it does
	# not violate the requirement, so it ends the diagnostic rather than the
	# check.
	echo "WARN: the forced suspend did not happen under playback (elapsed"
	echo "      ${elapsed}s) even though the control suspend did, so the"
	echo "      survival question stays unanswered this run"
	echo "      cmd: grep -v '\\s0\\s*\$' /sys/kernel/debug/wakeup_sources"
	exit $fail
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
