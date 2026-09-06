# #166 answered, and the answer is not the one the task assumed: there is no Hungarian MBN, and the nearest one costs LTE

2026-09-06, pmOS `linux-fp3-7.1.3-r88`, modem `MPSS.TA.3.1.C1-425464`.
**Reverted; the phone is back on `ROW_Commercial` and LTE.**

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

## What the modem actually carries

25 software configurations and one platform configuration. The active one is
**`ROW_Commercial`** — the generic "rest of world" build, which is what
[`leads/modem-carrier-config.md`](../../leads/modem-carrier-config.md) predicted
and what [#165](../2026-09-05_163-same-card-two-devices/) found unloaded.

☠️ **There is no Hungary-specific configuration.** The task said to load
`vodafone/commerci/hungary`; that path exists in Android MBN trees, not in this
modem's own list. What it has for this operator's group is:

```
UK-VoLTE-Vodafone      Spain-VoLTE-Vodafone   Netherlands-VoLTE-Vodafone
Italy-VoLTE-Vodafone   IE-VoLTE-Vodafone      Germany-VoLTE-Vodafone
Global-VoLTE-Vodafone  Non_VoLTE-Vodafone
```

The full before-state is `pdc-before-software.txt` and
`pdc-before-platform.txt`, saved **before anything was written** — the modem's
config store is persistent, shared by both slots, and survives a reflash of
either OS, so that capture is the only way back and not paperwork.

## The measurement

`Global-VoLTE-Vodafone` is the only candidate for an operator with no
country-specific build. Activated, then the modem restarted so it would take
effect:

| | before | after `Global-VoLTE-Vodafone` |
|---|---|---|
| active config | `ROW_Commercial` | `Global-VoLTE-Vodafone` |
| registration | **LTE**, signal 76-84 | **GSM/GPRS only** |
| time to register | seconds | 96 s of `searching` |

★ **It costs LTE outright.** Not a subtle regression: after a full modem power
cycle the phone registers on 2G and stays there. Reverting to `ROW_Commercial`
and restarting the modem brought LTE back immediately, which is the control that
makes this a measurement rather than a coincidence.

The likely reason is the band or PLMN set a Vodafone-group global build carries;
Vodafone HU (MCC 216, MNC 70) is evidently not in it. **Do not activate it
again**, and do not activate the country-specific ones on the same reasoning —
they will be narrower, not wider.

## What this means for the VoLTE work

The carrier-config route to VoLTE, as #166 framed it, **is closed by absence**:
there is no configuration for this operator to load, and the generic Vodafone one
is actively harmful here. Loading an MBN from elsewhere (an Android image) would
need `--pdc-load-config`, which writes a foreign blob into that same persistent
store, and nothing here justifies that yet.

That leaves the userspace route,
[`../2026-09-05_imsd-first-register/`](../2026-09-05_imsd-first-register/), whose
`500` is now better bounded: the network **does** allow IMS voice to this device
([`../2026-09-06_ims-vops-supported/`](../2026-09-06_ims-vops-supported/)), and
it **does** provision IMS for this SIM
([`leads/volte-is-provisioned.md`](../../leads/volte-is-provisioned.md)).

## ☠️ Two operational notes

- `qmicli --pdc-activate-config` **takes minutes and can appear to hang**. Two
  invocations here overran a 300 s and a 500 s timeout while in fact completing;
  the modem restarts underneath. Check the state afterwards rather than
  concluding from the timeout.
- After a config change the modem **renumbers** on D-Bus. Every `mmcli` call
  must use `-m any`; `-m 0` silently fails with rc=1 while a script reports
  progress, which cost three earlier measurements on this device today.
