#!/bin/sh
# #178/#179 sampler.
#   epoch  touch_irqs  err110  err6  err5  qup_timeout  qup_cleared  qup_held  boot_id
#
# ☠️ Counts come from the JOURNAL, not dmesg: the -5 storm of 2026-09-05 wrote
# 156 lines/s and overwrote the ring buffer that held its own beginning.
# ☠️ The IRQ count is located BY NAME. The i2c bus number and the input node are
# handed out in probe order and both moved on this device in one afternoon.
# ☠️ /proc/interrupts and the boot_id are ALWAYS the CURRENT boot. When BOOT
# names a past one they print as "-", because putting them next to a past boot's
# error counts is a regime mix, not a datum.
#
# The three qup_ columns exist for #179 and only have values on r84 or later:
#   qup_timeout  "timed out, bus"      - i2c-qup saw a transfer time out
#   qup_cleared  "bus cleared after"   - the hardware bus-clear worked (dev_dbg,
#                                        so it only appears with dynamic debug on)
#   qup_held     "bus still held"      - it did not
set -u
B=${BOOT:--b}
if [ "$B" = "-b" ]; then
	irqs=$(awk '/hx83112b/{s=0; for(i=2;i<=NF-4;i++) s+=$i; print s+0; exit}' /proc/interrupts 2>/dev/null)
	: "${irqs:=0}"
	bid=$(cat /proc/sys/kernel/random/boot_id)
else
	irqs=-; bid=-
fi
J=$(journalctl -k $B -o cat --no-pager 2>/dev/null)
c() { printf '%s' "$J" | grep -c "$1"; }
printf '%s %s %s %s %s %s %s %s %s\n' "$(date +%s)" "$irqs" \
	"$(c 'Failed to read input event: -110')" \
	"$(c 'Failed to read input event: -6')" \
	"$(c 'Failed to read input event: -5')" \
	"$(c 'timed out, bus')" "$(c 'bus cleared after')" "$(c 'bus still held')" \
	"$bid"
