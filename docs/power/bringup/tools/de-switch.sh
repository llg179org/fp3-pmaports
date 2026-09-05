#!/bin/sh
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Switch which session greetd starts at boot, for the phosh-vs-Sxmo power
# comparison. Run on the device as root, then reboot.
#
# Usage: de-switch.sh phosh | sxmo | show
#
# ☠️ The config is /etc/phrog/greetd-config.toml. /etc/greetd/ does not exist on
# this device and greetd.service passes no -c, so the obvious path is the wrong
# one and fails silently if you only write to it.
#
# ☠️ There is no console on this phone. A session command that does not exist
# gives a greeter that cannot start, on every boot, with no way to see why -
# so this refuses to write a command whose binary is not on PATH, and always
# leaves the previous config next to the new one.
set -u

CONF=/etc/phrog/greetd-config.toml
WANT=${1:?usage: de-switch.sh phosh|sxmo|show}

case "$WANT" in
show)
	echo "config: $CONF"
	sed -n '/\[initial_session\]/,/^$/p' "$CONF"
	echo "--- sessions installed:"
	ls /usr/share/wayland-sessions/ 2>/dev/null
	exit 0
	;;
phosh)  CMD="systemd-cat phosh-session" ;;
sxmo)
	# ☠️ Do not hardcode Sxmo's session command - read it out of the desktop
	# file the package installed, and fail loudly if the package is not there.
	DESK=/usr/share/wayland-sessions/swmo.desktop
	if [ ! -f "$DESK" ]; then
		echo "ABORT: $DESK missing - is postmarketos-ui-sxmo-de-sway installed?" >&2
		exit 1
	fi
	EXEC=$(sed -n 's/^Exec=//p' "$DESK" | head -1)
	if [ -z "$EXEC" ]; then
		echo "ABORT: no Exec= line in $DESK" >&2
		exit 1
	fi
	CMD="systemd-cat $EXEC"
	;;
*)
	echo "ABORT: unknown target '$WANT'" >&2
	exit 1
	;;
esac

# The binary has to exist, or the next boot has no greeter and no console.
BIN=$(echo "$CMD" | awk '{print $2}')
if ! command -v "$BIN" >/dev/null 2>&1; then
	echo "ABORT: '$BIN' is not on PATH - refusing to write a session that cannot start" >&2
	exit 1
fi

cp -a "$CONF" "$CONF.before-$WANT"
awk -v cmd="$CMD" '
	/^\[initial_session\]/ { in_is = 1; print; next }
	/^\[/ { in_is = 0 }
	in_is && /^command *=/ { printf "command = \"%s\"\n", cmd; next }
	{ print }
' "$CONF.before-$WANT" > "$CONF"

echo "wrote $CONF (backup $CONF.before-$WANT):"
sed -n '/\[initial_session\]/,/^$/p' "$CONF"
echo
echo "☠️ Now re-check the boot config from the HOST before rebooting - an apk"
echo "   install regenerates extlinux.conf and drops the fallback label:"
echo "     FP3_PW=<your pmOS password> ./tests/fp3-selftest --only boot-fallback --host 192.168.x.x"
