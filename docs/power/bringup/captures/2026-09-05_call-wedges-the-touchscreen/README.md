# ★ An incoming CS call wedged the touchscreen for three minutes — on r82

2026-09-05 18:10–18:14, pmOS `linux-fp3-7.1.3-r82` (source `3f843d0534e3`, which
**carries the touchscreen supply fix**), phone on battery and Wi-Fi, screen on,
operator reported the fault while using the phone normally.

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who observed the fault and reported it. MSISDN and
> IMSI masked; raw journal in `raw.txt`.

## The sequence, from the persistent journal

```
18:10:54  modem: radio_access_technology = '3gpp-geran',
                 extended_data_bearer_technology_3gpp = 'edge'      <- the call is on CS fallback
18:10:54  "couldn't load initial default bearer properties:
           Couldn't get LTE attach parameters: QMI protocol error (74)"  <- consistent: not on LTE
18:10:56  call state changed: ringing-in -> terminated
18:10:56  gnome-calls: Incoming call (5) -> Call ended (7)
18:10:57  kernel: qcom,slim-ngd.1: TX timed out:MC:0x21,mt:0x2
18:10:57  kernel: wcd9335-slim: TX timed out:MC:0x21,mt:0x2         <- the audio path tearing down
18:11:06  kernel: Himax-hx83112b-TS 3-0048: Failed to read input event: -5
   …      ~158 per second, without a gap, for three minutes
18:14:07  the last one — ended by an operator-initiated driver rebind
```

**Nine seconds after an incoming CS call ended, the touch controller wedged.**
The panel was not dead in the sense of silent: its **interrupt kept firing at the
same ~158/s** as the failing reads, so the controller was asserting IRQ
continuously and every i2c read returned `-5` (EIO).

## ☠️ What the operator actually sees: a key held down, not a dead screen

Reported alongside the freeze: **the calculator's `7` key stayed pressed**, and
the app had to be restarted to clear it.

That is a sharper description of the fault than "the touchscreen froze", and it
constrains the mechanism. A stuck key means userspace received a **touch-down
that never got its touch-up**: the controller wedged *while a finger was on the
glass*, mid-gesture, and the last state it managed to deliver was "contact
present at this coordinate". Everything after that was `-5`.

It also explains the interrupt behaviour. The controller had a pending touch to
report and kept **asserting IRQ at the same ~158/s as the failing reads** — it
was not silent, it was trying, and every read failed.

For the user this is worse than an unresponsive panel: an application receives a
button press with no release and stays in that state until it is restarted, even
after the driver recovers.

## Why this matters more than #142

| | #142, as characterised | this |
|---|---|---|
| error | `-110` (ETIMEDOUT) then `-6` | `-5` (EIO), **only** |
| duration | ~15 s, the QUP timeout constant | **3 minutes**, until a rebind |
| recovery | self-recovers | **needs `unbind`/`bind`** |
| trigger | first access after ≥10 s idle, screen off | **an incoming CS call ending**, screen **on** |

`-110` did not occur once in this boot. This is a different failure mode, and a
worse one: an operator whose phone does this has no touchscreen until something
rebinds the driver.

☠️ **It happened on a kernel that carries the supply fix**, with both rails
consumed (`3-0048-iovcc`, `3-0048-vdda` present throughout). So the fix does not
prevent this. Whether it *caused* it — by changing the controller's power state
across the display and modem transitions — is **not established**: this is one
occurrence.

## The recovery that works

```sh
# ☠️ screen must be On; rebinding with it off returns -5 and leaves no touchscreen
echo 3-0048 > /sys/bus/i2c/drivers/Himax-hx83112b-TS/unbind
echo 3-0048 > /sys/bus/i2c/drivers/Himax-hx83112b-TS/bind
```

Measured: **682 errors in 4 s before, 0 in 6 s after**, and zero since.

## What would turn one occurrence into a finding

- **A second call.** If another incoming CS call wedges it again, the trigger is
  real. That is one call, and it costs nothing.
- **The same call on r79.** r79 predates the supply fix (`5aafd59e`) and is in
  the boot menu as a fallback label. If r79 does *not* wedge, the fix is
  implicated; if it does, the fault is older than the fix and was simply never
  seen because nobody made a call while watching.
- ☠️ Whatever is measured, **the kernel ring buffer cannot hold it**. 158 lines a
  second overwrote the whole buffer in about two minutes, and the first attempt
  to read this fault reported "zero occurrences this boot" from a `dmesg` that
  had already lost them. Use `journalctl -k -b`, which persisted all of it.

## Also answered here, incidentally

The operator's standing question — does a call come in on EDGE or on VoLTE — is
answered by the same capture, from the modem's own report rather than from a UI:
**`3gpp-geran` / `edge`**. With the IMS switches held off, the call arrives by CS
fallback, as designed.

## ★★ The second call reproduced it — as the CLASSIC #142 signature

A second incoming call was placed deliberately, with a watcher sampling the RAT,
the call state and the touch-error count together (`call2-watch.log`):

```
18:19:13  tech=lte        calls=0  touch_err=0
18:23:39  tech=gsm,gprs   calls=0  touch_err=0    <- the RAT drops to 2G THREE SECONDS BEFORE the call is signalled
18:23:42  tech=gsm,gprs   calls=1  touch_err=0
18:23:56  tech=gsm,gprs   calls=1  touch_err=2    <- errors, during the call
18:24:13  tech=lte        calls=0  touch_err=2    <- call over, back to LTE
18:24:39  tech=lte        calls=0  touch_err=2    <- stable; no storm this time
```

and the two errors are:

```
18:23:54  Himax-hx83112b-TS 3-0048: Failed to read input event: -110
18:23:54  Himax-hx83112b-TS 3-0048: Failed to read input event: -6
```

**That is #142 exactly** — `-110` then `-6` — and the timing closes the argument:
the call was signalled at **18:23:39** and the log line appears at **18:23:54**,
**fifteen seconds later**, which is the i2c-qup transfer timeout constant. The
transfer hung at the moment of the fallback; the message is simply when the
timeout expired.

### ☠️ So the supply fix does NOT eliminate the operator-visible fault

r82 carries all three touchscreen-supply commits, and both rails had consumers
throughout (`3-0048-iovcc`, `3-0048-vdda`). The `-110`/`-6` pair happened anyway.

The mechanism the fix addressed is real and was measured — before it, `l6` fell
to **zero** voters when the display powered down; after it, the touch node keeps
one. That measurement stands. What falls is the **inference** that it was the
whole cause of #142. It was not.

### And the trigger is sharper than the one on record

`docs/touch/142-i2c-stall.md` characterises the fault as *first access after
≥10 s idle, with the screen off*. Neither held here: the screen was **on**, the
phone was **in use**, and the trigger was an **incoming CS call** — twice in
fifteen minutes, once as the `-5` wedge and once as the `-110` stall.

### Whole-boot tally

| code | count |
|---|---|
| `-110` | 1 |
| `-6` | 1 |
| `-5` | 28 608 |

Two distinct failures, one shared trigger.

### Also settled, twice now

The call arrives on **2G** — `tech=gsm,gprs`, and the modem's own call record says
`mode = 'gsm'`, `direction = 'mt'`. The RAT drops **before** the phone rings, so a
sampler started at the ring has already missed the transition.
