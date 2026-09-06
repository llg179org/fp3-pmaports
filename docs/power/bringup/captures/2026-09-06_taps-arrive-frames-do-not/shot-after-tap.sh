#!/bin/sh
# Does the COMPOSITOR hold the frame the operator cannot see?
#
# The app draws within ~1 ms of every tap (measured, median 1.0 ms over 122
# taps), so the client is not the problem. This grabs the compositor's output
# 2 s after a tap that FOLLOWS a quiet period, and records the log's mark count
# at that moment. A current image => the panel is stale; a stale image => the
# compositor is.
#
# ☠️ The first version required the tap to be isolated on BOTH sides and caught
# nothing: in that window the operator tapped every 0.28 s. This one triggers on
# the leading edge of a quiet period and records contamination instead of
# refusing to fire.
set -u
export XDG_RUNTIME_DIR=/run/user/10000 WAYLAND_DISPLAY=wayland-0
LOG=/home/fp3/taptest.log
OUT=/home/fp3/shots
mkdir -p "$OUT"; rm -f "$OUT"/*.png "$OUT"/index.txt
: > "$OUT/index.txt"

marks() { c=$(grep -cE '^[0-9:.]+  [.o]  #' "$LOG"); echo "${c:-0}"; }

last=$(marks)
quiet=0            # polls with no new tap
n=0
end=$(( $(date +%s) + 420 ))
while [ "$(date +%s)" -lt "$end" ] && [ "$n" -lt 12 ]; do
    cur=$(marks)
    if [ "$cur" -gt "$last" ]; then
        if [ "$quiet" -ge 7 ]; then          # >= ~2 s of silence before it
            sleep 2
            after=$(marks)
            n=$((n+1))
            grim "$OUT/shot$n.png" 2>>"$OUT/index.txt"
            echo "shot$n  $(date +%H:%M:%S)  marks_at_tap=$cur  marks_now=$after  contaminated=$([ "$after" -eq "$cur" ] && echo no || echo yes)  line: $(grep -E '^[0-9:.]+  [.o]  #' "$LOG" | tail -1)" >> "$OUT/index.txt"
            cur=$after
        fi
        last=$cur
        quiet=0
    else
        quiet=$((quiet+1))
    fi
    sleep 0.3
done
echo "done, $n shots" >> "$OUT/index.txt"
