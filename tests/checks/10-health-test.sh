#!/bin/sh
# Description: the system booted cleanly and has room to work
#
# Deliberately narrow patterns. A broad grep (say, for "subsys") matches on a
# perfectly normal boot, and a check that cries wolf gets ignored - which is
# worse than not having it. Anything known-noisy goes in baseline/dmesg-allow.txt
# with a reason, so the allowlist stays reviewable.
#
# â ï¸ An allowlisted line is still printed, with its count. An allowlist that
# swallows its entries silently turns into the thing it was meant to prevent:
# the run reads green and nobody ever sees the fault again.

fail=0

# Strip comments before use: grep -f would otherwise treat every comment line in
# the baseline as a pattern of its own.
allow=$(mktemp)
grep -v '^[[:space:]]*\(#\|$\)' "$DEVICE_DIR/baseline/dmesg-allow.txt" >"$allow" 2>/dev/null || true
units=$(mktemp)
grep -v '^[[:space:]]*\(#\|$\)' "$DEVICE_DIR/baseline/failed-units.txt" >"$units" 2>/dev/null || true
trap 'rm -f "$allow" "$units" "$klog"' EXIT

# â ï¸ Read the journal, not the ring buffer. Every WARNING on this device prints
# a ~1.5kB module list, so a few hundred of them evict the whole early boot:
# measured 2026-08-16, dmesg's oldest surviving line was 13684s into a boot that
# was 14351s old, while journalctl -k -b still had all 299 warnings from the
# ninth second. A fault check reading dmesg would have been looking at the last
# eleven minutes of an eighty-minute boot and calling it "the kernel log".
klog=$(mktemp)
if journalctl -k -b --no-pager >"$klog" 2>/dev/null && [ -s "$klog" ]; then
	klog_src='journalctl -k -b'
else
	dmesg >"$klog" 2>/dev/null
	klog_src='dmesg'
fi

# WARNING: is in the list because it was not, and a WARN storm went unseen: 299
# instances of "apcs-cpu0-pll failed to enable!" from nine seconds after boot,
# through a full battery that reported this check green. A WARN is a kernel
# developer saying a case should not happen; the check has no business deciding
# it does not matter.
raw=$(grep -E 'Kernel panic|Oops|BUG:|rcu_sched self-detected|remoteproc.*(crash|fatal)|WARNING:' "$klog")
strip() { sed 's/^[A-Z][a-z][a-z] [ 0-9][0-9] [0-9:]* [^ ]* kernel: //; s/^\[[^]]*\] *//'; }

hits=$(printf '%s\n' "$raw" | { [ -s "$allow" ] && grep -vFf "$allow" || cat; } | grep . || true)
if [ -n "$hits" ]; then
	echo "FAIL: kernel log contains fault signatures ($klog_src):"
	printf '%s\n' "$hits" | strip | sort | uniq -c | sort -rn | head -10 | sed 's/^/  /'
	echo "      cmd: journalctl -k -b | grep -E 'Kernel panic|Oops|BUG:|WARNING:'"
	fail=1
else
	echo "PASS: no panic/oops/BUG/WARNING/remoteproc-crash outside the allowlist"
fi

if [ -s "$allow" ]; then
	tolerated=$(printf '%s\n' "$raw" | grep -Ff "$allow" | grep -c . || true)
	if [ "${tolerated:-0}" -gt 0 ]; then
		echo "INFO: $tolerated allowlisted fault line(s), still there:"
		printf '%s\n' "$raw" | grep -Ff "$allow" | strip |
			sort | uniq -c | sort -rn | head -5 | sed 's/^/        /'
	fi
fi

# Disk full has bitten this device twice: it aborts an apk upgrade halfway and
# leaves a version-skewed stack that then crashes somewhere unrelated.
used=$(df / | awk 'NR==2 {gsub("%","",$5); print $5}')
if [ "${used:-100}" -ge 98 ]; then
	echo "FAIL: rootfs ${used}% full - an upgrade here would break mid-way"
	fail=1
else
	echo "PASS: rootfs ${used}% used"
fi

# The device runs degraded today; the point is that it does not get *more*
# degraded, so compare against the recorded set rather than against zero.
failed=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | sort)
newly=$(printf '%s\n' "$failed" | { [ -s "$units" ] && grep -vxFf "$units" || cat; } | grep . || true)
if [ -n "$newly" ]; then
	echo "FAIL: systemd units failed that are not in the baseline:"
	printf '%s\n' "$newly" | sed 's/^/  /'
	fail=1
else
	echo "PASS: no systemd unit failed outside the recorded baseline"
fi

exit $fail
