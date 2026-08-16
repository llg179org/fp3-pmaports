#!/bin/sh
# Description: the greeter brings up a graphical session at boot with no human
#
# This replaces 03-unlock-latency, which timed how long a *cold unlock* took.
# That check needed a person: arm a probe, reboot, have somebody type the PIN
# with nobody connected, then judge the trace. It measured something real, but
# it was the one thing in the battery that could not run unattended, and it was
# skipped in every run for months as a result.
#
# The greeter can be told to skip the human entirely: greetd's [initial_session]
# starts a session at boot without authenticating. Turning that on does not make
# the old check pass - it removes the path that check measured - so the honest
# move is to retire the latency question and test the thing that is now true:
# the phone reaches a working graphical session on its own.
#
# ☠️ Everything here is timed in MONOTONIC time. This device's RTC reads 1970
# until something sets the clock, so wall-clock timestamps jump mid-boot:
# measured 2026-08-16, loginctl printed "15min ago" for a session whose
# TimestampMonotonic said 81.6s after boot, on a phone that had been up for
# 16000s. Anything reading the human-readable column would have judged the wrong
# number, in the wrong direction, and looked reasonable doing it.

fail=0
CONF=/etc/phrog/greetd-config.toml
BASELINE="$DEVICE_DIR/baseline/autologin.txt"

# 1. The configuration. A commented-out block is the shipped default, so match
# only lines that are actually in force.
if [ ! -r "$CONF" ]; then
	echo "FAIL: no $CONF - is greetd-phrog installed?"
	echo "      cmd: apk info -W $CONF"
	exit 1
fi

want_user=$(awk '
	/^[[:space:]]*\[initial_session\]/ { in_s = 1; next }
	/^[[:space:]]*\[/ { in_s = 0 }
	in_s && /^[[:space:]]*user[[:space:]]*=/ {
		gsub(/.*=[[:space:]]*"?|"[[:space:]]*$/, ""); print; exit
	}
' "$CONF")

if [ -z "$want_user" ]; then
	echo "FAIL: [initial_session] is not enabled in $CONF, so the phone stops"
	echo "      at the greeter and waits for somebody"
	echo "      cmd: grep -A3 initial_session $CONF"
	echo "      Uncomment the block and set user to the account to log in:"
	echo "        [initial_session]"
	echo '        command = "systemd-cat phosh-session"'
	echo '        user = "fp3"'
	exit 1
fi
echo "PASS: [initial_session] logs in as $want_user at boot"

# 2. The session that resulted. Class=user rules out the systemd --user manager
# row, Seat=seat0 rules out this SSH connection, and Service names who created
# it - greetd, not sshd, not login.
#
# ☠️ Ask for one property per call. `loginctl show-session -p A -p B --value`
# does NOT print the values in the order they were requested, and a property
# with an empty value prints an empty line that word splitting then swallows -
# so a positional read of four properties came back shifted by one and matched
# nothing. Measured 2026-08-16: asking for Name, Class, Seat, Remote returned
# them as Name, Seat, Remote, Class, with Seat blank on the non-graphical rows.
sess_prop() { loginctl show-session "$1" -p "$2" --value 2>/dev/null; }

sid=""
for s in $(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}'); do
	[ "$(sess_prop "$s" Name)" = "$want_user" ] || continue
	[ "$(sess_prop "$s" Class)" = user ] || continue
	[ "$(sess_prop "$s" Seat)" = seat0 ] || continue
	[ "$(sess_prop "$s" Remote)" = no ] || continue
	sid=$s
	break
done

if [ -z "$sid" ]; then
	echo "FAIL: no local graphical session for $want_user - the autologin did"
	echo "      not produce one, or it has since died"
	echo "      cmd: loginctl list-sessions; journalctl -u greetd -b | tail -30"
	exit 1
fi

svc=$(sess_prop "$sid" Service)
typ=$(sess_prop "$sid" Type)
act=$(sess_prop "$sid" Active)
echo "PASS: session $sid is $want_user's, from $svc, $typ, Active=$act"

if [ "$svc" != greetd ]; then
	echo "FAIL: the session was created by '$svc', not greetd - something other"
	echo "      than the greeter logged this user in, so nothing here says the"
	echo "      autologin works"
	echo "      cmd: loginctl show-session $sid -p Service"
	fail=1
fi

# 3. When it happened. This is the whole discriminator between an autologin and
# a human who was quick: the check cannot see a hand on the phone, only that the
# session exists seconds rather than minutes into the boot. State the threshold
# rather than hiding it in a comparison.
mono=$(sess_prop "$sid" TimestampMonotonic)
if ! [ "${mono:-0}" -gt 0 ] 2>/dev/null; then
	echo "FAIL: session $sid has no TimestampMonotonic, so when it was created"
	echo "      cannot be established without trusting this device's clock"
	echo "      cmd: loginctl show-session $sid -p TimestampMonotonic"
	exit 1
fi
at=$(awk -v u="$mono" 'BEGIN { printf "%.1f", u / 1000000 }')
echo "cmd: loginctl show-session $sid -p TimestampMonotonic"
echo "INFO: the session was created ${at}s after boot"

MAX=$(sed -n 's/^AUTOLOGIN_MAX=//p' "$BASELINE" 2>/dev/null | head -1)
if [ -z "$MAX" ]; then
	echo "FAIL: no budget in baseline/autologin.txt (measured: ${at}s)"
	exit 1
fi
if awk -v a="$at" -v m="$MAX" 'BEGIN { exit !(a > m) }'; then
	echo "FAIL: ${at}s is past the ${MAX}s budget. Either the boot got slower,"
	echo "      or this session is a human unlock and the autologin never ran -"
	echo "      journalctl -u greetd -b separates the two"
	fail=1
else
	echo "PASS: within the ${MAX}s budget, so nobody was fast enough to be the"
	echo "      cause of it"
fi

# 4. And the shell is really there. A session with no phosh in it is a login
# that succeeded into nothing.
pid=$(pgrep -x phosh | head -1)
if [ -z "$pid" ]; then
	echo "FAIL: the session exists but phosh is not running in it"
	echo "      cmd: pgrep -ax phosh; journalctl --user-unit phosh -b | tail"
	exit 1
fi

# starttime is field 22 of /proc/PID/stat, in clock ticks since boot - the same
# monotonic base as above, and immune to the clock jump for the same reason.
ticks=$(awk '{ print $22 }' "/proc/$pid/stat" 2>/dev/null)
hz=$(getconf CLK_TCK 2>/dev/null || echo 100)
born=$(awk -v t="${ticks:-0}" -v hz="$hz" 'BEGIN { printf "%.1f", t / hz }')
echo "PASS: phosh is up (pid $pid, started ${born}s after boot,"
echo "      $(awk -v a="$at" -v b="$born" 'BEGIN { printf "%.1f", b - a }')s after the session was created)"

exit $fail
