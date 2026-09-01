# ★★★★★ Wi-Fi is not the lever — and the modem's wake is 9× longer without the cable

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed the measurement it rests on.

2026-09-01 05:57 → 08:07, **12 rounds**, cable out, **Wi-Fi up and associated**,
panel dark, ModemManager stopped. Battery 48 % → 47 %.

Tool: [`../../tools/modem-night.sh`](../../tools/modem-night.sh) `2 600 15 stopped up out`
— the `wifi=up` arm added the same morning. [`fit.txt`](fit.txt), raw in [`raw/`](raw/).

## Why it ran

One window on 2026-08-31 read **5.0 %** MPSS awake with ModemManager stopped
([`../2026-08-31_mpss-across-suspend-nomm/`](../2026-08-31_mpss-across-suspend-nomm/README.md)),
and the 47-round control of the same daemon state read **35.7 %**
([`../2026-09-01_modem-night-control/`](../2026-09-01_modem-night-control/README.md)).
That single window differed from every night in two ways at once — Wi-Fi up, and
the cable in. This arm separates them by moving only Wi-Fi.

**Pre-registered:** ~5 % ⇒ Wi-Fi up is the first D-track lever found; ~34–36 %
⇒ Wi-Fi is not it, and the difference is the cable or n=1.

## Result: ~36 %. Wi-Fi is not it.

| arm | Wi-Fi | MPSS awake |
|---|---|---:|
| control, 2026-09-01 | down | 35.7 % (logind) / 36.7 % (rtcwake) |
| **this arm** | **up, associated** | **36.2 % (logind) / 37.6 % (rtcwake)** |

Twelve rounds, all sleeping the full 600 s, all ended by `56 pm8xxx_rtc_alarm`.
That also reproduces the control's other finding a third time: with no daemon,
nothing wakes the AP, Wi-Fi up or down.

☠️ **No mA from this arm.** Two hours moved the pack 15.4 mV, and
`sleep-night-fit.py` refuses the fit in its own words — "residual is a large
fraction of the total travel - this fit is noise-dominated". The number it would
have printed (29.1 mA, rms residual 70 mAh against ~60 mAh of travel) is not
quoted anywhere for that reason. The arm was run for the duty, and only the duty
is reported.

## ★★★★★ What the pooled data now says, and the signature it produces

Every sleep window this project has taken with ModemManager stopped, across two
Wi-Fi states and two days:

```
n = 55 usable windows      min 33.4 %   max 42.9 %   mean 36.3 %
below 30 %: 0      below 20 %: 0      below 10 %: 0
```

**The 5.0 % reading has no companion in 55 samples.** Whatever it was, it is not
the normal behaviour of this phone with the daemon stopped.

> ☠️☠️☠️ **CORRECTED 2026-09-01 midday — "the 5 % has no companion" is false, and
> the variable is the boot.** The 5 % is **four** measurements over 34 minutes on
> 2026-08-31 05:38–06:12: legs A, B and A′ of
> [`captures/2026-08-31_mm-duty-ab/`](../../captures/2026-08-31_mm-duty-ab/README.md)
> (5.1 / 4.9 / 4.9 %) plus the 05:52 sleep window (5.0 %). **Leg B ran with
> ModemManager running, `registered`, `access tech: lte`, `attached` on vodafone
> HU** — so it is not a deregistered or powered-down modem.
>
> And every reading in this whole story — the 5 % episode and all 67 later
> windows — comes from **one uninterrupted boot**, started 2026-08-30 14:00:11:
>
> | measurement | uptime | MPSS awake |
> |---|---:|---:|
> | `mm-duty-ab` A/B/A′ + the 05:52 window | **16 h** | **4.9 – 5.1 %** |
> | the 86-round census | 22–30 h | 33.6 % |
> | the 47-round control | 31–40 h | 35.7 % |
> | the Wi-Fi-up arm | 40–42 h | 36.2 % |
> | the cable-in arm | 42–44 h | 35.5 % |
>
> ⇒ **The duty stepped from ~5 % to ~34 % inside a single boot** and has stayed
> there for 28 hours through every configuration tried — daemon on and off, Wi-Fi
> up and down, cable in and out. Nothing I varied moved it because **the variable
> was never a configuration**: it is elapsed state within the boot, or something
> done to the phone between 06:12 and 11:48 that morning. That is what
> [`tools/duty-vs-uptime.sh`](../../tools/duty-vs-uptime.sh) was written to ask and
> [`leads/sleep-length-is-a-state.md`](../../leads/sleep-length-is-a-state.md) already
> says about sleep length.
>
> **The good news is the size of it:** this stack *can* run a registered, attached
> LTE modem at 5 % duty. The D-track target is not hypothetical — it has been
> observed on this phone.

Decomposing the duty into how *often* the modem leaves XO shutdown and how long
it stays up each time is what makes the difference legible — the counters carry
both (`xo_total` and `xo_shutdowns`):

| | cycles/s | down per cycle | **awake per cycle** | down |
|---|---:|---:|---:|---:|
| control (Wi-Fi down, cable out), n=47 | 2.45 | 260 ms | **148 ms** | 63.6 % |
| this arm (Wi-Fi up, cable out), n=12 | 2.42 | 260 ms | **148 ms** | 63.1 % |
| the 5 % window (Wi-Fi up, **cable in, charging**), n=1 | 3.14 | 303 ms | **16 ms** | 95.0 % |

⇒ **The modem wakes at a similar rate in all three. What changes is how long each
wake lasts: 148 ms against 16 ms, a factor of nine.** That is a much more specific
target than "duty", and it rules out the intuitive story — this is not the network
paging us more often.

☠️ It also puts a number on something nobody had looked at: **the modem leaves XO
shutdown about 2.4 times a second, all night, in every configuration.** Whatever
that clock is, it is not LTE paging DRX, which is on the order of a second.

## What is left, and it is one variable

The 5 % window was taken with the cable **in and the battery `Full`** — the raw
capture says `# charger=Full` in its own header. So it differs from all 59
cable-out windows in exactly one remaining respect, and that respect is now
testable with n>1:

```sh
modem-night.sh 2 600 15 stopped up in     # cable in, input cut, Wi-Fi up
```

☠️ Note this also means the 5 % window was taken on a **charging** phone while the
48 mA floor it was paired with was taken on a **discharging** one — a third
mismatch in that pairing, on top of the two different runs and two different days
already recorded in the control capture.
