#!/bin/sh
# #142: does an i2c stall interrupt audio playback?  No human on either side.
#
# Sized to the MEASURED rate - 1 stall in 20 probes (5 %). Every earlier run was
# 3-8 probes, where a 5 % fault is absent 65-86 % of the time by chance, so all
# of those nulls were uninformative. 60 probes gives ~3 expected stalls.
#
# ☠️ Audio is judged by the PCM substream's `tstamp`, NOT by ear and NOT by
# hw_ptr - that field does not exist in this status file, and a parser for it
# would have returned nothing while the campaign ran, silently. tstamp was
# validated first against a known answer: 4.016 s of audio across 4 s of wall
# clock. If playback falters during a probe, tstamp advances by less than the
# wall time it spans.
#
# ☠️ Restore verifies AND acts. Twice today a stall left the chip unable to probe
# (-5), the rebind failed, and the phone sat with a dead touchscreen until a
# person noticed. If two rebinds fail here, this reboots the phone itself.
OUT=/home/fp3/142-full.txt
DT=/sys/bus/i2c/drivers/Himax-hx83112b-TS
P=/sys/devices/platform/soc@0/78b7000.i2c/power
ST=/proc/asound/card0/pcm0p/sub0/status
: > "$OUT"

atime()  { awk '/tstamp/{print $3; exit}' "$ST" 2>/dev/null; }
pstate() { awk '/^state/{print $2; exit}' "$ST" 2>/dev/null; }

restore() {
    echo auto > "$P/control" 2>/dev/null
    su fp3 -c 'XDG_RUNTIME_DIR=/run/user/10000 systemctl --user stop fp3-tone.service' 2>/dev/null
    echo 2-0048 > "$DT/bind" 2>/dev/null; sleep 3
    if [ -e /sys/bus/i2c/devices/2-0048/driver ]; then
        echo "== restore VERIFIED: touch bound $(date '+%H:%M:%S')" >> "$OUT"; return
    fi
    echo 2-0048 > "$DT/bind" 2>/dev/null; sleep 5
    if [ -e /sys/bus/i2c/devices/2-0048/driver ]; then
        echo "== restore VERIFIED on retry $(date '+%H:%M:%S')" >> "$OUT"
    else
        echo "== rebind failed twice - REBOOTING so the phone gets its touchscreen back" >> "$OUT"
        sync; (sleep 3; systemctl reboot) &
    fi
}
trap restore EXIT INT TERM

echo "== start $(date '+%F %H:%M:%S')  60 probes, 15 s idle, audio on" >> "$OUT"
su fp3 -c 'XDG_RUNTIME_DIR=/run/user/10000 systemd-run --user --unit=fp3-tone --collect speaker-test -D default -c 2 -t sine -f 440 -l 0' >> "$OUT" 2>&1
sleep 6
if [ "$(pstate)" != "RUNNING" ]; then
    echo "== ABORT: playback not RUNNING (state=$(pstate)); the audio question cannot be answered" >> "$OUT"
    exit 1
fi
echo "   playback CONFIRMED: state=$(pstate) tstamp=$(atime)" >> "$OUT"
echo 2-0048 > "$DT/unbind" 2>/dev/null; sleep 1
echo "   touch unbound: $([ -e /sys/bus/i2c/devices/2-0048/driver ] && echo STILL-BOUND || echo yes)" >> "$OUT"
echo auto > "$P/control"

i=1
while [ $i -le 60 ]; do
    sleep 15
    a0=$(atime); s0=$(date +%s)
    d=$(python3 /home/fp3/142-i2cprobe.py 2 0x50 0 1 2>&1 | sed -n 's/.*max \([0-9.]*\) s.*/\1/p')
    a1=$(atime); s1=$(date +%s); st=$(pstate)
    el=$((s1-s0))
    adv=$(python3 -c "print(round(${a1:-0}-${a0:-0},2))" 2>/dev/null)
    flag=""
    case "$d" in [1-9]*.*) flag="  <<< STALL";; esac
    if [ "$el" -ge 2 ]; then
        short=$(python3 -c "print(1 if ${adv:-0} < $el*0.9 else 0)" 2>/dev/null)
        [ "$short" = 1 ] && flag="$flag  <<< AUDIO SHORTFALL"
    fi
    echo "probe $i  dur=${d}s  wall=${el}s  audio_advanced=${adv}s  state=$st$flag" >> "$OUT"
    i=$((i+1))
done
echo "== done $(date '+%H:%M:%S')" >> "$OUT"
