#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# The gate that stands between "arm the night" and eight wasted hours.
#
# Every check here exists because its absence once cost a night, a measurement
# or a filesystem. It prints one line per gate and exits non-zero if any of them
# fails; queue.sh refuses to start unless it passes.
#
# ☠️ A gate that has never been seen to fail has proved nothing. Each check
# below is written so that it CAN fail: it reads the live state, never a flag we
# set ourselves earlier in the same script.
#
#   preflight.sh [min_capacity_pct] [nocable]     (default 95)
#
# 'nocable' declares the night runs with the cable physically out (a discharge
# leg armed by an operator who just unplugged it). The charger check then turns
# into a note instead of a gate: online=0 is the DECLARED state, not evidence of
# a leftover USBIN suspend. ☠️ It stays a hard FAIL by default because with the
# cable in, online=0 means exactly that leftover - the one that hands over a
# phone that silently will not charge.

set -u

MINCAP=95
NOCABLE=0
for a in "$@"; do
	case "$a" in
	nocable) NOCABLE=1 ;;
	*[!0-9]*) echo "unknown arg: $a" >&2; exit 2 ;;
	*) MINCAP=$a ;;
	esac
done
CHG=/sys/class/power_supply/pmi632-charger
BAT=/sys/class/power_supply/pmi632-battery
RPM=/sys/kernel/debug/qcom_rpm_master_stats
FAILED=0

ok()   { printf 'PASS  %-22s %s\n' "$1" "$2"; }
bad()  { printf 'FAIL  %-22s %s\n' "$1" "$2"; FAILED=$((FAILED + 1)); }
note() { printf '#     %-22s %s\n' "$1" "$2"; }

f() { cat "$1" 2>/dev/null || echo '?'; }

echo "# preflight uptime=$(cut -d. -f1 /proc/uptime) mincap=${MINCAP}%"

# --- 1. the filesystem the night will not be able to complain from ------------
# emergency_ro is invisible to a reader: the only honest test is a write.
if : > /root/.preflight-probe 2>/dev/null; then
	ok root-rw "wrote /root/.preflight-probe"
	rm -f /root/.preflight-probe
else
	bad root-rw "root is not writable - reboot before anything else"
fi

free_root=$(df -P -k / | awk 'NR==2 {print int($4/1024)}')
if [ "${free_root:-0}" -ge 150 ]; then
	ok root-space "${free_root} MB free"
else
	bad root-space "${free_root} MB free - under 150 MB, a log rotation can fill it"
fi

# ☠️ Everything the night records goes here, because /run survives a read-only
# root and the eMMC has already eaten one night's journal.
if : > /run/.preflight-probe 2>/dev/null; then
	free_run=$(df -P -k /run | awk 'NR==2 {print int($4/1024)}')
	rm -f /run/.preflight-probe
	if [ "${free_run:-0}" -ge 100 ]; then
		ok tmpfs "/run writable, ${free_run} MB free"
	else
		bad tmpfs "/run has only ${free_run} MB free"
	fi
else
	bad tmpfs "/run is not writable - the night would have no record"
fi

# --- 2. the way back if the change under test does not boot -------------------
# A change repeats on every boot and there is no console on this device. The
# fallback label is the entire recovery story, so verify the files it names
# actually exist rather than that the stanza is present.
#
# ☠ The default label name is NOT hard-coded. The scheme has already gone from
# 'postmarketOS' to prev/bothsets/sleepset/fallback, and a plain name-match
# silently fails the whole night the day someone renames a working default -
# measured 2026-08-23: the default was 'postmarketOS-prev' (clean r73, the very
# kernel that was running) and the old '= postmarketOS' check refused to arm on
# it. What we actually require is stronger and version-free: the default must
# resolve to a FROZEN, named kernel snapshot (vmlinuz-<tag>), never the bare
# live 'vmlinuz' symlink whose contents are whatever was installed last and may
# not boot - that is the r74 'sleepset' trap. And it verifies the file exists,
# which the old name-match never did.
EXT=/boot/extlinux/extlinux.conf
defl=$(sed -n 's/^default[[:space:]]*//p' "$EXT" 2>/dev/null | head -1)
resolve() { # $1=field -> path named by the default label's stanza
	awk -v want="$defl" -v fld="$1" '
		$1=="label"{cur=$2; next}
		cur==want && $1==fld{print $2; exit}' "$EXT" 2>/dev/null
}
kpath=$(resolve kernel); fpath=$(resolve fdt)
kfile=/boot/${kpath#/}; ffile=/boot/${fpath#/}
kbase=${kpath##*/}
if [ -z "$kpath" ]; then
	bad boot-default "default label '${defl:-?}' has no kernel line in $EXT"
elif [ "$kbase" = vmlinuz ]; then
	bad boot-default "default '$defl' boots the live 'vmlinuz' symlink, not a frozen snapshot - refusing (r74 no-boot trap)"
elif [ -s "$kfile" ] && [ -s "$ffile" ]; then
	ok boot-default "default '$defl' -> frozen $kbase (+ ${fpath##*/}), both present"
else
	bad boot-default "default '$defl' names $kbase / ${fpath##*/} but the file is missing or empty - no proven boot"
fi
if [ -s /boot/vmlinuz-fallback ] && [ -s /boot/sdm632-fairphone-fp3.dtb-fallback ]; then
	ok boot-fallback "vmlinuz-fallback and dtb-fallback both present and non-empty"
else
	bad boot-fallback "the fallback kernel or dtb is missing - there is no way back"
fi

# --- 3. power ----------------------------------------------------------------
# ☠️ USBIN_SUSPEND_BIT lives in the PMIC and survives a warm reboot. A leg that
# died without restoring it leaves a phone that silently will not charge, and
# the next night starts from a pack that only falls.
online=$(f $CHG/online); cstat=$(f $CHG/status)
if [ "$online" = 1 ]; then
	ok charger "online=1 status=$cstat"
elif [ "$NOCABLE" = 1 ]; then
	note charger "online=$online status=$cstat - cable declared OUT; USBIN state unverifiable until replug (restore paths unchanged)"
else
	bad charger "online=$online status=$cstat - USBIN may still be suspended from an earlier leg"
fi

cap=$(f $BAT/capacity); volt=$(f $BAT/voltage_now); cur=$(f $BAT/current_now)
if [ "${cap:-0}" -ge "$MINCAP" ] 2>/dev/null; then
	ok battery "capacity=${cap}% voltage=${volt}"
else
	bad battery "capacity=${cap}% is under ${MINCAP}% - charge before arming"
fi
note battery-current "current_now=$cur (one read; ±138 mA scatter, never trust a single sample)"

temp=$(f $BAT/temp)
case "$temp" in
''|'?') note battery-temp "unreadable" ;;
*) if [ "$temp" -lt 450 ] 2>/dev/null; then ok battery-temp "${temp} (dC)"
   else bad battery-temp "${temp} (dC) - too hot to start a night"; fi ;;
esac

# --- 4. nothing else may be on the device ------------------------------------
# Phase A measures suspends; another script waking the phone a minute would be
# measuring the instrument. This is the check that the 2026-08-19 legs needed.
stale=''
# ☠️ night-queue and night-guardian are deliberately NOT in this list. The queue
# runs this gate as its own first step, so listing it here made the check fail on
# itself - measured 2026-08-19, first armed night, aborted in 20 seconds. A gate
# has to exclude the thing that is asking.
for u in slope slope-dryrun await-charge idle-ladder freq-probe de-compare episode-watch rail-census; do
	if systemctl is-active --quiet "$u" 2>/dev/null; then stale="$stale $u"; fi
done
if [ -z "$stale" ]; then
	ok no-stale-units "no measurement unit is running"
else
	bad no-stale-units "still running:$stale"
fi

# --- 5. the instruments ------------------------------------------------------
# ☠️ rpm_master_stats is a module and nothing autoloads it. Without it the whole
# APSS column reads '?', which looks exactly like "the processor never
# collapsed" and is the opposite of what it means.
modprobe rpm_master_stats 2>/dev/null || true
if [ -r "$RPM/APSS" ]; then
	ok rpm-stats "$RPM/APSS readable"
else
	bad rpm-stats "no $RPM - modprobe rpm_master_stats failed"
fi

for s in vlow vmin; do
	if [ -r "/sys/kernel/debug/qcom_stats/$s" ]; then
		note "qcom_stats-$s" "Count: $(sed -n 's/^Count[[:space:]]*:[[:space:]]*//p' "/sys/kernel/debug/qcom_stats/$s" | head -1)"
	else
		bad "qcom_stats-$s" "missing"
	fi
done

# The counter-live check, which is the one that makes a convenient number
# believable: read three masters twice and require that at least two moved.
if [ -r "$RPM/APSS" ]; then
	m() { sed -n 's/^[[:space:]]*Shutdown count[[:space:]]*:[[:space:]]*//p' "$RPM/$1" 2>/dev/null | head -1; }
	a0=$(m APSS); b0=$(m MPSS); c0=$(m PRONTO); l0=$(m LPASS)
	sleep 20
	a1=$(m APSS); b1=$(m MPSS); c1=$(m PRONTO); l1=$(m LPASS)
	moved=0
	[ "${a1:-0}" -gt "${a0:-0}" ] 2>/dev/null && moved=$((moved + 1))
	[ "${b1:-0}" -gt "${b0:-0}" ] 2>/dev/null && moved=$((moved + 1))
	[ "${c1:-0}" -gt "${c0:-0}" ] 2>/dev/null && moved=$((moved + 1))
	if [ "$moved" -ge 2 ]; then
		ok counters-live "over 20 s: APSS +$((a1 - a0)) MPSS +$((b1 - b0)) PRONTO +$((c1 - c0)) LPASS +$((l1 - l0))"
	else
		bad counters-live "only $moved masters moved in 20 s - the file may be stuck"
	fi
fi

# --- 6. suspend --------------------------------------------------------------
# ☠️ There is no 'deep' on this platform; mem_sleep offers s2idle only. A night
# plan that waits for 'deep' to appear waits forever.
ms=$(f /sys/power/mem_sleep)
case "$ms" in
*s2idle*) ok mem-sleep "$ms" ;;
*) bad mem-sleep "'$ms' has no s2idle" ;;
esac
note suspend-stats "success=$(f /sys/power/suspend_stats/success) fail=$(f /sys/power/suspend_stats/fail)"

# --- 7. the panel ------------------------------------------------------------
# ☠️ backlight = 0 is not dpms off. A panel at zero brightness is still powered,
# and it was worth +24.5 mA of every floor measured before 2026-08-19.
dp=$(f /sys/class/drm/card0/card0-DSI-1/dpms)
if [ -w /sys/class/drm/card0/card0-DSI-1/dpms ]; then
	ok dpms "writable, currently $dp"
else
	bad dpms "/sys/class/drm/card0/card0-DSI-1/dpms not writable - cannot dark the panel"
fi

# --- 8. did the card already complain this boot -------------------------------
if dmesg 2>/dev/null | grep -qE 'mmc0: (cache flush error|mmc_hs400_to_hs200 failed)|mmcblk0: recovery failed'; then
	bad mmc-clean "the eMMC has already errored this boot - reboot before a long run"
else
	ok mmc-clean "no mmc error in dmesg this boot"
fi
note mmc-timing "$(sed -n 's/^timing spec:[[:space:]]*//p' /sys/kernel/debug/mmc0/ios 2>/dev/null | head -1)"

echo
if [ "$FAILED" -eq 0 ]; then
	echo "PREFLIGHT OK - the night may be armed"
	exit 0
fi
echo "PREFLIGHT FAILED - $FAILED gate(s); do not arm"
exit 1
