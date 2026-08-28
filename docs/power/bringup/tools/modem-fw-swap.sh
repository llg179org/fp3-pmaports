#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Swap the modem firmware pmOS loads from its rootfs for the one the device's own
# modem partition carries, and back again.
#
#   modem-fw-swap.sh partition   # load the partition's build (oracle's, 325768)
#   modem-fw-swap.sh rootfs      # restore ours (425464) from the .bak
#   modem-fw-swap.sh state       # print which build is in place, change nothing
#
# ☠️☠️ 2026-08-28: DO NOT RUN THIS. There is nothing to swap. Both modem
# partitions and our rootfs copy carry the SAME build - modem_a, modem_b and
# /lib/firmware all say QC_IMAGE_VERSION_STRING=MPSS.TA.3.1.C1-425464 and
# GEN_PACK-1.356774.1.425464.1. The "325768" that made this look like a
# difference is the METABUILD number out of the partition's verinfo/ver_info.txt,
# package metadata written at flash time whose "modem" field mirrors
# Meta_Build_ID; our own image embeds that same string too, among a dozen other
# build strings, so grepping for it confirms the difference from either side.
# The script is kept because the next reader of ver_info.txt will have the same
# idea, and `modem-fw-swap.sh state` against both sides settles it in seconds.
#
# WHY IT WAS WRITTEN: the oracle's MPSS master is awake 6.3 % of the time and ours
# 34-36 %, an awake MPSS costs +91 mA measured two independent ways, and every
# Linux-side lever tried against that duty came back flat (mmcli --disable,
# ModemManager stop, iio-sensor-proxy stop: 36/34/34, 38/36/37, 36/39/36 %). The
# modem image is the last difference between the two systems that is not shared:
# RPM, TZ and the bootloader all come from the same 2021 SDM632.LA.2.1-00015
# partitions on both, and only the modem build differs, because pmOS loads its
# own copy from /lib/firmware instead of the partition.
#
# WHAT IT IS NOT: this writes nothing to any partition. It reads modem_b through
# a READ-ONLY mount and copies files into the rootfs. Rollback is a file copy.
#
# ☠️ qcom_mdt_load reads metadata from the file the DT names (modem.mbn) and then
# pulls modem.bNN from BESIDE it - so the split image's segments must be present
# and must match the header. Swapping only one of the two leaves an image whose
# header and segments disagree and the modem will not authenticate.
#
# ☠️ Do not run this with a measurement in flight, and record capacity and
# voltage_now before the reboot it needs: it is a new boot, so it is a new
# baseline.
set -u
F=/lib/firmware/qcom/msm8953/fairphone/fp3
BAK=$F/modem.mbn.425464bak
M=/tmp/.modemmnt

ver() {
	# The build string lives in the image as plain text; grep it out of whichever
	# file is currently in place rather than trusting a marker file we wrote.
	strings -a "$1" 2>/dev/null | sed -n 's/^QC_IMAGE_VERSION_STRING=//p' | head -1
}

state() {
	echo "modem.mbn      : $(ver $F/modem.mbn)"
	echo "  size         : $(stat -c %s $F/modem.mbn 2>/dev/null)"
	echo "  split segs   : $(ls $F/modem.b?? 2>/dev/null | wc -l)"
	[ -f "$BAK" ] && echo "rootfs .bak    : $(ver $BAK)" || echo "rootfs .bak    : (absent)"
	echo "mba.mbn size   : $(stat -c %s $F/mba.mbn 2>/dev/null)"
	echo "remoteproc     : $(cat /sys/class/remoteproc/remoteproc1/state 2>/dev/null)"
}

case "${1:-state}" in
state) state ;;

partition)
	[ -f "$BAK" ] && { echo "refusing: $BAK already exists - already swapped?"; exit 1; }
	mkdir -p "$M"
	mount -o ro /dev/disk/by-partlabel/modem_b "$M" || { echo "mount failed"; exit 1; }
	[ -f "$M/image/modem.mdt" ] || { echo "no modem.mdt on the partition"; umount "$M"; exit 1; }
	cp -a "$F/modem.mbn" "$BAK" || { umount "$M"; exit 1; }
	cp "$M"/image/modem.b* "$F"/ || { umount "$M"; exit 1; }
	cp "$M/image/modem.mdt" "$F/modem.mbn" || { umount "$M"; exit 1; }
	sync
	umount "$M"
	echo "swapped to the partition build; reboot to load it"
	state
	;;

rootfs)
	[ -f "$BAK" ] || { echo "refusing: no $BAK to restore from"; exit 1; }
	cp -a "$BAK" "$F/modem.mbn" || exit 1
	rm -f "$F"/modem.b??
	rm -f "$BAK"
	sync
	echo "restored the rootfs build; reboot to load it"
	state
	;;

*) echo "usage: $0 {partition|rootfs|state}"; exit 2 ;;
esac
