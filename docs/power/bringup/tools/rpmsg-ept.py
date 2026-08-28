#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Open an rpmsg channel by name and get a /dev/rpmsgN for it.
#
#   rpmsg-ept.py /dev/rpmsg_ctrlN <CHANNEL> [src] [dst]
#
# Written to reach the modem's DIAG channel on mainline, where all seven DIAG
# rpmsg devices sit UNBOUND because no in-tree driver claims them.
#
# ☠️ The sysfs door does not work: writing the device name into
# /sys/bus/rpmsg/drivers/rpmsg_chrdev/bind fails. The channel is opened through
# the CONTROL device with RPMSG_CREATE_EPT_IOCTL.
#
# ☠️ The control index does NOT follow the remoteproc index. Map them before
# guessing:
#     for c in /sys/class/rpmsg/rpmsg_ctrl*; do
#         echo "$(basename $c) -> $(readlink -f $c/device)"
#     done
# On this device the modem (remoteproc0) is /dev/rpmsg_ctrl3.
#
# ☠️ Needs CONFIG_RPMSG_CTRL, which is not implied by CONFIG_RPMSG_CHAR. Shipped
# from linux-fp3 r78.
#
# ☠️ Nothing arrives on DIAG unprompted - it is request/response, so a reader on
# the new node stays at zero bytes until the logging masks are set.
import fcntl, struct, sys, os
# struct rpmsg_endpoint_info { char name[32]; __u32 src; __u32 dst; }
RPMSG_CREATE_EPT_IOCTL = 0x4028B501
dev, name = sys.argv[1], sys.argv[2]
src = int(sys.argv[3]) if len(sys.argv) > 3 else 0xFFFFFFFF
dst = int(sys.argv[4]) if len(sys.argv) > 4 else 0xFFFFFFFF
buf = struct.pack('32sII', name.encode(), src, dst)
fd = os.open(dev, os.O_RDWR)
try:
    fcntl.ioctl(fd, RPMSG_CREATE_EPT_IOCTL, buf)
    print("ok")
except OSError as e:
    print("ioctl failed:", e)
finally:
    os.close(fd)
