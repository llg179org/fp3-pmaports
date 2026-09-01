# What actually sleeps on this phone, and what each knob really does

> ⚠️ **AI-generated.** This page was written by Claude (Opus 5) working under the
> direction of Lajosházi, László Gergely, who reviewed every change and made or
> reviewed every measurement it rests on.

Written 2026-08-31, after a 10-hour measurement whose result only makes sense
once the picture below is clear. Every number here is measured on this device
unless it says otherwise; the commands are given so each can be re-checked.

The short version: **this phone contains two processors that sleep
independently, and every "sleep" setting a Linux distribution exposes controls
only one of them.** The other one is where the power goes.

---

## 1. Two processors, one battery

| | application processor (APSS) | modem (MPSS) |
|---|---|---|
| runs | Linux, your session, every daemon | Qualcomm firmware, loaded by remoteproc |
| sleeps via | `/sys/power/state`, i.e. suspend | its own internal power management, driven by the network |
| what a distro can set | everything | **nothing directly** |
| measured cost here | **54.9 mA** while awake | **~47 mA** at the duty this phone runs |

The two numbers come from a fitted model over many measured windows:

```
current [mA] = 54.9 + 135.0 x MPSS-duty
```

`MPSS-duty` is the fraction of wall-clock time the modem's remote processor is
awake, read from the RPM master stats. At this phone's measured LTE-idle duty of
**34.8 %** the modem term is `135.0 x 0.348 = 47.0 mA`, and the sum
`54.9 + 47.0 = 101.9 mA` matches the measured awake idle of **98.5 mA** to within
the spread of the awake band (88.5–128 mA across four legs).

☠️☠️ **An earlier revision of this page said here: "Suspending Linux removes the
first term and leaves the second untouched. That is not an inference — see §5."
Both sentences were wrong**, and the second one was the worse of the two: it
declared a conclusion to be a measurement. See the retraction at the head of §5.
The 47.0 mA figure is the modem term **at the duty this phone shows with
ModemManager running**; it is not a constant, and it does not describe a run in
which that daemon was stopped.

---

## 2. The layers that can ask for a suspend, and what each one is

Three different mechanisms are commonly confused. They are independent: turning
one off does not turn the others off, and a measurement that changes one says
nothing about the others.

### (a) `gnome-settings-daemon` — the session's idle policy

Two keys per power source, under
`org.gnome.settings-daemon.plugins.power`:

```sh
gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type
gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout
```

The `-type` key names **what the daemon does** once the session has been idle for
`-timeout` seconds. The enum is in
`/usr/share/glib-2.0/schemas/org.gnome.settings-daemon.enums.xml` and has seven
values:

```
blank=0  suspend=1  shutdown=2  hibernate=3  interactive=4  nothing=5  logout=6
```

| value | behaviour |
|---|---|
| `'suspend'` | after the timeout, **asks** logind for a system suspend |
| `'nothing'` | the timeout expires and **nothing happens** |

☠️ **`'nothing'` does not forbid sleep — it only declines to initiate it.** The
phone still suspends on `systemctl suspend`, on logind's own `IdleAction`, or on
`rtcwake`. Reading `'nothing'` and concluding "this phone cannot sleep" is a
category error; it is the difference between *no one asked* and *it refused*.

Measured on this device 2026-08-30:

| key | this phone | GNOME upstream default |
|---|---|---|
| `sleep-inactive-ac-type` | `'nothing'` | `'suspend'` |
| `sleep-inactive-battery-type` | `'nothing'` | `'suspend'` |
| `sleep-inactive-battery-timeout` | 900 | 900 |

and the two `'nothing'` values come from **different places**, which took a
measurement to establish:

* the **AC** branch is set by the distribution — line 2 of
  `/usr/share/glib-2.0/schemas/00_postmarketos-base-ui-gnome.gschema.override`
  (present even though this device runs phosh, not GNOME Shell);
* the **battery** branch is a **user-level dconf write**, one line to reverse:

  ```sh
  su fp3 -c 'dconf dump /org/gnome/settings-daemon/plugins/power/'
  # [/]
  # sleep-inactive-battery-timeout=900
  # sleep-inactive-battery-type='nothing'
  ```

☠️ **`gsettings` and `dconf` read the database of the user who runs them.** A
probe running as root under `systemd-run` reads *root's* dconf and therefore
reports the **schema default**, not what governs the session. This cost a
contradiction in one afternoon: two reads of the same key a minute apart returned
`'suspend'` and `'nothing'`, and both were correct. Always read user settings
under `su <user>`.

### (b) logind — the system's idle policy

```sh
busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
       org.freedesktop.login1.Manager IdleAction
```

☠️ **Not** `systemctl show systemd-logind -p IdleAction` — that asks for a *unit*
property, `IdleAction` is a property of the **logind D-Bus interface**, and the
systemctl form silently returns an empty string. A gate built on that empty
string refused to arm a night's measurement on 2026-08-30 and cost 35 minutes.

`logind.conf(5)` states three conditions for the action to fire, and all three
must hold:

> "…requires that user sessions correctly report the idle status to the system.
> The system will execute the action after **all sessions report that they are
> idle**, **no idle inhibitor lock is active**, and subsequently, the time
> configured with `IdleActionSec=` has expired."

Witnesses for each:

```sh
loginctl list-sessions --no-legend
loginctl show-session <id> -p Id -p Class -p Type -p IdleHint -p IdleSinceHint
systemd-inhibit --list
```

☠️ Do not pass `--value` with several `-p`: the values come back in schema order,
not the order asked for. Print the keys.

Two details that decide readings on this device:

* **Not every session counts.** systemd's `manager_get_idle_hint()` skips any
  session where `SESSION_CLASS_CAN_IDLE(class)` is false, and that macro admits
  only `USER`, `USER_EARLY`, `USER_LIGHT`, `USER_EARLY_LIGHT` and `GREETER`. The
  `Class=manager` session (`Service=systemd-user`) permanently reports
  `IdleHint=no` and is **not** a blocker.
* **Inhibitor mode matters.** `delay` inhibitors postpone a suspend by at most
  `InhibitDelayMaxSec`; only `block` inhibitors prevent one. On this phone the
  seven inhibitors held at idle are all `delay` for `sleep`, plus two `block`
  entries for `handle-power-key` — none of which blocks sleep.

☠️ And the one that catches every remote measurement: **an open ssh session is a
sleep inhibitor here** (`/etc/sleep-inhibitor.conf` ships an `ssh-session`
plugin). Any check you run over ssh forbids the thing you are checking. Start the
measurement, log out, and read it afterwards.

### (c) Direct suspend — what the measurements actually use

```sh
rtcwake -m mem -s 600      # what sleep-night.sh does
systemctl suspend          # goes through logind, runs its inhibitor handshake
```

☠️ These two are **not** interchangeable as measurement boundaries.
`systemctl suspend` makes logind run every delay inhibitor and wait for replies
*before* the kernel freezes, so anything you time from the `systemctl` call
includes that handshake. The last userspace instant before the freeze is a hook
in `/usr/lib/systemd/system-sleep/`, which runs after every inhibitor; three
boundary errors in one day came from not using it.

### (d) What kind of suspend this platform has

```sh
cat /sys/power/mem_sleep     # [s2idle]
cat /sys/power/state         # freeze mem disk
```

**`s2idle` is the only available sleep state** — `deep` does not appear in
`mem_sleep`, so there is no deeper state to be missed and no kernel knob that
would lower the floor further. Measured 2026-08-31; treat as a property of this
kernel/board, and re-read it after a base bump.

---

## 3. What none of these layers touches: the modem

**No sleep setting on the Linux side puts the modem to sleep.** The MPSS is a
separate processor with its own firmware and its own power management, and it
keeps the phone attached to the network whether or not Linux is suspended.

In particular:

* `systemctl stop ModemManager` stops a **userspace daemon**. The radio stays up
  and attached; what stops is the thing that talks to it. (`sleep-night.sh`
  refuses to run with ModemManager active — not to save power, but because a
  polling daemon would be the thing being measured.)
* An AP suspend does not propagate to the MPSS. It cannot: the modem must keep
  monitoring the paging channel to receive a call.
* The modem's own duty is set by what the **network** asks of it — DRX cycle,
  paging, RRC state — which is negotiated at attach time.

This is why the fitted model has a constant term and a modem term, and why they
behave differently under suspend.

---

## 3a. What the AP does *not* tell the other processors

Downstream carries a 90-line driver, `drivers/soc/qcom/smp2p_sleepstate.c`, whose
whole job is to raise a flag before the application processor suspends and lower
it on resume: bit 12 of an SMP2P entry named `sleepstate`, **1 = AP awake**,
**0 = AP going down**, with a deliberate 10 ms pause after clearing it so the
remote can see it before the freeze.

**Mainline has nothing equivalent.** In this tree:

```sh
ls drivers/soc/qcom/ | grep smp2p          # smp2p.c, trace-smp2p.h — no sleepstate
grep -rn sleepstate drivers/soc/qcom/ arch/arm64/boot/dts/qcom/    # nothing
grep -n PM_SUSPEND_PREPARE drivers/soc/qcom/smp2p.c                # nothing
```

☠️ **But read which remote it talks to before drawing the obvious conclusion.**
The vendor DT for this SoC family declares exactly one sleepstate entry and it
carries `qcom,remote-pid = <2>`; our own `msm8953.dtsi` says pid 2 is the **ADSP**
and pid 1 is the **modem**. So downstream does not tell the modem either, and this
mechanism cannot be the reason our modem behaves the same asleep and awake.

The full write-up, including the pre-registered experiment and the readings that
would make it a null result, is in
[`leads/smp2p-sleepstate-missing.md`](leads/smp2p-sleepstate-missing.md).

## 4. What the night measurement did, step by step

`tools/sleep-night.sh`, run 2026-08-30 18:25 → 2026-08-31 04:37. Its three
preconditions are hard `exit 1` gates, so the existence of the data proves they
held:

```
18:24:57 borrowing a 20 s idle-ab window to lock the session and take the panel down
18:25:38 panel: bl_power='4'
18:25:43 charge input cut: status=Discharging
18:25:43 start cap=90% v=4273645uV floor=55% sleep=600s gap=20s
04:37:03 signal - restoring charge input
```

| gate | why it exists |
|---|---|
| ModemManager not running | a polling daemon would end every suspend within 16–53 s (measured 2026-08-29) |
| `bl_power=4` | a lit panel dominates the current and changes the *regime*, not just the level |
| `status=Discharging` | on a cable, `current_now` is the **charger** current, not the load |

☠️ "Charge input cut" is **not** the cable being unplugged. It sets the PMIC's
`input_suspend` bit; the USB PHY stays powered and the CDC-NCM link stays
enumerated, deliberately, because the cable *is* the remote link and the host
cannot cut VBUS. So the floor below includes whatever that link costs — a term
never measured in mA on this device. **Never reboot while that bit is set.**

Each round is `20 s awake + 602 s asleep`. Fifty-eight rounds ran; every one
slept the full 602 s and every one ended on `56:pm8xxx_rtc_alarm`, i.e. on the
alarm rather than on anything interrupting it. `suspend_stats` went 14 → 71 with
`fail=0`, and the run was asleep **96.8 %** of its wall-clock.

☠️ The `cap` column in `rounds.txt` is **not** the instrument. `capacity`,
`charge_now` and `current_now` are three sysfs names for one software integrator
in `qcom_smbx.c` whose suspend-gap branch counts nothing by design. Across this
run it sat at 90 % for hours and then jumped to 71 % in one step, while the
voltage fell smoothly. **The instrument is `v_uV`**, fitted against a reference
discharge curve.

---

## 5. ☠️☠️ RETRACTED — the result stands, the explanation did not

**Kept in place rather than deleted, because the shape of the error is worth more
than a clean page.**

The measurement below is good: **`floor_mA` = 48 ± 5 mA** over 10.02 h with the
phone asleep 96.8 % of it. Everything after the fit is wrong.

> ☠️☠️ **RETRACTED FURTHER, 2026-09-01 — the 5.1 % is now the outlier, not the
> anchor.** This section replaced a 34.8 % duty with 5.1 % and rebuilt the
> arithmetic on it. That 5.1 % was **one window**. Fifty-five sleep windows since,
> with the daemon stopped, across Wi-Fi up and Wi-Fi down and two days, read
> **33.4 – 42.9 %, mean 36.3 %, none below 30 %**
> ([`captures/2026-09-01_modem-night-control/`](captures/2026-09-01_modem-night-control/README.md),
> [`captures/2026-09-01_wifi-up-arm/`](captures/2026-09-01_wifi-up-arm/README.md)).
> So "the modem term is 6.9 mA and 41 mA is unexplained" does not stand either.
>
> Worse for the pairing: the 48 mA and the duty beside it have **never been one
> run**. 48 mA is the 58-round night of 2026-08-30, whose duty was not measured;
> the duty came from a single window the next day, taken with the cable in and
> the pack `Full` — a **charging** phone, while the floor night was discharging.
>
> And the floor does not reproduce: an eight-hour run in the same daemon state
> with the cable **out** measures **100 ± 4 mA**. The 48 mA is not withdrawn — it
> is a real fit of a real night — but it is a number about a regime this page does
> not identify, which is the same failure this section was written to record.
>
> ☠️ Read the whole section below as **twice** superseded. It is kept, again, for
> the shape of the error: the correction of 2026-08-31 was made confidently from
> n=1, in a section whose own thesis is that a thorough-looking correction can be
> the thing that misleads.

> ☠️☠️☠️ **CORRECTED 2026-09-01 midday — "the 5 % has no companion" is false, and
> the variable is the boot.** The 5 % is **four** measurements over 34 minutes on
> 2026-08-31 05:38–06:12: legs A, B and A′ of
> [`captures/2026-08-31_mm-duty-ab/`](captures/2026-08-31_mm-duty-ab/README.md)
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
> [`tools/duty-vs-uptime.sh`](tools/duty-vs-uptime.sh) was written to ask and
> [`leads/sleep-length-is-a-state.md`](leads/sleep-length-is-a-state.md) already
> says about sleep length.
>
> **The good news is the size of it:** this stack *can* run a registered, attached
> LTE modem at 5 % duty. The D-track target is not hypothetical — it has been
> observed on this phone.

**The hidden assumption**, never stated and never checked: that the modem's duty
during that night was **34.8 %**. It was not measured — it was carried in from a
different regime. The night ran with **ModemManager stopped** (a hard gate, §4),
and measured 2026-08-31 with the daemon stopped the MPSS is awake **5.1 %** of a
600 s window, not 34.8 %. At 5.1 % the modem term is `135.0 × 0.051 = 6.9 mA`, so
of the 48 mA floor roughly **41 mA is unexplained** and the 47.0 ≈ 48 agreement
below is a coincidence.

☠️ **The "What this does not say" list at the end of this section names three
caveats and misses the load-bearing one.** That is worse than having written no
caveats at all: a thorough-looking list gave false comfort about exactly the
assumption that broke. A caveat list is only worth what its *omissions* cost.

☠️ **The method error, stated plainly:** the duty was *inferred from current*
under an assumption about what the AP draws asleep, when the direct instrument
(`modem-window.sh`) takes **ten minutes**. Half a day of documents was built on
the inference before the ten minutes were spent.

What survives: `floor_mA` as a number, the gates of §4, and everything in
§§1–4 that is a direct reading. What is now open is carried by two new questions —
what ModemManager does that keeps the modem awake, and what draws ~41 mA while
the AP is in s2idle. Neither is answered here.

---

### The retracted derivation, kept for the record

`tools/sleep-night-fit.py`, refitted with the flat top of the discharge curve
progressively removed (the tool's own `skip_hours` argument):

| leading hours dropped | fitted average draw |
|---|---|
| 0 (whole run) | 45.5 mA |
| 2 h | 48.5 mA |
| 3 h | 49.5 mA |
| 4 h | 50.5 mA |
| 5 h | 51.0 mA |

⇒ **`floor_mA` ≈ 48 ± 5 mA.** The estimate drifts upward as the flat top is
removed — expected, since travel there is inside the sample spread and drags the
slope toward zero — and the residual does not blow up, so the slope is real.

Now put that next to the model:

| state | AP/system term | modem term | total |
|---|---|---|---|
| awake, LTE idle | 54.9 mA | 47.0 mA | **98.5 mA** (measured) |
| asleep (s2idle) | ~0 | 47.0 mA | **≈47 mA** — measured **48 ± 5** |

**Suspend removes the AP term almost exactly and leaves the modem term
untouched.** The AP really does go down — 58/58 suspends, zero failures — and
what remains is the radio.

☠️ This **falsifies the reasoning** behind the reading pre-registered for this
step, which said `>40 mA ⇒ the AP is not really going down`. That branch assumed
the only way to a high floor was a failed suspend. The suspends succeeded; the
floor is high because the floor is the modem.

### What it means for the goal

With `night_mA = (1 - r) x 98.5 + r x floor_mA`, the residency needed to reach
50 mA is:

| `floor_mA` | sleep fraction `r` needed for 50 mA |
|---|---|
| 45.5 | 91.5 % |
| 48.0 | 96.0 % |
| 51.0 | **unreachable** — the floor itself is ≥ 50 |

⇒ **Residency alone cannot deliver the halving with any margin**, and at the top
of the fitted band it cannot deliver it at all. The two tracks that looked
independent have collapsed onto one quantity: suspend already takes the AP term
away for free, and after that only the **MPSS duty** is left. Reaching ≤ 50 mA
with margin means moving 34.8 % toward the oracle's 6.1 %.

### What this does not say (as written at the time — see the retraction above)

☠️ None of the three items below is the assumption that actually broke.

* The 47.0 mA modem term is computed from two fitted coefficients, each with its
  own uncertainty; the agreement with the measured floor is `n=1`.
* The floor includes the USB link, unmeasured in mA. If that costs a few mA the
  modem term matches even better — but "plausibly small" is not a number.
* Nothing here explains *why* the modem's duty is 34.8 % rather than 6.1 %. The
  oracle reaches 6.1 % on the same hardware and the same firmware, with and
  without a data context (measured 2026-08-30), which points at attach-time
  configuration — DRX and paging — and that is the open question.
