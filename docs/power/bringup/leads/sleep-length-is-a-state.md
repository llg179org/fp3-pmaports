# How long the phone sleeps is a state, not a property — and our alarms hid it

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed every measurement it rests on.

**What this retracts.** For a day the modem front was framed as *"something rings
the SMD edge every ~60 s; find the twelfth candidate"*. Eleven candidates had been
killed against that frame. It is the wrong frame, and the evidence was on the
host machine the whole time.

## The census that broke it

The phone's USB gadget drops on suspend and re-enumerates on resume, within a
second of the kernel's own `PM: suspend entry/exit` marks. So the host's `dmesg`
is a complete sleep log that **touches nothing on the phone** — no ssh, no poll,
no wake. Reading the whole of 2026-08-30 off it (`tools/host-sleep-census.sh`):

```
02:30:51 → 02:35:51   300 s      alarm was 300  → hit the alarm
02:41:03 → 02:46:03   300 s      alarm was 300  → hit the alarm
05:15:13 → 05:19:14   240 s      alarm was 240  → hit the alarm
05:19:55 → 05:23:56   240 s      alarm was 240  → hit the alarm
05:24:37 → 05:28:38   240 s      alarm was 240  → hit the alarm
─────────────────────────────────────────────────────────────
06:08 … 07:17        11–76 s     alarm was 240–600 → cut short, every time
─────────────────────────────────────────────────────────────
07:50:42 → 07:55:00   258 s      alarm was 600  → cut short
07:55:21 → 07:55:48    27 s      alarm was 600  → cut short
07:56:09 → 07:56:12     3 s      alarm was 600  → cut short
```

Three things fall out, and each kills something previously written here.

**1. ☠️ Not one sleep in this project has ever been measured against an alarm
longer than it wanted to be.** Every "full" sleep above equals its alarm exactly.
`300/300` and `240/240` are not measurements of how long the phone can sleep —
they are measurements of the alarm. The only sleeps that ever ended on their own
are the short ones, so the "good regime" may never have existed; it may only be
the regime where the alarm was shorter than whatever ends a sleep.

**2. ☠️ The ~60 s is a state with a decay, not a property.** Between 06:08 and
07:17 every sleep collapsed to 11–76 s. Left alone from 07:17 to 07:50 — no ssh,
no measurement, just other work — the next sleep ran 258 s. So the phone recovers
on its own, and the number is a function of what was recently done to it.

**3. ☠️ And what disturbs it is the waking, not the daemon.** The 07:50 series is
one disturbance-free run: 258 s, then 27 s, then 3 s, each starting seconds after
the previous resume. No ModemManager restart, no call, no configuration change
between them. **The act of waking is what shortens the next sleep.**

## What this invalidates

- **every A/B on the residency front, including this morning's terse comparison.**
  Each ran legs back to back, so leg 2 onward were inside the disturbed regime
  regardless of the knob under test. Two arms both in the disturbed regime compare
  nothing. The terse result ("52/61/62/61/63/63 s, no difference") is exactly the
  signature of *both arms saturated by the disturbance*, which is not the same
  finding as "terse does not help";
- **the eleven dead candidates** are not resurrected — but they were all killed
  against a frame that assumed a fixed ~60 s periodicity, so the ones killed by
  "the duty did not change" are worth re-reading before the twelfth is sought;
- **"the modem edge terminates every suspend"** is a statement about the disturbed
  regime only.

## The measurement discipline this forces

- ☠️ **Set the alarm longer than the answer you expect, or you are measuring the
  alarm.** A sleep that equals its alarm carries no information about duration.
  This is the sleep-shaped instance of a rule already in `/fp3-kernel-test`: every
  measurement needs a path to a result that is not the instrument's own bound.
- ☠️ **Leave a recovery gap between legs, and prove it was enough.** Back-to-back
  legs measure the previous leg. How long the gap must be is itself unknown —
  `tools/decay.sh` measures it, by sleeping repeatedly on a long alarm and
  plotting sleep length against time since the last disturbance.
- **Read the host's log, not the phone's, wherever it will answer.** It is free,
  it has no observer effect, and here it was the only witness that could see the
  pattern at all — three generations of on-device instrument were written and
  debugged before it was used once.

## Open

- **the shape of the recovery**: does sleep length climb back smoothly, in steps,
  or only after a fixed timeout? Running: `decay.sh none 15 900` — fifteen sleeps
  on a 900 s alarm, longer than any sleep yet observed, so each one ends on its
  own terms and the number is the phone's, not the alarm's;
- **what the disturbance actually is.** "Waking" is not a mechanism. Candidates
  worth separating: the resume path itself, the USB gadget re-enumerating, the
  modem re-syncing after `PrepareForSleep`/resume, or a queue of indications
  delivered on wake and re-armed each time;
- **then, and only then, re-run the knobs that were tested inside the disturbed
  regime** — terse first, since it is the one with a plausible mechanism.
