#!/usr/bin/env python3
"""Load an MBN carrier config into the modem over QMI PDC.

Reimplements what `qmicli --pdc-load-config` does, because that command
segfaults in libqmi 1.38 / qmicli 1.39: load_config_file_from_string() in
src/qmicli/qmicli-pdc.c calls g_free() on the pointer returned by
g_mapped_file_get_contents(), which points into the mmap'd region owned by
the GMappedFile, not into the heap.  The crash happens before the first
chunk is built, so nothing is ever sent to the modem.

Usage: pdc-load.py <device-uri> <file.mbn>
"""

import hashlib
import sys

import gi

gi.require_version("Qmi", "1.0")
gi.require_version("Qrtr", "1.0")
from gi.repository import GLib, Qmi, Qrtr  # noqa: E402

CHUNK_SIZE = 0x400  # LOAD_CONFIG_CHUNK_SIZE in qmicli-pdc.c

device_uri = sys.argv[1]
mbn_path = sys.argv[2]

with open(mbn_path, "rb") as f:
    payload = f.read()
total_size = len(payload)
digest = list(hashlib.sha1(payload).digest())
print(f"file: {mbn_path} ({total_size} bytes), sha1 "
      f"{hashlib.sha1(payload).hexdigest()}", flush=True)

loop = GLib.MainLoop()
state = {"offset": 0, "token": 0, "client": None, "device": None, "ok": False}


def finish(ok, msg):
    state["ok"] = ok
    print(("OK: " if ok else "ERROR: ") + msg, flush=True)
    loop.quit()


def make_chunk():
    """Build the next LoadConfig input, or None when the file is exhausted."""
    off = state["offset"]
    if off >= total_size:
        return None
    size = min(CHUNK_SIZE, total_size - off)
    inp = Qmi.MessagePdcLoadConfigInput.new()
    inp.set_token(state["token"])
    state["token"] += 1
    inp.set_config_chunk(Qmi.PdcConfigurationType.SOFTWARE, digest,
                         total_size, list(payload[off:off + size]))
    state["offset"] = off + size
    print(f"uploading {off}..{off + size} of {total_size}", flush=True)
    return inp


def load_config_ready(client, res, _user_data=None):
    """Response to one chunk; the real progress arrives as an indication."""
    try:
        output = client.load_config_finish(res)
        output.get_result()
    except GLib.Error as e:
        finish(False, f"load_config failed: {e.message}")


def send(inp):
    state["client"].load_config(inp, 10, None, load_config_ready, None)


def on_indication(client, output):
    try:
        output.get_indication_result()
    except GLib.Error as e:
        finish(False, f"indication reports failure: {e.message}")
        return

    try:
        frame_reset = output.get_frame_reset()
    except GLib.Error:
        frame_reset = False
    if frame_reset:
        finish(False, "modem requested a frame reset")
        return

    try:
        remaining = output.get_remaining_size()
    except GLib.Error as e:
        finish(False, f"no remaining size in indication: {e.message}")
        return

    if remaining == 0:
        finish(True, "finished loading, modem reports 0 bytes remaining")
        return

    print(f"modem wants {remaining} more bytes", flush=True)
    inp = make_chunk()
    if inp is None:
        finish(False, f"modem wants {remaining} more bytes but the file is "
                      f"exhausted at {state['offset']}")
        return
    send(inp)


def client_ready(device, res, _user_data=None):
    try:
        client = device.allocate_client_finish(res)
    except GLib.Error as e:
        finish(False, f"couldn't allocate PDC client: {e.message}")
        return
    state["client"] = client
    client.connect("load-config", on_indication)
    inp = make_chunk()
    if inp is None:
        finish(False, "empty file")
        return
    send(inp)


def open_ready(device, res, _user_data=None):
    try:
        device.open_finish(res)
    except GLib.Error as e:
        finish(False, f"couldn't open device: {e.message}")
        return
    device.allocate_client(Qmi.Service.PDC, Qmi.CID_NONE, 10, None,
                           client_ready, None)


def device_ready(_unused, res, _user_data=None):
    try:
        device = Qmi.Device.new_from_node_finish(res)
    except GLib.Error as e:
        finish(False, f"couldn't create QmiDevice: {e.message}")
        return
    state["device"] = device
    device.open(Qmi.DeviceOpenFlags.EXPECT_INDICATIONS, 15, None,
                open_ready, None)


def bus_ready(_unused, res, _user_data=None):
    """qmicli resolves a qrtr:// URI through the QRTR bus, not through GIO."""
    try:
        bus = Qrtr.Bus.new_finish(res)
    except GLib.Error as e:
        finish(False, f"couldn't access QRTR bus: {e.message}")
        return
    state["bus"] = bus
    node = bus.peek_node(node_id)
    if not node:
        finish(False, f"node {node_id} not found on the QRTR bus")
        return
    Qmi.Device.new_from_node(node, None, device_ready, None)


ok, node_id = Qrtr.get_node_for_uri(device_uri)
if not ok:
    print(f"ERROR: not a QRTR node URI: {device_uri}")
    sys.exit(1)
Qrtr.Bus.new(1000, None, bus_ready, None)
GLib.timeout_add_seconds(180, lambda: finish(False, "timed out after 180 s"))
loop.run()
sys.exit(0 if state["ok"] else 1)
