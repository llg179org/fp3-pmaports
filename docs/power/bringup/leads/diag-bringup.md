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

## What does not work yet

The data channel stays silent. Tried and all returning nothing:

- HDLC-framed `DIAG_VERNO_F` (`00`) and extended build ID (`7c`) —
  [`../tools/diag-probe.py`](../tools/diag-probe.py) does the framing (payload,
  CRC-16 X.25, `0x7E`, with `0x7D`/`0x7E` escaped);
- the same requests **unframed**, in case SMD packet boundaries replace HDLC;
- both again *after* the control handshake had arrived;
- answering with a `DIAG_CTRL_MSG_FEATURE` (id 3) feature mask and a
  `DIAG_CTRL_MSG_DIAGMODE` (id 4) block on `DIAG_CNTL` — neither drew a reply on
  the control channel either.

So the AP side of the handshake is incomplete, and guessing at it packet by packet
is the wrong method. The next attempt should read the downstream driver rather than
improvise: `drivers/char/diag/diagfwd_cntl.c` in the vendor 4.9 tree, which **is on
this disk** (`hadk22/kernel/fairphone/sdm632/`), and copy the exact sequence and
field layouts it sends on peripheral open.

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
