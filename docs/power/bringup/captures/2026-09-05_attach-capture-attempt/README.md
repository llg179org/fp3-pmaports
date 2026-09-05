# #169 attempt — the attach was never captured, and the reason is the DIAG command wall

**Date:** 2026-09-05, 10:45–11:00 CEST · **Slot:** a (Ubuntu Touch) · **Result:**
**no measurement**. Recorded because the failure is informative and because two
claims in the task that set it up were wrong.

## What was set up, and it worked

- ☠️ **`/dev/diag` exists on UT** (char 235,0). [`leads/imei-tac-gating.md`](../../leads/imei-tac-gating.md)
  said the port is reachable on pmOS and implied UT is not; that was an assumption
  written as fact, and it is **wrong**.
- QCSuper's **prebuilt aarch64 `adb_bridge`** (shipped in the QCSuper tree, NDK
  build, interpreter `/system/bin/linker64`) runs inside the Android container via
  `lxc-attach -n android`, prints `Connection to Diag established`, and listens on
  TCP 43555. No adb, no slot switch.
- QCSuper on the host reaches it with `--tcp <ip>:43555`, in a venv with
  `crcmod pyserial pyusb pycrate`.

## Where it stopped

```
[ERROR @ _base_input.py:274] Error: Diag request DIAG_LOG_CONFIG_F
                             with payload b'\x00\x00\x00\x00\x00\x00\x00' timed out
```

The pcap is **24 bytes — the file header and zero packets**
(`attach-empty.pcap`, kept as the evidence that nothing was captured).

☠️ **This is the wall [`leads/diag-bringup.md`](../../leads/diag-bringup.md)
already describes** — *"the modem answers control messages and never answers a
command"* — and the new fact is that **it holds on Ubuntu Touch too**, on the
stock downstream stack. It was previously only ever seen on mainline/pmOS, where
it was reasonable to suspect the port. It is not the port.

It also explains why the 2026-09-02 captures worked: `tools/diag-log-capture.py`
does not send a command. It sets the log mask over **`DIAG_CNTL`**, the channel
that does answer — its own docstring says so. That tool targets pmOS's rpmsg
control device and reports `no modem rpmsg control device` on UT, so the working
route has no UT-side implementation yet.

## What would make it work

A UT-side equivalent of the control-channel log-mask path: enable log codes
`0xB0EC`/`0xB0ED` (LTE NAS EMM plain OTA, in and out) through `/dev/diag` in the
downstream way, then read the stream. The decoder for the answer is written and
kept here as **`vops-scan.py`** — it walks the mandatory fields by their own
lengths, walks optional IEs by IEI and length, **requires the walk to close on the
message boundary**, discards any message where it does not, and says so explicitly
when a capture contains no ACCEPT at all. It has never been run on real data.

## Operational note worth keeping

Toggling `org.ofono.Modem.Online` false→true left the modem in
`NetworkRegistration.Status = searching` and it did not recover on its own for
several minutes. `org.ofono.NetworkRegistration.Register()` brought it back
immediately to `registered / lte / One HU`. ☠️ A detach/attach trigger is therefore
not self-restoring on this stack — always check the registration afterwards and
call `Register()` if needed.

## Mistakes made here, since they cost time and one needless modem toggle

1. ☠️ `pkill -f adb_bridge` matched the pattern of my own ssh command line and
   killed the session — **the exact trap already written down in the skill**, walked
   into anyway. Kill by PID.
2. The first capture attempt aborted on a missing Python dependency **after** the
   detach/attach had already been triggered, so the modem was cycled for nothing.
   Start the recorder, prove it is recording, and only then disturb the thing being
   measured.
