# fp3-selftest — functional regression battery

> ⚠️ **AI-generated.** This page — and the code, device tree and tooling it
> describes — was written by Claude (Opus 5) working under the direction of
> Lajosházi, László Gergely, who reviewed every change and made or reviewed
> every measurement it rests on. Kernel commits carry `Co-authored-by: Claude`;
> anything prepared for the LKML carries `Assisted-by:` instead and never a
> `Signed-off-by` from the assistant, since only a human can certify the DCO.

Run this after every kernel bump, so that "everything still works" is a
repeatable measurement instead of a memory.

The suite exists because of a specific near-miss: a missing DAPM route
(`SLIMBUS_0_RX` ← `SLIMBUS_0_RX Voice Mixer`) made the voice-call PCM impossible
to open, and nothing in a manual pass would have caught it — playback and
capture both still worked, only telephony was dead. `30-voice` encodes exactly
that regression so it cannot come back silently.

## Invocation

```sh
export FP3_PW=…            # device password — never stored in this repo

# the canonical run
./tests/fp3-selftest --no-cable --no-bt

# before flashing a build, with no device involved at all: are the required
# modules and device-tree nodes actually in the package?
./tests/fp3-selftest --preflight-apk ~/…/linux-fp3-7.1.3-r0.apk
```

The battery takes several minutes and the suspend check drops the USB link, so
run it detached and poll the log rather than in one foreground call:

```sh
nohup ./tests/fp3-selftest --no-cable --no-bt > /tmp/selftest.log 2>&1 &
until grep -qE '^(PASS|FAIL) - ' /tmp/selftest.log; do sleep 15; done
```

## What each check proves

| check | proves |
|---|---|
| `01-identity` | the running kernel is the one you think you are testing — build stamp, package version, source commit, device model. Blocks everything else, and reports **all four** results rather than stopping at the first |
| `03-autologin` | the greeter's `[initial_session]` brings up a graphical session at boot with nobody touching the phone, and phosh is alive in it |
| `05-modules` | required modules built; module tree matches the package; no hot-swap leftovers |
| `10-health` | no panic/oops/BUG/remoteproc crash; rootfs has room; no new failed units |
| `15-hwtest` | display, input devices, camera presence and vibrator against a recorded reference |
| `19-ucm-ownership` | the installed UCM verbs are ours **and** a package of ours owns the paths — the distro ships its own files there, and a hand-copied override reverts on the next upgrade |
| `20-audio` | codec enumerated on SLIMbus, playback and capture PCMs open |
| `21/22-audio-*` | a tone on the speaker reaches the handset/headset mic (`--acoustic`) |
| `25-sensor` | the SSC sensors enumerate and read: registry server running, all four IIO devices bound, proximity and ambient light readable, and `iio-sensor-proxy` sees both |
| `30-voice` | the VoiceMMode1 path routes and opens — **the regression this suite was built for** |
| `35-pulse` | userspace has a real sink and the handset mic — also proves the audio checks put the sound server back |
| `40-camera` | the sensor is not merely probed but linked into CAMSS |
| `44-camera-af-windows` | focus windows are offered in the sensor's **active pixel array** — not in whatever V4L2 format the last user of the camera left behind — and a window at either corner actually narrows the metering instead of falling back to the centre. The check leaves the sensor in a small format first, because without that step the right answer and the wrong one coincide |
| `45-camera-af-windows-pipewire` | the same window survives the trip **through PipeWire**, which is the path every application on this device actually uses. Needs a stream open — the IPA does not exist until somebody is capturing, and a control set against an idle node measures nothing — and it has to speak to the *logged-in user's* graph, not root's (see the traps below) |
| `50-charger` | the charger reports sane values **and current actually flows** |
| `52-fuel-gauge` | the reported capacity tracks the battery and not the CPU load. Takes the phone **off VBUS electrically** for the burn (`USBIN_SUSPEND_BIT` via the charger's writable `status`), so it measures a real load step with the cable still attached — on the charger the rail does not move at all and the check has nothing to judge |
| `60/65/70` | wifi connected, bluetooth powered, modem registered |
| `98-camera-af-rail` | a system resume leaves the focus motor's supply **off**. The defect it exists for is invisible from every other angle — `runtime_status` still reads `suspended`, `active_time` does not move, dmesg says nothing — and only the regulator witnesses it. Detached, because it suspends |
| `99-suspend` (category `power`) | the sleep-state menu matches `baseline/sleep-states.txt`, suspend happens and the RTC wakes it, **and the system power domain actually collapsed while it was down** — a suspend that freezes userspace but never lets the domains go still passes every outward test and saves nothing. Runs last and detached — resuming re-enumerates USB and drops the link every time |

## Rules the suite enforces

**Every failure blocks.** There is no xfail or TODO list. A subsystem that is
mid-bring-up fails until it works, and then goes green on its own. The camera is
in exactly that state today.

**An untested category cannot read as green.** `checks/CATEGORIES` lists the
topic categories, and the runner guards both directions: every listed category
must have a check, and every `wip/<base>/*` branch on the
[fork](https://github.com/llg179org/linux) must be listed. If a check is skipped,
its category is reported uncovered and
the run does not pass without `--allow-uncovered CAT`.

Every check now runs unattended. The last one that did not was the cold-unlock
latency measurement, retired 2026-08-16 — see "The login is automatic now".

## Adding a check

Drop a `NN-name-test.sh` in `checks/`. POSIX sh, exit code is the verdict,
output lines prefixed `PASS:`/`FAIL:`/`SKIP:` — the postmarketOS
`postmarketos-test` convention, so a check could move into a device `pmtest`
subpackage later without rewriting. Declare metadata in header comments:

```sh
# Category: voice      # counts towards topic-branch coverage
# Requires: modem      # skipped by --no-modem
# Detached: yes        # will drop the link; run detached and read the result file
```

The number decides the order, and the order is deliberate: cold checks early,
the audio block together, suspend last.

## Measured traps (do not rediscover these)

- **`aplay --dump-hw-params` always exits 1.** It aborts the open once it has
  printed the parameters, so its exit code is not an open/fail signal. Use a
  real one-second open of `/dev/zero` — that is silent and costs nothing.
- **The sound server holds the card**, and whether a second open gets EBUSY
  depends on whether the sink happens to be suspended at that instant. Any raw
  ALSA work must go through `audio_grab` in `lib/audio-state.sh`.
- **`amixer` needs `-D hw:0`.** ALSA's `default` device routes through
  PulseAudio, so once the sound server is stopped every plain `amixer` call dies
  with "Connection refused" — which looks exactly like a missing control and
  sends you hunting a kernel regression that is not there.
- **There is no `pulseaudio` systemd unit here**; the process calling itself
  pulseaudio is pipewire-pulse. Stop `wireplumber.service pipewire.service
  pipewire.socket`.
- **busybox `ps` has no `-C`.** Using it returns nothing silently, which made
  the sound-server detection report "not running" and skip the stop entirely.
- **`hwtest` needs root**, and its reference cannot live in `/tmp`:
  `fs.protected_regular` stops root writing over another user's file in a sticky
  directory. Installing it also pulls 13 packages and regenerates `/boot`.
- **Any `apk` operation can silently replace your device tree.** Installing an
  unrelated package fires the postmarketos-mkinitfs trigger, which reinstalls
  `/boot/<board>.dtb` **from the kernel package** over a hand-deployed one.
  Installing `hwtest` cost the camera exactly this way on 2026-07-25: the
  installed package predated the camera DT work, the sensor node disappeared,
  and the driver then never probed — with *no* dmesg lines to find, because
  there was nothing to bind to. `40-camera` now tells this apart from a probe
  failure by checking the live device tree first.
- **Every check runs as root, and PipeWire is a per-user service.** Root has no
  `XDG_RUNTIME_DIR` and no graph of its own, so `pw-cli` under the runner returns
  **zero nodes of any kind** — measured 2026-08-16. `45-camera-af-windows-pipewire`
  read that as "no libcamera node in the PipeWire graph" and skipped: a different
  claim from the true one, and one that reads like a fact about the device. It had
  been proved in both directions by hand as `fp3` and never once under the runner,
  which is exactly how a check ends up passing on nothing. Anything touching
  `pw-cli`, `systemctl --user`, `systemd-run --user` or `journalctl --user` has to
  cross into the session (`loginctl list-users` names it), and must report "cannot
  reach a graph" separately from "the graph has no camera node".
- **Never name an IIO device by index.** `42-camera-flash` read
  `iio:device1` for the USB input current and skipped every single run with
  "attach a cable" — including runs with a cable attached and the charger
  online, which is what made the message worth distrusting. The channel is on
  `iio:device0`; the index moves between boots. Match on the channel, and give
  "no such channel anywhere" a different message from "the input is offline".
- **☠️ `USBIN_SUSPEND_BIT` lives in the PMIC and survives a warm reboot.** Left
  set through a restart it has wedged the bootloader — fastboot enumerated and
  answered nothing, and only a held power button recovered it. Any check that
  suspends the charger input arms its release *before* the first write, runs it
  on every exit path, and never reboots while it is set. A phone that
  discharges with the cable plugged in is what a forgotten bit looks like.
- **Do not gate a charger disconnect on a negative `current_now`.** With the
  input FET open on a battery at 100%, `online` reads 0 and `status` reads
  `Discharging` while `current_now` reads exactly 0 — an idle full pack really
  is drawing nothing. Ask the ADC under the load instead, where a non-negative
  reading means something is genuinely wrong.
- **The sudo prompt has no trailing newline**, so it prepends itself to the
  first line of output. Send it to `/dev/null`; filtering it with `grep` deletes
  that line *including* your own first line of output.
- **A WARN storm evicts the boot from `dmesg`.** Each `WARNING:` on this device
  prints a ~1.5kB module list, so a few hundred of them push the early boot out
  of the ring buffer: measured 2026-08-16, `dmesg`'s oldest surviving line was
  13684s into a 14351s-old boot, while `journalctl -k -b` still had all 299
  warnings from the ninth second. A fault check reading `dmesg` was looking at
  the last eleven minutes of an eighty-minute boot and calling it "the kernel
  log". Read the journal, fall back to `dmesg`, and say which you read.
- **A fault check that ignores `WARNING:` is not a fault check.** `10-health`
  grepped only for panic/oops/BUG and reported green through 299 instances of
  `apcs-cpu0-pll failed to enable!` plus a `ktime_get()` WARN this project had
  introduced the day before. A WARN is a kernel developer saying a case should
  not happen; a test has no business deciding it does not matter. Known ones go
  in `baseline/dmesg-allow.txt` with a dated reason, and the check still prints
  each allowlisted line with its count — an allowlist that swallows its entries
  silently becomes the thing it was meant to prevent.
- **Put the device in the state you need, then put it back.** Three checks now
  do this rather than asking a human or skipping: `52-fuel-gauge` opens the
  charger's input FET for its load step, `65-bluetooth` clears an rfkill soft
  block, `98-camera-af-rail` restarts wireplumber to release the focus motor.
  Each arms its restore before the first change. The alternative is what
  `65-bluetooth` was: a permanent `--no-bt` on the command line, and a check
  nobody had watched fail in months.

## Why not just use hwtest?

We measured it rather than assuming. It runs headless, `--verify` returns 1 on a
regression, and it covers framebuffer, DRM, camera presence, vibrator and every
input device — so `15-hwtest` uses it for exactly that slice instead of
reimplementing it. It does not cover audio function, the voice path, the modem,
wifi, bluetooth, the charger, kernel health, modules or identity, which is what
the rest of the checks are for.

## Baselines

`baseline/` holds the things a check compares against. `modules-required.txt` is
maintained **by hand** on purpose — auto-generating it from a build would defeat
its only job, which is noticing that something stopped being built.
`failed-units.txt` and `dmesg-allow.txt` are deliberate, reviewable exceptions:
every line is a fault we have decided to stop looking at, so an unjustified
entry can hide a real regression for months.

`baseline/hwtest-reference.ini` is the recorded hardware state `15-hwtest`
compares against. Export it from a state you consider good
(`hwtest --export`), then edit it so components that *should* work read `True`
even if they are broken today — otherwise the breakage becomes the baseline and
stops being reported. The camera is `True` in there right now for exactly that
reason, and the check fails until the camera comes back.

## The login is automatic now

Until 2026-08-16 this suite carried `03-unlock-latency`, which timed a **cold
unlock**: on this device that is not a lockscreen being dismissed, because phosh
is not running at all. The phone sat at the greetd/phrog greeter as uid 113 and
authenticating started an entire user session from scratch — of the ~15s a human
perceived, roughly 7s was authentication and session setup before phosh existed
and ~8.4s was phosh starting up to idle (measured 2026-07-25, on a boot where
`Linger` was `no`; it reads `yes` now, so those two numbers no longer split the
same way).

That check needed a person: arm a probe, reboot, have somebody type the PIN with
nobody connected, then judge the trace. It could not be driven over SSH at all,
because logging in as the user starts the very `systemd --user` session whose
cold start was being timed. It was the one thing in the battery that could not
run unattended, and it was skipped in every run for months as a result.

greetd can skip the human entirely. `/etc/phrog/greetd-config.toml` ships an
`[initial_session]` block, commented out; enabling it logs the session in at
boot without authenticating:

```toml
[initial_session]
command = "systemd-cat phosh-session"
user = "fp3"
```

Turning that on does not make the old check pass — it **retires** it, by
removing the path it measured. So the question changed with the device:
`03-autologin` tests that the phone reaches a working graphical session on its
own, which is now the property that matters, and the whole battery runs with
nobody present.

**How it tells an autologin from a quick human**, since it cannot see a hand on
the phone: by *when* the session was created. `AUTOLOGIN_MAX` in
`baseline/autologin.txt` is the discriminator, not just a regression gate — keep
it tight enough that a person could not have done it. For calibration, a human
unlock measured 81.6s after boot on 2026-08-16, with phosh 7.4s behind it.

☠️ **Time it monotonically.** This device's RTC reads 1970 until something sets
the clock, so wall-clock timestamps jump mid-boot: `loginctl` printed "15min
ago" for a session whose `TimestampMonotonic` said 81.6s after boot, on a phone
that had been up for 16000s. The check reads `TimestampMonotonic` for the
session and field 22 of `/proc/PID/stat` for phosh, both of which count from
boot and neither of which the clock can move.

### Rejected end markers

The "home screen is up" signal was chosen by measurement, not assumption:

- **phosh CPU time going quiet — chosen.** During startup its deltas run to tens
  or hundreds of jiffies per sample; at idle they are exactly +1. Sharp, passive,
  no tooling.
- **Queued `systemd --user` jobs — disqualified, and instructively so.** Asking
  for them with `systemctl -M user@ --user list-jobs` *starts the user manager*.
  The probe causes what it observes.
- **MDSS/DSI interrupts as a page-flip proxy — never settles.** The display keeps
  refreshing at ~15 interrupts per sample forever, so there is no quiet to find.

### Why there is no screenshot anywhere in this suite

Every capture path on this device fails: `grim`/wlr-screencopy gets "no supported
format found" from phoc, the gnome-shell Screenshot D-Bus method returns false,
`/dev/fb0` reads all-zero even with the display awake and rendering
(`bl_power=0`, `dpms=On`, `blank` stuck at 4 — fbdev emulation is not wired to
the compositor), and xdg-desktop-portal is interactive and needs a user session
the greeter does not have. Where UI evidence is needed, D-Bus object state is
the substitute — a `/org/gnome/Calls/window/N` object, for instance, is a claim
about what is on screen rather than a log line about what was logged.
