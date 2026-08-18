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
