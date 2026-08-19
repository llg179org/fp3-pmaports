> ⚠️ **AI-generated.** Maintained by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

# The audio DSP never sleeps, and the vendor's does

## The finding

**LPASS shut down twice since boot, for 0.12 s in total.** On the vendor stack,
on the same hardware, it shuts down thousands of times and keeps the XO off.

Read from `/sys/kernel/debug/qcom_rpm_master_stats/` on 2026-08-19, against the
Ubuntu Touch oracle capture of 2026-08-15
([`2026-08-15_ut_oracle_rpm-master-stats.txt`](../captures/2026-08-15_ut_oracle_rpm-master-stats.txt)):

| master | shutdowns, pmOS | XO duration, pmOS | shutdowns, UT | XO shutdowns, UT |
|---|---|---|---|---|
| APSS | 816 039 | **0** | 19 269 | **0** |
| MPSS | 83 790 | ~5.5 h | 1 151 | 1 132 |
| PRONTO | 230 552 | ~6.7 h | 3 045 | 3 045 |
| **LPASS** | **2** | **0.12 s** | **4 344** | **4 280** |
| TZ | 0 | 0 | 0 | 0 |

☠️ **The counter is live and was shown to be.** Over one 60 s window with the
phone idle: APSS +1038, MPSS +188, PRONTO +529, **LPASS +0**. Three counters
move and one does not, so "2" is a measurement rather than a stuck file - which
is the check that a number this convenient has to pass before it is believed.

The APSS row is a bonus consistency check: the vendor's application processor
does not shut the XO down either, which is independent confirmation that closing
the XO branch was right.

## Why it matters

`qcom_stats/vlow` and `vmin` have read **Count: 0** in every capture ever taken
on this device - through the PLL fix, the RPM handshake fix, the XO A/B, and the
leg that saved 36 mA by cutting the modem. The RPM enters a low-power mode only
when the masters let it. **A master that never shuts down is a sufficient
explanation for a gate that never opens**, and LPASS is the only one in that
state.

It also fits the shape of the rest of the investigation:

- Five userspace candidates measured, all zero. The current is not in a service.
- ~25 mA of the awake floor is the panel, accounted for.
- Awake and dark is ~58-63 mA; asleep is ~43-79 mA. **Suspend buys very little**,
  which is what a permanently-awake DSP would produce regardless of what the
  application processor does.

## What is NOT yet established

☠️ **That the sensor stack is the holder.** Stopping `snsregd` and
`iio-sensor-proxy` and waiting three minutes did not move the counter - but
three minutes is short, and the negative only says those two are not sufficient
on their own. Something else may hold it, or nothing may release it.

☠️ **That LPASS *can* shut down on this kernel at all.** The oracle proves the
hardware does it; it does not prove our firmware load, our q6 stack and our
sensor clients leave a path to it.

☠️ **That fixing it recovers a specific number.** No current has been attributed
to LPASS yet. This is a named mechanism for a gate, not a measured term.

## ★★ Measured 2026-08-19 night: no client holds it, and killing the DSP does not open the gate

Step 1 ran as the first job of the first unattended night
([`../night/lpass-holders.sh`](../night/lpass-holders.sh), six stages, 240 s
each, the counter re-verified live in every one). Raw:
[`../captures/2026-08-19_lpass-holders.txt`](../captures/2026-08-19_lpass-holders.txt).

| stage | what was removed | APSS | MPSS | PRONTO | **LPASS** | vlow |
|---|---|---|---|---|---|---|
| S0 | nothing (control) | +4322 | +753 | +2107 | **+0** | 0 |
| S1 | `snsregd`, `iio-sensor-proxy` | +4275 | +753 | +2064 | **+0** | 0 |
| S2 | the SMGR drivers, all six | +4301 | +758 | +2100 | **+0** | 0 |
| S3 | `fp3-voiced`, `spkwatch`, `ringwatch` | +4640 | +755 | +2098 | **+0** | 0 |
| S4 | ☠️ **nothing — see below** | +4696 | +753 | +2102 | **+0** | 0 |
| S5 | **the ADSP itself** (`state=offline`) | +4267 | +752 | +2114 | **+0** | 0 |

Every stage passed its own counter-live check, 3 of 3 other masters moving.

**S5 is the one that matters, and it is a negative.** With the audio DSP stopped
outright - not idle, not unloaded, *offline* - the RPM still recorded no LPASS
shutdown and `vlow` still read 0. Whatever holds that gate shut, removing the
ADSP from the picture does not open it.

☠️ **S5 could not have succeeded, and that is a criticism of the stage rather
than a result about LPASS.** The counter it reads is a count of *handshakes*: a
subsystem increments it by telling the RPM it is going down. A subsystem that has
been halted does not perform that handshake at all - it is absent, not asleep -
and its last vote plausibly still stands. So "the ADSP was offline and LPASS did
not shut down" is what the instrument would print either way, and the stage
carries no information about who holds LPASS.

What S5 *does* say is narrower and still worth having: with the audio DSP
entirely out of the picture, `vlow` did not move. Whatever else is true, removing
that processor is not by itself enough to open the gate.

☠️ **The stages that could have succeeded - S1 through S4 - never suspended.**
They sampled a phone that was awake, and an awake application processor is a
reason for the DSP to stay up regardless of who else wants it down. That is the
flaw the next section walks into by accident and out of by luck.

☠️ **S4 was not a cut and the instrument said so.** Every q6 module stayed
loaded, `snd_soc_apq8016_sbc` at refcount 3 with **no module users listed** - the
references were the bound sound card, so `rmmod` could never have removed them.
The stage ran its full dwell and printed an LPASS delta having changed nothing.
It is only not a false finding because the script printed `still loaded`
immediately above the delta. Fixed: S4 now unbinds `c051000.sound-card` from
`qcom-apq8016-sbc` first, and says plainly when it cannot.

## ★★★ And then it collapsed - once, in the one suspend taken without USB

Not planned, and not visible to the stage table at all. It was caught because
[`../night/guardian.sh`](../night/guardian.sh) samples every 30 seconds through
everything else that runs, and the transition landed between two of its lines:

```
up=35219 ... lpass_shut=2 vlow=0 susp_ok=7      <- USB bound
up=35280 ... lpass_shut=3 vlow=0 susp_ok=8      <- USB unbound
```

`XO total duration` went 2 314 203 -> **593 000 251** ticks in the same window:
at 19.2 MHz that is 0.12 s -> **30.9 s**, i.e. the audio DSP kept the crystal off
for the *entire* 30-second suspend.

The eighth suspend of the boot was the one run by
[`../tools/usb-off-census.sh`](../tools/usb-off-census.sh), with `7000000.usb`
unbound from `dwc3-qcom` and `79000.phy` from `qcom-qusb2-phy`. The seventh, ten
minutes earlier, was a 30 s suspend with the same freshly-restarted ADSP and USB
attached, and LPASS did not collapse once.

**Two suspends, one difference.** ☠️ **n=1 on each side** - that is a lead, not a
result, and the A/B that alternates the two conditions is
[`../tools/lpass-usb-ab.sh`](../tools/lpass-usb-ab.sh).

If it holds, it reframes the whole page: LPASS does not "never sleep", it does
not sleep *while a USB cable is enumerated* - which has been true of every
measurement this investigation has ever taken, including every asleep current in
[`../../README.md`](../../README.md).

☠️ And it is the second time in one hour that USB turned out to be the difference
- the first was the [rail census](rpm-sleep-set.md), where four of five suspect
rails were the PHY's. The instrument that carries the data off the phone is
inside every measurement of the phone.

**So the lead is weakened where it was strongest and strengthened where it was
not.** LPASS remains the only master that never
shuts down, and that remains a sufficient explanation for `vlow`. What has been
removed is the easy version of it - "one of our clients is holding it" - which
was the version a patch would have come from.

## The next measurements, in order

1. ~~**Who holds it.**~~ **Done 2026-08-19, negative - see above.** The ADSP has clients on this kernel: the q6 audio stack
   (`q6afe`, `q6adm`, `q6asm`, `q6core`, `apr`) and the SMGR sensor drivers
   (`smgr`, `sns_smgr`, `smgr_accel/gyro/prox/mag`). Remove them in groups and
   watch the counter, longest-idle first.
2. **Whether it can.** If no combination moves it, the question becomes whether
   the ADSP is ever told it may sleep - the vendor sends explicit power-collapse
   requests over APR that mainline may simply not send.
3. **What it is worth.** Only once it moves: a slope leg with LPASS actually
   shutting down, against `baseline-20260819`.

☠️ Do not write a patch before step 1. The XO branch was mechanically plausible,
moved its counter from 0 to 1952, and changed the discharge slope by nothing.
