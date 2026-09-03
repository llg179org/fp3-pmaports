#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# HOST side. Watches a night from outside the device and, above all, gets the
# record off the phone while the phone is still able to hand it over.
#
# It does three things the device cannot do for itself:
#
#   1. It PULLS. Everything the night writes lives on tmpfs, which is exactly
#      what a reboot destroys - and the guardian's response to a dead card IS a
#      reboot. So the evidence has to be copied to the host on every poll, not
#      collected in the morning.
#   2. It notices silence. The device cannot report that it stopped answering.
#   3. It tries both links. WiFi is the survivable one; USB survives a WiFi
#      collapse. Either one alone has failed on this device before.
#
# ☠️ It never runs pmbootstrap and never touches the boot configuration. A
# supervisor that builds is a supervisor that competes with the thing it watches.
#
#   night-supervisor.sh <tag> [poll_s] [max_h]
#
# Writes to docs/power/night/runs/<tag>/ on the host: a timeline, plus a mirror
# of /run/night refreshed every poll.

set -u

TAG=${1:?usage: night-supervisor.sh <tag> [poll_s] [max_h]}
POLL=${2:-300}
MAX_H=${3:-14}

HOSTDIR=$(cd "$(dirname "$0")" && pwd)/runs/$TAG
mkdir -p "$HOSTDIR"
TL=$HOSTDIR/timeline.txt

WIFI=192.168.x.x
USB=172.16.42.1
SSHOPT="-o ConnectTimeout=8 -o StrictHostKeyChecking=no -o BatchMode=yes"

log() { printf '%s %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$TL"; }

# Return the first address that answers, or nothing.
link() {
	for ip in $WIFI $USB; do
		if timeout 15 ssh $SSHOPT "fp3@$ip" true 2>/dev/null; then echo "$ip"; return 0; fi
	done
	return 1
}

log "# supervisor $TAG start poll=${POLL}s max=${MAX_H}h -> $HOSTDIR"

t0=$(date +%s)
down=0
seen_active=0

while :; do
	now=$(date +%s)
	if [ "$(( (now - t0) / 3600 ))" -ge "$MAX_H" ]; then
		log "# max ${MAX_H}h reached, exiting"
		break
	fi

	if ip=$(link); then
		[ "$down" -gt 0 ] && log "# device answered again on $ip after $down missed poll(s)"
		down=0
		state=$(timeout 25 ssh $SSHOPT "fp3@$ip" '
			printf "up=%s q=%s g=%s cap=%s v=%s chg=%s root=%s\n" \
			  "$(cut -d. -f1 /proc/uptime)" \
			  "$(systemctl is-active night-queue 2>/dev/null)" \
			  "$(systemctl is-active night-guardian 2>/dev/null)" \
			  "$(cat /sys/class/power_supply/pmi632-battery/capacity 2>/dev/null)" \
			  "$(cat /sys/class/power_supply/pmi632-battery/voltage_now 2>/dev/null)" \
			  "$(cat /sys/class/power_supply/pmi632-charger/status 2>/dev/null)" \
			  "$(awk "\$2==\"/\" {print \$4}" /proc/mounts | cut -d, -f1)"
			tail -1 /run/night/queue.log 2>/dev/null' 2>/dev/null)
		log "$ip $(echo "$state" | tr '\n' ' | ')"

		# ☠️ Pull every poll. The guardian reboots on a dead card and tmpfs
		# does not survive that; anything not already on the host is gone.
		timeout 60 scp $SSHOPT -q "fp3@$ip:/run/night/*" "$HOSTDIR/" 2>/dev/null || true

		# The end condition is the queue's own last line, not the unit
		# state. A supervisor started after the queue ended would otherwise
		# never see it active and would poll until its own deadline.
		case "$state" in
		*'q=active'*) seen_active=1 ;;
		esac
		if grep -q 'QUEUE FINISHED' "$HOSTDIR/queue.log" 2>/dev/null; then
			log "# the queue reported itself finished - pulling once more and exiting"
			timeout 120 scp $SSHOPT -q "fp3@$ip:/run/night/*" "$HOSTDIR/" 2>/dev/null || true
			break
		fi
	else
		down=$((down + 1))
		log "!! device unreachable on both links (miss $down)"
		# Three misses at the default poll is a quarter of an hour of
		# silence: either a reboot that did not come back, or a link that
		# needs the morning. Keep polling - it may return - but say so
		# once, loudly, so the morning does not have to read the whole log.
		[ "$down" = 3 ] && log "!! ALERT: silent for $down polls (~$((down * POLL / 60)) min)"
	fi

	sleep "$POLL"
done

log "# supervisor $TAG done; artefacts in $HOSTDIR"
ls -la "$HOSTDIR" | tee -a "$TL"
