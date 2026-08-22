# Closed items

> ⚠️ **AI-generated.** These pages, and the code and measurements they describe,
> were written by Claude working under the direction of Lajosházi, László
> Gergely, who reviewed every change and made or reviewed every measurement
> they rest on.

Sections and numbered items moved out of [`TODO.md`](TODO.md) and
[`FP3-TODO.md`](FP3-TODO.md) once they were answered, fixed or disproved.
Everything is kept verbatim as it stood when closed — headings, numbering and
strikethrough included — so cross-references by number or title still resolve.
The numbering gaps left behind in `FP3-TODO.md` are deliberate for the same
reason: nothing was renumbered.

---

# From `TODO.md`

## ~~Is our own UCM verb what keeps the audio DSP awake?~~ — answered 2026-08-20: no, and the real holder is upstream

**Measured, both halves.** [`audio-hold-probe.sh`](power/bringup/tools/audio-hold-probe.sh)
on a fresh boot dropped the capture pre-route, then the playback route, then put
one back, with a 30 s suspend after each. Its first arm is a gate and it passed —
the phone was in the held state — and **every arm read `LPASS +0`, XO off 0 ms of
30 000**. Our UCM verb is not the holder.

**What is.** `clk_summary` shows `LPASS_CLK_ID_INTERNAL_DIGITAL_CODEC_CORE` at
`enable=1 prepare=1`, 19.2 MHz, consumer `c0f0000.codec` — which is bound to
**`msm8916-wcd-digital-codec`**, the SoC's *internal digital* codec, not the
SLIMbus WCD9335. It also holds `xo` as `ahbix-clk` at enable count 7. That mclk is
provided by the ADSP over APR, so the ADSP cannot power-collapse while it is
sourced.

`sound/soc/codecs/msm8916-wcd-digital.c`, `msm8916_wcd_digital_probe()` takes both
clocks **unconditionally at probe** and drops them only in `remove()` — no runtime
PM, no DAPM gating. ☠️ **This is upstream mainline code, not this port's.** It
affects every msm8916/8939/8953 board that instantiates the internal digital
codec, and on the FP3 that codec is not in the audio path at all: playback and
capture run over the WCD9335 on SLIMbus and the AW8898 on MI2S.

☠️ **The DAPM explanation was tested and is dead.** DAPM's own `MCLK` supply
widget reads `Off` and both PulseAudio sources are `SUSPENDED` while the clock
count is still 1 — a clock held outside DAPM cannot be released by anything DAPM
does, which is also why the four mixer arms all read zero.

**What remains to do here, in order:**

1. **Confirm on the device** — unbind `c0f0000.codec` from
   `msm8916-wcd-digital-codec`, suspend 30 s, read the LPASS counter. One command
   and one suspend. ☠️ Check afterwards that audio still works (the silent
   `20-audio` and `24-speaker-amp` checks); the internal codec should not be in
   the path, but "should not" is not a measurement.
2. **Then decide the fix.** Runtime PM on the clocks, or taking them from the
   codec's own DAPM supply widget. Either is a small upstream patch.
3. ☠️ **Do not schedule this for its current.** The whole mechanism — the ADSP
   collapsing through every suspend — is priced at ~4 % of the sleep current,
   inside the instrument's own spread. This is a correctness fix and an
   upstreamable one; it is not the deep-sleep lever.

**The night-work rule this entry established stands:** nothing may make a sound at
night. The audio coverage is automated and mostly silent (`20-audio`,
`24-speaker-amp` on the control bus); only `21-audio-acoustic` plays a tone, it is
already behind `--acoustic`, and `queue.sh` refuses any job line that would play
something.

## ~~`15-hwtest` cries wolf twice, and is the one check that is audible by default~~ — settled 2026-08-13

**Settled by narrowing what `hwtest` is asked to judge.** The check and the
reference now skip the same eleven components, and both list them, so `--verify`
keeps its regression semantics over what is left: the framebuffer, the DRM
connector and every input device — touchscreen, power key, volume keys and the
headset jack's input node, which nothing else in the suite covers. It runs
silently in two seconds and passes; the vibrator coverage it gave up came back
as a new `16-vibrator`, which reads the device and its force-feedback mask
without shaking the phone.

Three things were measured on the way, and each changed the answer:

* ☠️ **`--skip` takes one component per flag.** It is `action='append'` and the
  test is `c.__name__ in args.skip`, so `--skip Camera,Audio` matches nothing
  and skips nothing, silently.
* ☠️ **`hwtest --export` crashes on this device**, which is why the skip list is
  eleven long rather than three. It writes each result's path as a
  comment-shaped key, and Python 3.14's configparser refuses a key containing
  the delimiter — every IIO path has one (`iio:device2`), and so does the LED
  (`rgb:status`). The export dies with `InvalidWriteError` partway through,
  leaving a truncated file. Worth reporting upstream.
* ☠️ **The suite could not run over WiFi at all**, and the symptom was
  `device <ip> unreachable`. `lib/common.sh` forced
  `PreferredAuthentications=password -o PubkeyAuthentication=no`, while sshd
  here accepts a password only on the USB subnet — so our own SSH hardening
  locked the tests out of the wireless link. Fixed by letting the key be tried
  first, with the password as the fallback it always was.

The original report follows.

Two components of `hwtest` call this device broken when a check of our own says
otherwise, measured 2026-08-12 with `--verbose`:

* **camera** — it asks for a 320x240 and then a 640x480 JPEG and gets neither
  (`[Errno 2] ... '/tmp/320x240.jpg'`), on a sensor that captures its full
  4032x3024 on demand. `40-camera` judges the sensor, its subdev and its link
  into CAMSS, and passes.
* **proximity** — it wants `in_proximity_scale`, which this driver does not
  expose and does not have to: the channel reports raw counts with no physical
  unit. `25-sensor` reads `in_proximity_raw` (274 counts) and the
  iio-sensor-proxy properties in-call blanking depends on, and passes.

Separately, this is the **only check that makes noise without `--acoustic`** —
its audio component drives the loudspeaker (at half volume, since the check
borrows the level helpers) and its vibrator component runs the motor. The
suite's rule everywhere else is that anything audible is opt-in, and a full run
at night is not the moment to find the exception.

☠️ **`--skip` alone is not the fix.** A skipped component is *missing* from the
run, and `hwtest --verify` exits 1 on a removal as well as on a regression:
skipping components on the run but not in the reference turns one failure into
several. Whatever is skipped has to be skipped when the reference is exported
too — which is what was done above, and it is a decision about what the
baseline means rather than an edit to the check.

## ~~The handset microphone is dead on a fresh boot~~ — solved 2026-08-14: a package upgrade overwrote our UCM verb

**Cause, measured:** `/usr/share/alsa/ucm2/Fairphone/fp3/HiFi.conf` on the
device was **not ours**. It was the 423-byte stock file shipped by
`soc-qcom-msm8953-ucm-20-r0`, carrying a single `Speaker` device — where ours is
4057 bytes with Speaker, Earpiece and Headphones. The whole `ucm2/` tree was
rewritten `Aug 6 22:37`, when a package install last resolved `world`. Nothing
outside the tree was touched: `90-fp3-mic.pa`, `fp3-mic-select`, `fp3-voiced`,
the vibra rule and both services were all still in place, because they live in
`/etc` and `/usr/local` and are not package-owned.

That one file explains every symptom at once, and both mechanisms are already
written down in `userspace-audio/README.md`:

* our verb pre-routes MultiMedia1 to a backend, because a q6asm front end
  returns `EINVAL` on open until it is routed. The stock verb does not, so
  PulseAudio's profile probe failed, it found no working profile, and the card
  sat at `Active Profile: off` behind an `auto_null` sink — which is also why
  no `module-alsa-source` ever appeared.
* our verb pre-routes `DMIC0 → DEC0 → SLIMBUS_0_TX`, which is what makes
  `hw:0,1` openable. The stock verb does not, hence `Invalid argument`.

**Fix applied:** copied `userspace-audio/ucm2/Fairphone/fp3/HiFi.conf` back into
place and restarted the sound server with `pulseaudio -k`. Verified immediately
after: `Active Profile: HiFi (Speaker)`, the real sink back, `fp3-handset-mic`
present, and both checks green — `20-audio` (`capture PCM hw:0,1 opens`) and
`35-pulse`. No reboot, no kernel change.

☠️ **It was never a kernel regression, and the planned fallback-kernel A/B would
have proved nothing** — both kernels would have failed identically, since the
fault was a userspace file neither of them ships. The reboot was queued because
"whether this is a regression is not known"; what actually answered it was
looking at the file the failing layer reads. **Read the config the failing
component actually loaded before bisecting the thing underneath it.**

☠️ **Two files were reverted, not one — and the second was still broken after
the microphone came back.** The master config
`ucm2/conf.d/Fairphone_3/Fairphone_3.conf` was stock too (274 bytes against our
280), and the stock one does not register the `Voice Call` verb at all. So the
voice-call routing had no verb to apply, silently, and the passing microphone
checks said nothing about it. Found only by inventorying every file the package
ships against the repo, rather than by stopping at the one that explained the
reported symptom.

**Durability, done the same day:** the hand-copy is replaced by a package,
`userspace-audio/fp3-audio-ucm/`, which owns all three paths through
`replaces="soc-qcom-msm8953-ucm"`. Verified rather than assumed — reinstalling
the stock package left our files untouched and still owned by ours:

```
before:  4057  280
(1/1) Reinstalling soc-qcom-msm8953-ucm (20-r0)
after:   4057  HiFi.conf         owner=fp3-audio-ucm-1-r0
          280  Fairphone_3.conf  owner=fp3-audio-ucm-1-r0
```

`alsaucm` now lists both verbs (`HiFi`, `Voice Call`), and `20-audio`,
`35-pulse` and the new `19-ucm-ownership` all pass. That last check asserts
**identity and ownership separately**, since either can hold while audio is
broken: the right content with no owner is correct only until the next upgrade.

<details>
<summary>The original report and the three dead ends it recorded (2026-08-13)</summary>

Measured 2026-08-13 on `linux-fp3-7.1.3-r53`, in a full `fp3-selftest` run:

```
FAIL: 20-audio   capture PCM hw:0,1 (MultiMedia2) does not open
FAIL: 35-pulse   no fp3-handset-mic source - the mic drop-in did not load
dmesg:           MultiMedia2: ASoC: no backend DAIs enabled for MultiMedia2,
                 possibly missing ALSA mixer-based routing or UCM profile
```

Everything userspace is present and running: `90-fp3-mic.pa` is installed,
`fp3-mic-select` is enabled and active (and restarting it changes nothing), the
UCM files are in place, and PulseAudio is up with the speaker sink. What is
missing is the **capture routing**, and with it the source: `pactl list short
modules` shows no `module-alsa-source` at all, because the drop-in loads it
inside `.nofail` and it fails silently.

What has been established, so the next session does not repeat it:

* **Setting the route by hand gets further, and says where the wall is.**
  `amixer -c0 cset name='MultiMedia2 Mixer SLIMBUS_0_TX' 1` makes `arecord`
  *open* the PCM; the read then fails with `I/O error`. So the front end is a
  routing question and there is a second problem behind it on the SLIMbus TX
  side. The control was set back to `off` afterwards.
* ☠️ **"Nobody is logged in" was a good hypothesis and it is wrong.** The phone
  was indeed sitting at the greeter (`loginctl` showed `greetd ... greeter tty7`
  and no user session on seat0), and the drop-in's own comment says the capture
  routing comes from the HiFi UCM verb's `EnableSequence` when the card profile
  activates. But after a real login — `c68 fp3 seat0 tty7`, greeter gone,
  PulseAudio restarted — the source is still absent and `hw:0,1` still returns
  `Invalid argument`.
* **The UCM verb cannot even be queried** by that card name: `alsaucm -c
  "Fairphone 3" get _verb` answers *"No such file or directory"*, and `set _verb
  HiFi` changes nothing. Whether the card is addressable under another name is
  the obvious next thread.

**Whether this is a regression is not known**, and the cheapest way to find out
is already in place: `/boot/extlinux/extlinux.conf` has a `postmarketOS-fallback`
entry pointing at the previous kernel, so one reboot answers it. Nothing in r53
touches audio — its only kernel change is `ak7375` — so a fault on both sides
would point at userspace or at the boot-time SLIMbus race visible in the same
log (`wcd9335-slim: Failed to get logical address`, `SLIM TX timed out`, then a
recovery two seconds later).

</details>

## ~~The notification LED blinks forever after a missed call~~ — closed 2026-08-16, it does end

**Closed on the user's own observation:** the LED stopped when *all* notifications
were closed. So the feedback is ended after all — just not by dismissing the one
notification that started it, which is what "forever" was inferred from. Nobody
had tried clearing the whole tray before calling it endless.

Left below as it was measured, because the mechanism is still worth knowing and
the item may come back in the narrower form "dismissing one notification does not
end its own LED feedback". Item 1 stays the real question if it does.

**Original symptom:** after a missed call the LED keeps blinking; dismissing the
notification does not stop it.

It is **not** the camera flash — the phone exposes no flash or torch LED at all:

```
/sys/class/leds/ →  mmc0::   mmc1::   rgb:status
```

and the device tree contains no flash node (see the parked one below). What
blinks is `rgb:status`, the RGB status LED on the PMI632 LPG.

**Measured on the device:**

* `rgb:status` uses the `pattern` trigger with **`repeat = -1`** — repeat forever;
* feedbackd's `default.json` defines `phone-missed-call` as a `Led` feedback,
  `#00FFFF`, and `notification-missed-generic` as a blue one at frequency 500 —
  **neither carries a duration**, so the feedback runs until the client ends it;
* there is **no `fairphone,fp3.json` theme** installed (the FP5 has one, the FP3
  does not), so those generic rules are what apply.

**Immediate workaround:** `echo 0 | sudo tee /sys/class/leds/rgb:status/brightness`,
or restart feedbackd.

**Two things to do, in this order:**

1. Find out who fails to call `EndFeedback` when the notification is dismissed —
   phosh or the calls app. That is the actual bug; everything else limits the
   damage.
2. ~~Ship a `fairphone,fp3.json` feedbackd theme that gives those LED feedbacks a
   bounded duration.~~ ☠️ **Not possible with this feedbackd**, measured
   2026-08-13: an LED feedback has no duration to bound. The JSON keys the
   binary understands are `event-name`, `type`, `color`, `frequency`,
   `duration`, `effect`, `magnitude` and `parent-name`, and `duration` belongs
   to the vibra feedbacks alone — the only accessors are
   `fbd_feedback_vibra_get/set_duration`, there is no `max-duration` string in
   the binary at all, and `FbdFeedbackLed` has nothing but colours and
   `fbd_feedback_led_run`. An LED feedback runs until the client ends it, by
   construction.

   The timeout that does exist is **client-side**: `fbcli -t` passes one when
   triggering, so a caller can bound its own feedback. That makes item 1 the
   only real fix rather than merely the deeper one.

   What a `fairphone,fp3.json` theme *could* do is override
   `phone-missed-call` and `notification-missed-generic` with a bounded feedback
   of another type — a short `VibraRumble`, say — which stops the endless blink
   by removing the LED notification altogether. That is a decision about what
   the phone should do, not a bug fix, so it is not shipped here unasked. The
   theme would live next to the other userspace drop-ins this repo carries
   (`userspace-audio/udev`, `pulse`, `ucm2`).

   ☠️ Note also that those LED rules live in the theme's **silent** profile, not
   in `full` — the profiles cascade, so reading only `full` finds nothing and
   suggests, wrongly, that no rule applies.

## ~~Parked: the PMI632 camera flash~~ — it works, 2026-08-03

The parking reason was right and the fix was small. `leds-qcom-flash.c` accepts
three flash-module subtypes and refuses everything else with *"flash LED subtype
%#x is not yet supported"*; read over the SPMI regmap on the phone, the PMI632
module answers `0x18` in `FLASH_TYPE` and **`0x05`** in `FLASH_SUBTYPE`, which is
none of them. Enabling the node as it stood would have failed the probe exactly
as feared.

☠️ **The module is on the second USID, not the first.** `0xd300` reads back all
`XX` on `0-02` and the real values on `0-03`. The charger at `0x1000` on `0-02`
is the positive control that tells "wrong USID" from "the read path is broken".

It is the three-channel block with two channels bonded out, so the fix is a
fourth branch taking `mvflash_3ch_regs` with `max_channels = 2`. Measured with
the module idle, the live registers are that layout exactly — timers at
`0x40..0x42`, target currents at `0x43..0x45`, module enable `0x46`, current
resolution `0x47`, strobe `0x49..0x4b`, channel enable `0x4c`, torch clamp
`0xec` — which is also the map Qualcomm's downstream `qpnp-flash-led-v2` uses
for this PMIC, from the same code path as PMI8998 and PM8150, rejecting only
channel ids above 1. `CONFIG_LEDS_QCOM_FLASH` also had to be turned on; it was
not in the config at all.

Measured on `linux-fp3-7.1.3-r34` (`#35-fp3`), three ways, because the first
instrument lied:

| | |
|---|---|
| probe | `white:flash` under `/sys/class/leds`, nothing in dmesg |
| the hardware is programmed | `CHAN_EN 0x03` (both ganged channels), `MODULE_EN 0x80`, `ITARGET 0x3b` on both — 0x3b is 59, so (59+1) × 5 mA = 300 mA a channel, the 600 mA of `led-max-microamp` split in two |
| current flows | USB input ADC, three interleaved passes: off 74 437 / 87 737 / 76 729 against on 139 900 / 153 524 / 144 928 — no overlap |
| light comes out | the rear camera sees the scene go from mean 15.82, σ 0.81, 20 distinct values to mean 70.0, σ 34.4, ~240, repeatable to 0.09 across three passes |

☠️ **The battery is the wrong ammeter here, twice over,** and believing it
produced a confident "no current flows" about a flash that was visibly lit.
`pmi632-battery` exposes **no `current_now` at all** — the charger driver does
not implement the property — and the check's `|| echo 0` turned that missing
file into a reading of zero. Falling back to battery *voltage* droop was no
better: with a cable attached the torch is fed from USB, so the pack never sees
the load. The instrument that works is the PMIC's own USB input current ADC
(`in_voltage_usb_in_i_uv_input`), and it needs interleaved repeats — a single
on/off pair sits inside its noise. The positive control that would have caught
the second error early is cheap: eight busy loops drop battery `voltage_now` by
180 mV, so the channel *can* see a load of that size; the torch showing nothing
meant the path, not the light.

What is **not** carried over from downstream: on this PMIC the flash is fed by
the charger's boost, and downstream sets `POWER_SUPPLY_PROP_FLASH_ACTIVE` on the
charger around a strobe, via its own `schgm-flash` block at `0xA600`. Nothing in
mainline does that. It does not stop the torch — the charger's `VREG_OK` (bit 4
of `0xA607`) comes up on its own when the LED module is enabled, measured going
`0x00` → `0x36` — but the full 2 A strobe has not been tried and may well need
it. `FORCE_BOOST_CONTROL` at `0xA641` stays `0x00` throughout.

Checks: [`tests/checks/42-camera-flash-test.sh`](../tests/checks/42-camera-flash-test.sh)
for the registers and the current, and
[`userspace-camera/flash-check.py`](../userspace-camera/flash-check.py) for the
optical confirmation, which needs a scene and so cannot live in the unattended
battery.

Still open: the torch now appears under `/sys/class/leds`, which gives feedbackd
something new to blink — see the missed-call item above.
`CONFIG_V4L2_FLASH_LED_CLASS` is deliberately still off, so no
`/dev/v4l-subdev` exists for it and libcamera cannot drive the flash yet; that
was kept out so the bring-up measured one change.

## ~~Parked: the camera, after a WirePlumber crash traced to our own AF code~~ — found and fixed, 2026-08-08

Measured 2026-08-03, `linux-fp3` and `snapshot-50.0-r26` both otherwise fine.
WirePlumber itself segfaulted mid-session — not the Snapshot app, not the
kernel — with a C++ assertion inside our own autofocus algorithm:

```
.../bits/stl_vector.h:1282: ... operator[](size_type) const ...:
  Assertion '__n < this->size()' failed.
```

The stack trace goes straight through
[`0101-simple-autofocus.patch`](../userspace-camera/libcamera/0101-simple-autofocus.patch)'s
own code: `libcamera::ipa::soft::algorithms::Af::interpolatePeak()` indexed a
`std::vector<double>` out of bounds while interpolating the sharpness peak from
the contrast-detection statistics. Not yet localised to a specific input (which
zone table, which frame shape) that triggers it - only that it happened once,
live, during ordinary preview use.

systemd restarted WirePlumber on its own, but the app that had a camera stream
open when it died could not reattach - every resolution the viewfinder tried
came back with the same "Element failed to change its state", because the
PipeWire/portal session itself was gone, not the chosen size. This is the same
shape as the documented "restart wireplumber after a libcamera upgrade" trap in
[`userspace-camera/README.md`](../userspace-camera/README.md), just triggered by
a crash instead of an upgrade: killing and relaunching the app (which reopens
the portal session fresh) recovered it immediately, and no amount of
resolution-probing on the app side could have.

**Localised and fixed 2026-08-08** (`059c6de`, in `0101-simple-autofocus.patch`).
The out-of-bounds read was not in the zone grid but in the peak fit itself:
`interpolatePeak()` took its bound from `positions_`, but `planScan()` appends a
revisit of the first position and `detrend()` drops its sample, so `scores_` is
one entry shorter — and a peak at the last swept position made the `i+1`
neighbour lookup read one past the end of `scores_` every time. The fit now
bounds `i` against `scores_.size()` (empty-guard, a `< 3` early return, and the
`i==0`/`i+1>=size` clamp), so the three neighbour reads are always in range.
**Still unverified on hardware:** the fix builds and the reasoning is closed, but
nothing has re-run the live preview to confirm the crash is gone — fold that into
the next camera session on the device rather than a separate cold-boot.

## Settled: the two QDSP6SS framer pokes were not needed

Removed on 2026-07-29. `integration/<base>` used to carry two commits clearing
QDSP6SS `0x0c20002c` bit 3 — one in `qcom_q6v5_pas.c` after `AUTH_AND_RESET`,
one in `qcom-ngd-ctrl.c` before the capability exchange. Both are reverted,
along with the `qcom,slim-framer-quirk-reg` device tree property that armed the
second one (76 lines gone).

What settled it, on the same phone with the same protocol, one variable:

| | audio opens | tone across SLIMbus both ways | `MC:0x21` | codec |
|---|---|---|---|---|
| without the pokes | 8/8 cold boots | 8/8 | 8 | 1 |
| with the pokes | 8/8 cold boots | 8/8 | **8** | 1 |

Not a trace of a difference. Three things worth keeping from getting there:

* **The PAS poke never wrote anything.** Its own log line reads
  `QDSP6SS 0xc20002c 0x101->0x101` — by the time it runs, bit 3 is already
  clear. Only the SLIMbus one wrote (`0x10b->0x103`).
* **`MC:0x21` is not a fault signal.** It is `SLIM_USR_MC_DEF_ACT_CHAN`,
  "define and activate channel", from `qcom_slim_ngd_enable_stream()`. It
  appears eight times per boot **with and without** the pokes while audio works
  — the count tracks how many streams are started, not how many failed. Same for
  `MC:0xd` (`ADDR_QUERY`, which is why `Failed to get logical address` is
  followed 200 ms later by the codec answering) and `capability exchange
  timed-out`.
* **A boot with nobody logged in measures nothing.** The first version of this
  test counted `MC:0x21` in the kernel log and found none in twenty-five boots,
  because without a user session nothing starts audio and the log ends at
  twenty seconds. The metric has to open the audio path.

Reverting the PAS commit does **not** change which ADSP firmware is loaded: the
descriptor it added differed from the msm8996 one only in the firmware name and
the quirk register, and the FP3 device tree sets `firmware-name` on `&lpass`,
which the driver prefers. The `required-opps` CX-turbo idea that used to share
this experiment was already disproven separately —
`qcom_pas_pds_enable()` votes `INT_MAX` on every proxy power domain, measured
live as `cx_perf = 2147483647` for roughly 160 ms across the ADSP boot window,
so it was a no-op.

## ~~The loudspeaker amplifier dies partway through a session~~ — solved 2026-08-21: the ADSP resets the I2C pads; i2c-qup pinctrl fix in r64

*Root cause, proof and instruments: [`audio/amp-i2c-pad-reset.md`](audio/amp-i2c-pad-reset.md). The section below is kept as it stood while open.*

Measured 2026-08-16 on 7.1.3-r57. The AW8898 smart amplifier at `3-0034` is
present and probes, and then does nothing useful:

- **it does not answer on I²C.** `amixer -D hw:0 cset name='RX Volume' 0` — a
  write of the value the control already holds — fails, and the kernel logs
  `ASoC error (-5)` from both `soc_component_read_no_lock()` and
  `snd_soc_component_update_bits()` on register `0x0f`. The control reads back
  `0`, i.e. −127.5 dB, and cannot be moved off it.
- **it never sees its bit clock.** Every playback start logs
  `aw8898 3-0034: iis clock not detected (-110), playing anyway`.
- **so nothing comes out.** With a 1 kHz tone at full scale on `hw:0,0` and the
  handset DMIC0 capturing on `hw:0,1`, two seconds of capture gave peak 95 /
  RMS 5.8 against peak 38 / RMS 2.8 in silence — about 8 dB, where a working
  speaker a hand's width from the mic is tens of dB. The microphone is fine;
  the baseline proves it is live.

This is the same fault as the 2026-07-31 finding that the amp's PLL never
locks: the dying I²C is the consequence, not the cause. What is new is the
scale of what it hid.

☠️ **Nothing in the default battery measured it.** `20-audio` covers the codec
and the PCM opens, which is the entire digital path and none of the analogue
one. The only check that would have noticed is `21-audio-acoustic`, and that
sits behind `--acoustic` because an over-the-air measurement is too
environment-dependent to gate on — so the phone reported *27 ok, 0 failed* with
a loudspeaker that produces no sound. Worse, every acoustic run ever logged
here, back to 2026-07-29, had failed, and the failure was readable each time as
"the room was noisy" or "the phone was lying wrong". That excuse was written
down as the explanation on the morning of 2026-08-16 and it was wrong.

`tests/checks/24-speaker-amp-test.sh` now measures the amplifier where the room
cannot reach it — a round-trip write on its control bus, and its own clock
complaint after a one-second silent playback. It is in the default battery, and
it **fails today**, which is the honest state: the battery is 27 ok / 1 failed,
and the one failure is a loudspeaker that does not work.

Open, and not diagnosed further than the 2026-07-31 measurement.

## ~~The lock screen went black~~ — settled 2026-08-16: it points at a wallpaper that is not installed

phosh draws the lock screen from `org.gnome.desktop.screensaver picture-uri`,
which is a **different key** from the desktop wallpaper
(`org.gnome.desktop.background picture-uri`). Its value here was
`file:///usr/share/backgrounds/gnome/adwaita-timed.xml`, and that file does not
exist on this system — `gnome-backgrounds` is not installed — so phosh fell back
to plain black while the desktop behind it stayed green.

```sh
gsettings set org.gnome.desktop.screensaver picture-uri \
  file:///usr/share/wallpapers/postmarketos/contents/images/2000x2000.png
```

Verified by screenshot: locked before the change, black with the clock and the
notification; locked after it, the pmOS wallpaper. The lock screen was never
broken — only its background was missing.

☠️ **This was not caused by enabling the autologin, but it became visible
because of it.** With `[initial_session]` off, the first screen after a boot was
phrog, the greeter, which draws its own green background; that is what "the
screen used to be green" was. With autologin on, phrog never runs and the first
screen you meet is phosh's own lock screen, which had this fault all along. A
change in *which component you see* looks exactly like a regression in the one
you were seeing before.

---

# From `FP3-TODO.md`

The section each item belonged to is part of its first line's context; numbers
are the original ones.

1. ~~**The camera needs `sony,imx363.yaml` and a MAINTAINERS entry.**~~ **Fixed
   2026-07-31**: binding, MAINTAINERS block and a third cleanup commit after the
   byte-identical import. The node had been **skipped silently** by `dtbs_check`
   for want of a binding; now checked, it adds nothing (44 → 45 errors, the one
   addition being item 5). Details in
   [`TODO.md`](TODO.md#open-before-anything-is-submitted).

2. ~~**Six undocumented codec properties** on the audio `slim217,1a0` node.~~
   **Fixed 2026-07-30**: the WCD9335 binding carries them, and the button
   thresholds were renamed to the family's
   `qcom,mbhc-buttons-vthreshold-microvolt`.

3. ~~**`divclk1` and `wcd-vout-1p8` must move out from under `soc@0`**~~ —
   **fixed 2026-07-30**, both are at the board root.

4. ~~**`wcd-intr-default-state` fails the `qcom,msm8953-pinctrl` schema.**~~
   **Fixed 2026-07-30** by dropping `input-enable`. Details for 2-4 in
   [`TODO.md`](TODO.md#open-before-anything-is-submitted).

5. ~~**The battery node's `qcom,*` properties.**~~ **Moved 2026-08-12**, four
   commits on `wip/7.1.3/charger`: the JEITA thresholds, the soft-zone currents,
   the recharge voltage and the ID tolerance are properties of the charger node
   now, and the pack's identification resistor became the generic
   `id-resistor-ohms` in `battery.yaml`. Details in
   [`TODO.md`](TODO.md#open-before-anything-is-submitted).

6. ~~**`-ohm` → `-ohms`.**~~ **Done in the same commits**;
   `qcom,batt-id-pullup-ohms` is the only one left carrying a vendor prefix.

11. ~~**Two more invented WCD9335 property names, with an inverted default.**~~
    **Fixed 2026-07-31**, and not by renaming them: the codec was moved onto the
    shared `wcd-mbhc-v2`, so it now calls the family's own
    `wcd_dt_parse_mbhc_data()` and the invented properties were deleted from the
    driver, the binding and the board file. Details in
    [`TODO.md`](TODO.md#open-before-anything-is-submitted).

12. ~~**The rebase table's two audio rows are stale.**~~ **Re-measured
    2026-07-31** against fresh bases, all nine rows, against the regenerated
    thirteen-patch series: audio is now 11/12. Table above.

13. ~~**`submit/7.1.3/audio` still carries the private MBHC implementation.**~~
    **Regenerated 2026-07-31** as thirteen single-domain patches, the shared-MBHC
    change split three ways; `aw8898` is excluded because it is not in Linus'
    tree. Item 12 is now the only thing standing between this series and a
    rebase measurement. Details in
    [`TODO.md`](TODO.md#open-before-anything-is-submitted).

---

23. ~~**The jack is treated as 3-pole**~~ — **fixed 2026-07-31.** The codec moved
    onto the shared `wcd-mbhc-v2` with a legacy comparator backend, and a 4-pole
    headset and a 3-pole headphone now report differently
    (`SW_MICROPHONE_INSERT` only for the headset). **No TX gain control is
    exposed for the call path** is still open.

Items 34-40 all come from one reviewer pass over the audio **driver** commits on
2026-08-02 (`ca9aaa72`, `377269e4`, `254359e1`). **Nothing below is
implemented**, and each has a counter-argument that has to be settled first —
written out in [`TODO.md`](TODO.md#open-before-anything-is-submitted) item 15.
The pass also asked where the six codec properties are defined: they are in the
binding since 2026-07-30 (item 2 there); only the `wip` branch's discovery
ordering makes it look otherwise.

24. ~~**Streaming does not work end to end.**~~ **False, corrected 2026-08-01.**
    It streams: 15 240 960-byte frames, exactly 4032 x 3024 x 10 / 8, two
    consecutive frames differing, so it is live sensor data. The old finding was
    an artefact of asking for `RG10`, which this video node does not offer — the
    resulting `-EPIPE` from pipeline validation logs nothing and looks exactly
    like a broken driver. The correct format is **`pRAA`**. What is genuinely
    open is narrower: **nobody has checked the image is correct** (geometry,
    Bayer order, stride) against a known scene, and the link frequencies in the
    DT still disagree with the driver's mode tables. Details in
    [`docs/camera/README.md`](https://github.com/llg179org/fp3-pmaports/blob/main/docs/camera/README.md).
24c. ~~**The CSIPHY timer clock intermittently refuses to start** (`-EBUSY`,
    parked 2026-07-26).~~ **Fixed 2026-08-02**, and it was not a settle
    problem: `gcc-msm8953.c` placed `GPLL0_DIV2` at source select **2** for the
    three `csi*phytimer` RCGs, where every other camera mux in the file uses 4
    or 5. `ROOT_OFF` therefore never cleared and the only table entry derived
    from that source - 100 MHz, the one a 321 MHz link frequency picks - could
    never stream, while the 200/266 MHz GPLL0 entries always could. 9 of 9
    capture runs across two boots after the change, with nothing in dmesg.
    Carries a `Fixes:` tag and is upstream material. Detail in
    [`docs/camera/README.md`](https://github.com/llg179org/fp3-pmaports/blob/main/docs/camera/README.md#the-csiphy-timer-clock-and-why-the-camera-used-to-vanish).
24b. **Untested: the camera's exposure and gain controls.** The V4L2 controls
    exist on the sensor subdev; nothing has checked that writing them moves the
    image. Cheap to settle now that `focus-sweep.py` can hold one stream open -
    the same brightness statistic it already prints per frame is the measurement.

25. ~~**Parked: the PMI632 flash LED.**~~ **Works, 2026-08-03.** The parking
    reason was correct: the module reports subtype **`0x05`**, which
    `leds-qcom-flash.c` refuses outright, so enabling the node as it stood would
    have failed the probe. It is the three-channel block with two channels
    bonded out, so the driver takes a fourth branch with `max_channels = 2`;
    `CONFIG_LEDS_QCOM_FLASH` was not in the config either. ☠️ The module is on
    the **second** PMI632 USID (`0-03`), not the charger's. Confirmed three
    ways — registers programmed, USB input current separating over interleaved
    passes, and the rear camera measuring the lit scene — after the battery
    ammeter, which does not exist on this device, produced a confident false
    negative. Not carried over: the charger-side `FLASH_ACTIVE` handshake that
    downstream uses around a strobe. Detail in
    [`TODO.md`](TODO.md#parked-the-pmi632-camera-flash--it-works-2026-08-03).

26. ~~**The magnetometer is uncalibrated and its scale unverified**~~ — **both
    measured 2026-08-01.** Hard-iron `−0.63494 −0.69576 +0.71721` Gauss;
    soft-iron negligible (semi-axes within ±2%); and the scale is **correct** —
    the sphere's radius is 0.4865 G = 48.65 µT against an expected 48–50 µT for
    this latitude. The gap note said the two cannot be solved from each other,
    which is true one at a time and false for a full sphere, whose radius *is*
    the field strength. What is left is narrower: the driver exposes no
    `in_magn_*_calibbias`, so nothing can carry the offset, and it must not be
    hardcoded — it is per-unit and drifts.

27. ~~**The mount matrix is probably wrong**~~ — **fixed 2026-08-01**, and it was
    not merely wrong: the msm8996 value has **determinant −1**, so it was a
    reflection rather than a rotation and could not have suited any device. The
    new value is every one of those signs flipped. Measured from three
    orientations, and confirmed independently by the phone's own factory
    calibration, where the permutation between `/persist/sensors/accel_[xyz]`
    and registry keys 0–2 *is* this matrix.

28. ~~**Registry groups 20, 2691 and 3050 are zero-filled**, not real.~~
    **Corrected 2026-08-01 for group 20:** it is zero in this phone's own
    factory `sns.reg` as well, so `snsregd` serving zeros is serving the truth,
    not a stand-in. The factory calibrates the accelerometer, the proximity
    sensor and the ambient light sensor, and nothing else. **2691 and 3050 are
    still unmapped** and remain open.
28a. **The gyroscope and the magnetometer have no mount matrix at all** — only
    the accelerometer ever had one, and the magnetometer's does not follow from
    it, being a separate part.

32. ~~**The package now pins `debug-int/7.1.3`, not `integration/7.1.3`.**~~
    **Done and running.** The pin moved on 2026-07-30, and the package has been
    built and deployed from that branch many times since; what the phone runs
    carries the watchdog. The two rewrites this item was written about — the
    camera provenance and the debug split — are still only reachable through
    `archive/integration-7.1.3-pre-camera-provenance` and
    `archive/integration-7.1.3-pre-debug-split`, which is why those tags exist.
    ☠️ GitHub serves a source tarball only while the commit is reachable from some
    ref — check before trusting a pin:

    ```sh
    curl -sI -o /dev/null -w '%{http_code}\n' \
      "https://github.com/llg179org/linux/archive/<_commit>.tar.gz"   # 302, not 404
    ```

34. ~~**The padded-stride path works at the 1920x1080 sensor mode; the full
    readout is blocked by CMA, not by the GPU.**~~ **The full readout works,
    2026-08-12 — CMA was never on its path.** The stride half is done: camss
    grants a padded bytesperline on VFE 4.1 (checked with a direct
    VIDIOC_TRY_FMT), and libcamera's request now reaches the driver at all — it
    did not before, because the multiplanar path copies bytesperline only for
    the planes named in a count the upstream patch left at zero.

    **Re-measured 2026-08-08 on the deployed package (`linux-fp3-7.1.3-r48`,
    `#49-fp3`, with the r10 libcamera that carries the stride request), and the
    earlier "GPU faults" account did not hold up.** `cam` at the 1920x1080
    sensor mode (a 1280x960 request selects it) reports `Input 1920x1080 stride
    2560`, imports through EGL and **captures frames with no context fault** —
    the padded buffer is read by the GPU and comes back. What fails is the
    **full 4032x3024 readout** (a 1920x1080 or larger request selects it, the
    size cliff): `Input 4032x3024 stride 5120`, then
    `cma: __cma_alloc_frozen: reserved: alloc failed, req-size: 11907 pages`
    — ~48.8 MB contiguous — while CMA is fragmented to a largest run of ~30 MB.
    The dma-buf allocation fails *before* any buffer exists, so the GPU is
    never reached and there is no context fault to see. MemAvailable was
    2.5 GB throughout, so this is CMA contiguity, not memory pressure.

    That measurement stood, and the fix proposed from it — raising
    `CONFIG_CMA_SIZE_MBYTES` from 32 to 96 — **would not have worked, because
    the capture path does not allocate from CMA at all.** Re-measured 2026-08-12
    before spending the build cycle it asked for:

    | | |
    |---|---|
    | full readout | `cam -c1 -C15 -s width=4032,height=3024` captures **every frame**, `Input 4032x3024-RGGB-10-CSI2P stride 5120`, `bytesused 48771072` |
    | CMA during the capture | `CmaFree` sampled four times a second: **30304 kB throughout**, not one kilobyte moved |
    | CMA failures | none in `dmesg` |
    | camss | behind an IOMMU (`1b00020.camss` → `iommu_groups/1`), so the sensor readout never needs contiguous pages |

    `CmaFree` is the decisive one, and it settles the question in both
    directions: 30 MB free cannot satisfy a 49 MB request, so had the
    allocation come from CMA it would have failed — and had it come from CMA
    and succeeded, `CmaFree` would have dropped by ~48 MB. It does neither.

    Note also that 11907 pages is **exactly** 48 771 072 bytes, which is the
    `bytesused` of the ABGR8888 **output** frame, not the raw sensor readout.
    So the failing allocation was always the output buffer, and what changed is
    where that buffer comes from: `/dev/dma_heap/` offers only `default_cma_region`
    and `reserved`, both CMA-backed, but `/dev/udmabuf` exists and libcamera is
    now **r12** where the note was written against r10. The likely reason is
    therefore that libcamera's allocator now falls back to udmabuf instead of
    the CMA heap — likely, not measured: an A/B against r10 would settle it, and
    nothing depends on the answer while full resolution works.

    So the item is **not a blocker**: at the app's capped ≤1912x1080 size
    (item 33) the camera works, and the full readout works too. What remains
    open is only the *cost* — the full readout runs at about 5 fps, which is
    fine for a photo and not for a viewfinder.
