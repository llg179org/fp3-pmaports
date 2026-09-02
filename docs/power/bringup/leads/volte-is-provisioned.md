<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# ★ A hálózat AD IMS-t ennek a SIM-nek — a bizonyíték egy meglévő capture-ben volt

A [CSFB-függőség](csfb-is-a-dependency.md) felvetette, hogy ha a 2G elmegy, az
`imsd`-út a tartalék. De egy tartalék, amit **a hálózat nem provisionál**, nem
tartalék. A kérdés megválaszolható volt **új mérés nélkül**.

## Amit a hurok maga elárul

Az IMS-PDN hurok minden ciklusát a hálózat egy `ACTIVATE DEFAULT EPS BEARER
CONTEXT REQUEST`-tel (ESM **0xC1**, letöltő irány) nyitja, és **abban** a
**Protocol Configuration Options** mezőben adja vissza a **P-CSCF címeket** — a
SIP-proxyt, amivel a UE regisztrálna. A cím megléte *maga* a VoLTE-provisioning.

`tools/pcscf-scan.py`, a 2026-09-02-i hurok-capture-ön, **hossz-validált
TLV-sétával**:

| capture | log-bejegyzés | ESM 0xC1 | zárt PCO-séta | P-CSCF | kísérő tartalom |
|---|---:|---:|---:|---|---|
| `diag.bin` | 612 | **21** | **21 / 21** | `10.149.10.129` ×21, `10.150.10.129` ×21 | DNS `80.244.99.36` ×21, **IMS-signalling flag** ×21 |
| `diag-ims-held.bin` | 497 | **18** | **18 / 18** | ugyanaz a kettő, ×18 | ugyanaz |
| `diag-ims-off.bin` *(kontroll)* | 179 | **0** | — | **nincs** | — |

Négy dolog teszi ezt méréssé és nem minta-találattá:

1. **A séta a PCO fejlécétől indul és minden konténer saját hossz-mezőjével
   lép**, és a hosszaknak **az IE határán kell zárniuk**. 21/21 és 18/18 zárt.
   Egy elcsúszott illesztés olyan hosszra érkezne, ami nem zár — a szkript akkor
   a hibát jelenti, nem leletet.
2. **A kísérő konténerek értelmesek**: ugyanaz a séta hozza ki a DNS-szervert
   (`80.244.99.36`, publikus cím) és az **IM CN Subsystem Signalling Flag**-et —
   ez utóbbi nem cím, hanem a hálózat kimondása, hogy ez a PDN IMS-jelzésre való.
   Egy cím lehetne elavult provisioning-maradék; ez a flag a válasz maga.
3. **A negatív kontroll**: ahol a modem nem kért bearert, ott nulla REQUEST és
   nulla cím van.
4. **A számok pontosan egyeznek**: két P-CSCF cím, mindegyik pontosan annyiszor,
   ahány REQUEST van. Nincs gazdátlan szám.

☠️ **JAVÍTVA 2026-09-02 este — az első változat rossz üzenetet nevezett meg, és
csak azért adott jó választ, mert túl szélesen keresett.** A `0xC2` (ACCEPT) a UE
feltöltő visszaigazolása, és **nem visz PCO-t**; a szigorú séta rajta „0 / 22"-t
ír. A közölt „`10.149.10.129` ×22, `10.150.10.129` ×21, 22 elfogadás ellen"
párosítás **két független szám egybeesése** volt: a régi szkenner *minden*
ESM-üzenetet bájt-mintával pásztázott, a 22 pedig az elfogadások száma volt, nem
a címeké. A gazdátlan 21-es szám — amit akkor nem magyaráztam meg — pontosan ez
volt a hiba jelzése. A következtetés túlélte a javítást, de **nem a szerszám
érdeméből**.

## Mit jelent, és mit nem

**Jelenti:** a hálózat ennek az előfizetésnek IMS-t provisionál, tehát az
`imsd`-tartaléknak **van hova regisztrálnia**. A hálózati fél nem akadály.

☠️ **Nem jelenti**, hogy az üzemeltető beengedné **ezt a készüléket**: az
IMS-regisztrációt a szolgáltatók gyakran készülék-policyhoz (IMEI-lista, tanúsított
modellek) kötik. Az `imsd`-út tehát **két kapun** áll — technikai (a daemon
megépítése) és policy (beengednek-e) —, és ez a lelet csak az elsőt érinti a
hálózat oldaláról.

A második kapu legolcsóbb tanúja a tulajdonos **napi, gyári Androidos FP3-a
ugyanezen a hálózaton**: ha az hívás közben LTE-n marad, a policy megengedő
ehhez a modellhez; ha az is 2G-re esik, akkor nem.
