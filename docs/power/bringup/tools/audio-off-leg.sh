#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# What does the audio stack cost, in mA — the one measurement the LPASS story was
# never able to make.
#
#   audio-off-leg.sh set | clear | state | measure [window_s]
#
# WHY IT EXISTS. "The LPASS never sleeps" is caused by our audio boot path (proven
# 2026-08-21 by blacklist bisection: with the card, the digital codec, wcd9335 and
# the SLIMbus NGD controller all blocked, the ADSP enters XO shutdown ~75 s into
# boot and stays there). Its price was then measured by stopping the ADSP through
# remoteproc — floor 52.9 / 56.3 / 54.6 mA across A-B-A′, i.e. stopping it *costs*
# ~2 mA. But that is not the same experiment: it prices the ADSP being down, not
# the audio stack being absent, and the honest statement it supports is only "the
# audio stack running is not expensive".
#
# The question this settles is whether the audio series has to wait for the power
# work before it goes upstream. So the leg has to be the real one: a boot with the
# audio modules never loaded, against a boot with them loaded.
#
# ☠️ THE NGD MODULE IS NOT CALLED WHAT THE SOURCE FILE IS CALLED. `qcom-ngd-ctrl.c`
# builds into `slim-qcom-ngd-ctrl.ko`, so `lsmod` shows `slim_qcom_ngd_ctrl`; a
# rule written against `qcom_ngd_ctrl` matches nothing and the leg silently keeps
# the module it meant to remove. Read the Makefile, not the filename.
#
# ☠️ A PLAIN `blacklist` LINE DOES NOT WORK. It only stops loading by alias; a
# dependency load by name goes through anyway. `install <mod> /bin/false` is the
# form that holds, measured 2026-08-21.
#
# ☠️ THIS LEG CANNOT BE RUN INSIDE ONE BOOT, which is the rule everything else
# here obeys, so it needs its own control: run A, B, A′ as three boots and read
# the FLOOR (p10), not the median. The median carries the modem's per-boot offset
# of up to 15 duty points ≈ 20 mA; the floor has read 53-54 mA across every leg of
# every knob so far regardless of duty, so it is the column that can cross a
# reboot. Quote the median only with its own A and A′ around it.
#
# ☠️ THE LEG NEEDS A WITNESS, AND IT IS **NOT** THE LPASS — corrected before the
# first run, by reading the phone instead of the story. The plan was to require
# the ADSP to be asleep in the B leg. Measured 2026-08-29 16:30 on r79 with the
# FULL audio stack loaded (4 of 4 modules, one card): LPASS `enter` newer than
# `exit`, `Active cores bitmask: 0x0`, counters static across 20 s, and XO-off for
# **99.7 %** of a 3.1 h uptime. The ADSP already sleeps with audio up, so that
# condition is satisfied in the A leg too and separates nothing.
#
# The witness is therefore the thing the knob actually changes: **zero of the four
# modules loaded and zero sound cards**. The LPASS is still recorded in every leg,
# because whether it sleeps is now a question this run answers rather than assumes.
#
# ☠️ That reading also contradicts the 2026-08-28 matched pair, which had the LPASS
# awake 100 % of a 600 s window with `XO total duration` of literally 0. Both are
# single boots. Treat "does the ADSP sleep" as a per-boot property until a run with
# its own control says otherwise — the same discipline the modem duty needed.
#
# ☠️ Recovery: this writes /etc/modprobe.d only, so `clear` plus a reboot undoes
# it, and a phone that will not boot is recoverable through the Ubuntu Touch
# loop-mount route (fp3-kernel-test references/recovery.md). Audio does not come
# back without a reboot even after `clear`: wcd9335 has historically not freed its
# SLIM slave IRQ on teardown.
set -u
CONF=/etc/modprobe.d/fp3-audio-off.conf
MODS="snd_soc_apq8016_sbc snd_soc_msm8916_digital snd_soc_wcd9335 slim_qcom_ngd_ctrl"
RPM=/sys/kernel/debug/qcom_rpm_master_stats

usage(){ echo "usage: $0 set|clear|state|measure [window_s]" >&2; exit 2; }
[ $# -ge 1 ] || usage

lpass_down(){
	# The success signature, and the trap that goes with it: a static counter is
	# ambiguous. "Count stopped growing" means frozen AWAKE unless the last
	# XO-enter is NEWER than the last XO-exit. Read both, never the count alone.
	en=$(sed -n 's/.*XO shutdown enter @ *//p' "$RPM/LPASS" 2>/dev/null | head -1)
	ex=$(sed -n 's/.*XO shutdown exit @ *//p'  "$RPM/LPASS" 2>/dev/null | head -1)
	case "$en$ex" in ''|*[!0-9]*) echo unknown; return ;; esac
	[ "$en" -gt "$ex" ] && echo down || echo up
}

case $1 in
set)
	{
		echo "# written by audio-off-leg.sh - one leg of a power measurement"
		echo "# remove this file and reboot to restore audio"
		for m in $MODS; do echo "install $m /bin/false"; done
	} > "$CONF"
	echo "wrote $CONF:"; cat "$CONF"
	echo "☠️ reboot for it to take effect, then: $0 measure"
	;;
clear)
	rm -f "$CONF" && echo "removed $CONF - reboot to restore audio"
	;;
state)
	[ -f "$CONF" ] && echo "blacklist: PRESENT" || echo "blacklist: absent"
	echo "loaded: $(lsmod | awk '{print $1}' | grep -cE '^(snd_soc_apq8016_sbc|snd_soc_msm8916_digital|snd_soc_wcd9335|slim_qcom_ngd_ctrl)$') of 4"
	echo "cards: $(cat /proc/asound/cards 2>/dev/null | grep -c '^ *[0-9]')"
	echo "LPASS: $(lpass_down)"
	;;
measure)
	W=${2:-360}
	modprobe rpm_master_stats 2>/dev/null
	n=$(lsmod | awk '{print $1}' | grep -cE '^(snd_soc_apq8016_sbc|snd_soc_msm8916_digital|snd_soc_wcd9335|slim_qcom_ngd_ctrl)$')
	l=$(lpass_down)
	if [ -f "$CONF" ]; then
		leg=B
		# ☠️ The witness, not the module list: a B boot whose ADSP stayed awake
		# has not applied the knob and must not be labelled as if it had.
		[ "$n" -eq 0 ] || { echo "☠️ STOP: leg B but $n audio modules are loaded"; exit 1; }
		c=$(grep -c '^ *[0-9]' /proc/asound/cards 2>/dev/null || echo 0)
		[ "$c" -eq 0 ] || { echo "☠️ STOP: leg B but $c sound cards are present - the knob did not take"; exit 1; }
	else
		leg=A
		[ "$n" -eq 4 ] || echo "⚠️ leg A with only $n of 4 audio modules loaded - note it"
	fi
	O=/var/log/fp3/audiooff-$leg-$(date +%s)
	mkdir -p "$O"
	{
		echo "# audio-off-leg $(date '+%F %T') leg=$leg window=${W}s"
		echo "# kernel=$(uname -r) $(uname -v)"
		echo "# audio modules loaded: $n of 4   LPASS: $l   cards: $(grep -c '^ *[0-9]' /proc/asound/cards 2>/dev/null)"
		echo "# uptime=$(cut -d. -f1 /proc/uptime)s  cap=$(cat /sys/class/power_supply/pmi632-battery/capacity)%"
	} | tee "$O/log"
	/usr/local/bin/burst-master.sh "$W" >/dev/null 2>&1
	d=$(ls -dt /var/log/fp3/burst-master-* | head -1)
	cp -r "$d" "$O/data"
	echo "# leg $leg -> $O/data ($(grep -vc '^#' "$O/data/master.txt") samples)" | tee -a "$O/log"
	echo "# $O" | tee -a "$O/log"
	;;
*) usage ;;
esac
