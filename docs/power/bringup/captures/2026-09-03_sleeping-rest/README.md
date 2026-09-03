<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# ★ Az alvó rest működik — és ugyanez a mérés buktatta le az elfogadási kritériumot

2026-09-03 03:30–03:46, 15 × 60 s alvó minta, rádió ki, USB-bemenet felfüggesztve.
A [09-02-i éjszaka](../2026-09-02_night-replication/) két restje **nulla** suspenddel
futott — sima `sleep`-pel, tehát az AP végig ébren volt, és emiatt egyik OCV-végpont
sem tudott leülni.

## Amit a javítás hozott

| | 09-02 éjszaka | 09-03, `nap()`-pal |
|---|---:|---:|
| `PM: suspend entry` a rest alatt | **0** | **15** |
| a feszültség az utolsó 3 percben | −0,78…−0,91 mV/perc | **4,264 / 4,263 / 4,264 / 4,264 V** = ±1 mV |

A `sleep` → `rtcwake` csere tehát pontosan azt csinálja, amiért bekerült.

## ☠️ De a verdikt PIROS lett, és a hiba a MŰSZERBEN volt

A szkript „5,39 mV/perc, NOT RESTED"-et írt egy olyan sorozatra, aminek az utolsó
négy pontja **1 mV-on belül** van. Az ok: a meredekséget az utolsó hat pont
**első és utolsó** értékéből számolta — ez nem meredekség, hanem kétmintás
különbség —, és kilenc perccel a kezdés után egy terhelési letörés két mintát
30 és 90 mV-tal lehúzott. Az egyik pont épp az ablak *elejére* esett.

```
 496 s  4.282 V
 558 s  4.236 V   ← letörés
 620 s  4.204 V   ← letörés
 682 s  4.264 V
 744 s  4.263 V
 806 s  4.264 V
 868 s  4.264 V
```

Ugyanezen az adaton:

| becslő | eredmény |
|---|---|
| régi (első−utolsó, utolsó 6) | **5,42 mV/perc → NOT RESTED** |
| új (MAD-szűrés + illesztés, utolsó 6) | **0,10 mV/perc → RESTED**, „2 minta eldobva kiugróként" |

☠️ **A javítás nem simítás.** Egy terhelési letörés a restben **zavar**, nem zaj,
és meg kell nevezni: a szkript kiírja, hány mintát dobott, és ha négynél kevesebb
marad, a verdikt nem „nem ült le", hanem **„zavart rest"** — két különböző dolog,
és az egyiknek nem szabad a másiknak álcáznia magát. Ugyanaz az elv, mint a lábak
attribúciós szabályánál: a magyarázat a *címkét* változtatja, nem a sorsot.

☠️ **És egy ablak-hossz lecke.** Nyolc mintára (≈7 perc) az illesztés −2,73 mV/perc,
mert az ablak visszanyúlik a letörés *előtti* magasabb szintre — a letörés
maradandóan lejjebb vitte a pakkot, tehát ott valódi esés van. Hatra (≈5 perc)
0,10. A kritérium eredeti szándéka is „az utolsó öt perc" volt; a hosszabb ablak
nem robusztusabb, hanem **más kérdésre válaszol**.

Nyers adat: [`raw.txt`](raw.txt).
