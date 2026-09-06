#!/bin/sh
# Does the touchscreen lose taps right after the screen comes back?
#
# THE TRIGGER, reported by the operator 2026-09-06: power button off, power
# button on, then the first taps are dropped - a PIN digit not taken, digits
# missing in the calculator. That is the #142 screen gate seen from the user's
# side: "screen OFF" and "touch after resume" are two of its three measured
# gates.
#
# ☠️ WHY THIS IS SEMI-AUTOMATIC AND CANNOT BE OTHERWISE. The stimulus has to be
# a real finger. A uinput injector would deliver events straight into the input
# layer, bypassing the touch controller and the i2c bus - the very things under
# test - so it would pass unconditionally and prove nothing. The phone buzzes to
# say when to tap; the operator taps; everything else is measured.
#
# ☠️ IT INTERLEAVES A CONTROL. "Some taps were lost after resume" means nothing
# without "and this many were lost when the screen never went off". Both arms
# wait the same wall time, so only the screen state differs - the same shape as
# 142-trigger.sh, which is what made its 5/5 against 0/5 believable.
#
# ☠️ It NEVER unbinds the driver. The unbind reproducer needs the driver gone,
# which is not how the operator's fault happens, and a userspace probe on the
# same bus once wedged the controller into 1824 consecutive EIO and cost two
# reboots. Nothing here touches the bus.
#
# Measured at the INPUT LAYER, so it does not matter what is on the screen - a
# lock screen, the calculator, anything. A press is a press.
set -u
ROUNDS=${ROUNDS:-4}
BLANK=${BLANK:-15}          # >= the measured ~10 s idle gate
TAPS=${TAPS:-10}            # tap exactly this many times per window
WINDOW=${WINDOW:-12}
LOG=/home/fp3/142-gaps.txt

DB=$(tr '\0' '\n' < /proc/$(pgrep -x phosh | head -1)/environ 2>/dev/null |
     grep '^DBUS_SESSION_BUS_ADDRESS=' | cut -d= -f2-)
[ -n "$DB" ] || { echo "FATAL: no phosh session bus"; exit 1; }
[ -r "$LOG" ] || { echo "FATAL: $LOG missing - is fp3-touch-gaps running?"; exit 1; }
as_user() { su fp3 -c "DBUS_SESSION_BUS_ADDRESS='$DB' $1" >/dev/null 2>&1; }
screen()  { as_user "gdbus call --session --dest org.gnome.ScreenSaver \
              --object-path /org/gnome/ScreenSaver \
              --method org.gnome.ScreenSaver.SetActive $1"; }
dpms()    { cat /sys/class/drm/card0/card0-DSI-1/dpms 2>/dev/null; }
buzz()    { as_user "timeout 2 fbcli -E $1 -t 1"; }

irqs()    { awk '/hx83112b/{s=0; for(i=2;i<=NF-4;i++) s+=$i; print s+0; exit}' /proc/interrupts; }
presses() { grep -c 'PRESS' "$LOG"; }
kerr()    { journalctl -k -b -o cat --no-pager 2>/dev/null |
            grep -cE 'Failed to read input event|timed out, bus|Disabling IRQ|consecutive failed'; }

printf '=== resume-vs-control tap test  %s\n' "$(date '+%F %T')"
printf '=== %d rounds, blank %ds, %d taps per window of %ds\n\n' "$ROUNDS" "$BLANK" "$TAPS" "$WINDOW"
printf 'TAP %d TIMES when it buzzes ONCE. Stop at the DOUBLE buzz.\n' "$TAPS"
printf 'While the screen is dark, do NOT touch it - that would wake it early.\n\n'
printf '%-3s %-7s %-9s %5s %5s %6s %7s %s\n' rnd arm dark-\>lit taps lost irqs irq/tap kerr

r=1
while [ "$r" -le "$ROUNDS" ]; do
  for arm in RESUME CONTROL; do
    if [ "$arm" = RESUME ]; then screen true; else screen false; fi
    sleep 3
    # ☠️ VERIFY THE ARM ACTUALLY HAPPENED, DURING the blank and not after it.
    # Reading dpms once the screen is back says "On" in both arms and proves
    # nothing; a SetActive that silently failed would make RESUME identical to
    # CONTROL and the test would report "no difference" for the wrong reason.
    # 142-trigger.sh skips a round for exactly this, which is why its 5/5 vs 0/5
    # could be believed.
    mid=$(dpms)
    want=$( [ "$arm" = RESUME ] && echo Off || echo On )
    if [ "$mid" != "$want" ]; then
        printf '%-3s %-7s %-6s %5s %5s %6s %7s %s\n' \
               "$r" "$arm" "$mid" SKIP "wanted=$want" - - -
        [ "$arm" = RESUME ] && screen false
        continue
    fi
    sleep $((BLANK - 3))
    [ "$arm" = RESUME ] && screen false
    sleep 2                                   # let the panel settle either way
    got="$mid->$(dpms)"

    i0=$(irqs); p0=$(presses); e0=$(kerr)
    buzz button-pressed
    sleep "$WINDOW"
    buzz window-close; sleep 0.3; buzz window-close
    i1=$(irqs); p1=$(presses); e1=$(kerr)

    taps=$((p1 - p0)); lost=$((TAPS - taps)); di=$((i1 - i0)); de=$((e1 - e0))
    if [ "$taps" -gt 0 ]; then ipt=$((di / taps)); else ipt=0; fi
    printf '%-3s %-7s %-9s %5s %5s %6s %7s %s\n' "$r" "$arm" "$got" "$taps" "$lost" "$di" "$ipt" "$de"
  done
  r=$((r + 1))
done

echo
echo "=== done $(date '+%F %T') ==="
echo "lost < 0 means more presses than asked for - a double tap, not a fault."
