<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# ★★★★★ A főpróba megtalálta a hibákat, amiket az éjszaka nem mondott volna meg

2026-09-02 11:19–11:37, a teljes éjszakai lánc **tizedében**: `BOOTS=1`,
`LEGMIN=6`, `RESTMIN=3`, `ALARM=90`. Az indok, amiért egyáltalán lefutott: az
éjszakai mérés **egylövetű és felügyeletlen**, és szinte minden alkatrésze aznap
készült.

## Ami működött

A mechanika hibátlan. A `rest+OCV → reboot → láb → rest+OCV` sorozat végigment,
az állapotgép a reboot után magától folytatta (`step 0` → `step 1`), és a
szolgáltatás a végén **letiltotta önmagát** (`ENABLED=disabled`). Ez volt a
legfontosabb kockázat: egy állapotgép, ami nem tud leállni, boot-loop egy
telefonon, aminek csöngenie kell.

## ☠️ NÉGY HIBA, MIND NÉMA LETT VOLNA

### 1. A láb a DRÁGA állapotot mérte, miközben olcsónak hitte magát

A napló szerint „a reconciler szólt", és a futás ment tovább. A láb
visszaolvasása:

```
# IMS at start: voice=True VoWiFi=False video=telephony SMS=True UT=True
# IMS at end:   voice=True VoWiFi=False video=telephony SMS=True UT=True
```

Hat percen át az **IMS bekapcsolva**. Az ok: a konvergencia-ellenőrzés a
journalban a `fp3-ims-reconcile:` sztringre illesztett, és az illeszkedett a unit
saját **leírására** — *„Finished Hold the modem's IMS service switches off"* —,
amit a systemd akkor is kiír, ha a reconciler nem ért el semmit.

**Egy naplósor nem állapot.** A javítás a *vektort* olvassa, nem a naplót, és ha
négy percen belül nem megy off, **feladja a lábat** — mert a hiányzó láb egy rés,
a félrecímkézett láb egy hazugság.

A vektor-ellenőrzés mindhárom ágon megmutatva: a főpróbában mért rossz vektort
elutasítja, a jót átengedi, és a **részleges** driftet (csak az SMS áll vissza)
szintén elutasítja.

### 2. Az OCV a töltőn készült

```
11:19:54 battery 100% 4413005uV Charging
```

4,413 V a **töltő lebegtetési feszültsége**, nem a pakké. Az egész sönt nélküli
offset-korlát egy *pihentetett pakkot* igényel. A rádiót lekapcsoltuk, a töltőt
nem. Most mindkettő megy, és a script **ellenőrzi**, hogy a státusz tényleg
`Discharging`.

### 3. A sáv és a cella üresen maradt

```
# band/cell:
```

Az `sed` mintája elhagyta a záró aposztrófot, tehát a mezők üresek. A sáv ezen az
eszközön ~17 pp dutyt és ~54 mA-t ér — **egy sáv nélküli láb semmivel nem
összehasonlítható**. Javítva, és a láb *végén* is rögzíti, mert a sáv menet
közben elmozdulhat.

### 4. Az OCV nem ült le, és ezt nem mondta meg

A záró öt olvasás 3 perc pihenő után még **emelkedett** (4 347 801 → 4 348 969
µV). A script mostantól kiírja a driftet, hogy az olvasó leértékelhesse ahelyett,
hogy az utolsó értéket elhinné.

## A tanulság, amit a nap már kétszer kimondott

Mindhárom mai hibaosztály ugyanaz: **a lecke leírva, a kód a régit csinálja**, és
mindegyik **csak éles próbán** jött elő — a `RuntimeMaxSec=1800` egy 9 órás
ablakra, az `fp3-*` minta az állandó unitokra, és most egy grep, ami egy systemd
unit-leírást fogadott el mérési bizonyítéknak.

Nyers kimenet: `rehearsal-raw.txt`.
