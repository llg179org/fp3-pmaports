> ⚠️ **AI-generated.** Maintained by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

# The audio DSP never sleeps, and the vendor's does

> **CLOSED 2026-08-22.** Two latches, both fixed and in the package kernel
> since r64: the probe-time mclk hold in `msm8916-wcd-digital`
> (`4b09b2158dd8`) and the dropped SLIMbus stream teardown in
> `qcom-ngd-ctrl` (`dbb414e0be28`). On an ordinary full-stack boot the
> LPASS now duty-cycles and re-enters XO shutdown within ~30 s of audio
> use. Measurements and the corrected attribution of the "second latch":
> findings-log Part II (the former run-book) entries 2026-08-21 12:10 and 2026-08-22 10:30.

## ☠️☠️ 2026-08-27: THE CLOSING BANNER IS FALSE ON THE DEVICE TODAY

The banner above says the LPASS "now duty-cycles and re-enters XO shutdown within
~30 s of audio use", closed on r64. Measured 2026-08-27 on r77 (`#78-fp3`), across
five independent `burst-master.sh` windows of 189 samples each:

* `LPASS_xopct` — the percentage of each 2 s interval the DSP had the crystal shut
  down — is **0 in every sample of every window**;
* `XO total duration` is **9.4 s against 5½ hours of uptime**, i.e. **0.05 %**;
* the oracle, over a 565 s awake-idle window, is **97.1 %**.

That is 80× better than the 0.12 s the page was opened on, and still not sleep.
So the two latches were real and neither of them was the whole thing — **the DSP
is still awake essentially all the time**, and the sentence that closed this page
would have been believed for as long as nobody re-measured it.

☠️ **And it must not now be re-sold as a power lever.** The work below already
priced it: with the DSP *stopped entirely*, the current moved ~4 %, inside the
instrument's own spread. LPASS remains a correctness item and a sufficient
explanation for `vlow` = 0 — not a lever on the floor. The re-opening is about the
banner being false, not about the number being valuable.

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

### ☠️ It did not hold: USB is not the difference

[`../tools/lpass-usb-ab.sh`](../tools/lpass-usb-ab.sh), three alternating rounds
on a fresh boot, 30 s suspend per arm. **`LPASS +0` and `XOdur +0 ms` in all six**
([`../captures/2026-08-19_lpass-usb-ab.txt`](../captures/2026-08-19_lpass-usb-ab.txt)).
The one observed collapse had something else behind it.

**But the header of that same run is the more useful line.** Forty-seven seconds
into a fresh boot the counters already read `shutdowns=3 xo=2 xo_dur=2464840` -
0.128 s. So they **reset at every boot**, and every boot shows two or three
collapses of about 0.12 s in the first seconds and then nothing for hours.

That is not "a DSP that cannot collapse". That is **a DSP that collapses freely
until something opens a session on it, and then never again**. And it puts the
one 30.9 s collapse in its place: it came ten minutes after the ADSP had been
stopped and restarted, with nothing having touched audio since - a second
first-few-seconds, arriving in the middle of a suspend instead of a boot.

The test is [`../tools/lpass-restart-ab.sh`](../tools/lpass-restart-ab.sh): a
plain suspend against a suspend on a freshly restarted ADSP, alternating.

### ★★★ It held: one ADSP restart and the DSP collapses in every suspend after it

[`../tools/lpass-restart-ab.sh`](../tools/lpass-restart-ab.sh), three alternating
rounds, 30 s suspend per arm
([`../captures/2026-08-19_lpass-restart-ab.txt`](../captures/2026-08-19_lpass-restart-ab.txt)):

| round | arm | LPASS | XO off |
|---|---|---|---|
| 1 | plain | +0 | 0 ms |
| 1 | after restart | **+1** | **31 071 ms** |
| 2 | plain | **+1** | **30 846 ms** |
| 2 | after restart | +1 | 30 995 ms |
| 3 | plain | +1 | 30 756 ms |
| 3 | after restart | +1 | 31 259 ms |

**Round 1 plain is the only arm that did not collapse, and it is the only one
taken before the first restart.** So the effect is not "restart, then suspend" -
it is *restart once and it stays fixed for the rest of the boot*, which is why
the plain arms of rounds 2 and 3 collapse too. The crystal is off for 30.7-31.3 s
of a 30 s suspend: the whole of it.

**So something opened at boot holds a session on the ADSP and never closes it.**
Reloading the firmware tears that session down and nothing re-establishes it.
This is the shape the boot counters predicted: free collapses until the first
session, then none.

☠️ **`vlow` stayed 0 in all six arms.** LPASS collapsing is necessary and not
sufficient for the RPM's own low-power mode - something else votes too. The
original claim on this page (a master that never shuts down is a *sufficient*
explanation for `vlow`) is therefore **half wrong**: it was a sufficient
explanation while it was true, and now that it is false `vlow` has not moved.

☠️ **The sensors still answer after the restart** (`in_illuminance_input=7.0`,
`in_proximity_raw=245`), so this is not "the SMGR session died and took the
sensors with it".

### ☠️☠️ What it is worth: about 4 %, and that is inside the noise

Measured overnight, `adsprestart-20260819`, gated on a probe suspend that showed
the DSP collapsing for 30 625 ms of a 30 000 ms suspend before the four hours were
spent. 6 of 6 suspends, every one `slept=901s of 900s`. Raw:
[`../captures/2026-08-20_pmos_adsprestart-leg.txt`](../captures/2026-08-20_pmos_adsprestart-leg.txt).

| phase | window | slope | r² |
|---|---|---|---|
| A (asleep, DSP collapsing) | 4.0547 → 4.0106 V | **−34.32 mV/h** | 0.9885 |
| B (awake control) | 3.9795 → 3.8860 V | −73.13 mV/h | 0.9915 |

**Compare phase-A slopes directly, which is the rule the XO A/B paid for:**

| leg | cut | phase-A slope |
|---|---|---|
| `xo-on-20260818` | — | −35.29 mV/h |
| `xo-off-20260818` | — | −35.44 mV/h |
| `baseline-20260819` | — | −35.77 mV/h |
| **`adsprestart-20260819`** | **ADSP collapsing every suspend** | **−34.32 mV/h** |

**4 % against a baseline that reproduces to 1.4 %.** That is not zero and it is
not a result either: one leg, one arm, and the effect is the same size as two
baselines' disagreement.

☠️ **And the window is lower than the baseline's** (4.055→4.011 V against
4.088→4.059 V). Near 4.0 V the OCV curve is flatter, so the same current produces
a *slower* voltage fall — which biases this leg toward looking better than it is.
The honest reading is **"at most 4 %, plausibly nothing"**, not "4 %".

The awake control is 150.8 mA, which is the figure this instrument has always
reproduced, so unlike the modem leg this one's derived numbers are directly
comparable: **70.8 mA asleep against the baseline's 79.1 mA.**

**So the audio DSP's permanent wakefulness is a real mechanism that costs almost
nothing.** It sits alongside `vlow` never moving: the master goes down, the gate
stays shut, and the current barely notices. Whatever the 43–79 mA of sleep is
spent on, it is not the ADSP being awake.

### ★★ And the holder is named: an LPASS clock the codec never releases

Two measurements, minutes apart, on a fresh boot (2026-08-20 00:06):

**It is not the UCM verb.** [`../tools/audio-hold-probe.sh`](../tools/audio-hold-probe.sh)
dropped the capture pre-route, then the playback route, then put one back, with a
30 s suspend after each. Its first arm is a gate and it passed - the phone was in
the held state, `LPASS +0` as booted - and then **every arm read `LPASS +0`,
`XO off 0 ms of 30000 ms`**. Turning off both q6routing mixers changes nothing.

**It is a clock.** `clk_summary`, one line, with everything else in the LPASS
block at zero:

```
LPASS_CLK_ID_INTERNAL_DIGITAL_CODEC_CORE  enable=1  prepare=1  19200000 Hz  c0f0000.codec  mclk
```

That clock is **provided by the ADSP over APR** (`q6afe-clocks`), and it is held
prepared and enabled from boot. A processor cannot power-collapse while it is
sourcing a 19.2 MHz clock for someone else.

☠️☠️ **CORRECTED 2026-08-20: the holder is not the WCD9335 and not our work.**
The first version of this section read `c0f0000.codec` as "the codec" and
attributed it to this port's WCD9335 MCLK bring-up. Measured on the device:
`c0f0000.codec` is bound to **`msm8916-wcd-digital-codec`** — the SoC's *internal
digital* codec, a different device from the SLIMbus WCD9335 (`217:1a0:*`). It
holds two clocks: `mclk` and `xo` as `ahbix-clk` at enable count 7.

And the mechanism is in upstream mainline, not in anything this port wrote —
`sound/soc/codecs/msm8916-wcd-digital.c`, `msm8916_wcd_digital_probe()`:

```c
ret = clk_prepare_enable(priv->ahbclk);   /* xo, ahbix-clk */
ret = clk_prepare_enable(priv->mclk);     /* LPASS_CLK_ID_INTERNAL_DIGITAL_CODEC_CORE */
```

Both are taken **unconditionally at probe** and released only in `remove()`.
There is no runtime PM and no DAPM gating on either. So the ADSP is pinned awake
from the moment that driver binds until its module is unloaded.

☠️ **The evidence that killed the DAPM explanation is worth keeping**, because it
is what a plausible wrong answer looks like: DAPM's own `MCLK` supply widget reads
**`Off`** and both PulseAudio sources are `SUSPENDED`, while `clk_summary` still
shows `enable=1`. A clock held outside DAPM cannot be released by anything DAPM
does — which is also why the mixer probe's four arms all read zero.

**What this makes it:** an upstream defect affecting every msm8916/8939/8953 board
that instantiates the internal digital codec, and on the FP3 that codec is not
even in the audio path — playback and capture run over the WCD9335 on SLIMbus and
the AW8898 on MI2S. The fix is to take those clocks in runtime PM or in DAPM
rather than at probe.

It fits every observation this page has collected:

- it is taken at probe and never released, so the DSP is free for the first few
  seconds of a boot and held thereafter — which is exactly the counter's shape;
- an **ADSP restart** tears the APR session down and nothing re-enables it, which
  is why one restart frees the DSP *for the rest of the boot*;
- it is a clock, not a DAPM route, so the UCM mixers were never going to matter;
- the stage that removed the q6 stack (S4) never suspended, so it could not have
  seen it either.

☠️ **It is not ours** — see the correction above. The fix belongs in
`msm8916-wcd-digital.c`: take the clocks under runtime PM or from the DAPM supply
widget, instead of at probe.

☠️ **Unconfirmed on the device.** The source is unambiguous and the clock counts
match it, but no experiment has yet unbound that driver and watched the LPASS
counter. The test is one `unbind` and a 30 s suspend. It is cheap, and worth doing
for correctness — but on the leg above it buys about 4 % of the sleep current, so
it should not be scheduled ahead of anything that might buy more.

☠️ **This does not make the mechanism worthless — it makes it cheap and clean.**
Something we start at boot holds a session on the DSP forever; finding and
releasing it is a correctness fix worth having, and possibly an upstream one. It
is simply not the deep-sleep lever, and the next measurement should not be spent
as if it were.

If *that* holds, it reframes the whole page: LPASS does not "never sleep" - **something we
start keeps a session open on it and never closes it**, and the fix is a
release, not a new power-collapse request.

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

## ★★★ 2026-09-01 — the ADSP *does* sleep now, and ModemManager is what stops it

The 2026-08-27 re-opening above says the DSP "is still awake essentially all the
time": `LPASS_xopct` 0 in every sample of five windows, 9.4 s of XO-off against
5½ hours of uptime. That was measured **awake-idle**. Across a **600 s suspend**
on `#80-fp3` the picture is different, and the difference is not the kernel —
it is one userspace daemon.

121 rounds that slept the full ~600 s, from six census runs on two days, read
their LPASS XO-off delta straight out of
`/sys/kernel/debug/qcom_rpm_master_stats/LPASS` on both sides of the sleep:

| run | `mm` | n | LPASS XO-off, median |
|---|---|---:|---:|
| [`2026-08-31_modem-night`](../captures/2026-08-31_modem-night/README.md) | **running** | 43 | **27 s** |
| [`2026-09-01_bearer-arm`](../captures/2026-09-01_bearer-arm/README.md) | **running** | 6 | **19 s** |
| [`2026-09-01_modem-night-control`](../captures/2026-09-01_modem-night-control/README.md) | stopped | 43 | 617 s |
| [`2026-09-01_wifi-up-arm`](../captures/2026-09-01_wifi-up-arm/README.md) | stopped | 12 | 618 s |
| [`2026-09-01_cable-in-arm`](../captures/2026-09-01_cable-in-arm/README.md) | stopped | 11 | 618 s |
| [`2026-09-01_modem-core-cycle`](../captures/2026-09-01_modem-core-cycle/README.md) | stopped | 6 | 618 s |

★ **With ModemManager stopped the ADSP keeps its crystal off for the entire
window** — 617–618 s of XO-off across a 601 s sleep, the counter slightly
overrunning its own bracket because it accrues past the edges. **With
ModemManager running it is awake for 96–97 % of that same window.** The split is
perfect on `mm`, it holds across a reboot, and — importantly — the 2026-08-31
census and the 2026-09-01 night control are **the same boot**, so it is not a
per-boot state.

**What this changes for this page:**

- The 2026-08-19 finding — "LPASS shut down twice since boot, for 0.12 s" — and
  the 2026-08-27 re-measurement were both taken with the full stack up, i.e.
  with ModemManager running. Neither of them isolated the daemon, so neither is
  contradicted; what they measured has a name now.
- The two latches fixed in r64 were real and necessary, but they were not
  sufficient *and they were not the last holder*. Something ModemManager does —
  or something it keeps open on the modem, which in turn keeps the ADSP up — is
  the remaining one.
- ☠️ **It is still not obviously a lever.** The night control priced the daemon:
  stopping it cost 14 mA *more*, not less
  ([`../captures/2026-09-01_modem-night-control/`](../captures/2026-09-01_modem-night-control/README.md)),
  so "stop ModemManager and the ADSP sleeps" is not a saving as it stands. The
  question this opens is which *part* of what the daemon does holds the ADSP up,
  and whether that part can be dropped while keeping the phone usable.

☠️ **Where the mechanism is not yet known.** Nothing here says *how* a modem
daemon holds the audio DSP awake. The obvious shapes are an APR/q6 client the
daemon's voice-call setup leaves open, and a QMI/QRTR path that keeps a shared
resource voted. Neither is measured. The cheap next read is the ADSP's client
list with the daemon stopped and started inside one boot.

☠️ **Confounded, and the control is already running.** Both `mm=running` rows
predate today's `mm=running` control, and one of them also had a data bearer up.
The A′ leg on the phone as this is written is `mm=running` with no bearer, which
fills the missing cell. If its LPASS reads ~20 s, this table is the daemon; if it
reads ~618 s, the separator is something these six runs share with `mm` by
accident and the claim falls.
