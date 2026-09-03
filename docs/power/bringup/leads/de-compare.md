> ⚠️ **AI-generated.** Maintained by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

# Comparing what the desktop environment costs: phosh vs Sxmo

> ☠️ **DROPPED 2026-08-19, by decision, before Sxmo was ever installed.** Two
> reasons, and the first is the one that matters.
>
> **Disk.** `apk add --simulate postmarketos-ui-sxmo-de-sway` came back clean -
> no `Purging`, no deletions, 127 packages - but it also came back with the
> numbers: 1875 MiB installed now, 2140 MiB after, against **347 MiB free on a
> 2.4 G root**. That is a net 264 MiB plus a download cache, i.e. a real chance
> of filling `/` on a phone with no console whose eMMC has already dropped to
> `emergency_ro` once. Freeing it would have meant deleting 157 MiB of staged
> kernel images from earlier experiments - somebody else's data, for a
> nice-to-have.
>
> **And it was not worth that.** By the time the question came up, the awake
> budget had already been closed as a negative from the other direction: five
> userspace candidates measured, all zero, floor unmoved at ~85-87 mA. A second
> desktop environment would have measured a layer that has already been shown
> not to hold the missing current.
>
> What survives is the **phosh half**, which needs no install and no space: one
> leg with the screen off, read against the ladder's no-session floor. That
> answers "what does the session cost" without answering "which session is
> cheaper". The plan below is kept intact for whenever there is room on the
> root filesystem.

## Why this is worth a night

The power investigation has a hole in it: nothing has ever separated *the
platform floor* from *what the session running on top of it draws*. Every awake
figure on this device - the 130 mA that would not reproduce, the ~150 mA the
slope legs use as their control - was taken with phosh running. A second
environment is the cheapest instrument for that separation, because it changes
only the userspace stack and leaves the kernel, the DT and the firmware exactly
where they are.

## Which Sxmo

**`postmarketos-ui-sxmo-de-sway`.** Sxmo ships four: sway, river, dwm and i3.
Sway and river are Wayland; dwm and i3 are X11. Phosh is Wayland, so picking
sway keeps the comparison to *the shell* rather than turning it into
Wayland-versus-X11, which is a different question and a much larger one.

## The four legs

Two environments times two screen states, each from **its own boot**, each
35 minutes (600 s settle, then 50 samples at 30 s).

| leg | screen | what it answers |
|---|---|---|
| `phosh on` / `sxmo on` | on, backlight pinned to 50 % | what the user actually feels |
| `phosh off` / `sxmo off` | blanked, session still running | what the shell's background costs |

☠️ **Both are needed.** The panel dominates the screen-on figure and will bury a
real difference underneath it; the screen-off pair is where a compositor's
daemons and a set of shell scripts diverge. Reporting only the second would not
answer the question that was asked, and reporting only the first would hide the
answer.

☠️ **Same brightness, or the comparison is of two backlights.** The script pins
it to 50 % of `max_brightness` and records what it actually set, because a DE
that restores its own brightness on login would otherwise decide the result.

## How to switch, and why nothing is uninstalled

Install Sxmo **alongside** phosh and switch by changing which session greetd
starts. Nothing is removed, and switching back is one line and a reboot.

```sh
# ☠️ ALWAYS simulate first and read the output for "Purging". apk-tools 3
# re-resolves the entire world on any single install, and has already carried
# out a days-old half-finished upgrade as a side effect - which is how this
# phone once ended up with a session that had no shell.
sudo apk add --simulate postmarketos-ui-sxmo-de-sway

# Only if nothing is purged and phosh is untouched:
sudo apk add postmarketos-ui-sxmo-de-sway
```

☠️ **After any `apk add`, re-check the boot configuration.** The install
regenerates `/boot/extlinux/extlinux.conf`, which drops the fallback label, the
`panic=10` and the menu timeout - and there is no console on this device, so a
boot config that repeats a mistake every boot is the expensive kind of mistake.

```sh
fp3-selftest --only boot-fallback --host 192.168.x.x   # from the host
```

Then switch the session by editing `command` under `[initial_session]`, and
reboot.

☠️ **The file is `/etc/phrog/greetd-config.toml`, not `/etc/greetd/config.toml`.**
The latter does not exist on this device - `/etc/greetd/` is not even a
directory - and `greetd.service` passes no `-c`, so the path is easy to get
wrong twice. `apk info -L greetd` lists only the binary and its PAM file; the
config belongs to `greetd-phrog`. The first version of `de-compare.sh` read the
wrong path and would have recorded an empty session line without complaining,
which is why it now prints whether the file exists at all.

Today it reads:

```toml
[initial_session]
command = "systemd-cat phosh-session"
user = "fp3"
```

☠️ **Do not guess Sxmo's replacement for `phosh-session`.** Read it out of the
session file the package installs, after installing it:

```sh
cat /usr/share/wayland-sessions/swmo.desktop      # the Exec= line is the answer
```

The package's own `post-install` calls `tinydm-set-session` on that file, which
is a no-op here because this device uses greetd, not tinydm - expect that script
to fail and do not read the failure as a broken install.

Record what the config says in the leg output - `de-compare.sh` reads it back,
because the label passed on the command line is a promise and the config is the
fact.

## Running one leg

```sh
sudo systemd-run --unit=de-leg --collect /root/de-compare.sh sxmo off
```

☠️ As a transient unit, never in an ssh session. And ☠️ the leg takes the phone
off the charger with the PMIC's USBIN suspend bit, which survives a warm reboot
- the script restores it on every exit path including a kill, which the earlier
instruments did not.

## Reading it

```sh
python3 docs/power/de-compare-fit.py docs/power/de-compare-*.txt
```

☠️ Median, never mean: one `current_now` read on this device scatters by about
138 mA. The fitter prints the interquartile range next to the median so a quiet
leg can be told from a noisy one, and it refuses to be clever about legs that do
not share a screen state.
