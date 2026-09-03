<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# ★★★★★ The device-policy gate is OPEN: IMS registers on this phone, this SIM

Taken 2026-09-03 12:44–12:47 CEST on the UT oracle slot (`fastboot set_active a`),
kernel `4.9.218-perf-ubuntutouch+`, **same device, same IMEI, same SIM** — no card
was moved and nothing was reconfigured. The phone had been running pmOS on slot b
until 12:42.

## The finding

`list-modems-and-props.txt`, ofono on the vendor RIL:

```
[ org.ofono.IpMultimediaSystem ]
    Registered   = 1
    Registration = auto
    VoiceCapable = 1
    SmsCapable   = 1
```

with `Serial = <imei>` (our IMEI) and `NetworkRegistration` on `lte`.

Corroborated by the vendor's own daemons in the same capture:
`init.svc.vendor.imsqmidaemon: running`, `init.svc.vendor.imsdatadaemon: running`,
`vendor.ims.QMI_DAEMON_STATUS: 1`, `vendor.ims.DATA_DAEMON_STATUS: 1`.

## Why it settles two questions at once

The `imsd` path stood on two gates, and only the network-side one had been
answered (`../leads/volte-is-provisioned.md`: the network returns two P-CSCF
addresses and the IM CN Subsystem Signalling Flag in every bearer activation).
The open half was **policy**: operators commonly tie IMS registration to device
policy, so provisioning alone does not mean this handset would be let in.

`Registered = 1` on this IMEI is the operator letting this handset in.
`VoiceCapable = 1` is the registration carrying voice, i.e. VoLTE enabled on
**this** subscription — the dev phone's own SIM, which is a third card, on neither
of the daily handset's two plans.

☠️ **What it does not say.** That the *pmOS* stack can register — it has no IMS
implementation at all. This measures the subscription and the operator's policy
toward this IMEI, which is exactly what could not be measured from our own stack,
and is why the oracle slot was the instrument.

## The rest of the capture

`contexts-and-operators.txt`:

- `context3` is `Type = ims`, APN `ims`, `Protocol = dual` — the IMS PDN the vendor
  stack is configured for.
- `context1` (`internet.vodafone.net`) is **active** with a real address
  (`10.72.x.x/30`, DNS `80.244.x.x,.37`) — the oracle brings the data path up
  by itself, consistent with the 2026-08-28 finding that the cheaper system is the
  one doing more.
- ☠️ The operator's own name on the air is **`One HU`** (MCC 216, MNC 70), not
  "Vodafone HU". Our pmOS side prints the older name out of its own database. Same
  network, two names; `21670` is the identifier to trust.

## Reproducing

```sh
# host, phone in fastboot (systemctl reboot --reboot-argument=bootloader on pmOS)
fastboot set_active a && fastboot reboot          # UT came up in 64 s
ut-ssh 'python3 /usr/share/ofono/scripts/list-modems'
ut-ssh 'python3 /usr/share/ofono/scripts/list-contexts'
ut-ssh 'getprop | grep -i ims'
# back: reboot to bootloader, fastboot set_active b, fastboot reboot
```

## The attach-PDN list on both slots (queue 55)

`pmos-attach-pdn.txt`, taken on slot b at 12:53, four minutes after the return,
against `contexts-and-operators.txt` from the oracle.

| | pmOS (slot b) | UT oracle (slot a) |
|---|---|---|
| attach APN | **`INTERNET`**, ipv4, connected | `internet.vodafone.net` (context1, active) |
| MMS | profiles 10 and 13, `mms.vodafone.net` | context2, `mms.vodafone.net` |
| IMS | **profiles 11 and 14, `ims`, ipv4v6** | context3, `ims`, `Protocol = dual` |

Two things follow.

**The IMS profile is present on both slots.** Profiles 10–14 are named
`qdp_profile` — the vendor's Qualcomm Data Profile entries, persistent in the
modem's own storage. They are not created by whichever OS is booted and they
survive the slot switch, which is consistent with IMS registration coming up
immediately on the oracle rather than being negotiated from scratch.

☠️ **Our attach PDN is `INTERNET`, the vendor's is `internet.vodafone.net`.** We
attach with a different APN string from the one the vendor stack uses. Nothing so
far has depended on this knowingly, but the attach PDN is part of every bearer
measurement taken on this device, so it belongs in the record rather than in
someone's memory.
