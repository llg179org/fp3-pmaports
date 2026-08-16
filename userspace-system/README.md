# FP3 system-wide userspace pieces

> ⚠️ **AI-generated.** This page and the files it describes were written by
> Claude (Opus 5) working under the direction of Lajosházi, László Gergely, who
> reviewed every change and made or reviewed every measurement it rests on.

Small files that belong to the whole system rather than to one subsystem, and
that a reflash would otherwise take with it. Each one says what it undoes or
adds, and how to remove it.

## `profile.d/zz-fp3-gsk-renderer.sh` — give GTK4 its GPU back

`soc-qcom-msm8953-gpu` ships `/etc/profile.d/adreno-a506-quirks.sh`, which sets
`GSK_RENDERER=cairo` for every session on this SoC. Its own comment gives the
reason — *"so we prepare for the removal of the legacy GL renderer"* — which is
a portability decision, not a statement that GL is broken here. The cost is
that **every GTK4 application on the phone draws on the CPU**, the camera
viewfinder included, which is what a stuttering viewfinder looks like.

Measured on this device: Snapshot at **130 % CPU with cairo against 32 % with
`gl`**. Re-checked 2026-08-16 on gtk4 4.22.4 and mesa 26.1.6 — the GL renderer
still initialises, and EGL gives an OpenGL ES 3.1 core context on freedreno
a506, with no fallback and no error.

The drop-in sorts after the quirk, so it wins. Install and log in again:

```sh
scp userspace-system/profile.d/zz-fp3-gsk-renderer.sh fp3@$FP3_DEV_IP:/tmp/
ssh fp3@$FP3_DEV_IP 'sudo install -m 644 /tmp/zz-fp3-gsk-renderer.sh /etc/profile.d/'
```

☠️ **It only reaches the session at the next login.** The running phosh keeps
the environment it was started with, so nothing changes until a re-login or a
reboot. Check that it took by reading the compositor's own environment rather
than a shell's, since a shell would show the file working while the session
still ran on cairo:

```sh
tr '\0' '\n' < /proc/$(pgrep -x phosh)/environ | grep GSK_RENDERER
```

☠️ The renderer is called `gl`, not `ngl`.

Deleting the file goes back to the distro default.

## `fp3-nitz-clock` — a real date on a phone with no writable RTC

This device cannot keep time across a boot. `rtc-pm8xxx` offers three ways to
persist it and `pm8953.dtsi`'s `rtc@6000` enables none of them, so `hwclock -r`
reads 1970 on every boot and `hwclock -w` answers
`ioctl(RTC_SET_TIME) ... failed: No such device`. Until something corrects it
the phone runs on a fiction — which is why `systemctl` once dated a failure to
four weeks before the boot that produced it — and TLS, `apk` signatures and
every log timestamp are unreliable in that window.

With WiFi in reach `systemd-timesyncd` closes the window in seconds. Without
it, the **cellular network** is the only time source left: NITZ arrives on the
signalling channel, so it needs neither mobile data nor a data subscription.

`fp3-nitz-clock` is a bootstrap and deliberately not a time source. It runs
only while the clock is still before 2025, and does nothing at all otherwise,
so it can never pull a good clock backwards; NTP refines the result whenever a
network turns up.

```sh
scp userspace-system/fp3-nitz-clock fp3@$FP3_DEV_IP:/tmp/
scp userspace-system/systemd/fp3-nitz-clock.service fp3@$FP3_DEV_IP:/tmp/
ssh fp3@$FP3_DEV_IP 'sudo install -m 755 /tmp/fp3-nitz-clock /usr/local/bin/ &&
    sudo install -m 644 /tmp/fp3-nitz-clock.service /etc/systemd/system/ &&
    sudo systemctl daemon-reload && sudo systemctl enable fp3-nitz-clock.service'
```

`fp3-selftest --only clock` checks both that the clock is a real date and that
this script is still installed and enabled — two arms, because with WiFi in
reach the first passes on NTP alone and would go green on a phone that had lost
the second entirely.

### What was measured, and the two traps in it

☠️ **The value is UTC and the string labels it local.** Measured twice, on
2026-08-14 and again on 2026-08-16 (Vodafone HU, LTE): the modem answered
`2026-08-16T16:11:26+02` when real local time was 18:11:26 CEST, i.e. 16:11:26
UTC. The digits are UTC and the `+02` is wrong, so anything parsing the string
whole sets the clock **two hours slow**. The timezone is reported separately
and correctly, as 120 minutes. The script reads the digits and treats them as
UTC — and the epoch guard is what keeps the ambiguity from ever mattering:
being wrong about it costs two hours, being without the script costs 56 years.

☠️ **The Time interface is not always there.** Measured 2026-08-16: after a
cold boot `mmcli -m 0 --time` answered `error: modem has no time capabilities`
and `org.freedesktop.ModemManager1.Modem.Time` was absent from the modem's
D-Bus object — for the whole session, an hour and a half — while the modem was
registered on LTE at 75 % signal with the packet service attached. Restarting
ModemManager, or just disabling and re-enabling the modem, brought it straight
back: `modem has time capabilities, enabling the Time interface`, followed by
`network timezone polling started` and QMI `Get Network Time` traffic.

So the capability check appears to be decided once, early, and to come out
negative when it runs before the modem can answer. That is a hypothesis from
one boot, not a measurement of the mechanism; what is measured is that the
interface can be absent for an entire session on a modem that is perfectly
capable of it. The script therefore waits for the interface rather than
assuming it, says in the journal which of the two ways it failed, and exits 0
either way — restarting somebody else's daemon to work around this is not
something a clock bootstrap should be doing.

Also measured, and the reason the wait exists at all: registration completes
about **42 s after boot** (`3GPP registration state changed (registering ->
home)` at 17:11:03 for a boot at 17:10:21). A bootstrap that ran at a fixed
early point would find nothing.

### How it was proved

Not by watching it not fail. The clock was deliberately rolled back and the
script run against it:

```
elotte: 2001-06-01T00:05:12+00:00
clock set from the cellular network: 2026-08-16 16:17:22 UTC (waited 0s)
utana:  2026-08-16T16:17:22+00:00
```

Real local time at that moment was 18:17 CEST, so the phone was set to the
correct UTC. The same was done to the check: with `/usr/local/bin/fp3-nitz-clock`
moved aside, `71-clock` goes red on its second arm while the first still passes
on NTP — which is the failure it exists to catch.

☠️ One thing the rollback turned up: `date -u -s "1970-01-01 00:05:00"` is
refused by the kernel with `can't set date: Invalid argument`, while 1971 and
2001 are accepted. So a test that tries to reproduce the boot state exactly
cannot; use any date before the 2025 guard instead.
