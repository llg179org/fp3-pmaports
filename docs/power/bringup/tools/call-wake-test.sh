#!/bin/sh
# Does an incoming call raise this phone from suspend?
#
# ☠️ The existing probe-call.sh cannot answer this: it polls mmcli in a loop,
# which keeps the phone awake, so it can only observe a call the phone was
# already up for. This one puts the phone to sleep and reads, after the fact,
# WHICH wakeup source fired - the only evidence that distinguishes "the modem
# raised us" from "the RTC backstop expired".
#
# ☠️ MEASURED 2026-08-25, first run: this script's two chosen instruments BOTH
# came back empty on a call that demonstrably worked, and the journal is what
# proved it. Keep both corrections:
#
#   1. /sys/class/wakeup/*/wakeup_count does NOT attribute an s2idle wake. It
#      counts events announced with pm_wakeup_event(); an IRQ can break the
#      s2idle loop without announcing one, so every source read +0 while the
#      phone had plainly been raised. For s2idle the instrument is the
#      /proc/interrupts diff across the suspend, which is why it is taken here.
#   2. `mmcli --voice-list-calls` read immediately after resume is ONE SECOND
#      too early: the resume landed at 18:06:14 and the call object appeared at
#      18:06:15, so the script printed "No calls were found" about a call that
#      rang for the next 61 seconds. It now waits and re-reads.
#
#   call-wake-test.sh [backstop_seconds]
set -u
BACK=${1:-420}
OUT=/run/call-wake-test.txt

snap() {
	for d in /sys/class/wakeup/wakeup*; do
		[ -d "$d" ] || continue
		echo "$(cat $d/name 2>/dev/null) $(cat $d/wakeup_count 2>/dev/null) $(cat $d/event_count 2>/dev/null)"
	done
}

# The instrument that actually attributes an s2idle wake.
irqsnap() { awk 'NR>1 {s=0; for(i=2;i<=NF;i++) if ($i+0==$i) s+=$i; print $1, s, $NF}' /proc/interrupts; }

: > "$OUT"
{
echo "# call-wake-test backstop=${BACK}s uptime=$(cut -d' ' -f1 /proc/uptime)"
echo "# suspend_stats success=$(cat /sys/power/suspend_stats/success) fail=$(cat /sys/power/suspend_stats/fail)"
echo "# modem: $(mmcli -m any 2>/dev/null | sed -n 's/.*state: *//p' | head -1)"
echo "# backlight before: $(cat /sys/class/backlight/*/brightness 2>/dev/null | head -1) bl_power=$(cat /sys/class/backlight/*/bl_power 2>/dev/null | head -1)"
} >> "$OUT"
snap > /run/.wk0
irqsnap > /run/.irq0

T0=$(cut -d' ' -f1 /proc/uptime)
echo "# ---- going to sleep now, backstop ${BACK}s ----" >> "$OUT"
sync
rtcwake -m mem -s "$BACK" >> "$OUT" 2>&1
rc=$?
T1=$(cut -d' ' -f1 /proc/uptime)
snap > /run/.wk1
irqsnap > /run/.irq1

{
echo "# ---- awake ---- rtcwake rc=$rc"
echo "# uptime spanned: $(echo "$T1 $T0" | awk '{printf "%.1f", $1-$2}')s of a ${BACK}s backstop"
echo "# suspend_stats success=$(cat /sys/power/suspend_stats/success) fail=$(cat /sys/power/suspend_stats/fail)"
echo "# backlight after: $(cat /sys/class/backlight/*/brightness 2>/dev/null | head -1) bl_power=$(cat /sys/class/backlight/*/bl_power 2>/dev/null | head -1)"
echo "# WHICH SOURCE FIRED (name  d_wakeup_count  d_event_count) - nonzero only:"
paste /run/.wk0 /run/.wk1 | awk '{dw=$5-$2; de=$6-$3; if (dw!=0 || de!=0) printf "    %-46s +%-4d +%d\n", $1, dw, de}'
echo "# IRQs that fired across the suspend (the instrument that WORKS for s2idle):"
join /run/.irq0 /run/.irq1 2>/dev/null | awk '{d=$4-$2; if (d>0) printf "    %-8s +%-6d %s\n", $1, d, $5}' | sort -k2 -rn | head -12
echo "# calls seen by ModemManager (re-read after a settle - a call object can appear a second AFTER resume):"
sleep 5
mmcli -m any --voice-list-calls 2>&1 | head -5
echo "# journal, the evidence that actually proved it the first time:"
journalctl --since "-3min" --no-pager 2>/dev/null | grep -iE "call state changed|ringing" | tail -6
echo "# dmesg around the resume:"
dmesg | grep -E "PM: suspend (entry|exit)|wakeup|smd-edge" | tail -8
} >> "$OUT"
rm -f /run/.wk0 /run/.wk1 /run/.irq0 /run/.irq1
cat "$OUT"
