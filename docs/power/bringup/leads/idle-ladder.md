> ⚠️ **AI-generated.** Maintained by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

# The idle decomposition ladder

## The hole this fills

After the PLL fix, the RPM handshake fix and the XO A/B, **no mechanism accounts
for even 20 mA of the ~60 mA** the phone draws when it should be idle. Every
patch written before that budget exists is a guess, and the XO A/B is the proof:
it was a mechanically plausible story, it moved the APSS XO shutdown count from
0 to 1952, and it changed the measured discharge slope by nothing at all.

The ladder is not a fix. It is the list of terms.

## ☠️ It decomposes AWAKE idle, and that is on purpose

Every stage runs with the kernel running. The number this investigation is
chasing - ~60 mA - is a *suspended* figure, so it is worth saying why an awake
ladder is the right instrument for it rather than a detour.

The two regimes are close. The suspend leg of 2026-08-17 put the sleeping phone
at about 60 mA; this ladder's first S0 sample read 85 mA with the session
stopped and the panel dark. **s2idle roughly halves the draw and no more**,
which means most of what the phone burns awake is still burning with the kernel
frozen. A term that is large awake is therefore a candidate for being large
asleep - the ladder narrows the search cheaply, in twenty-minute stages that
never touch suspend and never touch the eMMC.

What it cannot do is *prove* a term survives suspend. That is what step 4 of the
night is for: one full slope leg with whatever the ladder names largest actually
cut, measured asleep. **The ladder proposes; the slope leg decides.**

## Why one boot, not four reboot-matched legs

The original plan was four separate legs, each from its own boot. The XO A/B
killed that plan by measuring the variance it would have to fight: the same
phone, in the same state, eight hours apart, gave **150.1 mA** for its awake
reference one time and **161.0 mA** the other. Seven per cent of boot-to-boot
spread, against terms we are trying to resolve at ten milliamps.

A ladder inside one boot pays no boot-to-boot variance at all. What it pays
instead is drift - with time, temperature and state of charge - and that is
measurable rather than assumed. **Stage R restores everything and re-runs the
baseline.** If R returns to S0, the ladder is sound. If it does not, the gap is
the error bar, it gets quoted, and every marginal smaller than it is noise.

## Why cumulative

Each stage keeps the previous stage's cuts, so a stage's number is the
**marginal** cost of that step *given everything above it is already gone*. That
is the quantity that decides what to fix next, and it is deliberately not the
same as each item's cost measured alone: two consumers that hold the same rail
up look free individually and expensive together, and a ladder shows that while
four isolated legs hide it.

The price is that the ladder answers in its own order. A different order would
attribute a shared rail to a different stage. That is a real limitation, not a
flaw to be argued away - if a marginal matters, it gets its own experiment.

## The stages

| stage | what is removed (cumulative) | the suspicion |
|---|---|---|
| S0 | nothing; session stopped, panel dark | the floor everything else is measured against |
| S1 | `cups` `avahi-daemon` `bluetooth` `udisks2` `tuned` `tuned-ppd` | desktop-distro services that no phone needs; free to remove if they cost anything |
| S2 | `snsregd` `iio-sensor-proxy` | the sensor stack talks QMI to the ADSP continuously; a plausible reason LPASS never idles |
| S3 | `spkwatch` `ringwatch` `fp3-voiced` | **our own** additions. If the port's own watchers are a term, that is on us |
| S4 | `ModemManager` `rmtfs` `tqftpserv` | the modem stack; MPSS is one of the masters that must vote for sleep |
| S5 | the wifi radio (`nmcli radio wifi off`) | the one term with a known non-trivial cost, kept last because it takes the link with it |
| R | nothing - everything restored | drift control |

☠️ **From S5 the phone is reachable over USB only** (`172.16.42.1`). The radio
goes down with `nmcli`, not by stopping `NetworkManager`, because NM also owns
`usb0` and stopping it would take the last way in along with the one being
measured.

## The guards, and the instrument they replace

`idleleg.sh` (2026-08-15) is superseded and should not be run again. It never
took the phone off the charger, and both of its captures - `idleleg-A2fixed.txt`
and `idleleg-B2ctl.txt` - read `current_now = 0` for all fifty samples against a
voltage that never moved. Full pack, cable attached, gauge with nothing to say.
**Those two legs measured nothing**, and any conclusion resting on them is void.

So this script refuses to start unless:

- USBIN suspend actually took (`online=0` **and** the battery says `Discharging`),
- and `current_now` is not zero.

Either failure aborts before the first sample, with the reason in the log.

☠️ The USBIN suspend bit lives in the PMIC and **survives a warm reboot**. The
script restores it on every exit path including a kill - and restores every
service and the wifi radio with it, so a leg that dies at 03:00 does not leave a
phone that cannot charge.

## Running it

```sh
sudo systemd-run --unit=idle-ladder --collect /root/idle-ladder.sh
```

☠️ As a transient unit, never in an ssh session - S5 disconnects the session
that would be hosting it. Runs about **2 h 35 min**: 600 s of first settle, then
seven stages of 240 s settle and 60 samples at 20 s.

☠️ Do not run anything CPU-heavy on the device while it samples, from either
link. The whole measurement is the idle draw.

## Reading it

```sh
scp fp3@192.168.100.17:/home/fp3/idle-ladder.txt docs/power/<date>_idle-ladder.txt
python3 docs/power/idle-ladder-fit.py docs/power/<date>_idle-ladder.txt
```

The fitter prints the **median** per stage - never the mean, because one
`current_now` read here scatters by about 138 mA - with the interquartile range
and the extremes beside it, then the marginals, then `R - S0` and the sentence
that says which marginals that gap disqualifies.

## The result, 2026-08-18

Capture: [`2026-08-18_idle-ladder.txt`](../captures/2026-08-18_idle-ladder.txt). One boot,
seven stages, 60 samples each, drift control at the end.

| stage | floor (p10) | ±SE | median | what was cut |
|---|---|---|---|---|
| S0 | **85.3** | 1.5 | 151.0 | baseline |
| S1 | **84.6** | 1.7 | 137.0 | cups avahi bluetooth udisks2 tuned tuned-ppd |
| S2 | **85.9** | 1.2 | 145.6 | snsregd iio-sensor-proxy |
| S3 | **85.6** | 1.4 | 137.6 | spkwatch ringwatch fp3-voiced |
| S4 | **169.7** | 0.3 | 178.5 | ModemManager rmtfs tqftpserv |
| S5 | **170.3** | 0.4 | 175.8 | wifi radio |
| R | **88.6** | 1.7 | 137.9 | *everything restored* |

**Drift control: R − S0 = +3.4 ± 2.3 mA** over two and a half hours. The ladder
holds.

### ☠️ The median was the wrong statistic, and the ladder nearly said nothing

Read the same seven stages by median and every marginal lands inside its own
error bar: −40.8 ± 16.8 for the modem step, and ±15-21 mA of noise on
everything else. Read them by the **floor**, and the standard errors are 0.3 to
1.7 mA and four of the five steps are resolved to a milliamp.

The reason is what the distribution is. It is not a noisy measurement of one
current; it is a quiet floor with bursts on top - p10 at 85 mA, p75 at 200, max
at 495. **None of these stages was changing the burst rate**, so the bursts are
weather and the floor is the signal. A median sits halfway up the weather and
inherits all of its variance.

☠️ This generalises past this instrument: before picking median-versus-floor,
look at whether the thing being changed acts on the level or on the rate. Here
the synthetic test that validated the fitter *hid* this, because it generated
Gaussian noise around a level - exactly the distribution the median is right
for, and not the one the device produces.

### Three classes of userspace eliminated

- desktop services (`cups avahi-daemon bluetooth udisks2 tuned tuned-ppd`):
  **+0.6 ± 2.3 mA**
- the sensor stack (`snsregd iio-sensor-proxy`): **−1.3 ± 2.1 mA**
- our own watchers (`spkwatch ringwatch fp3-voiced`): **+0.3 ± 1.8 mA**

All three are zero. The sensor stack in particular was a prime suspect - it
talks QMI to the ADSP continuously and was the plausible reason LPASS never
idles - and it costs nothing measurable. Neither do our own additions, which is
worth knowing before anyone spends a night optimising them.

**What that adds up to is a negative with teeth:** the ~60 mA is not being spent
by anything running as a service on top of this kernel.

### ☠️ RETRACTED: stopping the modem stack does NOT cost 84 mA

**The controlled probe says no.** `freq-probe.sh` ran three phases in one boot
at 23:32-00:26 - baseline, modem stack stopped, restored -
[`2026-08-18_freq-probe.txt`](../captures/2026-08-18_freq-probe.txt):

| phase | floor (p10) | policy0 transitions/min | little cluster at 614 MHz |
|---|---|---|---|
| P0 baseline | 86.7 mA | 799 | 93.7 % |
| P1 **modem stopped** | **88.9 mA** | 733 | 94.5 % |
| P2 restored | 89.2 mA | 798 | 93.7 % |

Stopping `ModemManager`/`rmtfs`/`tqftpserv` costs about **2 mA**, not 84. The
cluster did not pin: it sat at its lowest OPP 94 % of the time in every phase,
and it kept changing frequency at ~750 transitions per minute throughout. The
cpufreq lock-up story is dead too.

So the ladder's S4 and S5 stages recorded **a real 44-minute episode** - floor
85.6 → 169.7 mA, variance collapsed, PLL storm to exactly zero - that was
**not caused by the thing that was changed at its boundary**. It began at the S4
cut and cleared before stage R, and the modem cut is now excluded as the cause.

☠️ **This is the ladder's one structural weakness, and it is worth naming.** A
cumulative ladder attributes whatever happens during a stage to that stage's
cut. It buys freedom from boot-to-boot variance and pays for it in exactly this
coin: a spontaneous 44-minute episode looks identical to a 84 mA finding. The
drift control catches slow drift; it cannot catch an episode that starts and
ends inside the ladder. **Any single-leg marginal that large deserves its own
A/B before it is believed** - which is what happened here, four hours later, and
it cost the claim.

What remains true, and unexplained: something doubled this phone's idle floor
for 44 minutes and silenced the PLL storm completely while it did. There is no
instrument on it yet.

### The original reading, now superseded

`S3 → S4` is **−84.1 ± 1.4 mA**. The floor did not fall when
`ModemManager`/`rmtfs`/`tqftpserv` stopped, it **doubled**, 85.6 → 169.7 mA, and
stayed there through S5. Restoring them at stage R brought it back to 88.6.

Two things go with it, both from the same capture:

| stage | floor | `wait_for_pll` warnings in the window |
|---|---|---|
| S0 | 85.3 | 14 |
| S1 | 84.6 | 21 |
| S2 | 85.9 | 66 |
| S3 | 85.6 | 23 |
| S4 | 169.7 | **0** |
| S5 | 170.3 | **0** |
| R | 88.6 | **0** |

- The sample-to-sample **variance collapsed**: S4's interquartile range is
  172-225 mA against S0's 90-202, and S5's SE is 0.4 mA.
- The `apcs-cpu0-pll` warning storm went to **exactly zero** for the 40 minutes
  S4 and S5 lasted, having run at 14-66 per 20-minute window before it.

☠️ Zero PLL warnings is not good news here. That warning is emitted per *failed
frequency transition*, so zero warnings alongside a doubled, rock-steady draw
reads as **the little cluster stopped changing frequency at all, at a high
one** - not as the storm having been cured. Stage R had zero warnings too and a
low floor, so the correlation is not simply "storm ⇒ current"; something about
S4 changed the governor's behaviour and something about R changed it back.

**The ladder cannot settle this** because it carried no cpufreq instrumentation
- a real gap in the script, and the reason `freq-probe.sh` exists. Three phases
in one boot, baseline / modem-stopped / restored, sampling the whole
`time_in_state` residency table rather than a single `scaling_cur_freq` read.

☠️ Do not read S5 as "the wifi radio is free". It measured −0.6 mA, but S5 ran
entirely inside the anomalous pinned state, where a 10 mA term would be
invisible against a floor that had already doubled. That stage has to be redone.

## Stage S5 redone properly, 2026-08-19: the wifi radio costs nothing either

The ladder's S5 measured the radio at −0.6 mA but ran entirely inside the
anomalous episode, so the number was void. Redone with `freq-probe.sh` as a
three-phase A/B in one clean boot -
[`2026-08-19_wifi-probe.txt`](../captures/2026-08-19_wifi-probe.txt):

| phase | floor (p10) | ±SE | median | ±SE | policy0 trans/min | little cluster at 614 MHz |
|---|---|---|---|---|---|---|
| P0 radio on | 86.4 | 1.6 | 129.3 | 13.5 | 820 | 93.6 % |
| P1 **radio off** | 87.5 | 1.7 | 130.3 | 11.3 | 833 | 93.2 % |
| P2 radio on | 89.6 | 3.7 | 140.9 | 16.5 | 810 | 93.6 % |

**wifi costs −1.1 ± 2.4 mA** (P0−P1) and **+2.1 ± 4.0 mA** (P2−P1), against a
drift control of +3.1 ± 4.0. Zero on the floor *and* zero on the median, so it
is not hiding in bursts either. An associated, idle wifi link on this device is
free to within a few milliamps.

☠️ Worth noting that the ladder's void number happened to be right. That is not
a reason to have trusted it - it was measured inside a state where a 10 mA term
would have been invisible, and being accidentally correct is not a property an
instrument can be relied on for.

## What the awake idle budget now looks like

Five candidates measured, each with its own control:

| candidate | cost at the floor | instrument |
|---|---|---|
| desktop services (`cups avahi bluetooth udisks2 tuned`) | +0.6 ± 2.3 mA | ladder |
| sensor stack (`snsregd iio-sensor-proxy`) | −1.3 ± 2.1 mA | ladder |
| our own watchers (`spkwatch ringwatch fp3-voiced`) | +0.3 ± 1.8 mA | ladder |
| wifi radio | −1.1 ± 2.4 mA | `freq-probe` A/B |
| modem stack | +2.2 mA *(≈23 mA on the median - bursts, not floor)* | `freq-probe` A/B |

**The floor is ~85-87 mA and none of it has been attributed to anything running
in userspace.** Every service that was a plausible suspect has been measured and
come back at zero, and the two radios with it.

That is the useful shape of a negative result: it moves the search off userspace
entirely and onto the platform - the kernel, the RPM votes and the regulator
sleep set, which is where [`rpm-sleep-set.md`](rpm-sleep-set.md) already points.
The one thing that has moved a number since is the modem cut measured **asleep**
(36 % off the discharge slope, findings-log Part II), and its cost is bursts rather than
baseline - which is why it shows up in a slope and not in a floor.

## ☠️★★ CORRECTION, 2026-08-19: ~25 mA of every floor above is the panel

The `phosh` screen-off leg came back with a floor of **58.3 ± 0.4 mA** against
this ladder's no-session floor of **85.3 ± 1.5 mA**. A session cannot draw
negative current, so the difference was never the session.

It was the panel. **The ladder stops `greetd`** - and with no compositor left,
nothing blanks the display. `phosh` blanks it. Every stage of this ladder, and
both `freq-probe` runs, therefore ran with a *powered* panel at zero backlight
brightness, which is not the same thing as a dark one.

Measured directly, [`2026-08-19_disp-probe.txt`](../captures/2026-08-19_disp-probe.txt):

| phase | floor (p10) | ±SE | `dpms` |
|---|---|---|---|
| P0 | 87.1 | 2.8 | **On** |
| P1 | **62.6** | 5.8 | **Off** |
| P2 | 87.2 | 2.5 | **On** |

**The panel costs +24.5 ± 6.4 mA** (P0−P1) and **+24.6 ± 6.3 mA** (P2−P1),
against a drift control of **+0.1 ± 3.7 mA**. As clean as this instrument gets.

**What has to be re-read, and what stands.**

- **Every floor level on this page is ~25 mA too high.** The real awake platform
  floor, panel off, is **~58-63 mA**, not ~85.
- **Every marginal on this page stands unchanged.** They are differences between
  stages that all shared the same panel state, and a constant offset cancels in
  a difference. The three userspace nulls are still nulls; the wifi null is
  still a null.
- ☠️ **The "s2idle roughly halves the draw" framing is dead.** Awake floor with
  the panel off is ~58-63 mA and the best suspend leg derives 43 mA. Suspend is
  buying **very little** over an idle, dark, awake phone - which is exactly what
  a `vlow` count of 0 has been saying all along, and is a much sharper statement
  of the problem than "we are 60 mA over budget".

**The lesson, which cost the whole night's levels:** `backlight = 0` is not
`dpms off`. A panel at zero brightness is still powered, and a measurement that
dims instead of blanking reports a lit panel as a dark one. Worse, the error is
invisible in exactly the way that matters - it shifts every level by the same
amount, so the internal consistency of the run looks perfect.
