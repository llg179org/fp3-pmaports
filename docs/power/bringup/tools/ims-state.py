#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
"""Read the modem's IMS state - the one thing `qmicli` cannot do over qrtr.

    ims-state.py            read it (RUNS ON THE DEVICE, touches the modem)
    ims-state.py --check    verify every symbol this needs exists, touch nothing

WHY A SCRIPT AND NOT qmicli
===========================
Every IMSA/IMS state query answers `InvalidOperation` until the client has been
BOUND, and binding cannot be done from qmicli on this transport:

  * a qrtr client ID belongs to the SOCKET, so it dies with the process that
    allocated it - `--client-no-release-cid` then `--client-cid=1` in a second
    qmicli gives "Unknown client 1 for service imsa";
  * and one qmicli process refuses to do both - "too many IMSA actions
    requested".

So bind and read have to happen on one client in one process. That is all this
file is. libqmi's GObject introspection is already installed here
(`Qmi-1.0.typelib`, `Qrtr-1.0.typelib`), so it needs no compiler.

WHAT IT IS FOR
==============
The leading explanation for this port's two modem power regimes is a retry with
exponential backoff inside the modem, and the reviewer's first candidate is the
modem's own IMS client retrying registration against a network our stack never
provisions it for. Whether that client is registered, retrying, or idle is the
reading that would decide it.

☠️ It is an INTERACTION with the modem. Never run it inside an undisturbed
window - it belongs before the window opens or after it closes.
"""
import sys

import gi
gi.require_version("Qmi", "1.0")
gi.require_version("Qrtr", "1.0")
from gi.repository import Qmi, Qrtr, GLib   # noqa: E402

TIMEOUT = 15
loop = None
state = {"rc": 1, "dev": None, "cid": None, "client": None}


def die(msg):
    print("error: %s" % msg, file=sys.stderr)
    finish()


def finish():
    # release the client if we got one, then stop
    d, c = state["dev"], state["client"]
    if d is not None and c is not None:
        try:
            d.release_client(c, Qmi.DeviceReleaseClientFlags.RELEASE_CID,
                             TIMEOUT, None, lambda *_: loop.quit())
            return
        except Exception:
            pass
    loop.quit()


def show_reg(out):
    print("IMS registration")
    try:
        ok, st = out.get_ims_registration_status()
        print("  registered: %s" % (ok and st))
    except Exception as e:
        print("  status: <not reported> (%s)" % e)
    for name, getter in (("technology", "get_ims_registration_technology"),
                         ("error code", "get_ims_registration_error_code"),
                         ("error message", "get_ims_registration_error_message")):
        try:
            r = getattr(out, getter)()
            print("  %s: %s" % (name, r[1] if isinstance(r, tuple) else r))
        except Exception:
            pass


def show_services(out):
    print("IMS services")
    for label, g in (("voice", "get_ims_voice_service_status"),
                     ("video telephony", "get_ims_video_telephony_service_status"),
                     ("video share", "get_ims_video_share_service_status"),
                     ("SMS", "get_ims_sms_service_status"),
                     ("UE-to-TAS", "get_ims_ue_to_tas_service_status")):
        try:
            r = getattr(out, g)()
            print("  %-16s %s" % (label, r[1] if isinstance(r, tuple) else r))
        except Exception as e:
            print("  %-16s <not reported> (%s)" % (label, e))


def on_services(client, res, _):
    try:
        out = client.get_ims_services_status_finish(res)
        out.get_result()
        show_services(out)
        state["rc"] = 0
    except Exception as e:
        print("IMS services: %s" % e)
    finish()


def on_reg(client, res, _):
    try:
        out = client.get_ims_registration_status_finish(res)
        out.get_result()
        show_reg(out)
        state["rc"] = 0
    except Exception as e:
        print("IMS registration: %s" % e)
    client.get_ims_services_status(None, TIMEOUT, None, on_services, None)


def on_bind(client, res, _):
    try:
        out = client.bind_finish(res)
        out.get_result()
        print("bound to IMSA")
    except Exception as e:
        # keep going: the read is the measurement, and a bind that refuses is
        # itself a result worth printing next to it
        print("bind refused: %s" % e)
    client.get_ims_registration_status(None, TIMEOUT, None, on_reg, None)


def on_client(dev, res, _):
    try:
        client = dev.allocate_client_finish(res)
    except Exception as e:
        return die("allocate IMSA client: %s" % e)
    state["client"] = client
    inp = Qmi.MessageImsaBindInput.new()
    inp.set_binding(0)
    client.bind(inp, TIMEOUT, None, on_bind, None)


def on_open(dev, res, _):
    try:
        dev.open_finish(res)
    except Exception as e:
        return die("open device: %s" % e)
    dev.allocate_client(Qmi.Service.IMSA, Qmi.CID_NONE, TIMEOUT, None,
                        on_client, None)


def on_device(src, res, _):
    try:
        dev = Qmi.Device.new_from_node_finish(res)
    except Exception as e:
        return die("create device: %s" % e)
    state["dev"] = dev
    # NONE, not PROXY: qrtr multiplexes clients natively, so this coexists with
    # a running ModemManager the way qmicli has all along. qmi-proxy is for
    # cdc-wdm, where the device node is exclusive, and asking for it here would
    # fail on a daemon that is not running.
    dev.open(Qmi.DeviceOpenFlags.NONE, TIMEOUT, None, on_open, None)


def on_bus(src, res, _):
    try:
        bus = Qrtr.Bus.new_finish(res)
    except Exception as e:
        return die("qrtr bus: %s" % e)
    node = bus.peek_node(0)
    if node is None:
        return die("no qrtr node 0 - is the modem up?")
    Qmi.Device.new_from_node(node, None, on_device, None)


def check():
    """Verify every symbol without creating a bus or touching the modem."""
    need = [
        (Qrtr.Bus, "new"), (Qrtr.Bus, "new_finish"), (Qrtr.Bus, "peek_node"),
        (Qmi.Device, "new_from_node"), (Qmi.Device, "new_from_node_finish"),
        (Qmi.Device, "open"), (Qmi.Device, "allocate_client"),
        (Qmi.Device, "release_client"),
        (Qmi.ClientImsa, "bind"), (Qmi.ClientImsa, "bind_finish"),
        (Qmi.ClientImsa, "get_ims_registration_status"),
        (Qmi.ClientImsa, "get_ims_services_status"),
        (Qmi.MessageImsaBindInput, "new"),
        (Qmi.MessageImsaBindInput, "set_binding"),
    ]
    bad = ["%s.%s" % (o.__name__, a) for o, a in need if not hasattr(o, a)]
    for const in ("CID_NONE",):
        if not hasattr(Qmi, const):
            bad.append("Qmi." + const)
    for enum, member in ((Qmi.Service, "IMSA"),
                         (Qmi.DeviceOpenFlags, "NONE"),
                         (Qmi.DeviceReleaseClientFlags, "RELEASE_CID")):
        if not hasattr(enum, member):
            bad.append("%s.%s" % (enum.__name__, member))
    if bad:
        print("MISSING: " + ", ".join(bad))
        return 1
    print("all symbols present - safe to run for real")
    return 0


def main(argv):
    global loop
    if len(argv) > 1 and argv[1] == "--check":
        return check()
    loop = GLib.MainLoop()
    Qrtr.Bus.new(1000, None, on_bus, None)
    GLib.timeout_add_seconds(60, lambda: (die("timed out"), False)[1])
    loop.run()
    return state["rc"]


if __name__ == "__main__":
    sys.exit(main(sys.argv))
