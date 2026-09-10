#!/bin/sh
# hx-kprobes.sh  -- root. (Re)arm the himax kprobes against the LIVE module.
# ☠️ Kprobes resolve module symbols at creation; after a module reload the old
# events keep their old addresses and count nothing while reporting "enabled"
# (measured 2026-09-11: hx_irq frozen at 113078 while /proc/interrupts advanced).
# Deployed as a file: the $retval inside an ssh argument string gets eaten.
T=/sys/kernel/debug/tracing
echo 0 > $T/events/kprobes/enable 2>/dev/null
echo > $T/kprobe_events
ok=0
for spec in 'p:kprobes/hx_irq himax_irq_handler' 'r16:kprobes/hx_irq_r himax_irq_handler ret=$retval' \
            'p:kprobes/hx_rd himax_read_events' 'r16:kprobes/hx_rd_r himax_read_events ret=$retval'; do
    if echo "$spec" >> $T/kprobe_events 2>/dev/null; then ok=$((ok+1)); else echo "  not armed: $spec"; fi
done
echo 1 > $T/events/kprobes/enable
echo "armed $ok events; enable=$(cat $T/events/kprobes/enable)"; cat $T/kprobe_profile
