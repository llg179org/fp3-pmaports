# Does our IPA driver ever complete its handshake with the modem?

> ⚠️ **AI-generated.** Written by Claude under the direction of Lajosházi, László
> Gergely, who reviewed every change and made or reviewed every measurement.

**Status: read from source, not yet read from the device.** Opened 2026-08-29
evening, after the vendor tree landed.

## Why this is the surviving candidate

Ten candidates are dead ([`modem-idle-lte.md`](modem-idle-lte.md),
[`modem-carrier-config.md`](modem-carrier-config.md)). What survives has to be
something the **AP tells the modem once**, that is neither a daemon, nor a
setting, nor traffic — and the IPA QMI handshake is exactly that shape. Two
observations already point at it and were recorded before this page existed:

- `qrtr-lookup` on pmOS shows an **IPA control service (49)** offered by the modem
  **with nobody talking to it**;
- the IPA hardware probes (`7900000.ipa`) and **no channel is ever brought up**.

## What the source says, on both sides

☠️ **mainline is not missing the code.** msm8953 does not use `drivers/net/ipa`
(that is v3+); its DT says `compatible = "qcom,ipa-lite-v2.6"` and the driver is
**`drivers/net/ipa2-lite/`**, which has its own `ipa-qmi.c` — 1334 lines,
carrying `ipa_init_modem_driver_req`, an `init_driver_work`, the
`INDICATION_REGISTER` server side and a `QMI_INIT_DRIVER_TIMEOUT` of 60 s. So the
handshake is implemented.

`CONFIG_QCOM_IPA2_LITE=m` in `config-fp3.aarch64`, and `ipa.c` carries
`MODULE_DEVICE_TABLE(of, ipa_match)` with `qcom,ipa-lite-v2.6`, so it should
autoload off the DT node.

★ **Which sharpens the question rather than closing it.** The code exists, the
config enables it, the hardware probes — and the modem's IPA service still has no
client. So either the module never loads, or it loads and the handshake does not
complete. Those are different faults with different fixes, and one command tells
them apart.

☠️ Note the v2 comment in `ipa-qmi.c`: *"With IPA v2 modem is not required to send
DRIVER_INIT_COMPLETE request to AP. We start operation as soon as
IPA_UC_RESPONSE_INIT_COMPLETED irq is triggered."* The v2 path waits on a hardware
interrupt from the IPA microcontroller, not on a message. If that interrupt never
arrives, `ipa_qmi_ready()` is never called and nothing logs an error — a silent
stall, which is the shape that survives this long.

## The read that decides it — run when the phone is free

```sh
lsmod | grep ipa                       # did the module load at all?
dmesg | grep -iE 'ipa|qmi'             # probe result, and any 60 s INIT_DRIVER timeout
ls -l /sys/bus/platform/drivers/ipa*/  # is 7900000.ipa actually bound?
qrtr-lookup                            # does service 49 have a client now?
```

| result | what it means |
|---|---|
| module not loaded | the handshake never had a chance — try `modprobe`, then re-measure the duty |
| loaded, bound, no timeout logged, service 49 still unattended | the v2 `IPA_UC_RESPONSE_INIT_COMPLETED` interrupt path is the place to look |
| loaded and a timeout logged | the modem is refusing or not answering — compare the request against the oracle's |

## Comparing against the oracle

The oracle's own tree is now fetched
([`vendor-kernel-sources.md`](vendor-kernel-sources.md)):

```sh
cd /mnt/1TB/Fp3-Sailfish/hadk22/kernel/fairphone/sdm632
git show ut-halium-10.0:drivers/platform/msm/ipa/ipa_v2/ipa_qmi_service.c
```

☠️ **And a result that has to be held against any conclusion here**: killing
`ipacm` and `netmgrd` on the oracle did **not** make its modem expensive (6.4 %
and 5.3 %). That is consistent with the handshake being the thing that matters —
the *kernel* performs it, once, and the daemons are downstream of it — but it also
means a positive result here has to explain why the daemons are free.

☠️ And what no source comparison can answer: why a modem that never got the
handshake would respond by staying awake. That is firmware, and only DIAG sees
inside.
