# Instrument index

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed every change and made or reviewed
> every measurement these tools produced.

One line per script, taken from **its own header comment** — this file is
generated, so a tool that describes itself badly reads badly here, and the fix
belongs in the tool.

Why it exists: there are over a hundred instruments in this directory and no way
to see that from inside a session. The cost of not having the list is not
untidiness, it is **writing an instrument that already exists** — the
near-misses are close enough to be invisible (`terse-ab.sh` beside
`terse-ab-clean.sh`, `decay.sh` beside `restwake.sh`, `wake-service.sh` beside
`wake-qmi.sh`), and each pair exists because the second one was needed, not
because the first was forgotten. Read this before writing a new script.

☠️ **A tool listed here is not a tool that still measures what its name says.**
Several were built for questions that have since been answered or withdrawn, and
the withdrawal lives in `findings-log.md`, not in the script. Treat a line here
as "this exists and this is what it was for", never as "this is current".

## Where to start

- `host-sleep-census.sh` — sleep lengths from the **host's** USB log. Costs the
  phone nothing and cannot perturb what it measures; use it to watch any run.
- `wake-service.sh` / `wake-qmi.sh` — what ended a sleep, by QRTR service and by
  QMI message respectively. `run-wake-qmi.sh` drives the second from the host.
- `radio-off-sleep.sh` — the A‑B‑A′ that showed the wakes come from the network.

## Every instrument

| script | what it is for |
|---|---|
| `ab-leg-fit.py` | Fit an alternating-arms leg: one slope per SUSPEND, compared arm against arm |
| `ab-leg.sh` | Both arms of a sleeping-current comparison from ONE pack |
| `adsp-restart-leg.sh` | What is the ADSP's held session worth? |
| `adsp-vlow.sh` | adsp-vlow — does the RPM reach vlow once the ADSP is gone entirely? |
| `audio-hold-probe.sh` | Is it OUR UCM verb that keeps the audio DSP awake? |
| `audio-off-leg.sh` | What does the audio stack cost, in mA — the one measurement the LPASS story was |
| `await-charge.sh` | Wait until the pack is charged, then hand over to the next measurement |
| `band-ab.sh` | A-B-A' on the LTE band the modem is allowed to camp on, inside one boot |
| `boot-level-sample.sh` | One duty window per boot, with everything that might explain the boot's level |
| `burst-attrib-fit.py` | Split a burst-attrib.sh capture by the thing it is trying to explain - the |
| `burst-attrib.sh` | Decide whether an awake current burst is the CPU being awake at all, or something |
| `burst-knob-ab.sh` | A-B-A' on ANY one knob, measured with burst-attrib.sh |
| `burst-master-fit.py` | Split a burst-master.sh capture by the current and print each RPM master's |
| `burst-master-knob.sh` | A-B-A' on one knob, measured with burst-master.sh instead of burst-attrib.sh |
| `burst-master.sh` | Name the remote processor that is up during an awake current burst |
| `burst-modem-ab.sh` | A-B-A' on the modem's RF, to test whether the awake current burst is the radio |
| `burst-profile.py` | Characterise the BURSTS in an idle-ab window, not the level. The ladders showed |
| `burst-rail-fit.py` | Split a burst-rail.sh capture by the current and report, per rail, how often it |
| `burst-rail.sh` | Which RAIL is up when the current is up |
| `burst-source.sh` | Find what produces the awake current bursts, by recording the current AND the |
| `burst-wlan-ab.sh` | A-B-A' on the wlan radio, to test whether the awake current burst is WiFi |
| `call-wake-test.sh` | Does an incoming call raise this phone from suspend? |
| `camera-wedge-hunt.sh` | camera-wedge-hunt.sh [PASSES] [OUTDIR] - reproduce the camss/IOMMU wedge and |
| `coulomb-probe.sh` | Is there a fast instrument hiding in the fuel gauge? |
| `de-compare-fit.py` | Read de-compare legs and print the median current per leg, with the spread |
| `de-compare.sh` | One leg of a desktop-environment power comparison. Run it once per (DE, |
| `de-switch.sh` | Switch which session greetd starts at boot, for the phosh-vs-Sxmo power |
| `decay.sh` | How long does a DISTURBANCE keep the modem from letting the phone sleep? |
| `diag-handshake.py` | Walk the modem's DIAG control handshake to the point where the data channel is |
| `diag-probe.py` | Send a DIAG request to the modem and print what comes back |
| `discharge-fit.py` | Reduce a discharge-run.sh capture to the three numbers it was run for: |
| `discharge-gate.sh` | Wait for the charger to TERMINATE (status=Full), then hand the unit to the |
| `discharge-run.sh` | One continuous discharge from a full pack to the phone switching itself off, |
| `duty-vs-uptime.sh` | Is the modem's awake duty a per-BOOT constant, or does it DECAY after a boot? |
| `emmc-watch.sh` | Did the eMMC fall off the bus, and was the application processor collapsed |
| `episode-watch.sh` | Catch the episode |
| `fp3-charge-guard.service` | [Unit] |
| `fp3-night-ladder.service` | [Unit] |
| `freq-probe.sh` | Does stopping the modem stack pin the little cluster at a high OPP? |
| `gptattr.py` | Read (and optionally set) the Qualcomm A/B boot-control attribute bits that |
| `host-sleep-census.sh` | Sleep census read entirely from the HOST, touching nothing on the phone |
| `idle-ab-fit.py` | Read one or more idle-ab.sh outputs and print the comparison |
| `idle-ab.sh` | The same idle measurement on BOTH operating systems, so the two numbers are a |
| `idle-ladder-fit.py` | Fit an idle-ladder capture: median current per stage, and the marginal cost |
| `idle-ladder.sh` | The idle decomposition: what actually makes up the awake-idle draw, measured |
| `idle-leg.sh` | One leg of an idle-current measurement on the FP3 |
| `idle-suspend-window.sh` | DOES THE PHONE SUSPEND ON ITS OWN, AND WHAT DOES IT COST WHEN IT DOES? |
| `ipa-handshake-probe.sh` | Did our IPA driver ever complete its handshake with the modem? |
| `kmsg-tap.sh` | kmsg-tap.sh OUTFILE - stream the device's kernel log to a file ON THE HOST |
| `ladder-summary.py` | Summarise a night-ladder run: how much the pack actually gave up over the whole |
| `learn-cycle.sh` | One discharge span wide enough for the gauge to learn the pack from, and a |
| `learn-prep.sh` | Get the pack to a terminated charge, then hand over to learn-cycle.sh |
| `leg3-control.sh` | Does zeroing the sleep-set XO vote save any current? |
| `leg3.sh` | Does zeroing the sleep-set XO vote save any current? |
| `lowpower-call2.sh` | Does an incoming call still reach the phone when ModemManager puts the modem in |
| `lpass-bisect.sh` | lpass-bisect — does the sensor stack pin the ADSP awake? |
| `lpass-restart-ab.sh` | Does the audio DSP collapse only while nothing has opened a path on it? |
| `lpass-trace.service` | [Unit] |
| `lpass-trace.sh` | lpass-trace — sample the LPASS master stats from before the freeze |
| `lpass-usb-ab.sh` | Does the USB PHY stop the audio DSP from power-collapsing? |
| `modem-fw-swap.sh` | Swap the modem firmware pmOS loads from its rootfs for the one the device's own |
| `modem-window-fit.py` | Read one or more modem-window.sh captures and print the per-master awake duty |
| `modem-window.sh` | ONE instrument, BOTH systems: an RPM master-stats window with the modem's full |
| `mpss-leg.sh` | mpss-leg.sh — two things at once |
| `night-ladder.sh` | An idle-ab.sh ladder that needs nothing from the host: it runs on the phone, |
| `oracle-capture.sh` | Capture the RPM-side ground truth from the Ubuntu Touch oracle on slot_a |
| `panel-witness.sh` | Every candidate witness for "is the panel actually off", printed side by side, |
| `pll-ramp-fit.py` | Read a pll-vs-voltage.sh log and answer the one question it was run to |
| `pll-sweep.sh` | pll-sweep.sh - force N cpufreq transitions on one cluster and count how many |
| `pll-vs-voltage.sh` | pll-vs-voltage.sh - run the same cpufreq sweep repeatedly while the battery |
| `press-power-key.py` | Press the power key from software, via /dev/uinput |
| `qmi-msgids.txt` | QMI message-id -> name, generated from libqmi data/*.json (llg179 clone) |
| `radio-off-sleep.sh` | Is the thing that ends every sleep coming FROM THE NETWORK, or from the modem |
| `rail-census-parse.py` | Turn a rail-census capture into the list of rails that vote active and never |
| `rail-census.sh` | Name the rails that vote active and never vote sleep |
| `restwake.sh` | How long does the phone sleep as a function of HOW LONG IT WAS LEFT ALONE? |
| `ring-source.sh` | ring-source.sh — is the modem edge's ~one-per-2-s signal ring produced by an |
| `rpm-write-ab.sh` | A-B-A' on the eMMC host's runtime-PM autosuspend delay, counting the RPM |
| `rpm-xo-snapshot.sh` | One line per RPM master: how long it has let the XO go, cumulatively, since boot |
| `rpmsg-ept.py` | Open an rpmsg channel by name and get a /dev/rpmsgN for it |
| `rpmstats_raw.py` | Raw reader for the RPM sleep-stats records in message RAM (msm8953) |
| `run-wake-qmi.sh` | HOST side: deploy tools/wake-qmi.sh to the phone and run the census |
| `sleep-knob-ab.sh` | A-B-A' on one knob, measured in SUSPEND RESIDENCY rather than in duty or mA |
| `sleep-night-fit.py` | Price suspend residency in mA from a sleep-night.sh log |
| `sleep-night.sh` | What is suspend residency worth, in mA? |
| `sleepset-witness.sh` | Witness the probe-time RPM sleep-set votes |
| `slope-fit.py` | Reduce a suspend-slope.sh run to a suspend current |
| `slope-leg.sh` | A slope leg with an arbitrary cut applied - the generalisation of leg3.sh and |
| `smd-wake-source.sh` | WHICH CHANNEL rings the modem's SMD edge and ends the suspend? |
| `soc-ladder.sh` | Map the oracle's idle current against state of charge, on ONE boot |
| `suspend-leg.sh` | How much does the phone draw while it is actually asleep? |
| `suspend-rate.sh` | How OFTEN does a suspend end early, and under which conditions? |
| `suspend-slope.sh` | How much does the phone draw while it is actually asleep? |
| `terse-ab-clean.sh` | Does ModemManager's TERSE state buy residency? - the honest re-run |
| `terse-ab.sh` | Does ModemManager's TERSE state buy residency, and does the suspend PATH decide |
| `terse-call.sh` | Does an incoming call reach the phone while ModemManager has it in TERSE state? |
| `usb-off-census.sh` | Take the rail census again with the USB PHY powered down |
| `ut-vlow-idle.sh` | Oracle half of the deep-sleep differential (UT 4.9, slot_a). The downstream |
| `vlow-idle.sh` | Runtime-idle vlow/vmin witness, pmOS control half of the oracle differential |
| `vlow-probe.sh` | Does zeroing the sleep-set XO vote let the RPM reach vlow? |
| `vlow-ring.sh` | vlow-ring.sh — read the vlow Client Votes ring immediately after a suspend |
| `votes-decode.sh` | votes-decode.sh — empirical decode of the RPM vlow "Client Votes" mask |
| `votes-decode2.sh` | votes-decode2.sh — continue the Client Votes decode by subtraction |
| `votes-post-resume.sh` | votes-pr-v2 — read the RPM Client Votes mask right after a real suspend window |
| `wake-attrib.sh` | WHICH source wakes the phone from s2idle, on battery versus on the cable? |
| `wake-qmi.sh` | WHICH QMI MESSAGE ends the sleep? - one layer below wake-service.sh |
| `wake-service.sh` | WHICH SERVICE's traffic ends the sleep? |
| `wakesrc-rested.sh` | NAME what ends a RESTED phone's sleep - the one sleep that is worth naming |
| `wakeup-census.sh` | Does the modem keep WAKING the application processor, or does it merely never |
