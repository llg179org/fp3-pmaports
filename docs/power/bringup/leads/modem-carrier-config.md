# Does our modem run without the carrier configuration the vendor stack selects?

> ⚠️ **AI-generated.** Written by Claude under the direction of Lajosházi, László
> Gergely, who reviewed every change and made or reviewed every measurement it
> rests on.

**Status: the pmOS side is read; the oracle side decides it.** Opened 2026-08-29,
first read taken the same afternoon.

## Why this is the shape the evidence now demands

The elimination table in [`modem-idle-lte.md`](modem-idle-lte.md) is exhausted:
nine candidates dead, including every userspace daemon on *both* sides, a live PDP
context on ours, and our client masked from boot so the modem had never been
spoken to. And on 2026-08-29 the last environmental variable fell too — the oracle
windows turn out to have been taken on **cell 1470762**, the *expensive* eutran-1
cell, at 5.4–8.1 % against pmOS's 48.9–52.7 % on the same cell. So the network is
not the variable: same cell, same band, same carrier, same firmware build
(`MPSS.TA.3.1.C1-425464` on both), eight to nine times the awake duty.

What is left has to be **something the modem is told once, that we never tell it**,
and that is not a daemon, not a client and not traffic. There is exactly one such
layer on a Qualcomm modem that the host is responsible for and that mainline has
no equivalent of:

**The carrier configuration (PDC / "MBN").** A Qualcomm modem ships with a generic
configuration and a set of operator-specific ones. Selecting and activating the
right one is a **host** job — on Android the vendor stack does it during bring-up.
It carries exactly the class of parameter that would move idle duty: idle-mode and
DRX behaviour, reselection timers, feature enables per operator. A modem running
the generic fallback would camp and page correctly (which ours does — it registers
and stays registered) while behaving conservatively about sleep, and it would do so
**identically on every cell**, which is what we measure.

☠️ Do not confuse this with `modem.mbn`, the modem *firmware image* in the rootfs.
That was compared byte-for-byte between the two systems and is identical
(2026-08-28); this is a different object selected at runtime over QMI.

## The first read, and it costs nothing

The PDC service answers this directly, and libqmi speaks it. On **each** system:

```sh
qmicli -d qrtr://0 --pdc-list-configs                # what is available
qmicli -d qrtr://0 --pdc-get-selected-config         # what is active
qmicli -d qrtr://0 --pdc-get-config-info=...         # per-config detail
```

On the oracle the QMI path is the vendor's, so read it there through whatever
client is available rather than assuming `qrtr://0` looks the same.

**The result that would make this a mechanism**: an operator configuration
selected on the oracle and none (or the generic one) selected on pmOS. **The
result that kills it**: both sides report the same selected config, in which case
this page closes the way the other nine did.

☠️ **It is a read, not a write.** Activating a configuration changes persistent
modem state and can leave the radio unusable if the wrong one is applied; nothing
here writes until the read says there is something to write and a recovery path
has been established. The device's own rule applies with full force — a modem
brought down badly costs audio until reboot and a mixer write afterwards oopses
the kernel.

## If it reads positive

The A-B is then available and it is inside one boot: activate the configuration
the oracle uses, re-measure the duty with `burst-master.sh`, deactivate, measure
again. The per-boot offset rule makes the A′ leg mandatory.


## The pmOS read, 2026-08-29

[`../captures/2026-08-29_pdc-configs/`](../captures/2026-08-29_pdc-configs/).
`qmicli --pdc-list-configs` takes `platform` or `software` (not `hw`/`sw`), and
both answered:

| type | count | active |
|---|---|---|
| `platform` | 1 — `SR_DSDS-LA-7+7_mode-SDM632` | ☠️ **none: Inactive** |
| `software` | 25 | **`ROW_Commercial`** |

So this modem carries a full carrier-configuration set — 24 operator packages
sitting unused, including `Global-VoLTE-Vodafone` and seven country-specific
Vodafone builds — and runs the **generic Rest-of-World** software config with the
**platform config not activated at all**.

★ That is the shape the hypothesis predicted. It is **not yet evidence**, for one
reason that has to be stated before anyone acts on it:

☠️ **PDC activation is persistent in the modem.** It lives in modem storage, not in
the host, so if the oracle had activated something else, this read would show it —
the same modem, the same storage, one slot switch apart. The likeliest outcome of
the oracle read is therefore that it says exactly the same thing, which would kill
this lead. The case where it does not is the interesting one: a vendor stack that
**re-activates on every boot** would leave the persistent state looking like ours
between boots.

☠️ And `ROW_Commercial` may well be the correct choice here — there is no Hungarian
package in the list at all, so "generic" is not by itself a fault.

## What is still to do

1. **Read the same two lists on the oracle** (slot switch). Same config active on
   both ⇒ this page closes with the other nine candidates.

   The route, from the 2026-08-28 switch: `systemctl reboot
   --reboot-argument=bootloader` — ☠️ started with `systemd-run`, because a
   backgrounded `sudo sh -c "(sleep 1; reboot bootloader) &"` silently does
   nothing on this device — then `fastboot set_active a` from the host. `qbootctl`
   cannot do it here: it looks for `/dev/bsg/ufs-bsg0` and this is eMMC.

   ☠️ Whether `qmicli` even exists on the oracle is unknown; its QMI goes through
   the vendor rild. If it is absent, the fallback is the vendor's own record of
   what it activated, not an assumption that it activated nothing.
2. Only if they differ: an A-B-A′ inside one boot, activating what the oracle
   activates and measuring the duty. ☠️ Nothing is written before step 1 answers —
   activating the wrong configuration changes persistent modem state.

   ☠️ The tempting shortcut is to skip step 1 and just activate the platform
   config here, on the argument that `SR_DSDS-LA-7+7_mode-SDM632` is this chip's
   own platform package and `--pdc-deactivate-config` undoes it. It is deliberately
   **not** taken: the read costs one slot switch and tells us whether the write is
   a fix or a guess, and a persistent modem write made without knowing which is
   exactly the class of action this project has a rule against.
