# The measured trigger reproduced on r85, and it did not fail

2026-09-06 06:05. Kernel r85 (`#86-fp3`, `_commit=9c2d03f147c8`). Operator's own
words: *"06:05 hívásos nyomkodós teszt nem bukott"*.

## What was reproduced, deliberately

On 2026-09-05 at 18:23 the touch fault could be dated to its trigger: the failing
read began the second an incoming call arrived, one second after the modem fell
back `lte -> gsm`. This run recreated exactly that:

```
06:05:13  access technology changed (lte -> gsm, gprs)
06:05:14  call ... state ringing-in
06:05:20  call state changed: ringing-in -> active (accepted)
```

and the operator kept tapping throughout — presses #82 to #89 are timestamped
06:05:30, during the active call, with hold times of 56-100 ms and no
irregularity.

**Kernel errors this boot: zero.** No `-110`, no `-6`, no `-5`, no
`timed out, bus`, no `Disabling IRQ`, no `consecutive failed reads`.

## What this is worth, stated honestly

**One sample.** The fault was never deterministic - on r82 it fired five times in
eleven minutes, but with calls involved in only one of the five. A single
successful call-plus-tapping run is the first positive sign for r85, and it is
not proof. The pre-registered bar for #179 is 36 ACTIVE minutes, and this is
about four.

It is, though, the first time the *measured* trigger was recreated on purpose
rather than waited for.

## The instrument, and why it changed twice this morning

The operator's real symptom turned out not to be lag at all: *"6:00 körül 4
leütés helyett csak 1-et írt ki"* - four taps, one digit. Lost taps, not slow
ones, and with **no kernel error of any kind**. A gap logger cannot see that: a
tap that never reaches the input layer leaves no gap, it leaves nothing.

So the logger grew two halves, each proved on a known positive before use:

* **v4 - press counting.** Every `BTN_TOUCH` transition is logged with a running
  count, so a known typed string (the operator types `7777888899988877777`) can
  be compared against what the input layer actually delivered. Proved by feeding
  exactly four synthetic taps through a FIFO: four `PRESS` lines, 50 ms holds.
* **v5 - interrupt vs frame.** `/proc/interrupts` says how often the chip raised
  its line; `SYN_REPORT` says how often the driver delivered. A window with
  interrupts and no frames is a tap the kernel swallowed, and needs nobody
  watching a calculator.

☠️ Two traps caught while building v5, both by testing rather than reasoning:

* The first interrupt parser used a regex expecting **two** fields between the
  counts and the name. The real line has three (`msmgpio  65 Level  hx83112b`),
  so the regex would have swallowed `msmgpio` into the numbers and crashed on
  `int()`. Rewritten to take the leading numeric fields, and tested against that
  exact line: 4768 expected, 4768 returned, `None` for a name that does not
  exist.
* The swallowed-tap detector needed an **in-use gate**. Without it, a chip
  raising periodic interrupts with the screen off would flag every window
  forever - and a detector that always fires detects nothing. It now only
  evaluates when a frame was delivered in the last 10 s.

☠️ And the honest limit on automation: the *stimulus* cannot be automated. A
`uinput` injector would deliver events straight into the input layer, bypassing
the touch controller and the i2c bus - the very things under test - so it would
pass unconditionally. Only the verification half is automatable, and it now is.

## Still unexplained

The 05:57 and 06:00 slowdowns. Neither carried a kernel error, and the gap logger
was not yet running for the first and covered only six seconds of the second. The
one gap it did record was `down=False`, a normal pause between touches, not a
stall. Both remain open, and the instrument now covers the next one from the
start.
