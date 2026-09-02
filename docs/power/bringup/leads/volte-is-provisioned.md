<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# ★ A hálózat AD IMS-t ennek a SIM-nek — a bizonyíték egy meglévő capture-ben volt

A [CSFB-függőség](csfb-is-a-dependency.md) felvetette, hogy ha a 2G elmegy, az
`imsd`-út a tartalék. De egy tartalék, amit **a hálózat nem provisionál**, nem
tartalék. A kérdés megválaszolható volt **új mérés nélkül**.

## Amit a hurok maga elárul

Az IMS-PDN hurok minden ciklusa `ACTIVATE DEFAULT EPS BEARER CONTEXT ACCEPT`-tel
zárul (ESM 0xC2), és a hálózat abban a **Protocol Configuration Options**
mezőben adja vissza a **P-CSCF címeket** — a SIP-proxyt, amivel a UE
regisztrálna. A cím megléte *maga* a VoLTE-provisioning.

`tools/pcscf-scan.py`, a 2026-09-02-i hurok-capture-ön:

| capture | log-bejegyzés | ESM 0xC2 | P-CSCF |
|---|---:|---:|---|
| `diag.bin` | 612 | **22** | `10.149.10.129` ×22, `10.150.10.129` ×21 |
| `diag-ims-held.bin` | 497 | **19** | ugyanaz a kettő, ×18 és ×18 |
| `diag-ims-off.bin` *(kontroll)* | 179 | **0** | **nincs** |

A számok a bearer-elfogadásokhoz kötöttek, nem a fájl méretéhez: ahol a modem nem
kért bearert, ott nulla cím van. Ez zárja ki, hogy a keresés véletlen
minta-illeszkedést talált volna — a keret-fejtés ebben a repóban **illesztett,
nem specifikációból vett**, tehát kellett hozzá a negatív kontroll.

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
