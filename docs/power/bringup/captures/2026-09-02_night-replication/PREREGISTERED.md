<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# Előregisztráció — a 2026-09-02-i éjszakai replikáció, az adat megérkezése ELŐTT

Ez a lap **19:08 és 03:15 között** készült, amíg a mérés futott, és **egyetlen
szám sem látszott belőle**. Az egyetlen host-oldali érintés az éjszakára egy
poll volt 19:23:49-kor, a nyitó restben.

☠️ **Miért van erre szükség.** Ez a projekt a héten négy publikált történetet
vont vissza, és mind a négy ugyanabból a hibaosztályból jött: **az adat
megérkezése után illesztett magyarázat**. Egy jóslat, amit utólag írok le, nem
jóslat. Ha a reggeli számok az alábbi sávokba esnek, a lezárás nem csak *mért*
lesz, hanem **megjósolt** — és ha nem esnek bele, az itt leírt sávok mondják meg,
hogy melyik feltevés bukott, nem az emlékezetem.

## Mit csinál az éjszaka (a szkript forrásából, nem emlékezetből)

| lépés | szegmens | USB-bemenet | várt hossz |
|---|---|---|---|
| 0 | nyitó rest + OCV (rádió ki) | **felfüggesztve** | adaptív, ≤ 90 perc |
| — | reboot + konvergencia + sáv-pin | **vissza kapcsolva** | ~10–15 perc × 3 |
| 1, 3, 5 | láb 1–3, IMS off, 90 s-os ébresztők | **felfüggesztve** | 75 perc × 3 |
| vég | záró rest + OCV (rádió ki) | **felfüggesztve** | 30 perc |

## ☠️ A szerkezeti probléma, amit a jóslat előtt kell kimondani

**A külső OCV-pár NEM tiszta kisülést zárójelez be.** A `night-run.sh`
szándékosan visszakapcsolja a töltő-bemenetet minden reboot előtt (a
felfüggesztés-bit a PMIC-ben él és túlélné a meleg rebootot, így a telefon némán
töltésképtelenül jönne vissza) — tehát **három szakaszon a bemenet be van
kapcsolva**. Ha a kábel fizikailag be van dugva, a pakk ezalatt **tölt**, és az
éjszakai ΔQ nem a fogyasztás integrálja, hanem fogyasztás **mínusz** töltés.

Ez nem hiba a szkriptben — a reboot-biztonság fontosabb —, hanem egy tag, amit a
mérlegbe be kell írni. Két eset, és a naplóból **eldönthető, melyik**, mert
minden lépés elején rögzül a `pmi632-charger/status`:

- **A kábel nincs bedugva** ⇒ a „vissza kapcsolva" szakaszokon sem folyik áram,
  az éjszaka végig kisülés, a mérleg zárható.
- **A kábel be van dugva** ⇒ a reboot-szakaszok pozitív tagot visznek, amit a
  feszültségből nem lehet kibontani. Ekkor a teljes-éjszakai OCV-korlát
  **elesik**, és a `|ε|`-korlát csak a *lábakon belüli* szakaszokra mondható ki,
  vagy sehogy. Ezt reggel ki kell mondani, nem elkenni.

## Előregisztrált jóslatok

Az elfogadási küszöb **előre**: a mérleg akkor zárt, ha a két oldal **10 %-on
belül** egyezik. Ennél lazábbra utólag nem engedek.

| tétel | jóslat | mire épül |
|---|---|---|
| láb-átlagok (3 db) | **40,3 mA** körül, egymástól **±5 mA-en belül** | a 09-02-i cenzus B-lába, 19/30 ablak, ±1,3 belül-lábon |
| a boot-közti szórás | **< 5 mA** (a három láb-átlag szórása) | ez a mérés tárgya; ha nagyobb, a 40,3-at nem szabad egy számként idézni |
| rest-áram (rádió ki, bemenet ki) | **25–35 mA** | a rádió-ki szegmens a legolcsóbb ismert állapot |
| reboot + konvergencia | **150–350 mA**, szakaszonként 10–15 perc | ébren, modem felhúzás alatt; a leglazább tagom |
| nyitó rest hossza | 60–90 perc (adaptív, 90-es plafon) | 19:22-kor már −2 mV/2 perc |
| **ΔQ az éjszakára, ha a kábel KI van húzva** | **270–330 mAh** | 90′×30 + 3×75′×40,3 + 3×12′×250 + 30′×30 |
| ugyanez SoC-ban | **12–15 pont** | 2185 mAh-s pakk |
| ugyanez feszültség-úton | **60–80 mV** | a 08-28-i görbe lokális meredeksége a 4,0–4,2 V sávban |

☠️ A ΔQ-jóslatom **magasabb**, mint a bírálóé (230–280 mAh), és a különbség
majdnem teljes egészében a reboot-tagban van — az az egyetlen szegmens, amire
ebben a projektben nincs mért szám. Ha reggel a mérleg a 230–280 sávba esik, az
azt jelenti, hogy **a reboot olcsóbb, mint hittem**, nem azt, hogy a lábak
rosszak; ezt előre kimondom, hogy ne utólag válasszak magyarázatot.

## Amit a görbével szabad, és amit nem

- **Szabad:** a 2026-08-28-i kisütési görbét **lokális meredekségre** (mAh/mV)
  használni a ma éjjeli feszültség-tartomány körül.
- **Nem szabad:** abszolút SoC-ra. A görbe 110 mA terhelés *alatt* készült, tehát
  minden pontja ≈ 16 mV-tal (R≈0,15 Ω) a valódi OCV alatt ül; ez a Δ-ból
  elsőrendben kiesik, az abszolút hozzárendelésből nem.
- **A Peukert-tag elhanyagolható**: C/20–C/55 tartományban a kitevő ~1,0, az
  eltérés 1–2 % alatt.

## ☠️ Egy szám javítva, még az elemzés előtt

Az offset-korlát eddig `|ε| ≤ 1,6 δ` alakban szerepelt, `Ī = 110 mA`-rel. A 110
a kisütés **mediánja** (108); a mAh-tengely viszont **integrál**, tehát a helyes
skála az **átlag: 2185 mAh / 17,94 h = 121,8 mA**. Ezzel

$$I_{QG}-I_{OCV}=\varepsilon\left(1-\frac{I}{\bar I}\right),\qquad
1-\frac{40}{121{,}8}=0{,}672 \;\Rightarrow\; |\varepsilon| \le 1{,}49\,\delta$$

a korábbi 1,57 helyett. A publikált korlát tehát **konzervatív volt, nem
hibás** — és a görbe meredekség-hibáját (`g`) is beszámítva a becsületes alak
`|ε| ≤ 1,49 (δ + I·|g|)`, ami néhány százalékos `g` mellett ~1–2 mA lazulás.

Mindkét szám a forrásban állt végig: `2026-08-28_discharge-to-shutdown/analysis.md`
— *„p10 56, **median 108**, p90 217 mA (**mean 122**, and the mean is not the
number)"*. A mondat vége igaz — de arra a kérdésre, amire ott válaszolt. Egy
integrál skálázásához **az átlag a szám**.
