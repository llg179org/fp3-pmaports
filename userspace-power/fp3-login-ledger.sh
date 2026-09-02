#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# THE DEVICE-SIDE HALF OF THE MEASUREMENT LOCK: every ssh login, from anywhere,
# writes itself into a ledger, and says so loudly while a measurement is running.
#
# WHY THIS EXISTS, AND WHY THE HOST-SIDE GATE WAS NOT ENOUGH. The session already
# refuses to touch the phone while `fp3-measure` says one is running - but that
# gate is PATTERN-BASED and SESSION-SCOPED: it inspects this session's tool calls.
# On 2026-09-02 the overnight replication was disturbed by a host-side watcher
# loop that had been started BEFORE the gate could see anything, polling by ssh
# every 300 s - fifteen AP wakes inside a leg whose measured quantity is how long
# the AP stays asleep. Nothing on the phone knew, and nothing on the host was
# asked. A second terminal, a second machine, or the owner's own shell would all
# have gone the same way.
#
# ☠️ IT MUST NEVER REFUSE A LOGIN. This phone has to stay reachable - a
# measurement is worth less than a recovery, and a lock that can strand the device
# is a brick waiting for the one night nobody is watching. So this is ADVISORY:
# it records and it shouts, it does not block. Everything below is wrapped so that
# a failure here cannot fail the login.
#
# WHAT IT BUYS THE MEASUREMENT. The leg's audit currently counts
# "Accepted publickey" lines - a number with no owner, which can only convict.
# With a ledger the morning can ATTRIBUTE: this login was the watchdog at 19:52,
# that one was a human at 03:14, and the leg is disturbed by the second and not by
# the first. Attribution is what turns a red audit into a usable one.
#
# Install: /usr/local/bin/fp3-login-ledger.sh, called from root's ~/.ssh/rc.

LEDGER=/var/log/fp3/logins.tsv
LOCK=/run/fp3-measuring

{
	mkdir -p /var/log/fp3 2>/dev/null

	# ☠️ SSH_CONNECTION IS THE ONLY HONEST WITNESS OF WHO CAME IN. $SSH_CLIENT is
	# the same information and deprecated; the environment a client can set
	# (SendEnv, command lines) is the client's claim, not evidence.
	client=$(echo "${SSH_CONNECTION:-?}" | awk '{print $1}')
	cmd=${SSH_ORIGINAL_COMMAND:-interactive}
	# one line, tab-separated, monotonic time beside the wall clock because the
	# RTC on this device reads 1970 until something sets it
	mono=$(awk '{print int($1)}' /proc/uptime 2>/dev/null)
	held=no
	[ -e "$LOCK" ] && held=yes

	printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
		"$(date '+%F %T' 2>/dev/null)" "$mono" "$client" "$held" "$$" \
		"$(echo "$cmd" | tr '\t\n' '  ' | cut -c1-120)" \
		>> "$LEDGER" 2>/dev/null

	if [ "$held" = yes ]; then
		# The warning goes to stderr so a scripted login still sees it in its
		# error stream without corrupting the stdout it came to read.
		{
			echo "☠️☠️ A MEASUREMENT IS RUNNING ON THIS PHONE - you just woke it."
			cat "$LOCK" 2>/dev/null | sed 's/^/   /'
			echo "   This login is now in $LEDGER and the leg's audit will find it."
			echo "   If it was not deliberate, leave now; the wake is already spent."
		} >&2
	fi
} 2>/dev/null || true

exit 0
