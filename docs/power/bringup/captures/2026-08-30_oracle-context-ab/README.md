# 2026-08-30 — the oracle's own data-context A-B-A′, and it retires the netmgrd story

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

**Command:** `ut-context-ab.sh 360` on slot_a (Ubuntu Touch,
`4.9.218-perf-ubuntutouch+`), 13:35–13:54. Three 360 s `modem-window.sh` windows,
one instrument, the ofono data context as the only deliberate variable.
**Compared against:** pmOS's own bearer A-B-A′ of 2026-08-28
(`captures/2026-08-28_bearer-master-ab/`, 35.0 / 36.0 / 36.8 %) and pmOS's
no-bearer baseline of 34.8 %.

## Why it was run

Every A/B on the duty gap had been run on pmOS. The oracle was only ever
*snapshotted* — so the standing story, *"the cheaper system is the one doing
more; it holds a PDP context and we never bring one up"*, had never been tested
by taking the context away from **the cheaper system**. That is the one-sided
rule this project keeps writing down, applied to the lever instead of the
baseline.

## The reading

| leg | data contexts | **MPSS awake** | LPASS awake | signal |
|---|---|---|---|---|
| A | `rmnet_data0` + `rmnet_data2` | **6.9 %** | 3.0 % | 30 |
| **B** | `rmnet_data0` only (`DeactivateAll`) | **5.2 %** | 2.9 % | 20 |
| A′ | `rmnet_data0` + `rmnet_data1` (restored) | **5.4 %** | 2.9 % | 22 |

`Technology = lte` and `Status = registered` on all three.

**The duty did not rise. It fell slightly**, and A′ (5.4 %) sits closer to B
(5.2 %) than to A (6.9 %), so the 1.5-point spread is baseline drift rather than
the lever.

## What it settles

⇒ **The data context is not the difference.** The oracle runs at 5–7 % with its
bearer and without it, while pmOS runs at 34.8 %. The gap survives the lever
completely.

⇒ **The `netmgrd` / `ipacm` story is retired**, exactly as the pre-registered
reading in `power/NEXT-RUN.md` said it would be if this outcome came up. It was
the most attractive remaining explanation of the duty gap and it is now measured
away from both sides: pmOS's bearer A/B was flat, and so is the oracle's.

⇒ It also **rehabilitates that pmOS A/B** rather than casting doubt on it. Two
independent systems now say the same thing about the same lever, which is a
stronger result than either leg alone.

⇒ By the frame's decision table, D1 lands on *"attach-time configuration"* —
DRX, paging cycle, or whatever the vendor RIL negotiates at registration. That is
**step D2**, and D2 is bring-up work with a reboot per attempt, not an
afternoon's measurement.

## ☠️ Two honesty notes, both weakening rather than helping

1. **Leg B is not "no data at all".** ofono's `DeactivateAll` took down
   `rmnet_data2` and left `rmnet_data0` (10.17.x.x) up — the IMS/default
   context. So the lever was *one context instead of two*, not *bearer versus no
   bearer*. The pmOS side of the comparison genuinely had **no** bearer, so the
   two are not exactly the same experiment.
2. **The signal drifted across the legs** (30 → 20 → 22). A weaker signal costs a
   modem *more*, and B and A′ were both weaker **and** lower-duty — so the
   confound pushes against the observed direction rather than producing it. That
   strengthens the conclusion, and it is only knowable because the instrument now
   records the radio context on every leg, which the 2026-08-24 oracle capture
   did not.
