#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
"""Read, and optionally turn off, the modem's IMS service — the reversible lever.

    ims-toggle.py read | off | on          (ON THE DEVICE, touches the modem)

WHY
===
The modem raises an IMS PDN and tears it down again every ~8.4 s, forever
([`../captures/2026-09-02_diag-ota-pmos/`]). Every cycle needs an RRC connection,
so the UE never returns to RRC_IDLE — which is the whole 6.9 % vs 38 % duty gap.

The first intervention failed: an AP-held bearer on the same APN did not satisfy
whoever is asking (18 cycles in 90 s with the bearer up, against 22 in 120 s
without). So aim further upstream — at the IMS service itself.

`QMI_IMS` (the settings service) has `Set IMS Services Enabled Setting`, whose
input carries `ims_service_enabled`: the master switch. Unlike deleting profiles
or switching the PDC config, **this is reversible in one command**, which is why
it goes first.

☠️ It is an INTERACTION, and `off` changes what the modem does. Never run it
inside an undisturbed window, and always pair a duty measurement with the state
the switch was actually in - read it back, do not assume the write took.

☠️ **IMS off means no VoLTE and no IMS-routed calls.** On this device calls are
CSFB anyway (the IMS services have never registered), but say it out loud rather
than discover it during a call test.

☠️ Bind first. Every IMS read refuses on an unbound client, and the bind cannot
be done from qmicli over qrtr - the client ID dies with the process. Hence this
file; see ims-state.py for the same pattern against IMSA.
"""
import sys

import gi
gi.require_version("Qmi", "1.0")
gi.require_version("Qrtr", "1.0")
from gi.repository import Qmi, Qrtr, GLib   # noqa: E402

TIMEOUT = 15
loop = None
st = {"rc": 1, "dev": None, "client": None, "action": "read"}


def finish():
    d, c = st["dev"], st["client"]
    if d is not None and c is not None:
        try:
            d.release_client(c, Qmi.DeviceReleaseClientFlags.RELEASE_CID,
                             TIMEOUT, None, lambda *_: loop.quit())
            return
        except Exception:
            pass
    loop.quit()


def show(out):
    for label, g in (("registration", "get_ims_registration_service_enabled"),
                     ("voice", "get_ims_voice_service_enabled"),
                     ("VoWiFi", "get_ims_voice_wifi_service_enabled"),
                     ("video telephony", "get_ims_video_telephony_service_enabled"),
                     ("SMS", "get_ims_sms_service_enabled"),
                     ("UT", "get_ims_ut_service_enabled"),
                     ("USSD", "get_ims_ussd_service_enabled")):
        try:
            r = getattr(out, g)()
            print("  %-16s %s" % (label, r[1] if isinstance(r, tuple) else r))
        except Exception as e:
            print("  %-16s <not reported> (%s)" % (label, e))


def on_read(client, res, _):
    try:
        out = client.get_ims_services_enabled_setting_finish(res)
        out.get_result()
        print("IMS services enabled setting:")
        show(out)
        st["rc"] = 0
    except Exception as e:
        print("read failed: %s" % e)
    finish()


def on_write(client, res, _):
    try:
        out = client.set_ims_services_enabled_setting_finish(res)
        out.get_result()
        print("write accepted — reading it back (a write that is not read back "
              "is a hope, not a change)")
    except Exception as e:
        print("write failed: %s" % e)
    client.get_ims_services_enabled_setting(None, TIMEOUT, None, on_read, None)


def on_bind(client, res, _):
    try:
        client.bind_finish(res).get_result()
        print("bound to IMS")
    except Exception as e:
        print("bind refused: %s" % e)
    if st["action"] == "read":
        client.get_ims_services_enabled_setting(None, TIMEOUT, None, on_read, None)
        return
    # ☠️ The setter names and the getter names do NOT correspond one-to-one.
    # Measured 2026-09-02: set_ims_service_enabled(False) came back as
    # "UT: False" with voice, video and SMS still True. So set every switch
    # explicitly rather than trusting a master flag that may not be one.
    want = (st["action"] == "on")
    inp = Qmi.MessageImsSetImsServicesEnabledSettingInput.new()
    for setter in ("set_ims_service_enabled", "set_ims_voice_over_lte_enable",
                   "set_ims_video_telephony_service_enable",
                   "set_ims_sms_service_enable", "set_ims_ut_service_enable",
                   "set_ims_voice_wifi_service_enable",
                   "set_ims_ussd_service_enabled", "set_ims_presence_enabled",
                   "set_ims_rcs_enabled", "set_ims_xdm_client_enabled",
                   "set_ims_autoconfig_enabled"):
        try:
            getattr(inp, setter)(want)
        except Exception as e:
            print("  (%s not settable: %s)" % (setter, e))
    client.set_ims_services_enabled_setting(inp, TIMEOUT, None, on_write, None)


def on_client(dev, res, _):
    try:
        c = dev.allocate_client_finish(res)
    except Exception as e:
        print("allocate IMS client: %s" % e, file=sys.stderr)
        return finish()
    st["client"] = c
    inp = Qmi.MessageImsBindInput.new()
    inp.set_binding(0)
    c.bind(inp, TIMEOUT, None, on_bind, None)


def on_open(dev, res, _):
    try:
        dev.open_finish(res)
    except Exception as e:
        print("open: %s" % e, file=sys.stderr)
        return finish()
    dev.allocate_client(Qmi.Service.IMS, Qmi.CID_NONE, TIMEOUT, None,
                        on_client, None)


def on_device(src, res, _):
    try:
        dev = Qmi.Device.new_from_node_finish(res)
    except Exception as e:
        print("device: %s" % e, file=sys.stderr)
        return finish()
    st["dev"] = dev
    dev.open(Qmi.DeviceOpenFlags.NONE, TIMEOUT, None, on_open, None)


def on_bus(src, res, _):
    try:
        bus = Qrtr.Bus.new_finish(res)
    except Exception as e:
        print("qrtr bus: %s" % e, file=sys.stderr)
        return finish()
    node = bus.peek_node(0)
    if node is None:
        print("no qrtr node 0", file=sys.stderr)
        return finish()
    Qmi.Device.new_from_node(node, None, on_device, None)


def main(argv):
    global loop
    st["action"] = argv[1] if len(argv) > 1 else "read"
    if st["action"] not in ("read", "off", "on"):
        print(__doc__.strip()); return 2
    loop = GLib.MainLoop()
    Qrtr.Bus.new(1000, None, on_bus, None)
    GLib.timeout_add_seconds(60, lambda: (finish(), False)[1])
    loop.run()
    return st["rc"]


if __name__ == "__main__":
    sys.exit(main(sys.argv))
