> ☠️ **CLOSED 2026-09-05.** The dev card was put into a certified stock-Android
> handset and took a terminating call on **GSM** (4G only after teardown), while a
> different card in that same handset holds 4G through a call. The subscription is
> the variable, so no software work on our side - IMS stack included - can give this
> phone a 4G call on this card. See `../captures/2026-09-05_ut-call-rat-newsim/`
> Part 2. Reopening requires a VoLTE-provisioned card in the FP3, not more analysis.

> **2026-09-05, second SIM, direct IMS instrument:** the oracle is IMS
> registered and voice-capable (`IpMultimediaSystem.Registered=true`,
> `VoiceCapable=true`) and *still* takes terminating calls on EDGE - the RAT
> drops 2-3 s before the call is even signalled, and a 21 s answered call ran
> entirely on 2G. An IMS stack is therefore not the lever for the 2G
> dependency. See `../captures/2026-09-05_ut-call-rat-newsim/`.

<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# ★★ What would the `imsd` path cost? — the estimate is itself a gate

> ☠️ **2026-09-05: THE PREMISE OF THIS PAGE IS NOT SUPPORTED.** It prices `imsd`
> as the contingency for 2G retirement — *"if 2G goes, it is what is left"*. That
> night the UT oracle, which runs a complete vendor IMS stack and reports
> `ims=1` throughout, was measured **falling back to EDGE for an incoming call**
> and returning to LTE one second after it ended. So `imsd` would give pmOS what
> UT already has, and UT falls back anyway. The estimate below (days, not weeks)
> and everything it says about libqmi and the missing policy still stand; what
> does not stand is the reason for urgency. See
> [`../captures/2026-09-05_ut-call-rat/README.md`](../captures/2026-09-05_ut-call-rat/README.md).

Because of the [CSFB dependency](csfb-is-a-dependency.md), `imsd` is not an
ambitious alternative but a **contingency**: if 2G goes, it is what is left. The
[network gate is open](volte-is-provisioned.md). So the question is not whether
it is worth it, but whether it costs **weeks or days** — and that estimate is
itself a decision, because a week-long item does not fit on the tail of a power
investigation.

The estimate was made **entirely off the phone**, while the device was measuring.

## ☠️ What we had wrong at first: there is no code in `imsd`

[`flamingradian/imsd`](https://codeberg.org/flamingradian/imsd) had been referred
to in this repository as "the `imsd` path", as though an existing daemon needed
porting. Cloned:

| | |
|---|---|
| contents | **`README.md` + three `.md`**, one `.drawio`, two `.png` |
| code | **none** — no `.c`, no `.py`, no build system |
| the substantive document | `IMS-QUALCOMM.md`, 1105 lines |
| last commit | **2024-01-30** (`194bbc6`), i.e. over two and a half years ago |

So it is not porting but **writing**, from a reverse-engineering note that is
itself unfinished: of the 17 messages it records, **six** say `Service: ???`.

## ★ What we had underestimated: libqmi already carries four IMS services

The `libqmi` 1.39.1 tree (`data/qmi-service-ims*.json`) implements **four** IMS
services, built up since 1.34:

| service | messages |
|---|---|
| `IMS` | Set/Get IMS Policy Manager Settings, Set/Get **IMS Services Enabled** Setting, Bind |
| `IMSA` | Get IMS Registration Status, Get IMS Services Status, Register Indications, **Bind**, **Get Bind** |
| `IMSDCM` | **PDP Activate Request**, **PDP Deactivate Request** |
| `IMSP` | Get Enabler State |

`IMSDCM`'s two messages are **precisely the missing AP half** this investigation
was looking for: the modem asks for a PDN, and somebody has to answer. The
transport, the client handling and the message definitions therefore **exist** —
what is missing is *policy*, not protocol.

## The six "unknown" messages: two identified, one open

Decoding the note's raw hex TLV by TLV and comparing against libqmi's message
IDs:

| msg | ID | TLV content | what it is |
|---|---|---|---|
| 6, 7 | `0x0034` | `01`: eight zero bytes | **`IMSA: Get Bind`** — a query with an empty payload |
| 8 | `0x0033` | `01`: `02 00 00 00` | **`IMSA: Bind`** — binding to identifier 2 |
| 5 | `0x002E` | `10`: `01`, `11`: `00000000` | unidentified (the candidates come from other services) |
| 2, 4 | `0x0023` | `01`: string, **`fe80::99ec:bfef:aa30:48c0`** | the AP telling the modem the **link-local IPv6 address** of the IMS interface; libqmi has no such message |

☠️ **The two identifications are not equally strong, and the difference is the
point here.** A message ID is meaningful **per service**, so a bare ID match
occurs in several services (`0x0034` in five places). The `0x0033`/`0x0034` pair
is different: **adjacent IDs, a setter and a getter**, payload shapes that fit
exactly (empty query / four-byte binding identifier), and the ordering agrees
too. That is a structural match, not a numeric coincidence — and the rule that
tells them apart is the same one as in the [P-CSCF
decode](volte-is-provisioned.md): **the length and the structure either close, or
they do not**.

## The estimate

**Days, not weeks — but not today.** What is in place: the QMI transport, the
four IMS service definitions in libqmi, bringing the bearer up (measured
2026-09-01, `mmcli --simple-connect`), and the network provisioning. What is
missing: a policy that answers the `PDP Activate Request`, plus one message
(`0x0023`, announcing the link-local address) that libqmi does not know.

☠️ **Two gates still stand in front of it, and neither is a coding question:**

1. **Will the network admit this device?** Network provisioning is proven, device
   policy is not. The deciding witness is the **UT oracle slot on this same
   hardware, with the same IMEI** — not a different phone.
2. **The libqmi version on the phone.** The IMS clients have existed since 1.34,
   and some of the messages in the tree are 1.40. That is a device-side read, and
   since the [Dependencies
   section](../captures/2026-09-02_ims-ma3/README.md) the leg header logs it
   anyway.

## A re-pricing that follows from this

Fixing the silent DIAG stream (the "why does it tear down after 30 ms" question)
has become **cheaper still**. Its main burden — whether the network was willing
to give IMS at all — was lifted by the PCO decode. What remains of it is needed
for debugging **after** `imsd` is built, and is not decision-relevant before
that.

## Sources

- <https://codeberg.org/flamingradian/imsd> — `IMS-QUALCOMM.md` (GPLv3, Dylan Van Assche, 2024)
- `libqmi` 1.39.1, `data/qmi-service-ims.json`, `-imsa`, `-imsdcm`, `-imsp`
