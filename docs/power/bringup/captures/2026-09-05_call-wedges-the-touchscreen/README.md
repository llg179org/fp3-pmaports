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
