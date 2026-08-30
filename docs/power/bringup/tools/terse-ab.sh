#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
#
# Does ModemManager's TERSE state buy residency, and does the suspend PATH decide
# whether it is applied?
#
# ☠️ THE TRAP THIS SCRIPT EXISTS TO AVOID: terse STICKS. It is applied on the
# logind sleep signal and only undone on the logind RESUME signal, so a leg that
# suspends via `rtcwake -m mem` right after a logind leg inherits the previous
# leg's terse state and looks identical to it. That is exactly how an earlier
# A-B-A-B produced "the two paths are equivalent" from data that says the
# opposite. Every leg here therefore restarts ModemManager first, so each starts
# from the same non-terse state, and each leg's terse lines are counted from the
# journal rather than assumed.
#
#   terse-ab.sh <rounds> <alarm_s>
set -u
N=${1:-3}; S=${2:-300}
O=/var/log/fp3/terse-ab.log
mkdir -p /var/log/fp3
EDGE=$(awk '/smd-edge/ && $(NF-2)==57 {l=$1; sub(":","",l); print l}' /proc/interrupts | head -1)
say(){ echo "$*" >> "$O"; }
: > "$O"
say "# terse-ab $(date '+%F %T') rounds=$N alarm=${S}s"
say "#   ExecStart: $(systemctl show ModemManager -p ExecStart --value | sed 's/.*argv\[\]=//; s/ ;.*//')"
say "#   modem edge irq=${EDGE:-?}"
say "# leg  path      slept/alarm  wake_irq  terse_lines_in_leg"

# ☠️ SH FUNCTIONS HAVE NO LOCAL SCOPE. The first version of this script used `i`
# as the counter here AND as the outer loop's round counter, so a leg silently
# advanced the loop past its end - the giveaway was a leg labelled "l22". Every
# helper below uses a prefixed name for exactly that reason.
wait_reg(){ _wr=0; while [ $_wr -lt 60 ]; do
	case "$(mmcli -m any 2>/dev/null | sed -n 's/.*state: *//p' | head -1)" in
	*registered*|*connected*) return 0;; esac; sleep 2; _wr=$((_wr+2)); done; return 1; }

leg(){ # $1 = path label
	systemctl restart ModemManager
	wait_reg || say "#   ☠️ modem did not register within 60s before $1 leg"
	sleep 5
	t0=$(date +%s); s0=$(cat /sys/power/suspend_stats/success)
	if [ "$1" = rtcwake ]; then
		rtcwake -m mem -s "$S" >/dev/null 2>&1
	else
		systemctl suspend
		# ☠️ systemctl suspend does NOT block - wait for the counter, cap the wait
		_sw=0; while [ "$(cat /sys/power/suspend_stats/success)" = "$s0" ] && [ $_sw -lt 60 ]; do sleep 1; _sw=$((_sw+1)); done
		while [ $(( $(date +%s) - t0 )) -lt $((S + 5)) ]; do sleep 2; done
	fi
	t1=$(date +%s); s1=$(cat /sys/power/suspend_stats/success)
	w=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)
	tl=$(journalctl -u ModemManager --since "@$t0" --no-pager 2>/dev/null | grep -ci terse)
	printf '%-4s %-9s %4ds/%-4ds  %-8s %s%s\n' "$2" "$1" "$((t1-t0))" "$S" "${w:-?}" "$tl" \
		"$([ "${w:-}" = "${EDGE:-x}" ] && echo '   <-modem-edge')" >> "$O"
}

rnd=1
while [ $rnd -le $N ]; do
	leg rtcwake "r$rnd"
	sleep 10
	leg logind  "l$rnd"
	sleep 10
	rnd=$((rnd + 1))
done
say "# done $(date '+%F %T')"
