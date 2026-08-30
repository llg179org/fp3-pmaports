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

## ☠️ The instrument that reproduced the trap it was written to study

`decay.sh`, written *after* the finding above, slept fifteen times with a **ten
second** gap between rounds. On a 900 s alarm it produced

```
43 s, 1 s, 3 s, 7 s, 18 s, …
```

which is not a decay curve — it is the disturbed regime measuring itself, exactly
the failure the page above describes, committed within the hour of writing it
down. The gap was a constant chosen without thinking, and recovery here is a
tens-of-minutes process.

**The rule that follows is sharper than "leave a gap":** when an effect has an
unknown time constant, **the recovery interval is the independent variable, not a
setting.** A constant gap — any constant gap — assumes the answer.

`tools/restwake.sh` is the corrected instrument: rest for N minutes doing nothing,
then take **exactly one** sleep on an alarm longer than any sleep yet observed, and
report one number. The rounds vary N; the rounds are the curve. Two details that
are not incidental:

- **one sleep per round**, because a second one would corrupt its own next point;
- the alarm is 1800 s and the script **says so when a sleep hits it**
  (`THE ALARM (so this is a floor, not a value)`), since a sleep that equals its
  alarm is the failure this whole page is about.

`tools/wakesrc-rested.sh` is its per-channel counterpart, for after the curve is
known: rest, then **one traced** sleep, and name the channel whose interrupt ended
it. ☠️ It exists because the 2026-08-22 per-channel census — the one that answered
"IPCRTR, signal-level, not messages" and closed several candidates — ran on
back-to-back short sleeps, i.e. entirely inside the disturbed regime. That answer
may describe only what a freshly woken phone does, not what ends a rested phone's
sleep.


## ☠️☠️ RETRACTED 09:40 — there is no recovery. The 258 s was an outlier.

The corrected instrument answered, and it answered against the page above
(`tools/restwake.sh`, rest as the independent variable, 1800 s alarm so every
sleep ends on the phone's terms):

| rest | slept | ended by |
|---|---|---|
| 2 min | 22 s | modem edge |
| 5 min | 6 s | modem edge |
| 10 min | 3 s | modem edge |
| 20 min | 6 s | modem edge |
| **40 min** | **3 s** | modem edge |

**Leaving the phone alone changes nothing.** Forty minutes of rest buys three
seconds. So the 07:50 reading of 258 s was a one-off, and the entire "disturbed
regime with a decay" hypothesis was built on it — by the same session that had,
an hour earlier, written *"the flattering outlier is the one that travelled"*
into this repository and a rule about it into a skill. **Recording the rule does
not confer immunity to it.**

### What survives, and it is not nothing

- ☠️ **"Every full sleep equals its alarm"** still stands, and is still the
  reason no residency number here ever measured the phone;
- ☠️ **"Back-to-back legs measure the previous leg"** still stands as a
  discipline, even though the specific disturbance it was invoked to explain does
  not exist. The terse A/B is still owed a re-run — not because the arms were
  saturated by a *decay*, but because its alarm was shorter than sleeps this
  phone takes;
- ★ **and the real pattern is now visible, because the recovery hypothesis was
  covering it.** At 02:30 and 05:15 this phone slept its **full** 300 s and 240 s
  alarms. Through the entire morning it never once reached 43 s. The difference
  is not rest, and it is not anything we did — the candidate that fits is **time
  of day**, i.e. traffic arriving from the network, which is diurnal in a way the
  modem's own housekeeping is not.

`tools/radio-off-sleep.sh` is the control that separates those two and nothing
else does: one leg with the radio disabled, A-B-A′, 1800 s alarms.

- radio off and it still sleeps badly ⇒ the modem generates it; the network is
  out of the picture and the lever is on our side
  (`leads/selective-smd-wakeup.md`);
- radio off and it sleeps long ⇒ it comes from the network, and 3GPP power save
  becomes the subject.

☠️ On which: **`libqmi` has no PSM or eDRX control at all** — checked in the tree
at `b7913df`, where NAS carries only a `QMI_NAS_SERVICE_STATUS_POWER_SAVE` status
enum, and the `SET_POWER_SAVE_MODE` hits are the old Gobi API's CTL service,
which is a different thing. So it cannot be requested with the tools present. And
the two are not interchangeable for this goal: **PSM makes the device
unreachable** for the duration, which forfeits exactly what the goal is defined
by, while **eDRX keeps it registered** and only lengthens the paging interval.
Only the second is worth wanting here. Not checked, and therefore not claimed:
whether this modem's firmware supports either, and whether this network offers
eDRX.

### The one DRX lever libqmi *does* expose — and why it is not this one

Re-checked 2026-08-30, one layer more carefully than "libqmi has nothing":
`qmicli --nas-get-drx` exists (NAS `0x0089`, since libqmi 1.28) and is **read
only** — the tree has no `Set DRX`, so it reports a value it cannot change. What
it reports is the **2G/3G CN paging cycle**, whose whole range is
`QMI_NAS_DRX_CN6_T32` … `CN9_T256` (`qmi-enums-nas.h`), i.e. 32–256 radio frames
= **0.32 s to 2.56 s**.

That range settles it without a measurement: the thing under investigation is a
wake roughly **once a minute**, and the longest paging cycle this control can
describe is 2.56 s. Two orders of magnitude apart, so the paging cycle cannot be
what schedules our wakes — and it would not be even if it were slower, because a
paging occasion is serviced inside the modem and only becomes an AP wake when
the modem sends a QMI indication about it. **The AP-visible event is the
indication, not the paging.**

Worth one read anyway (it is free and it is data), but do not spend a session on
it, and ☠️ do not let its name make it look like the eDRX lever: eDRX is a
different, longer-timescale mechanism that this control neither reports nor
sets. The eDRX question therefore stays exactly where it was — needing a raw
QMI message whose id is **not in libqmi and must not be guessed**; an invented
message id is indistinguishable from a real one until it silently does something
else.

### The eDRX question, taken as far as it goes without a device

Searched 2026-08-30, so that the next session does not repeat it:

- **libqmi**: no eDRX and no PSM message of any kind (`grep -ril edrx data/ src/`
  and the PSM/T3324/T3412 spellings all return nothing at `b7913df`). The only
  DRX thing is the read-only paging-cycle report dealt with above.
- **the on-disk vendor tree** (`hadk22/`, the Sailfish/hybris build): searched
  `hardware/` and `vendor/` for `edrx` and for `QMI_NAS_` in headers — **nothing**.
  The telephony side of this device is closed blobs; there is no QMI NAS header
  in the tree to read a message id out of.

So the id is not obtainable from anything we hold, and ☠️ **it must not be
guessed** — a wrong QMI message id is not rejected as nonsense, it is a
*different* message, and one sent to a modem's NAS service with made-up TLVs is
the kind of mistake whose symptom appears somewhere else entirely.

**One admissible device-side step remains**, and it is free:
`qmicli --nas-get-supported-messages` returns the modem's **own** bitmask of the
NAS message ids it implements. If that set contains nothing beyond libqmi's
definitions, this firmware has no eDRX message to call and the avenue is closed
by the modem rather than by our tooling — a real answer either way. If it does
contain more, the extra ids are a *measured* list, which is still not a licence
to decide which of them is eDRX. Wired into `tools/run-wake-qmi.sh` as a
pre-census read, since it costs one awake query.

## 2026-08-30 midday — four windows the modem did not end, and the one correlate worth testing

`captures/2026-08-30_spread/`: four consecutive 600 s alarms, **601 / 601 / 600 /
601 s slept, every one ended by `pm_wakeup_irq=72` — the RTC**. Until then every
short sleep on this front had ended on IRQ 139/141, the modem's SMD edge. The
host's USB log agrees, and it is the better witness because it never touches the
phone.

So the regime is real and it is not subtle: the same configuration gives 52–63 s
in the morning and a filled window at midday. **What flips it is now the
question**, and more samples of one regime cannot answer it — that is what the
four rounds already establish, and why the remaining sixteen were dropped.

### The correlate, stated as a hypothesis and not as a finding

Every long sleep of the day falls **after** the radio-off control at 10:10
(`mmcli --disable` then `--enable`) and the ModemManager restart at 10:27. Every
short one falls before. That is a clean split in time, and it is also **exactly
the shape of a coincidence**: time of day, network load and cell state all split
the same way, and none of them has been measured.

☠️ It is written here because it is testable, not because it is believed. Five
hypotheses were withdrawn on this front in a single day and each was a plausible
story written down before the measurement allowed it. The honest reading today
is: *there is a regime change, and the radio cycle is the only lever we know we
pulled.*

### The test, designed before the result

A‑B‑A′ with the radio cycle as the lever, inside one session so nothing else
drifts:

1. **A** — wait for, or find, the short regime. ☠️ This leg is the hard part and
   it must not be faked: if the phone is filling its windows, there is nothing to
   improve and the experiment has to wait. Do not run B against an A that was
   already long.
2. **B** — `mmcli --disable` / `--enable`, then the same alarm, same path
   (logind), same number of rounds.
3. **A′** — the return leg. Two legs are not a comparison; the day already
   produced two "results" that were drift.

If B and A′ separate, the fix is a **userspace radio cycle** — cheap, reversible,
and it keeps the phone registered, which the low-power arm did not. If they do
not, the correlate was the clock and the search moves to what else changes
between morning and midday: network load, serving cell, signal quality. ☠️ None
of those is recorded in any capture on either side, which is a gap worth closing
in the instrument before spending another day on it.

## 2026-08-30 12:20 — the eDRX avenue is closed by the modem, not by our tooling

`qmicli -d qrtr://0 --nas-get-supported-messages` answers

```
error: couldn't get supported NAS messages: QMI protocol error (71): 'InvalidQmiCommand'
```

so this firmware does not implement the introspection message either. That was
the last admissible route, and all three are now measured rather than assumed:

| route | result |
|---|---|
| libqmi's own definitions | no eDRX or PSM message exists (`b7913df`) |
| the on-disk vendor tree | no QMI NAS header at all; the telephony side is closed blobs |
| the modem's own list of what it implements | `InvalidQmiCommand` |

☠️ **The item closes as blocked, not as answered**, and the distinction is the
point: nothing here says this modem lacks eDRX. It says we cannot ask it with
anything we have, and that **an invented message id stays forbidden** — a wrong
QMI id is not rejected as nonsense, it is a *different* message, and one sent to
a modem's NAS service with fabricated TLVs fails somewhere else entirely.

`--nas-get-drx` is still worth its one line as data, with the caveat already on
this page: it reports the 2G/3G paging cycle (0.32–2.56 s), which is neither the
eDRX lever nor capable of explaining a per-minute wake.
