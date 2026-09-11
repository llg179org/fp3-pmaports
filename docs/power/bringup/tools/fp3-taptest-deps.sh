#!/bin/sh
# fp3-taptest-deps.sh -- root. (Re)start what the .O tap-test instrument depends
# on, so the app-grid icon brings up the whole measurement, not just the window:
#   1. fp3-kcontacts: the kernel-side contact logger on the touchscreen's CURRENT
#      event node (it changes after a driver rebind), writing /var/log/kernel-contacts.log
#   2. the himax kprobes, re-created against the live module (dead after a reload)
# Runs under a sudoers NOPASSWD rule limited to this file; keep it root-owned 0755.
NODE=$(ls /sys/bus/i2c/devices/2-0048/input/input*/ 2>/dev/null | grep -o 'event[0-9]*' | head -1)
[ -n "$NODE" ] || { echo "deps: no touchscreen event node - driver not bound?"; exit 1; }
systemctl stop fp3-kcontacts 2>/dev/null
systemd-run --unit=fp3-kcontacts --collect /usr/bin/python3 /home/fp3/armb/kernel-contacts.py /dev/input/$NODE /var/log/kernel-contacts.log >/dev/null 2>&1
sleep 0.5
KP=$([ -x /usr/local/bin/hx-kprobes.sh ] && /usr/local/bin/hx-kprobes.sh 2>/dev/null | head -1)
echo "deps: kcontacts $(systemctl is-active fp3-kcontacts) on /dev/input/$NODE; ${KP:-kprobes: script missing}"
