# Does our modem run without the carrier configuration the vendor stack selects?

> ⚠️ **AI-generated.** Written by Claude under the direction of Lajosházi, László
> Gergely, who reviewed every change and made or reviewed every measurement it
> rests on.

**Status: hypothesis with a cheap first read, not yet measured.** Opened
2026-08-29, after the reading that forced it.

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
