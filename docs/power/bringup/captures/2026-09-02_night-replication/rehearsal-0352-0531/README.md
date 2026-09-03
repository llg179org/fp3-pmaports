<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# ☠️ A második főpróba (03:52–05:31) és a hiba, amit kihozott: az OCV **kitalált 0 mV driftet** írt volna

Ez a futás a 121. tétel főpróbája **után** ment, a `0b311ba` javításokkal, és
`=== NIGHT COMPLETE ===`-tel zárt. Miniatűr paraméterekkel (3 perces lábak,
`alarm=10s`, `RESTMIN=5`) — tehát **a lábak árama érvénytelen**, és a leg 3-at
egy ssh-belépés is megzavarta (az audit ezt helyesen ki is írta). Az értéke nem
a mérésben van, hanem abban, amit a szerkezetéről elárult.

## A lelet: a tag-et megsemmisíti a saját becslője

Az `ocv()` a meredekséget így olvassa be:

```sh
set -- $(grep "^$1 " "$D/ocv.txt" | tail -6 | awk '…')
slope=${1:-}; dropped=${2:-0}
```

A `set --` **felülírja a pozicionális paramétereket**, tehát attól a sortól
kezdve `$1` már **a meredekség**, nem a `start`/`end` címke. Az utána következő
sorok viszont még `$1`-et használnak:

```sh
first=$(grep "^$1 " "$D/ocv.txt" | head -1 | awk '{print $3}')
last=$(grep  "^$1 " "$D/ocv.txt" | tail -1 | awk '{print $3}')
s "OCV $1 done: ${last}uV, drift over the last 80 s: $(( (last - first) / 1000 )) mV"
```

**Az eszközön mérve, a valódi `ocv.txt` ellen, még a mérés-éjszaka előtt:**

```
FIXED  -> OCV end done: 4154137uV, drift: -83 mV
BROKEN -> OCV 0.10 done: uV, drift: 0 mV
```

`grep "^0.10 "` semmit nem talál, tehát `first` és `last` **üres**, a busybox
aritmetika pedig az üres operandust **0**-nak veszi (külön ellenőrizve;
`set -u` nem üt be, mert a változók be vannak állítva, csak üresek). A futás
tehát **nem hasal el** — ez a rossz hír.

☠️ **Egy kitalált `0 mV drift` tökéletesen pihent pakknak olvasódik.** Ez a
legrosszabb alak, amit egy elromlott műszer felvehet: pontosan akkor jelenti a
lehető legjobb eredményt, amikor **semmit nem mért**. A nyers `ocv.txt` túléli,
tehát a végpontok offline visszanyerhetők — de a futás saját verdiktje nem, és
az éjszakai lánc éppen attól a verdikttől függ, hogy az OCV-végpontokat
elfogadja-e.

**Javítás:** `tag=$1` az `ocv()` elején, és minden `set --` utáni hivatkozás
`$tag`-re. A `night-run.sh`-ban javítva, `busybox sh -n`-nel szintaxis-ellenőrizve
és az eszközre telepítve (md5 egyezik a repóéval).

## Amit ez a MÓDSZERRŐL mond

A hibát nem kód-olvasás találta meg, hanem az, hogy a **főpróba naplóját
elolvastam, mielőtt az éles futás elindult volna**. A napló nem hibát jelzett:
`OCV end slope over the last 5 min:  mV/min ☠️ NOT RESTED` — egy üres hely, ahol
szám tartozna, és egy elmarasztaló verdikt, ami *az üres helyre* vonatkozott. A
blank meredekség oka külön hiba volt (a here-doc, `0b311ba`), és a javítása után
maradt ez a második, amit a blank addig eltakart.

☠️ **Ugyanaz a család, harmadszor ebben a szálban:** a műszer élettartama, a
műszer közege, és most a műszer *címkéje*. Mindhárom úgy bukott meg, hogy a
kimenet elfogadhatónak látszott.

## Az éjszaka előtti takarítás

A `/var/log/fp3/night` **minden fájlja hozzáfűzéssel** íródik (`>>`) — `ocv.txt`,
`run.log`, `samples-B.txt`, `mpss-B.txt` —, és az `ocv.txt`-t a drift-számítás
`head -1` / `tail -1`-gyel olvassa vissza. Ha az éles futás ugyanabban a
könyvtárban indul, **a főpróba 03:56-os nyitó OCV-je lenne az éjszaka
kezdőpontja**, és a lábak mintái elé a 3 perces főpróba mintái kerülnének.

Ezért a futás-könyvtár ide mentve, az eszközön pedig
`/var/log/fp3/night-rehearsal-20260903-0531`-re átnevezve. Az éles futás üres
könyvtárban, `state=0`-ról, a beépített alapértékekkel indul: `BOOTS=3`,
`LEGMIN=75`, `RESTMIN=30`, `ALARM=90`, `BAND=eutran-1` — ellenőrizve, hogy
**nincs `conf` fájl**, tehát nincs örökölt miniatűr paraméter.
