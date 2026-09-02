#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
"""Hold the modem's IMS service switches where we want them — a reconciler, not a setter.

    fp3-ims-reconcile.py [off|on]          default off

Prints one line per run to stdout, which under systemd means the journal, so the
history of "when did it drift and how often" accumulates for free.
Exit 0 = the vector matches what we asked for. Exit 1 = it does not, after all
attempts; say so loudly rather than leaving a caller to assume.

WHY A RECONCILER AND NOT A BOOT ONE-SHOT
========================================
The modem raises an IMS PDN and tears it down again every 8.4 s forever, which
holds the UE in RRC_CONNECTED and costs ~44 pp of modem duty (measured three
times: 44.5→4.8, 45.6→asleep, 48.0→4.4). Switching every IMS service off stops
it dead, and on this network costs nothing: the phone still rings, answers,
carries audio both ways and receives SMS over the CS path.

☠️ BUT THE SETTING DOES NOT SURVIVE A REBOOT. Measured 2026-09-02: after a
system reboot, before any write, the original vector was back. (It *does*
survive a modem firmware restart — but that test ran in a degraded environment
where ModemManager had not enumerated the modem for an hour, so nothing was
there to rewrite it. Weak evidence for a strong claim.) Without something that
re-asserts it, every reboot silently restores the expensive configuration.

☠️ AND ORDERING CANNOT FIX IT. `After=ModemManager.service` is not enough:
"the daemon started" and "the daemon finished initialising the modem" are
different moments — MM probes asynchronously and the modem object appears tens
of seconds later, and whatever re-applies the defaults may run later still. So
this does not try to win a race. It converges: read, compare, write, READ BACK,
retry with backoff, and let a timer run it again.

☠️ EVERY SWITCH IS SET AND READ INDIVIDUALLY. The setter names and the getter
names do not correspond one-to-one on this firmware — measured twice, on
different switches — so a master flag proves nothing and a write that was not
read back is a hope, not a change.
"""
import sys
import time

import gi
gi.require_version("Qmi", "1.0")
gi.require_version("Qrtr", "1.0")
from gi.repository import Qmi, Qrtr, GLib   # noqa: E402

TIMEOUT = 15
ATTEMPTS = 5
BACKOFF = (2, 5, 10, 20)      # seconds between attempts

# The switches we can both set and read. Anything the firmware refuses to report
# is left out of the verdict rather than silently counted as agreeing.
GETTERS = (("voice", "get_ims_voice_service_enabled"),
           ("vowifi", "get_ims_voice_wifi_service_enabled"),
           ("video", "get_ims_video_telephony_service_enabled"),
           ("sms", "get_ims_sms_service_enabled"),
           ("ut", "get_ims_ut_service_enabled"))
SETTERS = ("set_ims_service_enabled", "set_ims_voice_over_lte_enable",
           "set_ims_video_telephony_service_enable",
           "set_ims_sms_service_enable", "set_ims_ut_service_enable",
           "set_ims_voice_wifi_service_enable",
           "set_ims_ussd_service_enabled", "set_ims_presence_enabled",
           "set_ims_rcs_enabled", "set_ims_xdm_client_enabled",
           "set_ims_autoconfig_enabled")

st = {"loop": None, "dev": None, "client": None, "vector": None,
      "want": False, "wrote": False, "err": None}


def log(msg):
    print(msg, flush=True)


def finish():
    d, c = st["dev"], st["client"]
    if d is not None and c is not None:
        try:
            d.release_client(c, Qmi.DeviceReleaseClientFlags.RELEASE_CID,
                             TIMEOUT, None, lambda *_: st["loop"].quit())
            return
        except Exception:
            pass
    st["loop"].quit()


def read_vector(out):
    v = {}
    for label, getter in GETTERS:
        try:
            r = getattr(out, getter)()
            v[label] = bool(r[1] if isinstance(r, tuple) else r)
        except Exception:
            v[label] = None          # not reported — excluded from the verdict
    return v


def on_read(client, res, _):
    try:
        out = client.get_ims_services_enabled_setting_finish(res)
        out.get_result()
        st["vector"] = read_vector(out)
    except Exception as e:
        st["err"] = "read failed: %s" % e
    finish()


def on_write(client, res, _):
    try:
        out = client.set_ims_services_enabled_setting_finish(res)
        out.get_result()
    except Exception as e:
        st["err"] = "write failed: %s" % e
    client.get_ims_services_enabled_setting(None, TIMEOUT, None, on_read, None)


def on_bind(client, res, _):
    try:
        client.bind_finish(res).get_result()
    except Exception as e:
        st["err"] = "bind refused: %s" % e
        return finish()
    if not st["wrote"]:
        client.get_ims_services_enabled_setting(None, TIMEOUT, None, on_read, None)
        return
    inp = Qmi.MessageImsSetImsServicesEnabledSettingInput.new()
    for setter in SETTERS:
        try:
            getattr(inp, setter)(st["want"])
        except Exception:
            pass                     # not settable on this firmware; not fatal
    client.set_ims_services_enabled_setting(inp, TIMEOUT, None, on_write, None)


def on_client(dev, res, _):
    try:
        st["client"] = dev.allocate_client_finish(res)
    except Exception as e:
        st["err"] = "allocate IMS client: %s" % e
        return finish()
    inp = Qmi.MessageImsBindInput.new()
    inp.set_binding(0)
    st["client"].bind(inp, TIMEOUT, None, on_bind, None)


def on_open(dev, res, _):
    try:
        dev.open_finish(res)
    except Exception as e:
        st["err"] = "open: %s" % e
        return finish()
    dev.allocate_client(Qmi.Service.IMS, Qmi.CID_NONE, TIMEOUT, None, on_client, None)


def on_device(src, res, _):
    try:
        st["dev"] = Qmi.Device.new_from_node_finish(res)
    except Exception as e:
        st["err"] = "device: %s" % e
        return finish()
    st["dev"].open(Qmi.DeviceOpenFlags.NONE, TIMEOUT, None, on_open, None)


def on_bus(src, res, _):
    try:
        bus = Qrtr.Bus.new_finish(res)
    except Exception as e:
        st["err"] = "qrtr bus: %s" % e
        return finish()
    node = bus.peek_node(0)
    if node is None:
        st["err"] = "no qrtr node 0 (the modem is not up yet)"
        return finish()
    Qmi.Device.new_from_node(node, None, on_device, None)


def one_pass(write):
    """One bind + (optional write) + read. Returns the vector, or None."""
    st.update(loop=GLib.MainLoop(), dev=None, client=None, vector=None,
              wrote=write, err=None)
    Qrtr.Bus.new(1000, None, on_bus, None)
    GLib.timeout_add_seconds(60, lambda: (finish(), False)[1])
    st["loop"].run()
    return st["vector"]


def disagreement(vector, want):
    if vector is None:
        return None
    return sorted(k for k, v in vector.items() if v is not None and v != want)


def main(argv):
    action = argv[1] if len(argv) > 1 else "off"
    if action not in ("off", "on"):
        print(__doc__.strip())
        return 2
    want = (action == "on")
    st["want"] = want

    for attempt in range(ATTEMPTS):
        vector = one_pass(write=(attempt > 0))
        bad = disagreement(vector, want)
        if vector is None:
            log("fp3-ims-reconcile: cannot read the modem (%s); attempt %d/%d"
                % (st["err"] or "no reason given", attempt + 1, ATTEMPTS))
        elif not bad:
            if attempt == 0:
                log("fp3-ims-reconcile: already want=%s, nothing to do  %s"
                    % (action, vector))
            else:
                log("fp3-ims-reconcile: ☠️ HAD DRIFTED, corrected on attempt %d  %s"
                    % (attempt + 1, vector))
            return 0
        else:
            log("fp3-ims-reconcile: ☠️ want=%s but %s disagree  %s"
                % (action, ",".join(bad), vector))
        if attempt < ATTEMPTS - 1:
            time.sleep(BACKOFF[min(attempt, len(BACKOFF) - 1)])

    log("fp3-ims-reconcile: ☠️ GAVE UP after %d attempts; last error: %s"
        % (ATTEMPTS, st["err"] or "read-back still disagrees"))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
