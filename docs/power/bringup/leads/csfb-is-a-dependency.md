<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# ☠️ A takarékos konfiguráció egy hálózati szolgáltatáson áll: CSFB

**CS** = *Circuit Switched*, a klasszikus 2G/3G-s beszédhívás-út. **CSFB** =
*Circuit Switched FallBack*: a UE LTE-n táborozik, de amikor CS-hívás jön, a
hálózat a hívás idejére átküldi 2G/3G-re.

## A mérés

A `fp3-ringlog` a hívás **után** olvassa a sávot, és 2026-09-02-án három egymást
követő hívásnál `gsm-900-extended`-et rögzített, miközben a telefon LTE-n
táborozott (`mmcli … access tech: lte`). A modem `--nas-get-system-info`-ja
`Domain: 'cs-ps'`-t ad: az LTE-regisztráció **tartalmazza a CS-tartományt**, azaz
az SGs-kapcsolat él a hálózat (vodafone HU, 21670) és a MSC között.

Vagyis a hívások nem „valahogy" jönnek át — **méréssel igazoltan CSFB-vel**.

## ☠️ Amit ez a jelentésről mond

A `≤50 mA` konfiguráció ára az, hogy az IMS-t lekapcsoljuk, és a hívás CS-en jön.
Ez **nem a telefon tulajdonsága, hanem a hálózaté**: ha az üzemeltető
lekapcsolja a 2G-t (a 3G-t Magyarországon már lekapcsolták), akkor ezen a
konfiguráción a bejövő hívás nem lassabb lesz, hanem **nem lesz**.

A jelentés eddig úgy fogalmazott, hogy „a hívás-út működik IMS=off mellett" — ez
igaz, de hiányzott belőle a **feltétel**. A helyes alak:

> A hívás-út működik IMS=off mellett, **amíg a hálózat CS-tartománya elérhető**
> (mérve: SGs él, a hívás gsm-900-ra esik vissza). Ez a konfiguráció így egy
> hálózati szolgáltatásra támaszkodik, aminek a kivezetése be van jelentve a
> szektorban — nem a mi eszközünkön múlik, és nem a mi ütemünk szerint.

## Amit ez a TERVRŐL mond

Az `imsd`-út — az AP-oldali IMS-daemon megépítése, ami VoLTE-t adna — eddig
„külön projekt, külön döntéssel, nem ennek a szálnak a farka" címkével feküdt.
Ez a besorolás **túl alacsony**: nem kíváncsiság, hanem a **tartalék terv**.
Ha a 2G elmegy, a választás nem „IMS ki vagy be", hanem „VoLTE vagy semmi", és
akkor a 8,4 s-os PDN-hurok kikapcsolása helyett azt kell megérteni, **miért**
bontja a modem a bearert — vagyis pontosan a 64. tétel, amit most a néma
DIAG-folyam blokkol.

## Amit NEM állítunk

Nincs mérésünk arról, hogy ez a hálózat mikor kapcsolja le a 2G-t, és a
szolgáltatói bejelentések nem tartoznak ehhez a repóhoz. Amit tudunk: **ma
működik**, és a konfigurációnk függ tőle.
