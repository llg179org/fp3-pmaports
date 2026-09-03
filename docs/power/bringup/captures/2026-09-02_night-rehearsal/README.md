<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# ★★★★★ The rehearsal found the defects the night would not have reported

2026-09-02 11:19–11:37, at a **tenth** of the full night chain: `BOOTS=1`,
`LEGMIN=6`, `RESTMIN=3`, `ALARM=90`. The reason for running it at all: the night
measurement is **one-shot and unattended**, and almost every part of it was built
that same day.

## What worked

The mechanics were faultless. The `rest+OCV → reboot → leg → rest+OCV` sequence
ran through, the state machine resumed by itself after the reboot (`step 0` →
`step 1`), and the service **disabled itself** at the end (`ENABLED=disabled`).
That was the biggest risk: a state machine that cannot stop is a boot loop on a
phone that has to keep ringing.

## ☠️ FOUR DEFECTS, ALL OF WHICH WOULD HAVE BEEN SILENT

### 1. The leg measured the EXPENSIVE state while believing itself cheap

The log said "the reconciler spoke", and the run carried on. The leg's own
read-back:

```
# IMS at start: voice=True VoWiFi=False video=telephony SMS=True UT=True
# IMS at end:   voice=True VoWiFi=False video=telephony SMS=True UT=True
```

Six minutes with **IMS on**. The cause: the convergence check matched the string
`fp3-ims-reconcile:` in the journal, and that matched the unit's own
**description** — *"Finished Hold the modem's IMS service switches off"* — which
systemd prints whether or not the reconciler achieved anything.

**A log line is not a state.** The fix reads the *vector*, not the log, and if it
does not go off within four minutes it **gives up on the leg** — because a
missing leg is a gap, and a mislabelled leg is a lie.

The vector check is demonstrated on all three branches: it rejects the bad vector
measured in the rehearsal, passes the good one, and also rejects a **partial**
drift (only SMS coming back on).

### 2. The OCV was taken on the charger

```
11:19:54 battery 100% 4413005uV Charging
```

4.413 V is the **charger's float voltage**, not the pack's. The whole
shunt-free offset bound needs a *rested pack*. The radio was switched off, the
charger was not. Now both go, and the script **verifies** that the status really
reads `Discharging`.

### 3. Band and cell came out empty

```
# band/cell:
```

The `sed` pattern dropped the closing apostrophe, so the fields were empty. On
this device the band is worth ~17 pp of duty and ~54 mA — **a leg without a band
is comparable to nothing**. Fixed, and it is now recorded at the *end* of the leg
too, because the band can move mid-run.

### 4. The OCV had not settled, and did not say so

The closing five reads were still **rising** after a 3-minute rest (4 347 801 →
4 348 969 µV). The script now prints the drift, so a reader can discount it
instead of believing the last value.

## The lesson the day had already stated twice

All three of that day's defect classes are the same one: **the lesson is written
down, the code does the old thing** — and each surfaced **only in a live
rehearsal**: `RuntimeMaxSec=1800` against a 9-hour window, the `fp3-*` pattern
against permanent units, and now a grep that accepted a systemd unit description
as measurement evidence.

Raw output: `rehearsal-raw.txt`.

---

# Second rehearsal, after the four fixes — all five expectations met, and two new defects

2026-09-02 11:41–11:59, the same miniature shape. The expectations were written
down **before** the run, so that nothing could be explained into place
afterwards.

| # | expectation | result |
|---|---|---|
| 1 | the leg's `IMS at start` **and** `at end` all `False` | ✅ both |
| 2 | no "charger status … not Discharging" | ✅ 0 hits |
| 3 | `band/cell` filled in, at the end of the leg too | ✅ — **and this is what found a defect** |
| 4 | the drift printed in mV at both OCVs | ✅ 5 mV and 6 mV |
| 5 | the service disables itself | ✅ `disabled` |

## ★ The vector gate fired for real

```
11:47:27 vector NOT off yet (attempt 0) - starting the reconciler
11:47:52 vector verified off: voice=False VoWiFi=False video=telephony SMS=False UT=False
```

Exactly the state that ruined the first rehearsal — except this time it came out
**before** the measurement, not after.

## ☠️ NEW DEFECT 1: the band moved mid-leg

```
# band/cell:        eutran-3 / 1470732
# band/cell at end: eutran-1 / 1470762
```

In six minutes. On this device the band is worth ~17 pp of duty and ~54 mA; three
legs across three boots may differ **in the boot alone**, otherwise they measure
the largest confounder ever recorded here. Fix: the legs run band-pinned, and the
leg **shouts** if the band moves anyway.

That defect was found by the very field the *first* rehearsal had shown to be
missing.

## ☠️☠️ NEW DEFECT 2: my own check ruined the measurement

The leg's median sleep came out at **9 s** against a 90 s alarm: 28 samples in
six minutes instead of four, and the gate kept **one** of the 28.

The cause: at 11:49 — mid-leg — I looked at the phone over ssh and with a ping,
to answer a question. **An ssh login is an AP wake.** The same trap had been
written down that morning, addressed to the owner.

The gate's scale is the leg's *own* sleep, so the disturbed leg **still produced
a number** (45.1 mA), and nothing said it was disturbed. Fix: the fit says so —

```
☠️☠️ THIS LEG WAS DISTURBED: median sleep 9 s against a 90 s alarm.
     Something woke the AP - an ssh login, a ping, a poller.
     The number above is not the sleeping floor of anything.
```

Raw output: `rehearsal-2-raw.txt`.
