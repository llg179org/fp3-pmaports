<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# The IMS loop has a designed counterpart, and we do not run it

**Status:** open lead, and the best current answer to *"is there intent behind
this wasteful behaviour?"* — **yes: the modem is playing one half of a two-party
protocol.** Sources are cited; the two device-side measurements are our own.

## What the modem does here

Measured in [`../captures/2026-09-02_diag-ota-pmos/`](../captures/2026-09-02_diag-ota-pmos/):
22 complete PDN up/down cycles in 120 s on APN `ims`, spaced 8.3–8.7 s, each one
needing an RRC connection. The UE's own `PDN DISCONNECT REQUEST` arrives ~30 ms
after it accepted the bearer it just asked for, and carries **no ESM cause** —
too fast for anything network-dependent, so a *local* precondition fails between
"bearer up" and "first SIP message".

## The counterpart, from the reverse-engineering literature

[`flamingradian/imsd`](https://codeberg.org/flamingradian/imsd) documents the
Android side by `strace`ing `imsdatadaemon` (GPLv3, `IMS-QUALCOMM.md`). Three
statements from it bear directly on our loop:

1. **The IMS stack lives in modem firmware, but cannot register alone.** *"IMS
   status reporting is now possible, but only for modems that initialize the IMS
   stack completely in the firmware. Most Qualcomm SoCs do not do this and
   require several daemons to initialize the IMS stack on the modem."*

2. **The modem cannot see the AP finish.** *"After setting up the data connection,
   additional commands are needed to trigger an actual registration because the
   modem does not know when Android has completed the data connection setup."*
   ⇒ this is why our arm 1 failed: `mmcli --simple-connect apn=ims` supplies the
   data call and **nothing else**. The measurement agreed — 18 cycles in 90 s with
   the AP-held bearer up, against 22 in 120 s without it.

3. ★ **Traffic runs the other way too.** Of the 17 QMI messages the daemon
   exchanges, msg 2 and msg 4 are annotated *"Incoming QMI message, instead of
   sending to service!"* — the **modem issues a QMI request to the AP** (message
   id `0x0023`) and the daemon answers with a QMI response. Its TLV decodes as
   ASCII: `66 65 38 30 3A 3A …` = `fe80::99ec:bfef:aa30:48c0`, an IPv6
   link-local address. So the firmware asks the AP about the interface it was
   handed, and expects to be answered.

## What our own two instruments say about that

- `qrtr-lookup`: the **modem is the server** on all three IMS services and there
  is **no client on our side**.
- The 300 s QMI census ([`../captures/2026-09-01_qmi-census-awake/`](../captures/2026-09-01_qmi-census-awake/)),
  taken in the expensive state with IMS on, recorded **14 modem→AP messages,
  all of them NAS msg 81 (signal info)** — zero IMS traffic in either direction.

☠️ **These two do not prove the modem is asking us and being ignored.** They say
the opposite in a specific way: a QMI request from the modem is addressed to a
*client*, and with no client bound there is nobody to address, so it never asks.
The failure is upstream of the exchange, not inside it.

## What this makes of the behaviour

Not a bug, and not waste by design: a **half-configured stack**. The carrier
config (a generic `ROW_Commercial` MBN profile — see
[`modem-carrier-config.md`](modem-carrier-config.md)) enables IMS, the firmware
plays its half, the precondition it needs from the AP never arrives, it releases
and retries every 8.4 s forever.

Two directions follow, and they are opposites:

| | what it does | what it costs |
|---|---|---|
| **turn IMS off** | measured to stop the loop dead (220 ESM messages → 0) | no VoLTE, no IMS-routed SMS; on this device calls are CSFB anyway, so the loss may be nil — **untested, see the ring and SMS boxes** |
| **supply the missing half** | `imsd`'s route: hold the IMS bearer *and* answer the firmware | gains VoLTE; unfinished upstream — the doc's own msgs 2, 4–8 are still `Service: ???` |

☠️ **What is still not measured** is whether stopping the loop moves the duty.
The one window taken with IMS off is unusable (DIAG log masks still armed
modem-side, and the band moved inside the window); the band-pinned A/B/A' ladder
`../tools/ims-ab.sh` is what answers it.

## Sources

- <https://codeberg.org/flamingradian/imsd> — `IMS-QUALCOMM.md`, `README.md`
- <https://gitlab.freedesktop.org/mobile-broadband/ModemManager/-/issues/378> — VoLTE in ModemManager
- <https://gitlab.freedesktop.org/mobile-broadband/libqmi/-/merge_requests/347> — IMS status reporting in libqmi
