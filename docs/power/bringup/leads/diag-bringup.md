# Bringing the modem's DIAG interface up on mainline

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

So the control side works and the data side still does not. What is left is the
part of the vendor driver after the feature exchange — `DIAG_ID` assignment, the
mask updates in `diag_masks.c`, and peripheral buffering mode — and it should be
transcribed, not guessed. The source is on this disk
(`hadk22/kernel/fairphone/sdm632/drivers/char/diag/`).

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
