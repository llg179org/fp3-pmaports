# A kapuk — mi tiltja a munkát, mikor jár le, és megérte-e

> ⚠️ **AI-generated.** Ezt a lapot és a leírt méréseket Claude (Opus 5) írta
> Lajosházi, László Gergely irányításával, aki minden változtatást átnézett.

Ez a projekt hookokkal védekezik a saját visszatérő hibái ellen: egy hiba
megtörténik, és utána egy kapu megakadályozza, hogy még egyszer megtörténjen.
Minden kapu **fel tud mutatni egy incidenst** — és pontosan ezért veszélyesek:
az incidens örökre igaz marad, a kapu haszna nem.

☠️ **A kérdés, amit eddig senki nem tett fel: tüzelt-e még JOGOSAN azóta?** Egy
kapu, ami két hete nem fogott semmit, de minden körben szól, nettó negatív. Ez a
lap ezért nem azt írja le, *miért* született egy kapu, hanem hogy **mit csinál
azóta** — és mikor kell újra megnézni.

**A szabály, ami az egészet keretezi:** a nettó irány addig rendben, **amíg a
kivétel ugyanolyan olcsó, mint a hozzáadás.** Ha egy kaput nehezebb elvenni,
mint betenni, a készlet csak nőni tud, és a rothadás beépül.

## A kapuk

| kapu | esemény | miért született (incidens) | felülvizsgálat |
|---|---|---|---|
| [`risky-target.cjs`](https://github.com/llg179org/fp3-pmaports) *(a skills-repóban)* | `PreToolUse` | 2026-08-16 boot-hang: a tudás két helyen megvolt (`docs/deploy/README.md` és a `/fp3-kernel-test` skill), de mindkettő **húzó** mechanizmus — tudnod kell, hogy szükséged van rá. Ez a *célpontra* kulcsol, ezért anélkül tüzel, hogy bárki tudná, hogy kellene | **2026-10-01** |
| `precompact-status.cjs` | `PreCompact` | 2026-08-23 06:10: auto-tömörítés 264k-nál, `bandsFired: []`, nulla sáv-injektálás — a session munkaállapota elveszett. Nem függ attól, hogy a modell észrevesz-e valamit: a lemezen lévő transzkriptet olvassa | **2026-10-01** |
| `measurement-watch.cjs` | `PostToolUse`, `Stop` | „mérés + figyelő = egy objektum": kétszer bukott prózában, ezért lett gép által kikényszerítve. ☠️ És 2026-09-02-án a **figyelő maga** volt a zavar egy alvás-hosszt mérő lábban — egy kapunak ára van | **2026-09-15** ☠️ *korábbi dátum: ennek a kapunak MÉRT mellékhatása van* |
| `queue.cjs` | `Stop`, `SessionStart` | 2026-09-03: a hook saját 124 tételes listát tartott egy négy napja nem frissült `TODO.md` mellett. Ez már nem tart listát; a sor a `TODO.md`-ben van | **2026-10-01** |
| ~~`autonomy.cjs`~~ | — | **nyugalmazott 2026-09-03.** A repóban marad, kikapcsolva; a `queue.cjs` váltotta | — |

## A három mérőszám, 2026-09-03

### 1. Karbantartási hányad — **4,4 % a commitokból, 5,4 % a sorokból**

A kérdés: mennyi munka megy a szerszámok karbantartására a valódi munkához
képest? 2026-08-20 óta:

| | hook-repó | munka-repó (nyers capture-ök nélkül) | hányad |
|---|---:|---:|---:|
| commit | 32 | 697 | **4,4 %** |
| hozzáadott sor | 2 616 | 45 388 | **5,4 %** |

☠️ **A capture-öket ki kellett venni a nevezőből**, különben a szám hamisan
kedvező: nyers adattal együtt a munka-repó 131 249 sor, és a hányad 2,0 %-ra
esik. Egy nevező, amit adat-dömping hizlal, bármilyen szerszám-költséget
elrejt.

**Ítélet: rendben.** Húsz sorból egy megy a szerszámra.

### 2. Kapunkénti precizió — **NEM MÉRHETŐ, és ez maga a lelet**

A nyugalmazott `autonomy.cjs` naplója 37 tüzelést rögzített:

| kapu | tüzelés | |
|---|---:|---:|
| `open-work` | 23 | 62,2 % |
| `review-due` | 9 | 24,3 % |
| `unrecorded-result` | 3 | 8,1 % |
| `OVERRIDE:human-reschedule` | 1 | 2,7 % |
| `OVERRIDE:consulted-none` | 1 | 2,7 % |

☠️ **A napló azt rögzíti, hogy egy kapu tüzelt — soha nem azt, hogy igaza
volt-e.** Ezért a precizió visszamenőleg nem számolható ki, és a „ha a
hamis-blokk-ráta meghaladja a fogásokat, nettó negatív" szabály **nem
alkalmazható a meglévő adatra**. Ez nem részletkérdés: pontosan az a mérőszám
hiányzik, ami eldöntené, hogy egy kaput el kell-e venni.

Amit **ebből a futásból** meg lehet címkézni, mert van rá tanú:

- `unrecorded-result` (3×) — a külső bírálat nevezte meg *„a compaction-veszteség
  egyetlen aktív védelmének"*. Hamis tüzelésre nincs adat. **Jogos.**
- `review-due` (9×) — a 2026-09-03 07:36-os tüzelés **üresjáratban** történt
  (nulla elvégezhető tétel, a következő esemény 11 óra múlva), tehát az
  *időzítése* hibás volt. A kikért bírálat viszont **három számomat döntötte
  meg**, tehát a tüzelés tartalmilag hasznos volt. Címke: **rosszul időzítve, nem
  fölösleges.**
- `open-work` (23×) — visszamenőleg nem címkézhető.

**Teendő, ami ebből következik:** a kapu-napló bejegyzésének kell egy
**kimenet-mező** (`fogás` / `hamis` / `felülbírálva`), amit a kapu *lezárásakor*
kell kitölteni. Amíg nincs, a következő felülvizsgálat ugyanígy vak lesz.

### 3. Felülbírálási ráta — **5,4 %** (2/37)

Két explicit felülbírálás: egy `human-reschedule`, egy `consulted none`.

**Ítélet: a kapukat betartják, nem kerülik meg.** Ha ez a szám 20 % fölé megy,
az azt jelenti, hogy a kapu rosszul van hangolva, nem azt, hogy a felhasználója
fegyelmezetlen.

## ☠️ Amit ez a felülvizsgálat menet közben talált

**Két kapu egyáltalán nem volt verziókövetve.** A `fp3-risky-target.cjs` és a
`precompact-status.cjs` csak a `~/.claude/hooks/` alatt létezett, nulla
találattal a skills-repóban. Egy kapu git-történet nélkül **auditálhatatlan**:
nem lehet megkérdezni, mikor került be, milyen incidensre, és mi változott rajta
azóta — vagyis pont az a három kérdés, amire ez a lap való. Mindkettő bekerült a
repóba és symlinkkel van a helyén; mindkettő tüzelés-tesztelve a költöztetés
után.

## Hogyan kell egy kaput elvenni

Ugyanolyan olcsón, mint betenni — ez a lap fenti szabálya, kimondva:

1. A `settings.json`-ből ki a bejegyzés (a fájl maradhat, kikapcsolva).
2. Egy sor **ide**, hogy mikor és **milyen mérés alapján** lett elvéve.
3. Nem kell hozzá engedély, ha a felülvizsgálati dátum lejárt és a kapu azóta
   nem mutat fogást.

☠️ Egy kapu elvétele **nem** kudarc-beismerés. A kapu egy incidensre válaszolt;
ha az a hibamód megszűnt (más lett a szerszám, más lett az eljárás), a kapu
tovább él a saját indoklásán, és onnantól már csak fogyaszt.
