#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# The safety net that makes an unattended night defensible.
#
# The standing gate on overnight running is the eMMC: on 2026-08-18 the card
# stopped answering (-110), root went emergency_ro, and the journal from that
# moment on contained nothing but its own failure to write. It has not recurred
# across four long runs since, including two overnight-length ones - but "it has
# not recurred" is not a mechanism, and the way to run anyway is not hope, it is
# a net.
#
# This is emmc-watch.sh plus an action. It differs in three ways:
#
#   1. It ACTS. On a confirmed write failure it restores the charger, dumps what
#      it can to tmpfs and reboots, so the morning finds a live phone with a
#      timestamped record instead of a dead one with none.
#   2. ☠️ It restores the charger FIRST, always. USBIN_SUSPEND_BIT lives in the
#      PMIC and survives a warm reboot: rebooting while a leg had USBIN
#      suspended produces a phone that silently will not charge, which is a
#      worse morning than the one it is rescuing.
#   3. It watches the pack. A leg that overruns its own floor drains toward a
#      flat battery with nobody in the room; below EMERG_UV the guardian takes
#      the charger back regardless of what the leg wants.
#
# ☠️ THE LOG LIVES ON tmpfs. /run survives a read-only root and that is the
# entire reason this file is not a journal grep.
# ☠️ The RTC reads 1970 on this device, so every timestamp is uptime seconds.
#
#   guardian.sh [interval_s]
#
# Environment:
#   NIGHT_REBOOT_ON_FAIL=0   watch and record, but never reboot (default 1)
#   NIGHT_EMERG_UV=3550000   pack floor at which the charger is taken back
#   NIGHT_MAX_H=14           stop watching after this many hours

set -u

GAP=${1:-30}
DIR=/run/night
LOG=$DIR/guardian.log
PROBE=/root/.guardian-probe
CHG=/sys/class/power_supply/pmi632-charger
BAT=/sys/class/power_supply/pmi632-battery
RPM=/sys/kernel/debug/qcom_rpm_master_stats/APSS
STATS=/sys/kernel/debug/qcom_stats

REBOOT_ON_FAIL=${NIGHT_REBOOT_ON_FAIL:-1}
EMERG_UV=${NIGHT_EMERG_UV:-3550000}
MAX_H=${NIGHT_MAX_H:-14}

mkdir -p "$DIR"
f() { cat "$1" 2>/dev/null || echo '?'; }
up() { cut -d. -f1 /proc/uptime; }
say() { echo "$*" >> "$LOG"; }

# ☠️ The master-stats lines are TAB-INDENTED, so a pattern anchored hard at ^
# matches nothing and every reading silently prints '?'. The anchor still has to
# be there: the same file carries "XO shutdown count" as well.
m() { sed -n "s/^[[:space:]]*$1[[:space:]]*:[[:space:]]*//p" "$RPM" 2>/dev/null | head -1; }
# Same field, any master: master_field <MASTER> <field>
mf() { sed -n "s/^[[:space:]]*$2[[:space:]]*:[[:space:]]*//p" "$(dirname "$RPM")/$1" 2>/dev/null | head -1; }
c() { sed -n 's/^Count[[:space:]]*:[[:space:]]*//p' "$STATS/$1" 2>/dev/null | head -1; }

# ☠️ Nothing autoloads this. Without it the APSS column is '?' throughout, which
# reads as "the processor never collapsed".
modprobe rpm_master_stats 2>/dev/null || true

restore_charger() {
	echo Charging > $CHG/status 2>/dev/null || true
}

# What we know at the instant it went wrong, written where it can still be read.
dump_evidence() {
	{
		echo "=== guardian evidence, uptime=$(up) reason=$1 ==="
		echo "--- mmc ios ---";        cat /sys/kernel/debug/mmc0/ios 2>/dev/null
		echo "--- rpm APSS ---";       cat "$RPM" 2>/dev/null
		echo "--- qcom_stats ---";     for s in vlow vmin; do echo "$s: $(c $s)"; done
		echo "--- suspend_stats ---";  cat /sys/power/suspend_stats/success /sys/power/suspend_stats/fail 2>/dev/null
		echo "--- power supply ---";   for k in status online capacity voltage_now current_now temp; do
			echo "$k=$(f $BAT/$k) chg_$k=$(f $CHG/$k)"; done
		echo "--- dmesg tail ---";     dmesg 2>/dev/null | tail -80
		echo "--- units ---";          systemctl list-units --state=running --no-legend --no-pager 2>/dev/null
	} >> "$DIR/evidence-$1.txt" 2>&1
}

say "# guardian start uptime=$(up) gap=${GAP}s reboot_on_fail=$REBOOT_ON_FAIL emerg=${EMERG_UV}uV max=${MAX_H}h"

START=$(up)
DEADLINE=$((START + MAX_H * 3600))
fails=0
emerg_done=0

while :; do
	now=$(up)
	[ "$now" -ge "$DEADLINE" ] && { say "# guardian: max ${MAX_H}h reached, exiting at uptime=$now"; break; }

	# THE detector. A reader cannot see emergency_ro; a writer can, and the
	# first failed write stamps the transition to within one interval.
	if : > "$PROBE" 2>/dev/null; then
		rw=ok
		fails=0
	else
		rw=FAIL
		fails=$((fails + 1))
	fi

	volt=$(f $BAT/voltage_now)
	printf 'up=%s write=%s timing=%s clock=%s apss_shut=%s apss_xo=%s lpass_shut=%s vlow=%s vmin=%s susp_ok=%s susp_fail=%s cap=%s v=%s i=%s chg=%s online=%s\n' \
		"$now" "$rw" \
		"$(sed -n 's/^timing spec:[[:space:]]*//p' /sys/kernel/debug/mmc0/ios 2>/dev/null | head -1)" \
		"$(sed -n 's/^clock:[[:space:]]*//p' /sys/kernel/debug/mmc0/ios 2>/dev/null | head -1)" \
		"$(m 'Shutdown count')" "$(m 'XO shutdown count')" \
		"$(mf LPASS 'Shutdown count')" \
		"$(c vlow)" "$(c vmin)" \
		"$(f /sys/power/suspend_stats/success)" "$(f /sys/power/suspend_stats/fail)" \
		"$(f $BAT/capacity)" "$volt" "$(f $BAT/current_now)" \
		"$(f $CHG/status)" "$(f $CHG/online)" \
		>> "$LOG"

	# --- the pack floor ---------------------------------------------------
	# Well below any leg's own FLOOR (3.80 V), so this only fires when a leg
	# has already lost control of its own descent.
	case "$volt" in
	''|'?') : ;;
	*)	if [ "$volt" -lt "$EMERG_UV" ] 2>/dev/null && [ "$emerg_done" -eq 0 ]; then
			say "# GUARDIAN: pack at ${volt}uV, below ${EMERG_UV} - taking the charger back"
			dump_evidence pack-floor
			restore_charger
			emerg_done=1
		fi ;;
	esac

	# --- the card ---------------------------------------------------------
	# Two consecutive failures, not one: a single failed write during a
	# remount or a full moment is not the same event as a card off the bus.
	if [ "$fails" -ge 2 ]; then
		say "# GUARDIAN: root unwritable for $fails intervals at uptime=$now"
		dump_evidence emmc-ro
		# ☠️ Charger first, unconditionally, and before any reboot path.
		restore_charger
		say "# GUARDIAN: charger restored -> status=$(f $CHG/status) online=$(f $CHG/online)"
		if [ "$REBOOT_ON_FAIL" = 1 ]; then
			say "# GUARDIAN: rebooting in 20 s so the morning finds a live phone"
			sleep 20
			sync 2>/dev/null &
			sleep 5
			# A graceful reboot can block on the filesystem that just
			# died, which is precisely the case we are in.
			echo b > /proc/sysrq-trigger 2>/dev/null
			reboot -f 2>/dev/null
		else
			say "# GUARDIAN: reboot disabled, continuing to watch a dead filesystem"
			fails=0
		fi
	fi

	sleep "$GAP"
done
