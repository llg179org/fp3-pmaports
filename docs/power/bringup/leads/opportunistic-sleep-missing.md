# Nothing on this system asks for a suspend — and the kernel cannot autosleep

> ⚠️ AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.

**Opened 2026-08-30**, prompted by a third-party claim that pmOS drains twice
what Android does because "all devices do that with suspend broken".

## What the claim gets right, and where it is wrong

Right, and stated by postmarketOS itself on
[Power saving](https://wiki.postmarketos.org/wiki/Power_saving):

> "Upstream kernels tend to have a lot higher idle power consumption than
> downstream (android-based) kernels found in other Linux mobile distros, due to
> one or more device components being active and draining power even when screen
> is off, or other unsupported driver features."

The *phenomenon* is documented. The *mechanism* named there is *runtime* power
management — components live with the screen off — which is not "suspend broken".

Wrong on this device, and measured: suspend works. In the step-0 run started
2026-08-30 15:58, ten consecutive rounds each slept the full 602 s and every one
ended on `56:pm8xxx_rtc_alarm`. Nothing interrupted them.

☠️ **Conditional on ModemManager being stopped.** `sleep-night.sh`'s own header
records the 2026-08-29 measurement: with the daemon running every suspend dies
within 16-53 s. So the suspend is not broken — it is *interrupted*, which is a
different fault with a different fix.

☠️ The generic "broken suspend" story on the web is about x86 laptops losing S3
to s2idle in firmware. This SoC has no S3 to lose; that material does not
transfer.

## The real gap

Nothing on pmOS asks for a suspend:

* `sleep-inactive-ac-type='nothing'` (postmarketos-base-ui-gnome) — and this
  phone is always on a cable, because the cable is the link;
* `IdleAction=ignore` in logind;
* `/etc/sleep-inhibitor.conf` makes an ssh session a sleep inhibitor.

The Android-style answer is not available either. The wiki's
[Opportunistic Sleep](https://wiki.postmarketos.org/wiki/Opportunistic_Sleep)
page says of the daemon that would drive it:

> "Stated is very work in progress, it isn't ready for use or packaged for
> postmarketOS yet"

and names two required kernel options, `CONFIG_PM_WAKELOCKS=y` and
`CONFIG_PM_AUTOSLEEP=y`. **Measured in `linux-fp3/config-fp3.aarch64`:**

```
CONFIG_PM_WAKELOCKS=y
CONFIG_PM_WAKELOCKS_LIMIT=100
CONFIG_PM_WAKELOCKS_GC=y
# CONFIG_PM_AUTOSLEEP is not set
```

⇒ `/sys/power/autosleep` does not exist on this kernel. Half the mechanism is
compiled in and the half that drives it is not.

## ☠️ The policy list above is only half of it — checked 2026-08-30

`sleep-inactive-ac-type='nothing'` is the **AC** branch. pmaports overrides only
that one; the whole of `00_postmarketos-base-ui-gnome.gschema.override` under
`[org.gnome.settings-daemon.plugins.power]` reads:

```
sleep-inactive-ac-type='nothing'
ambient-enabled=false
```

`sleep-inactive-battery-type` is **not** overridden, and GNOME's own default for
it is `'suspend'` with `sleep-inactive-battery-timeout=1200` (20 minutes).

⇒ **On battery this phone should suspend by itself after 20 minutes idle. On the
cable it never will.** Every measurement this project has taken was on the cable,
because the cable is the link - so the configuration that governs the phone as a
*phone* is the one branch we have never been in.

This is a reading of pmaports and of upstream GNOME defaults, **not** a device
measurement: the schema on the device has to be read (`gsettings get
org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type` and
`-timeout`), and whether UPower reports "on battery" when the PMIC input is
suspended is a separate question. Both fold into R1b.

Note also pmaports issue
[#990](https://gitlab.postmarketos.org/postmarketOS/pmaports/-/work_items/990)
("radically reduce suspend time", closed): pmOS *does* suspend on idle as a
matter of policy - the default timeout was cut from 15 minutes to two in v21.12.
So "pmOS never suspends" is wrong as a general statement about the distribution;
it is right about *this phone on a cable*.

## What this does NOT explain — read before acting on it

☠️ The measured model for this device is `mA = 54.9 + 135.0 x MPSS-duty`, and the
gap to the oracle is in the **awake** duty (34.8 % vs 6.1 %). Residency is a
*separate* track. Even a perfect opportunistic-sleep implementation says nothing
about why the modem is awake a third of the time while the phone is up, so this
lead must not be allowed to absorb the D-track.

☠️ And it is not a drop-in switch. The wiki states the caveat plainly: "A
wakelock must be held while the display is on." Turning on autosleep without a
daemon that holds wakelocks means a phone that suspends while it is being used.

## Pre-registered next step

Not "enable AUTOSLEEP". First **R1b** (`idle-suspend-window.sh`): with
`IdleAction=suspend` and a 60 s threshold, does the phone suspend on its own at
all, and does anything let it stay down? A `success` delta of 0 over the window
means the policy layer alone is enough to explain the absence of sleep, and the
kernel option is not yet the question.
