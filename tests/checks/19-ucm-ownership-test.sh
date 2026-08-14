#!/bin/sh
# Category: audio
# Description: the installed UCM verb is ours, and a package owns it
#
# The FP3 use-case configuration lives at paths the distro's own
# soc-qcom-msm8953-ucm also ships. While those files were merely copied into
# place by hand, any upgrade of that package silently put the stock versions
# back: the handset microphone stopped existing (the stock HiFi verb routes no
# capture path and leaves MultiMedia1 unrouted, so PulseAudio finds no working
# profile) and the voice-call verb stopped being registered. Both are invisible
# from the kernel side, and the symptom appears days after the apk operation
# that caused it - it reads as a kernel regression and has cost a session once.
#
# fp3-audio-ucm exists to own those paths so apk leaves them alone. This check
# is the guard on that arrangement, and it deliberately asserts two different
# things, because either alone can be true while audio is broken:
#
#   1. IDENTITY - the file is the one we wrote. Presence proves nothing: the
#      stock file sits at the same path with the same name and mode and reads
#      as correctly installed.
#   2. OWNERSHIP - a package of ours owns the path. Without this the content
#      may be right today and reverted by the next upgrade, so a passing
#      identity check alone would be a guarantee with an expiry date.

fail=0

UCM_DIR=/usr/share/alsa/ucm2
PKG=fp3-audio-ucm

# Each file is identified by a string only our version contains, rather than by
# size or checksum: those change every time we legitimately edit the verb, which
# would make this check fail for the one reason it must not - our own work.
check_file() {
	path=$1
	marker=$2
	what=$3

	if [ ! -f "$path" ]; then
		echo "FAIL: $what missing: $path"
		return 1
	fi

	if ! grep -q "$marker" "$path"; then
		echo "FAIL: $what is not ours: $path"
		echo "      (no '$marker' - the distro's stock file is most likely back;"
		echo "       reinstall $PKG and check what last ran apk)"
		return 1
	fi

	owner=$(apk info -W "$path" 2>/dev/null | sed 's/.*owned by //')
	case "$owner" in
	"$PKG"*)
		echo "PASS: $what is ours and owned by $owner"
		return 0
		;;
	'')
		echo "FAIL: $what is ours but NO package owns it: $path"
		echo "      it was hand-copied, so the next upgrade of the stock"
		echo "      package will silently revert it - install $PKG"
		return 1
		;;
	*)
		echo "FAIL: $what is ours but owned by $owner, not $PKG: $path"
		echo "      that package's next upgrade overwrites it"
		return 1
		;;
	esac
}

# The HiFi verb: only our version pre-routes the handset mic decimator.
check_file "$UCM_DIR/Fairphone/fp3/HiFi.conf" "DEC0" "HiFi verb" || fail=1

# The master config: only our version registers the voice-call verb.
check_file "$UCM_DIR/conf.d/Fairphone_3/Fairphone_3.conf" "Voice Call" \
	"UCM master config" || fail=1

# VoiceCall.conf has no counterpart upstream, so nothing can overwrite it - but
# it is meaningless if it is absent while the master config references it.
check_file "$UCM_DIR/Fairphone/fp3/VoiceCall.conf" 'SectionDevice."Mic"' \
	"voice-call verb" || fail=1

# alsa-lib's own opinion, which is what the sound server acts on. The files can
# all be right and still not parse.
verbs=$(alsaucm -c "Fairphone 3" list _verbs 2>/dev/null)
if printf '%s\n' "$verbs" | grep -q 'HiFi' &&
	printf '%s\n' "$verbs" | grep -q 'Voice Call'; then
	echo "PASS: alsa-lib reads both verbs (HiFi, Voice Call)"
else
	echo "FAIL: alsa-lib does not offer both verbs"
	echo "      got: $(printf '%s\n' "$verbs" | tr '\n' ' ')"
	fail=1
fi

exit $fail
