#!/bin/sh
# Run a command in the logged-in user's session, from a check that is root.
#
# ☠️ The runner runs every check as root, and a good deal of what a check wants
# to ask about is a *per-user* service: PipeWire, wireplumber, the user's
# journal. Root has no XDG_RUNTIME_DIR and no graph of its own, so `pw-cli ls
# Node` as root does not return a shorter list - it returns nothing at all,
# measured on this device 2026-08-16. A check that reads that as "the thing I
# was looking for is absent" makes a claim about the device out of a fact about
# the harness, and that claim reads as plausible forever.
#
# So: session_init sets sess_user/sess_uid and returns non-zero if there is no
# session to talk to, and as_user runs a command inside it. Every caller must
# separate "I could not reach the instrument" from "the instrument says no".
#
# Setting XDG_RUNTIME_DIR by hand is itself how a dead session gets
# misdiagnosed as a broken daemon, so callers pair this with a reachability
# gate - prove the session answers something before believing what it says
# about anything.

session_init() {
	_row=$(loginctl list-users --no-legend 2>/dev/null |
		awk '$2 != "root" { print $1, $2; exit }')
	[ -n "$_row" ] || return 1
	sess_uid=${_row%% *}
	sess_user=${_row#* }
	[ -n "$sess_uid" ] && [ -n "$sess_user" ]
}

as_user() {
	if [ "$(id -u)" = "$sess_uid" ]; then
		sh -c "$*"
	else
		su "$sess_user" -c "XDG_RUNTIME_DIR=/run/user/$sess_uid \
DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$sess_uid/bus $*"
	fi
}
