# What pmOS decided for us — the power-relevant distribution defaults

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed every measurement it rests on.

**Why this page exists.** Two separate investigations here were settled, before
their first measurement, by a value the distribution had set in a package-owned
file: the camera's stutter (`GSK_RENDERER=cairo`, weeks) and the modem's suspend
behaviour (`--test-quick-suspend-resume`, days). Neither was visible in upstream
documentation or in our tree. This page is the enumeration, so the next
investigation starts from it. **The method** — the sweep, and why it goes *before*
the measurement — is in `/fp3-porting-debug` ("what the distribution decided for
you"); this page is the current answer, which is exactly the part that goes stale.

Read it off the device rather than trusting the table:

```sh
for d in /usr/lib/systemd/system/*.d; do for f in "$d"/*.conf; do
  echo "--- $f [$(apk info -W "$f" 2>/dev/null | sed 's/.*owned by //')]"
  grep -vE '^\s*(#|$)' "$f"; done; done
gsettings list-recursively org.gnome.settings-daemon.plugins.power   # as the session user
systemd-inhibit --list
cat /sys/power/mem_sleep
```

Source side, in a `pmaports` checkout: `grep -rl '<key-or-switch>' main/`.

## ☠️ The two that decided a measurement

| what | where it comes from | why it matters |
|---|---|---|
| `ExecStart=/usr/sbin/ModemManager --test-quick-suspend-resume` | `postmarketos-base-ui`, `…/ModemManager.service.d/quick-suspend-resume.conf` (and `/etc/conf.d/modemmanager` for OpenRC) | selects `CLEANUP_TERSE` on suspend — the modem is told to stop signalling everything except call/text. On this device that is the difference between a suspend that holds and one the modem's SMD edge ends in seconds. Applied on logind's sleep signal only, so anything that suspends via `rtcwake` never gets it. Full write-up: [`leads/modemmanager-suspend-modes.md`](leads/modemmanager-suspend-modes.md) |
| `sleep-inactive-ac-type='nothing'` | `postmarketos-base-ui-gnome`, `00_postmarketos-base-ui-gnome.gschema.override` | **on AC the session never asks to suspend at all.** A phone on the USB link — which is every measurement session here — is on AC. `sleep-inactive-battery-type` is *not* overridden, so it keeps the GNOME default. This is the mechanism behind "neither system ever sleeps"; verify the live values with `gsettings`, since an override is a default and the user's dconf can sit on top of it |

## The rest of the power-relevant surface

| setting | value | source package |
|---|---|---|
| `ambient-enabled` | `false` (no ambient-light brightness) | `postmarketos-base-ui-gnome` |
| `unlock-sim` | `true` (gsd-wwan unlocks the SIM) | `postmarketos-base-ui-gnome` |
| sleep inhibitor plugins | `ssh-session-open`, `apk-running` — both `what: sleep` | `postmarketos-base-ui`, `/etc/sleep-inhibitor.conf` ☠️ **an open ssh session is configured to hold sleep off**, and every measurement here runs over ssh. This file is the OpenRC-side inhibitor daemon's; confirm on the device whether anything reads it under systemd before drawing a conclusion — `systemd-inhibit --list` is the arbiter |
| `HandlePowerKey=ignore`, `AllowSuspendInterrupts=yes` | `/etc/elogind/logind.conf` | `postmarketos-base-ui` — **elogind, not systemd-logind**; on a systemd install this file is inert. Check `/etc/systemd/logind.conf{,.d}` for the one that applies |
| kernel cmdline addition | `quiet` | `postmarketos-base` |
| OOM policy | `ManagedOOMMemoryPressure=kill` at 80 % (system) / 50 % (user apps) | `postmarketos-base-systemd` |
| `iio-sensor-proxy` | `TimeoutStopSec=3` | `postmarketos-base-ui` |
| suspend self-test | `echo mem > /sys/power/state` with a 6 s RTC alarm | `postmarketos-test/90-suspend-test.sh` — ☠️ the distro's own suspend check also bypasses logind, so a passing `90-suspend-test` says nothing about the path a real suspend takes |

## What this changes about our own numbers

- **every residency figure measured with `rtcwake`** describes the state where
  ModemManager was never told to go terse — not the state a real suspend happens
  in. Re-measurement on the logind path is what `tools/terse-ab.sh` is for;
- **"the phone never suspends on its own"** is a configured policy on AC, not a
  fault to be debugged. Any comparison against the oracle has to state which
  system was on AC, and any autonomous-idle measurement has to either run off the
  charger or drive the suspend itself;
- **an ssh session may be configured to inhibit sleep.** Where it does, a
  measurement taken over the link measures the link.
