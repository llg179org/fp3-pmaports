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

---

# Második főpróba, a négy javítás után — mind az öt elvárás teljesült, és két új hiba

2026-09-02 11:41–11:59, ugyanaz a miniatűr alak. Az elvárásokat **a futás előtt**
rögzítettük, hogy utólag ne lehessen rámagyarázni.

| # | elvárás | eredmény |
|---|---|---|
| 1 | a láb `IMS at start` **és** `at end` csupa `False` | ✅ mindkettő |
| 2 | nincs „charger status … not Discharging" | ✅ 0 találat |
| 3 | `band/cell` kitöltve, a láb végén is | ✅ — **és épp ez talált hibát** |
| 4 | a drift mV-ban kiírva mindkét OCV-nél | ✅ 5 mV és 6 mV |
| 5 | a service letiltja önmagát | ✅ `disabled` |

## ★ A vektor-kapu élesben elsült

```
11:47:27 vector NOT off yet (attempt 0) - starting the reconciler
11:47:52 vector verified off: voice=False VoWiFi=False video=telephony SMS=False UT=False
```

Pontosan az az állapot, ami az első főpróbát tönkretette — csak most **a mérés
előtt** derült ki, nem utána.

## ☠️ ÚJ HIBA 1: a sáv elmozdult a láb közepén

```
# band/cell:        eutran-3 / 1470732
# band/cell at end: eutran-1 / 1470762
```

Hat perc alatt. A sáv ezen az eszközön ~17 pp dutyt és ~54 mA-t ér; három láb
három booton **csak a bootban** különbözhet, különben a legnagyobb mért
konfundálót méri. Javítás: a lábak sáv-pinelve futnak, és a láb **kiabál**, ha a
sáv menet közben mégis elmozdul.

Ezt a hibát az a mező találta meg, amit az *első* főpróba hiányzónak mutatott.

## ☠️☠️ ÚJ HIBA 2: a mérést a saját ellenőrzésem rontotta el

A láb medián alvása **9 s** lett egy 90 s-os ébresztő ellen: 28 minta hat perc
alatt négy helyett, és a kapu 28-ból **egyet** tartott meg.

Az ok: 11:49-kor — a láb közepén — ssh-val és pinggel néztem meg a telefont, hogy
megválaszoljak egy kérdést. **Egy ssh-bejelentkezés AP-ébresztés.** Ugyanez a
csapda aznap reggel írásban is szerepelt, a tulajdonosnak címezve.

A kapu skálája a láb *saját* alvása, ezért a zavart láb **így is adott egy
számot** (45,1 mA), és semmi nem mondta, hogy zavart. Javítás: a fit kimondja —

```
☠️☠️ THIS LEG WAS DISTURBED: median sleep 9 s against a 90 s alarm.
     Something woke the AP - an ssh login, a ping, a poller.
     The number above is not the sleeping floor of anything.
```

Nyers kimenet: `rehearsal-2-raw.txt`.
