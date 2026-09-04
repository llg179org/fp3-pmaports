# The i2c stall does not interrupt audio. 2026-09-04, 60 probes, two witnesses.

## The measurement

60 automated probes, 15 s apart, with a 440 Hz tone playing throughout and the
touchscreen driver unbound so nothing could collide with the probe.

```
probe 3   dur=14.9915 s (STALL)   wall=15 s   audio_advanced=15.09 s   state=RUNNING
60 probes · 1 stall · 0 audio shortfalls
```

Across the 15 s in which the i2c transaction was hung, the card played **15.09 s
of audio in 15 s of wall clock** — it lost nothing. The operator, listening
independently and without being told what the instrument said: *"I perceived the
sound as continuous."*

**Two witnesses of different kinds agree.** The stall is confined to that one i2c
controller: it is not a shared clock, not a shared power domain, not a
system-wide stall. The audio path (a different QUP controller plus the ADSP) runs
straight through it. That excludes a whole class of explanations.

☠️ The audio measure is `tstamp` from the PCM substream, **not** `hw_ptr` — that
field does not exist in this status file, and the parser written for it would
have returned nothing for sixteen minutes while the campaign happily reported
"no shortfall". It was validated first against a known answer: 4.016 s of audio
across 4 s of wall clock.

## The rate, and how the human and automated data unify

The operator asked how often the automated test probes, and the answer reframed
everything. They tapped a calculator about once a second; the ledger records
**51 touch interrupts per active second (max 121)**, each one an i2c read. The
automated probe does **one read every 15 s** — a factor of ~760 apart.

Yet the automated probe stalls far more often *per read*. Both are explained on
one denominator — **the first access after the controller has been idle**:

```
operator session 12:29-13:19
  38 721 i2c reads, 15 stalls   ->  0.039 % per transaction
  109 pauses >= 2 s             ->  13.8 % per resume

automated probe (every probe IS a first-access-after-idle)
  rate campaign   1 / 20        ->  5.0 %
  audio campaign  1 / 60        ->  1.7 %
```

Per transaction the two differ by three orders of magnitude; per *resume* they
are the same phenomenon at the same order. 109 pauses x ~14 % predicts ~15
stalls, and 15 were observed.

☠️ This also retires a worry from earlier in the day. The rate campaign found no
trend between 10 s and 60 s of idle and I read that as "idle length does not
matter". It means the opposite: the controller autosuspends after **1 s**, so all
five levels were already past the threshold. The interesting range is *below* one
second, and nothing has been measured there.

## Next, and it needs no human

Probe at 0.2 / 0.5 / 0.8 / 1.5 / 3 s idle. If everything under 1 s is clean and
everything over it stalls, the runtime autosuspend is the trigger, demonstrated
rather than argued — and the fix follows from it.
