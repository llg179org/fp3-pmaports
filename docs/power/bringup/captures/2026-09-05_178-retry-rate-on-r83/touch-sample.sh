#!/bin/sh
# #178 sampler: one line per call.
#   epoch  touch_irqs  err110  err6  err5  boot_id
#
# ☠️ Counts come from the JOURNAL, not dmesg: the -5 storm of 2026-09-05 wrote
# 156 lines/s and overwrote the ring buffer that held its own beginning.
# ☠️ The IRQ count is located BY NAME. The i2c bus number and the input node are
# handed out in probe order and both moved on this device in one afternoon.
# ☠️ /proc/interrupts and the boot_id are ALWAYS the CURRENT boot. When BOOT
# names a past one, they do not belong on the same line as its error counts -
# printing them anyway put 2671 next to r82's error totals in the very run that
# validated this script, which is a regime mix, not a datum. They print as "-".
set -u
B=${BOOT:--b}
if [ "$B" = "-b" ]; then
	irqs=$(awk '/hx83112b/{s=0; for(i=2;i<=NF-4;i++) s+=$i; print s+0; exit}' /proc/interrupts 2>/dev/null)
	: "${irqs:=0}"
	bid=$(cat /proc/sys/kernel/random/boot_id)
else
	irqs=-; bid=-
fi
c() { journalctl -k $B -o cat --no-pager 2>/dev/null | grep -c "Failed to read input event: -$1"; }
printf '%s %s %s %s %s %s\n' "$(date +%s)" "$irqs" "$(c 110)" "$(c 6)" "$(c 5)" "$bid"
