# What the network grants, what this phone deliberately switches off, and one thing that is genuinely new

2026-09-05, pmOS on slot_b, `linux-fp3-7.1.3-r81` (`3f843d0534e3`), qmicli
1.39.0, SIM on One HU (MCC 216 / MNC 70), camped LTE, registered home.

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely. No subscriber identifiers are reproduced; the raw
> captures were scrubbed on the way off the device and `tests/no-identifiers.sh`
> is clean.

☠️ **This page was rewritten within the hour.** Its first version presented three
findings, and two of them were wrong in a way that mattered. What they were and
why they fell is at the bottom, kept rather than deleted.

## The one finding that stands: the network grants this UE IMS voice

```
$ qmicli -d qrtr://0 --nas-get-system-info
	LTE service:
		...
		Voice support: 'yes'
		IMS voice support: 'yes'
		MCC: '216'   MNC: '70'   Tracking Area Code: '5300'
```

`IMS voice support` is the *IMS voice over PS session indicator* — the per-UE bit
the network sends in the EPS network feature support IE. Queue item #169 spent
weeks trying to read it out of a DIAG capture of an LTE attach that never worked.
It is a decoded field of one qmicli call.

☠️ **And that call was already in use on this phone**, for a different line of the
same output: `leads/csfb-is-a-dependency.md` quotes its `Domain: 'cs-ps'`. The
answer to #169 was four lines further down, in output that had already been
printed.

**How far to trust it**, stated as its basis rather than as confidence:

* **Stable** — identical across three consecutive reads.
* **Not a constant** — the adjacent boolean `eMBMS coverage info support` decodes
  as `'no'` from the same message, and GSM/WCDMA report `'none'` where LTE
  reports `'available'`. The decoder discriminates.
* **Right structure** — MCC, MNC, TAC and Cell ID in the same block match the
  operator the phone is on.
* **Corroborated independently** — on Ubuntu Touch this same SIM completed a real
  SIP REGISTER with One HU's core and got a P-Associated-URI back. Different
  instrument, different OS, same conclusion about this subscriber.
* ☠️ **Not established** — that the field tracks the network's *per-UE grant*
  rather than a UE-side capability. Settling that needs a network known to
  withhold VoLTE, which is not available here.

Also read, and also unremarkable: `--voice-get-config` reports
`Current Voice Domain Preference: 'ps-preferred'`. The modem already prefers PS
for voice.

## What "every IMS service reads no" actually is

Not a fault, not a modem default, and not a discovery: it is **this phone's
deliberate configuration**, and it is re-asserted every five minutes.

`userspace-power/fp3-ims-reconcile.py`, installed as
`fp3-ims-reconcile.service` + `.timer` since 2026-09-02, holds every IMS switch
off because the modem otherwise raises and tears down an IMS PDN every 8.4 s
forever, holding the UE in RRC_CONNECTED at a cost of about **44 percentage
points of modem duty** (measured three times). `tests/checks/56-ims-config-test.sh`
checks it.

So the reading `voice: no, video: no, VoWiFi: no, UE-to-TAS: no, SMS: no,
USSD: no` is the intended state of this phone, correctly maintained.

## Why the MBN hypothesis (#166) is weakened, not supported

#166 proposed loading a Hungarian carrier config on the theory that the generic
`ROW_Commercial` withholds VoLTE. The two things such a config would fix — the
network's IMS-voice grant and the voice domain preference — **already read
correctly**. The measurement points away from the carrier config.

The modem holds 25 software configs, none Hungarian; the nearest is
`Global-VoLTE-Vodafone` (One HU is the former Vodafone Hungary). Activating it
stays cheap and reversible (restore: activate
`software,5C:F9:CA:DA:5C:35:85:17:BA:3B:B8:88:D0:34:2B:79:BD:5F:AD:ED`), but it
was **not** done: changing a config to fix a symptom the measurements attribute
elsewhere is how a coincidence gets recorded as a cause.

## ☠️ The two claims that fell, and why

**1. "No tool can write the IMS switches, so I wrote one."** The CLI gap is real
— `qmicli` exposes `--ims-get-ims-services-enabled-setting` and no setter, in
1.39.0 and in the 1.39.1 checkout, though libqmi has defined
*Set IMS Services Enabled Setting* (IMS `0x008f`, `0x10` = IMS Voice Over LTE
Enable) since 1.38 and the installed library exports the API.

But the **capability was never missing**. `fp3-ims-reconcile.py` has been writing
exactly those switches since 2026-09-02, through the same introspection API, from
this repository, on this phone. A new tool was written without looking for the
existing one; it has been deleted.

**2. "IMS stays not-registered after enabling it."** Void. The reconciler's timer
reverted the write inside the observation window — the journal shows it, in
those words:

```
fp3-ims-reconcile: ☠️ want=off but ut,voice disagree  {'voice': True, ..., 'ut': True}
fp3-ims-reconcile: ☠️ HAD DRIFTED, corrected on attempt 2
```

Two minutes of `not-registered` measured the reconciler doing its job, not the
modem declining to register. It was **not** evidence for the missing-AP-half
theory and was briefly reported as if it were.

**3. A correction the mistake did produce.** The first version said the IMS
queries need qmi-proxy, because they answer `InvalidOperation` without `-p`.
That is wrong: `fp3-ims-reconcile.py` opens the device with
`DeviceOpenFlags.NONE` and works. The real shape is two separate things —

| symptom | actual cause | fix |
|---|---|---|
| `QMI protocol error (70): InvalidOperation` | the IMS/IMSA client was never **bound** | send `--ims-bind` / `--imsa-bind` first |
| `Unknown client N for service imsa` | a CID does not survive between two `qmicli` **processes** | `-p`, so both go through qmi-proxy |

Only the second is about the proxy. Conflating them turns a client-lifetime
detail into a false claim about the modem.

## Commands

```sh
qmicli -d qrtr://0 --nas-get-system-info | grep -A6 'LTE service'   # the grant
qmicli -d qrtr://0 --voice-get-config | grep Domain                 # ps-preferred
/usr/local/bin/fp3-ims-reconcile.py off                             # the switches
systemctl status fp3-ims-reconcile.timer
```

☠️ Any experiment that needs the IMS switches ON must **stop
`fp3-ims-reconcile.timer` first and start it again afterwards**, or the
reconciler will silently undo it mid-measurement.
