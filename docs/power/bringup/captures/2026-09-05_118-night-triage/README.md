# #118 — the morning triage: the night failed, and so did the one before it

Evaluated 2026-09-05 03:15, against
[`../2026-09-02_night-replication/PREREGISTERED.md`](../2026-09-02_night-replication/PREREGISTERED.md),
which was written before either night's data existed. Raw:
`triage-output.txt`, `run.log`, `ocv.txt`; instrument
[`../../tools/night-triage.sh`](../../tools/night-triage.sh).

## The verdict, in the triage's own order

**1-3, the validity gates that come first: clean.** Zero ssh logins, zero
unexpected units, zero incoming calls on all three legs. The service vector was
verified off on each (`voice=False VoWiFi=False SMS=False UT=False`). Band and
cell identical throughout, `eutran-1 / 1470762`, start and end of every leg.
Nothing external disturbed this night.

**4, the OCV endpoints: both suspect.**

```
rest start hit its 90 min ceiling without settling   -2.02 mV/min, drift -26 mV
rest end   hit its 30 min ceiling without settling   -0.83 mV/min
```

**5, the legs: all three dropped.**

```
leg1   median sleep 13 s   47.9 mA  [46.8, 49.1]   DROPPED
leg2   median sleep 18 s   47.7 mA  [46.4, 48.9]   DROPPED
leg3   median sleep  9 s   45.7 mA  [43.6, 47.8]   DROPPED
                           against a 90 s alarm
```

**6, the object of the whole exercise:** `means: 0.0 0.0 0.0`, boot-to-boot
sd = 0.0 — not because the legs agreed but because **no leg survived to be
averaged**.

## What this does to the pre-registration

Nothing, and that is the correct outcome to record. Every predicted band -
leg means around 40.3 ± 5 mA, boot-to-boot spread < 5 mA, rest current 25-35 mA,
ΔQ 270-330 mAh - sits *downstream* of validity gates that failed. The honest
form is not "the predictions were wrong" but **the data never became eligible
for comparison**.

☠️ One tempting reading has to be refused explicitly. The three dropped legs
agree with each other to within **2.2 mA** - 47.9, 47.7, 45.7 - which looks like
exactly the tight boot-to-boot band the night was run to find. It is not. Those
numbers describe an AP that woke every 9-18 s, so they are not a sleeping floor;
what their tightness shows is that the *wake pattern* is highly reproducible,
which is a different and more interesting fact.

## ☠️ The same failure, twice

[`../2026-09-02_night-replication/triage-output.txt`](../2026-09-02_night-replication/triage-output.txt),
the night before:

```
rest start hit its 90 min ceiling   -0.91 mV/min      (suspect)
rest end   hit its 30 min ceiling   -0.78 mV/min      (suspect)
leg dropped: unexpected units: Network Manager Script Dispatcher Service;;
             median sleep 11 s against a 90 s alarm
```

Two consecutive nights, both halves failing the same way: the AP will not stay
asleep for 90 s, and the pack will not rest inside the ceilings. This is not bad
luck, it is the measurement as designed being unable to produce its number on
this device.

It also fits what was established independently on 2026-09-04: **nothing on this
phone asks for a suspend** (`leads/opportunistic-sleep-missing.md`), so the only
sleeps are the ones a measurement forces - and when it forces them, something
ends them within seconds.

## What blocks the next attempt, concretely

☠️ **Corrected the same evening — see
[`WHY-THE-LEGS-FAIL.md`](WHY-THE-LEGS-FAIL.md).** This was too strong. The
2026-09-02 night *did* name its wake source (NetworkManager retrying a DHCP lease
197 times in a 77-minute leg) and `night-run.sh` carries the fix; on 2026-09-03
that fix worked and leg 1's window holds **zero** NM/DHCP lines - one journal
line in seventy-six minutes - and the leg failed anyway. The accurate statement
is narrower and worse: the known wake source was found, mitigated, and the night
still failed, so whatever ends these sleeps is below the journal. That page also
finds that legs 2 and 3 ran with `ModemManager --log-level=DEBUG` while leg 1 had
no ModemManager at all, so the three legs were not comparable to each other
either. The legs record `log.txt`, `mpss-B.txt`, `samples-B.txt` and nothing else
- no `wakeup_sources` snapshot, no wake-reason capture. The triage says "naming the source buys the next run, not
this leg", and the next run cannot name it either unless the instrument is
changed to record it.

So the prerequisite for a third attempt is an instrument change, not another
night: capture `/sys/kernel/debug/wakeup_sources` (or the equivalent
wake-reason) across each leg, and only then re-run. Repeating the night
unchanged would produce a third identical failure.

## What is NOT touched

`docs/power/README.md` already states the cheap state honestly - *"leg of one
boot, 40.3 ± 1.3 mA within-leg, calibration unbounded"* - and poses the open
question *"is 40.3 mA a number or a leg?"*. That question stays open; only its
pointer needed updating, because the replication route it named has now been
tried twice and failed.
