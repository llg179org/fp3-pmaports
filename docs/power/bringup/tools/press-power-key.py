#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Press the power key from software, via /dev/uinput.
#
# Why this exists. On the Ubuntu Touch oracle the screen cannot be taken down
# by any of the obvious routes, all measured 2026-08-25:
#   * it never blanks on its own - powerd's inactivity action is not set to
#     display-off, and NO inhibitor is held while it stays lit;
#   * com.canonical.Unity.Screen.setScreenPowerMode("off", r) answers `true`
#     for two of its reason codes and leaves the panel powered anyway;
#   * writing 4 to /sys/class/graphics/fb0/blank drops the MDSS clocks, but
#     the compositor undoes it within minutes AND the PMI632 LCDB bias rails
#     (lcdb_ldo / lcdb_ncp, both 5500 mV) stay enabled throughout - so the
#     panel is only half off, and the measurement is wrong in the expensive
#     direction.
# The one path that produces a real screen-off is the power key, because the
# compositor is the thing that has to agree, and that is what it listens to.
# So: synthesise the key rather than needing a human at the phone.
#
# ☠️☠️ MEASURED 2026-08-25, FIRST USE: THIS SCRIPT POWERED THE PHONE OFF.
# It sent one 120 ms tap and the phone shut down - RNDIS disconnected, the
# gadget came back as mass storage, and the phone sat on the offline-charging
# screen until a human held the hardware button. The cause is certain (nothing
# else happened in that second); the mechanism is not proven, and the most
# likely one is that the RELEASE was never seen: the compositor may bind a
# freshly created uinput device only after the press, and UI_DEV_DESTROY half a
# second later tears the device down with the key still logically held. A held
# power key is a long press, and a long press is a shutdown.
#
# So the fix below is: release, sync, and then wait a LONG time before
# destroying the device - and, because a stuck modifier is the failure mode,
# send the release twice. ☠️ This is a hypothesis-driven fix and it has NOT
# been validated. Do not run this unattended, and do not run it as part of a
# measurement leg, until one supervised run has shown the phone blanking its
# screen and staying up.
#
#   press-power-key.py            # one tap
import fcntl, struct, sys, time

UINPUT = "/dev/uinput"
UI_SET_EVBIT, UI_SET_KEYBIT = 0x40045564, 0x40045565
UI_DEV_CREATE, UI_DEV_DESTROY = 0x5501, 0x5502
EV_SYN, EV_KEY = 0x00, 0x01
SYN_REPORT, KEY_POWER = 0, 116

def emit(fd, typ, code, val):
    # struct input_event on 64-bit: timeval (2x s64) + u16 + u16 + s32
    fd.write(struct.pack("@llHHi", 0, 0, typ, code, val))
    fd.flush()

def main():
    try:
        fd = open(UINPUT, "wb", buffering=0)
    except PermissionError:
        sys.exit("need root for " + UINPUT)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
    fcntl.ioctl(fd, UI_SET_KEYBIT, KEY_POWER)
    # struct uinput_user_dev: char name[80] + input_id{u16 x4} + u32 ff_effects
    #                         + 4 x (ABS_CNT=64) s32 arrays
    name = b"fp3-power-key".ljust(80, b"\0")
    fd.write(name + struct.pack("@HHHHi", 0x03, 0x1234, 0x5678, 1, 0)
             + b"\0" * (4 * 64 * 4))
    fd.flush()
    fcntl.ioctl(fd, UI_DEV_CREATE)
    time.sleep(0.5)          # let udev and the compositor bind the new device
    emit(fd, EV_KEY, KEY_POWER, 1); emit(fd, EV_SYN, SYN_REPORT, 0)
    time.sleep(0.12)
    emit(fd, EV_KEY, KEY_POWER, 0); emit(fd, EV_SYN, SYN_REPORT, 0)
    time.sleep(0.2)
    # ☠️ Belt and braces: a release that is not seen reads as a held key, and a
    # held power key powers the phone off. Repeat it, then leave the device in
    # place long enough that nothing can miss it.
    emit(fd, EV_KEY, KEY_POWER, 0); emit(fd, EV_SYN, SYN_REPORT, 0)
    time.sleep(5.0)
    fcntl.ioctl(fd, UI_DEV_DESTROY)
    fd.close()

main()
