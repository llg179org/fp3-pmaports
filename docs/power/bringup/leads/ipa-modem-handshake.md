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


## ★★★ 2026-08-29 — the source comparison, both sides, and what it eliminates

With the oracle's own tree fetched ([`vendor-kernel-sources.md`](vendor-kernel-sources.md)),
mainline `drivers/net/ipa2-lite/ipa-qmi.c` and downstream
`drivers/platform/msm/ipa/ipa_v2/ipa_qmi_service.c` can be read side by side.

### The QMI identifiers are identical

| | downstream (oracle) | mainline (ours) |
|---|---|---|
| host service | `0x31` / vers 1 / ins **1** | `0x31` / vers 1 / ins **1** |
| modem service | `0x31` / vers 1 / ins **2** | `0x31` / vers 1 / ins **2** |

★ **`0x31` is 49 decimal** — exactly the "IPA control service (49) with nobody
talking to it" that `qrtr-lookup` reports on pmOS. Our driver looks up precisely
the service the modem is offering, at the same version and instance. **A
mismatched service or version is eliminated.**

### mainline sends the request, and logs every failure

`ipa_client_init_driver_work()` builds a complete `INIT_DRIVER` request — memory
layout, route and filter table bounds, `skip_uc_load`, platform type — sends it
with a 60 s timeout, and calls `dev_err()` on **every** failure path: txn init,
send, and await. So a handshake that is attempted and fails is not silent.

### Which leaves exactly two silent paths

☠️ **1. The work never runs.** `ipa_client_init_driver_work` is scheduled from the
`new_server` callback. If the qmi client handle never sees the modem's server, no
request is sent, no error is logged, and `qrtr-lookup` shows the service
unattended — which is what it shows. The most ordinary cause is that **the module
is not loaded at all**, in which case there is no handle to see anything.

☠️ **2. The uC interrupt never arrives.** Even with the handshake done, the v2 path
gates on `IPA_UC_RESPONSE_INIT_COMPLETED` before `ipa_qmi_ready()` fires.

Both are read-only questions and
[`../tools/ipa-handshake-probe.sh`](../tools/ipa-handshake-probe.sh) answers them.
☠️ Note the ordering this establishes: **do not go looking for missing code or a
protocol mismatch.** Both are now eliminated from the source, and the remaining
fault is operational — loaded or not, interrupt or not.

## ★★★ 2026-09-01 — CLOSED, from the other end: the data path works

This lead asked whether our IPA driver ever completes its handshake with the
modem, because `qrtr-lookup` showed service 49 unattended and no channel ever
came up. **A channel came up.**

```
mmcli -m any --simple-connect='apn=internet.vodafone.net'
  -> Bearer/1  connected: yes  multiplexed: yes  interface: qmapmux0.0
     10.112.79.62/30  gw 10.112.79.61
ip link set qmapmux0.0 up ; ip addr add 10.112.79.62/30 dev qmapmux0.0
  -> 3/3 ping to 8.8.8.8, and 252 bytes each way over a 73-minute run
```

`qmapmux0.0` is a QMAP multiplexer channel on **`rmnet_ipa0`**, and packets went
through it in both directions. A driver that never completed its `INIT_DRIVER`
handshake does not carry traffic, so the two silent paths this page narrowed the
fault to — *the work never runs* and *the uC interrupt never arrives* — are both
eliminated by the data flowing.

☠️ **The missing piece was never the modem or the kernel: it was host-side IP
configuration.** pmOS has no `netmgrd` and no `ipacm`, so nothing brings
`qmapmux0.0` up or puts the network-assigned address on it. Two `ip` commands
after the connect are the whole difference. That also explains the original
observation honestly: the service looked unattended because nobody had ever asked
for a bearer, not because the handshake was broken.

☠️ **What this is inferred from, and the read that would make it direct.** The
conclusion rests on the interface name and on traffic passing, not on the QMI
handshake being observed. The phone was mid-measurement when this was written, so
the confirming read is still owed and is the same one this page always specified:

```sh
lsmod | grep ipa ; qrtr-lookup | grep -i ' 49 '   # service 49 with a client now?
dmesg | grep -iE 'ipa|init_driver'                # and no 60 s timeout logged
```

☠️ **And the power conclusion goes the other way from what this page assumed.**
The premise here was that a modem which never got the handshake responds by
staying awake. With the context up the duty went **from ~35 % to 48.8 %** and the
LPASS stopped sleeping entirely
([`../captures/2026-09-01_bearer-arm/`](../captures/2026-09-01_bearer-arm/README.md)).
So the handshake is not the withheld thing that would let the modem sleep — and
the note above, that killing `ipacm` and `netmgrd` on the oracle did not make its
modem expensive, now reads as the earlier warning it was.
