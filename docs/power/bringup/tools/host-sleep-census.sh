#!/bin/bash
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
# Sleep census read entirely from the HOST, touching nothing on the phone.
# The phone's USB gadget drops on suspend and re-enumerates on resume, within a
# second of the kernel's own PM: suspend entry/exit marks - so every
# disconnect/new pair on this machine is one sleep window, acquired for free and
# with zero observer effect. No ssh, no poll, no wake.
set -u
UP=$(cut -d. -f1 /proc/uptime); NOW=$(date +%s)
sudo dmesg | grep -oE '^\[ *[0-9]+\.[0-9]+\] usb 1-5: (USB disconnect|new high-speed)' \
| awk -v up="$UP" -v now="$NOW" '{
    match($0, /[0-9]+\.[0-9]+/); ts = substr($0, RSTART, RLENGTH) + 0;
    wall = now - up + ts;
    ev = ($0 ~ /disconnect/) ? "down" : "up";
    if (ev == "down") { d = wall } else if (d) { printf "%s  %s  %4d s asleep\n", strftime("%H:%M:%S", d), strftime("%H:%M:%S", wall), wall - d; d = 0 }
  }' | tail -"${1:-40}"
