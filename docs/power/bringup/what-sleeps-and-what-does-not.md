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

☠️ **Suspending Linux removes the first term and leaves the second untouched.**
That is not an inference — see §5.

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

## 5. The result, and why it says the floor is the radio

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

### What this does not say

* The 47.0 mA modem term is computed from two fitted coefficients, each with its
  own uncertainty; the agreement with the measured floor is `n=1`.
* The floor includes the USB link, unmeasured in mA. If that costs a few mA the
  modem term matches even better — but "plausibly small" is not a number.
* Nothing here explains *why* the modem's duty is 34.8 % rather than 6.1 %. The
  oracle reaches 6.1 % on the same hardware and the same firmware, with and
  without a data context (measured 2026-08-30), which points at attach-time
  configuration — DRX and paging — and that is the open question.
