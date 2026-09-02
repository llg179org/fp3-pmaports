<!-- AI-generated: written by Claude Opus 5 as part of an AI-assisted port. -->

# A ket IMS-check bemutatasa az eszkozon (2026-09-02)

Egy check, amit sosem lattunk bukni, nem check hanem dekoracio. Mindketto
mindket agat megjarta az elo telefonon.

## 56-ims-config-test.sh — konfiguracio-szint

| allapot | eredmeny |
|---|---|
| IMS=off, timer fut | `PASS` (rc=0) |
| IMS=on | `FAIL` (rc=1) a pontos hibauzenettel |

☠️ **Es a bemutatas TALALT egy hibat magaban a checkben:** az `enabled` es az
`active` ket kulon kerdes. Egy kezzel leallitott timer tovabbra is `enabled`-et
ir, tehat a check atment, mikozben a kovetkezo reboottal a vektor visszaallt
volna es semmi nem allitotta volna helyre. Javitva: mindkettot kerdezi, es kulon
mondatban mondja meg, melyik hianyzik.

## 57-ims-duty-test.sh — viselkedes-szint

Ket 120 s-os ablak, ugyanazon a savon es cellan (`eutran-3` / `1470732`), tehat
a sav mint konfundalo ki van zarva:

| allapot | duty | ebredes/s | ms/ebredes | eredmeny |
|---|---|---|---|---|
| IMS=on  | 37,1 % | 2,41 | 154,1 | `FAIL` (rc=1) |
| IMS=off |  5,0 % | 3,13 |  16,0 | `PASS` (rc=0) |

A 3,13/s = 1/320 ms, a paging DRX ciklus: az olcso allapotban a UE camped, nem
tart kapcsolatot. A 2,41/s a paging-utem ALATT van — ezek nem paging-alkalmak,
hanem kapcsolat-karbantartas; ezert kerdez a check kulon a duty-ra es kulon az
ebredes-utemre.

## A reconciler elesben, kozben

A demo kozepen az `fp3-ims-reconcile` sajat naploja:

```
fp3-ims-reconcile: ☠️ HAD DRIFTED, corrected on attempt 2  {'voice': False, 'vowifi': False, 'video': False, 'sms': False, 'ut': False}
```

Vagyis a driftet nem szimulaltuk: a check-demo maga allitotta vissza IMS=on-ra,
es a reconciler ezt eszrevette es visszaigazitotta, visszaolvasassal.

Nyers kimenet: `57-ims-duty-test-both-ways.txt`.
