<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# ★★ Mibe kerülne az `imsd`-út? — a becslés maga is kapu

A [CSFB-függőség](csfb-is-a-dependency.md) miatt az `imsd` nem ambiciózus
alternatíva, hanem **tartalék**: ha a 2G elmegy, ez marad. A
[hálózati kapu nyitva van](volte-is-provisioned.md). A kérdés tehát nem az, hogy
megéri-e, hanem hogy **hetekbe vagy napokba kerül** — és ez a becslés maga is
döntés, mert egy hetes tétel nem fér el egy fogyasztás-vizsgálat farkán.

A becslés **teljes egészében a gépen készült**, miközben a telefon mért.

## ☠️ Amit elsőre rosszul tudtunk: az `imsd`-ben nincs kód

A [`flamingradian/imsd`](https://codeberg.org/flamingradian/imsd) ebben a repóban
eddig úgy szerepelt, hogy „`imsd` útja" — mintha egy meglévő daemont kellene
portolni. Klónozva:

| | |
|---|---|
| tartalom | **`README.md` + három `.md`**, egy `.drawio`, két `.png` |
| kód | **nincs** — se `.c`, se `.py`, se build-rendszer |
| a lényegi dokumentum | `IMS-QUALCOMM.md`, 1105 sor |
| utolsó commit | **2024-01-30** (`194bbc6`), azaz több mint két és fél éve |

Tehát nem portolás, hanem **írás**, egy visszafejtési jegyzetből, ami maga is
befejezetlen: a benne rögzített 17 üzenetből **hatnál** `Service: ???` áll.

## ★ Amit viszont eddig alábecsültünk: a libqmi már négy IMS-szolgáltatást visz

A `libqmi` 1.39.1 fájában (`data/qmi-service-ims*.json`) **négy** IMS-szolgáltatás
van implementálva, 1.34 óta épülve:

| szolgáltatás | üzenetek |
|---|---|
| `IMS` | Set/Get IMS Policy Manager Settings, Set/Get **IMS Services Enabled** Setting, Bind |
| `IMSA` | Get IMS Registration Status, Get IMS Services Status, Register Indications, **Bind**, **Get Bind** |
| `IMSDCM` | **PDP Activate Request**, **PDP Deactivate Request** |
| `IMSP` | Get Enabler State |

Az `IMSDCM` két üzenete **pontosan az a hiányzó AP-fél**, amit ez a vizsgálat
keresett: a modem kér egy PDN-t, és valakinek felelnie kell rá. A transzport, a
kliens-kezelés és az üzenet-definíciók tehát **megvannak** — ami hiányzik, az a
*politika*, nem a protokoll.

## A hat „ismeretlen" üzenet: kettő azonosítva, egy nyitva

A jegyzet nyers hexét kibontva (TLV-nként), és a libqmi üzenet-ID-ivel összevetve:

| msg | ID | TLV-tartalom | mi ez |
|---|---|---|---|
| 6, 7 | `0x0034` | `01`: nyolc nulla bájt | **`IMSA: Get Bind`** — lekérdezés, üres payloaddal |
| 8 | `0x0033` | `01`: `02 00 00 00` | **`IMSA: Bind`** — kötés a 2-es azonosítóhoz |
| 5 | `0x002E` | `10`: `01`, `11`: `00000000` | nem azonosított (a jelöltek más szolgáltatásokból valók) |
| 2, 4 | `0x0023` | `01`: string, **`fe80::99ec:bfef:aa30:48c0`** | az AP közli a modemmel az IMS-interfész **link-local IPv6 címét**; libqmi-ben nincs ilyen üzenet |

☠️ **A két azonosítás nem egyforma erős, és a különbség itt a lényeg.** Egy
üzenet-ID **szolgáltatásonként** értelmes, tehát puszta ID-egyezés több
szolgáltatásban is akad (`0x0034` öt helyen). A `0x0033`/`0x0034` páros azért
más: **szomszédos ID, setter és getter**, a payloadok alakja pontosan illik
(üres lekérdezés / négybájtos kötés-azonosító), és a sorrend is stimmel. Ez
szerkezeti egyezés, nem szám-egybeesés — a különbséget ugyanaz a szabály mondja
ki, mint a [P-CSCF-fejtésnél](volte-is-provisioned.md): **a hossz és a szerkezet
zár, vagy nem zár**.

## A becslés

**Napok, nem hetek — de nem ma.** Ami a helyén van: a QMI-transzport, a négy
IMS-szolgáltatás definíciója a libqmi-ben, a bearer felhúzása (2026-09-01-én
mérve, `mmcli --simple-connect`), és a hálózati provisioning. Ami hiányzik: egy
politika, ami válaszol a `PDP Activate Request`-re, plusz egy üzenet
(`0x0023`, a link-local cím közlése), amit a libqmi nem ismer.

☠️ **Két kapu áll még előtte, és egyik sem kódolási kérdés:**

1. **Beengedi-e a hálózat ezt a készüléket?** A hálózati provisioning bizonyított,
   a készülék-policy nem. A döntő tanú az **UT-orákulum slot ugyanezen a vason,
   azonos IMEI-vel**, nem egy másik telefon.
2. **A libqmi verziója a telefonon.** Az IMS-kliensek 1.34 óta léteznek, a fában
   lévő üzenetek egy része 1.40-es. Ez eszköz-oldali olvasás, és a
   [Függőségek szakasz](../captures/2026-09-02_ims-ma3/README.md) óta a
   láb-fejléc úgyis logolja.

## Egy átárazás, ami ebből következik

A néma DIAG-folyam javítása (a „miért bont 30 ms után" kérdés) **tovább
olcsósodott**. A fő terhét — hogy a hálózat egyáltalán akart-e IMS-t adni — a
PCO-fejtés levette. Ami maradt belőle, az az `imsd`-építés **utáni**
hibakereséshez kell, előtte nem döntés-releváns.

## Források

- <https://codeberg.org/flamingradian/imsd> — `IMS-QUALCOMM.md` (GPLv3, Dylan Van Assche, 2024)
- `libqmi` 1.39.1, `data/qmi-service-ims.json`, `-imsa`, `-imsdcm`, `-imsp`
