# ★★★★★ SOLVED 2026-09-02 — the data path was never the problem; we were knocking on the wrong door

> **The log stream works.** 38 299 bytes of LTE RRC and NAS logs in 120 s, and it
> named the duty gap in one capture:
> [`../captures/2026-09-02_diag-ota-pmos/`](../captures/2026-09-02_diag-ota-pmos/README.md).
>
> **What changed:** this page spent days on the DIAG *command* path — asking the
> modem a question and never being answered. The power question never needed a
> question asked. It needed the modem's own **log stream**, and logs are turned
> on by a **control** message on the channel that already worked:
>
> ```
> DIAG_CTRL_MSG_LOG_MASK = 9      (diagchar.h, vendor tree on disk)
> struct diag_ctrl_log_mask       (diagfwd_cntl.h)
> ```
>
> The peripheral's own feature mask, 0x3EF7, decoded on this page on 2026-08-29,
> sets **bit 11, MASK_CENTRALIZATION** — which means exactly "send me my masks as
> control packets". The evidence that the door existed had been sitting in this
> file for four days, one paragraph above the wall.
>
> ☠️ **The lesson is not about DIAG.** Everything below is correct: the command
> path really is silent, and every combination tried really did return zero. The
> error was scope — treating "the instrument does not work" as settled when what
> had been shown was "one *use* of the instrument does not work". Ask what the
> measurement actually needs before debugging the path it does not need.
>
> Tool: [`../tools/diag-log-capture.py`](../tools/diag-log-capture.py). It does
> the whole sequence in one process, because the control handshake is answered
> once per boot.

# (original) Bringing the modem's DIAG interface up on mainline

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed every measurement it rests on.

**Status: the channels are open, the control side talks, the data side does not
answer yet.** This page exists so the next attempt starts here rather than at the
beginning.

## Why it is wanted

[`modem-idle-lte.md`](modem-idle-lte.md) has run out of things to subtract: the
modem core is awake 29–52 % on pmOS and 5–8 % on the oracle, on the same hardware,
firmware, operator and cell, and every candidate on both sides is dead. The
remaining questions are all about what the modem is doing during its awake time,
and the modem's own SMD edge is silent through the legs where our duty is 35 % — so
nothing on the AP side is going to answer them. DIAG is the instrument that would.

## What works

**The kernel side, from r78.** `CONFIG_RPMSG_CHAR=m` was already set; the missing
symbol was **`CONFIG_RPMSG_CTRL`**, without which userspace cannot create an
endpoint on an rpmsg device at all. r78 is that one line.

**Opening a channel** — [`../tools/rpmsg-ept.py`](../tools/rpmsg-ept.py):

```sh
python3 rpmsg-ept.py /dev/rpmsg_ctrl3 DIAG        # -> /dev/rpmsg0
python3 rpmsg-ept.py /dev/rpmsg_ctrl3 DIAG_CNTL   # -> /dev/rpmsg1
```

☠️ Two traps. The sysfs door does **not** work — writing the device name into
`/sys/bus/rpmsg/drivers/rpmsg_chrdev/bind` fails; the channel opens through the
*control* device with `RPMSG_CREATE_EPT_IOCTL` (`0x4028B501`). And **the control
index does not follow the remoteproc index**: on this device the modem
(`remoteproc0`) is `/dev/rpmsg_ctrl3`. Map them with
`readlink -f /sys/class/rpmsg/rpmsg_ctrl*/device` rather than guessing.

**The control channel is alive.** Opening `DIAG_CNTL` produces 2225 bytes
immediately — [`../captures/2026-08-29_diag-bringup/diag-cntl-modem.bin`](../captures/2026-08-29_diag-bringup/diag-cntl-modem.bin)
— and it parses cleanly as 30 packets in the `{cmd:u32, len:u32, body}` control
format, consuming every byte: 28 × command-range registrations, then a
one-byte `cmd=12`, then an 8-byte `cmd=28`. **The modem announces itself and then
waits.**

## The handshake, corrected from the vendor source — and the modem answers

☠️ **The control-message IDs were guessed wrong the first time and the guesses
were close enough to look plausible.** From
`hadk22/kernel/fairphone/sdm632/drivers/char/diag/diagfwd_cntl.h`, which is on this
disk: `DIAG_CTRL_MSG_DIAGMODE` is **3**, `DIAG_CTRL_MSG_FEATURE` is **8** — the
first attempt sent 3 and 4. Reading the vendor header took two minutes and
replaced an evening of packet guessing.

The feature packet, exactly as `diag_send_feature_mask_update()` builds it
(`diag_masks.c`):

```
ctrl_pkt_id      u32 = 8
ctrl_pkt_data_len u32 = 4 + FEATURE_MASK_LEN(2) = 6
feature_mask_len u32 = 2
feature_mask     u16 = bits 0,2,9,11,14,15  -> 0xCA05
```

(`F_DIAG_FEATURE_MASK_SUPPORT`, `LOG_ON_DEMAND_APPS`, `STM`,
`MASK_CENTRALIZATION`, `DCI_EXTENDED_HEADER_SUPPORT`, `DIAGID_SUPPORT`.)

**★ The modem answers it.** Sending that packet on `DIAG_CNTL` draws a reply
stream — `cmd 22` (`LAST_EVENT_REPORT`), then the log-range, SSID-range and
build-mask reports. The peripheral had sent 2225 bytes on open and 6160 by the time
the feature mask went out; after it, the conversation continues. **The control side
of the handshake is working.**

★ And a detail worth carrying into the power question rather than the protocol one:
`struct diag_ctrl_msg_diagmode` contains a **`sleep_vote`** field. DIAG has its own
say over whether the peripheral sleeps, so turning logging on is not a neutral
observation of the thing being measured.

## What does not work yet

The data channel stays silent. Tried and all returning nothing:

- HDLC-framed `DIAG_VERNO_F` (`00`) and extended build ID (`7c`) —
  [`../tools/diag-probe.py`](../tools/diag-probe.py) does the framing (payload,
  CRC-16 X.25, `0x7E`, with `0x7D`/`0x7E` escaped);
- the same requests **unframed**, in case SMD packet boundaries replace HDLC;
- both again *after* the control handshake had arrived;
- subsystem-dispatch commands aimed at ranges the modem actually registered
  (`4B <subsys> <cmd16>` for subsys 0x04, 0x0D, 0x2A, 0xFF), after decoding all 28
  `DIAG_CTRL_MSG_REG` packets — the modem registers `cmd_code` 0xFF/0x80 with
  subsystem ids 0x02, 0x04, 0x05, 0x0B, 0x0D, 0x0E, 0x0F, 0x1C, 0x1E, 0x21, 0x2A,
  0x2D, 0x36, 0x44, 0x54, 0x5B, 0xFF;
- the correct `DIAG_CTRL_MSG_FEATURE` (8) — which **does** get answered — followed
  by `DIAG_CTRL_MSG_DIAGMODE` (3) with `real_time = 1`;
- opening `DIAG_CMD` as a separate request/response channel, which the modem then
  closed under us (`BrokenPipeError` on the next read).

## ☠️ The DIAG_ID gate was the right reading of the wrong peripheral

The gate in `diagfwd_write()` is real and was read correctly out of the vendor
driver — it drops a `TYPE_CMD` packet with `return 0` unless the peripheral's
feature mask has been received, ours sent, and, **when the peripheral advertises
`F_DIAG_DIAGID_SUPPORT`**, a DIAG_ID assigned and sent back.

**This modem does not advertise it.** Decoded from its own announcement
(`captures/2026-08-29_diag-bringup/`):

```
cmd=8 len=6  02000000 f73e     ->  feature_mask_len = 2, mask = 0x3EF7
```

`0x3EF7` sets bits 0, 1, 2, 4, 5, 6, 7, 9, 10, 11, 12, 13 — and **bit 15,
`F_DIAG_DIAGID_SUPPORT`, is clear.** There is no `pkt_id 33` to echo, none ever
arrives, and the third condition never applies. Two things the mask *does* say,
both of which were then tested:

- **bit 4 `F_DIAG_REQ_RSP_SUPPORT`** — the peripheral has a dedicated command
  channel, so commands belong on `DIAG_CMD` rather than `DIAG`;
- **bit 6 `F_DIAG_APPS_HDLC_ENCODE`** — the forward direction is *not* HDLC-framed.

☠️ **And the gate is on the AP side anyway.** `diagfwd_write()` describes what the
*vendor's own driver* refuses to send. Writing to the rpmsg endpoint directly
bypasses it entirely, so it could never have explained our silence. Reading the
driver was right; assuming its bookkeeping constrains a different sender was not.

## ★ The handshake is answered once per boot

Measured twice: the **first** `DIAG_CNTL` endpoint of a boot draws **6160 bytes**;
every endpoint opened afterwards in the same boot draws **9**. So a retry inside one
boot is not a retry — it measures an already-consumed state machine, and the result
is indistinguishable from "the modem does not answer". Several of the earlier
attempts in the list above were second attempts. `diag-handshake.py` now warns on a
short open burst and keeps every endpoint open in one process.

## Where it actually stands

On a **fresh boot**, in **one process**, with the control handshake done and the
peripheral's own mask decoded, all eight combinations are silent:

| channel | framing | request | answer |
|---|---|---|---|
| `DIAG_CMD` | raw | `00`, `7c` | 0 bytes |
| `DIAG_CMD` | HDLC | `00`, `7c` | 0 bytes |
| `DIAG` | raw | `00`, `7c` | 0 bytes |
| `DIAG` | HDLC | `00`, `7c` | 0 bytes |

The read path demonstrably works — 6160 unprompted bytes at open, parsing cleanly
to the last byte. The **write** path has never been shown to reach the modem: no
write has ever produced an observable response, and `os.write()` returning without
error only proves the SMD channel accepted the buffer. That is the next thing to
establish, and it is a different question from the one this page has been asking.

## What was learned along the way, and is worth keeping

- **An open DIAG channel is not itself a lever.** Two windows with the endpoint
  held open read **49.5 %** and **49.7 %** MPSS duty — no drop. (It is not evidence
  of a rise either; see the next point.)
- ☠️ **The pmOS duty is not a stable number.** Across the day it has read 29.1,
  33.3, 34.2, 34.8, 35.0, 36.0, 36.8, 37.1, 44.4, 49.5, 49.7 and 51.6 %. The
  oracle's, over five windows, has read 5.3–8.0 %. The comparison survives that
  spread easily, but **any pmOS-side A/B needs its own control leg** — which is
  what `burst-master-knob.sh` is for, and why single-leg results here are quoted
  as ranges.
- ☠️ **A window taken before the modem has registered is not a window about the
  modem.** The first duty measurement on r78 read 44.4 % with `mmcli` still
  answering "couldn't find modem". Confirm `state: registered` first — the
  discipline `modem-window.sh` was built to enforce, forgotten within an hour of
  building it.
- The serving cell is **identical** to the oracle's (`3GPP cell ID 1470762`,
  MCC 216 MNC 70, LTE TAC 5300), so the matched comparison is matched.
- `qmicli --nas-get-drx` returns `unknown` — that field does not describe LTE idle
  DRX on this modem, so it is not the read that settles the DRX question.
