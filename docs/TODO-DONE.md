# Closed items

> ⚠️ **AI-generated.** These pages, and the code and measurements they describe,
> were written by Claude working under the direction of Lajosházi, László
> Gergely, who reviewed every change and made or reviewed every measurement
> they rest on.

Sections and numbered items moved out of [`TODO.md`](TODO.md) once they were
answered, fixed or disproved. (Until 2026-08-24 there was a second source, the
by-branch `FP3-TODO.md`, since folded into `TODO.md`; the `# From FP3-TODO.md`
group below is where its closed items were archived.) Everything is kept verbatim
as it stood when closed — headings, numbering and strikethrough included — so
cross-references by number or title still resolve. The numbering gaps left behind
in `TODO.md` are deliberate for the same reason: nothing was renumbered.

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

### Corrected the same day: it is not permanently dead

Everything above was measured on a boot that had been up about three hours. On a
**fresh boot** the amplifier is healthy: `RX Volume` reads and writes at 255, the
1 s silent playback draws no clock complaint at all, and the speaker is properly
loud — the same 1 kHz tone that moved the handset mic's peak to 95 before the
reboot moved it to **1466** (RMS 765.7 against 3.2 in silence) after it. The
`24-speaker-amp` check passed in the battery on that boot: 28 ok, 0 failed.

So the fault is a **transition during a session**, not a constant, and the open
question is what causes it. The 2026-07-31 measurement said the same thing in
other words — a cold boot heals it until the first failed playback attempt —
and the driver's error path (`aw8898_set_power(false)` after the PLL wait times
out) is the mechanism that would make one failure permanent for the rest of the
boot.

☠️ **What I wrote this morning — "the loudspeaker is silent", "this check has
never been seen to PASS" — was a state of one boot stated as a property of the
phone.** Everything measured was real; the generalisation was not, and it took
one reboot to break it. The corrected claims are in the check headers.

### And the acoustic check is now failing for a third reason

On the healthy boot `21-audio-acoustic` still fails, but the numbers changed
completely: alsabat reports **peak 6000.00 Hz at 22.21 dB, total 35.3 dB in a
5 Hz band** — a real, strong acoustic signal, at the sixth harmonic of the 1 kHz
it played. That is distortion, not silence.

`23-audio-slimbus` passes on exactly this shape, because it judges whether the
target frequency was detected rather than trusting alsabat's exit code (it
records `rc=21 from sidebands above the fundamental`). `21-audio-acoustic` still
requires `rc == 0`, so it calls a working speaker broken. Open: judge it the way
23 does, and separately find out why 1 kHz comes back with its sixth harmonic
dominant — the amp runs at 0 dB (`RX Volume` 255) by default, so clipping is the
first thing to rule out.

### The transition reproduced on one boot, and what it costs to measure it

Measured 2026-08-16, evening, with the jack plugged in. The whole day's
uncertainty came from comparing states across boots; a before/after pair on a
**single** boot settles it. Both halves used the same validated instrument, the
mixer round-trip in `24-speaker-amp`:

```sh
fp3-selftest --only speaker-amp                     # before
fp3-selftest --acoustic --only audio-acoustic,audio-headset
fp3-selftest --only speaker-amp                     # after
```

| | `RX Volume` | |
|---|---|---|
| before the acoustic run | readable and writable at **255** | the amp answers |
| after the acoustic run | reads **0**, writing it back fails | gone for the rest of the boot |

So an acoustic run is what flips it, the flip is one-way, and only a reboot
restores it. A rebind does not: unbinding warns three times at
`_regulator_put+0x5c` and the re-probe then fails with `Chip ID check failed,
-EIO`, so the driver cannot talk to the chip it just reset either.

The `0` is a **failed read**, not a written value: `aw8898_mute()` uses
`PWMCTRL`'s hard-mute bit, not the volume register, so nothing in the driver
writes 0 to `HAGCCFG7`. `amixer` prints 0 because the read returned `-EIO`, and
the kernel logs `ASoC error (-5)` from `soc_component_read_no_lock()` at the
same moment.

Still open: which operation inside the acoustic run does it. The suspect is the
end of the stream — the only surviving `aw8898_set_power(aw8898, false)` is on
`SND_SOC_DAPM_POST_PMD`, and a chip in power-down cannot be woken by a write
that has to cross the bus it just stopped answering. The startup path no longer
powers down on a clock miss (it warns `playing anyway` and returns 0), so that
earlier one-way door is already closed and is not this one.

☠️ **Two instruments lied for most of an hour, and both were unvalidated.**

- A hand-rolled raw-I²C read through `/dev/i2c-N` reported the chip NAKing while
  the driver's own `regmap_read_poll_timeout()` was succeeding in the same
  second. It had never once been shown returning a chip ID.
- Reading `/sys/kernel/debug/regmap/<dev>/registers` with `cache_bypass=1`
  reported every register as `XXXX` on a chip that was answering fine. That dump
  walks all 256 addresses live, and this chip implements a handful, so a
  wholesale `XXXX` is the normal reading for a *healthy* part — it says nothing
  about whether the device is on the bus.

The mixer round-trip was the only path with a known positive behind it, and it
is the one that gave the answer. Same rule as everywhere else in this file: a
check that has never been seen succeeding cannot be read as a failure.

☠️ And the i2c bus number moved again mid-investigation — `4-0034` on one boot,
`2-0034` on the next, `4-0034` on the one after. Two scripts written that
evening hardcoded bus 4 and spent several minutes measuring an empty address on
a boot that had it on bus 2. Resolve it from the device `name`, the way
`24-speaker-amp` does.

### The headset mic hears it too, so the capture path is not the problem

Measured 2026-08-16 with a headset plugged in, on a fresh boot. Both acoustic
checks fail with the same shape rather than with silence: `21-audio-acoustic`
(handset DMIC0) reports peaks at 5500 Hz / 15.7 dB and 6000 Hz / 22.0 dB, and
`22-audio-headset` (analogue headset mic) reports 5500 Hz / 20.5 dB and
6000 Hz / 21.7 dB — for a 1 kHz tone whose fundamental is not the peak in
either. Two independent microphones on two different paths agree, so neither
microphone is at fault and the headset ADC path is alive; what reaches them is a
badly distorted version of what was played. The open question is the amplifier's
output, not the capture side.

☠️ Check order matters here: `21` and `22` sort before `24`, so a battery that
selects all three kills the amplifier in the acoustic checks and then reports
the I²C failure from `24` — which reads as three failures with one cause. To
learn the amp's state *before* an acoustic run, ask for it on its own first.

### Retracting the retraction: the cache was the liar, and here is why

Measured 2026-08-16, later the same evening. The two probes retracted above were
right, and the mixer round-trip that overruled them was wrong. Three probes run
within a second of each other on a fresh boot, at 28.8 s uptime:

| probe | says |
|---|---|
| raw chip-ID read through `/dev/i2c-N` | NAK |
| `cache_bypass=1` regmap dump | `00: XXXX` |
| **a real write** — `cset 'RX Volume' 254` | `-EIO`, refused |
| a `cget` of the same control | `255`, cheerfully |

The `cget` is the odd one out because it never reaches the chip. The driver's
`regmap_config` is:

```c
static const struct regmap_config aw8898_regmap = {
	.reg_bits = 8,
	.val_bits = 16,
	.max_register = AW8898_MAX_REGISTER,
	.cache_type = REGCACHE_MAPLE,
};
```

`cache_type` with **no `volatile_reg` callback at all**, so every register is
cacheable. Three consequences, in rising order of seriousness:

1. **A read of any register can be served from the cache**, which is why `RX
   Volume` reads 255 on an amplifier that is not on the bus.
2. **A write of the value already cached is skipped entirely** — regmap elides
   it — so a "write it back to itself" probe can succeed without a single bus
   transaction. That was the flaw in `24-speaker-amp`'s first I²C arm, now
   fixed: it moves the control by one step (0.5 dB) and puts it back, which
   forces the transaction.
3. **`SYSST` (0x01) is cacheable too**, and that is the register
   `aw8898_prepare()` polls for the PLL-lock bit. After the first read of the
   boot, `regmap_read_poll_timeout()` is polling a cached word that cannot
   change, so a PLL that locks late can never be observed to lock. That is a
   candidate root cause for the entire "the PLL never locks" finding of
   2026-07-31 - not yet confirmed by a patched kernel, and stated here as a
   hypothesis with a source basis, not as a measurement.

The fix is a `volatile_reg` marking at least the status registers volatile.
Kernel change, `audio` category.

What this does **not** explain is why a real write is refused at all. That is
still open, and the earlier claim that "the acoustic run flips it" rests on a
before/after pair whose "before" was a cache read - so it is withdrawn too. Two
things survive the withdrawal, because both used a real write: an `RX Volume`
write is refused on every boot measured tonight, whether or not a stream is
running, and it is refused equally at 254 and at 231, so the level is not the
variable.

☠️ The lesson is one level up from "validate your probe". All three of the
evening's probes were *validated against each other* and agreed - and the
agreement was worthless, because two of them shared a cache. **Two instruments
that share a layer are one instrument.** The write was the only probe that had
to touch the wire, and it was the one worth trusting.

### The `volatile_reg` fix is in, and it turned -110 into -5

*2026-08-16 evening, `linux-fp3-7.1.3-r58` (`#59-fp3`,
`_commit=5db94248edcf39f7b0d1a0aabd77c09173d78813`). The kernel change is
`ASoC: aw8898: mark SYSST volatile so the PLL poll can see it change` on
`wip/7.1.3/audio`, cherry-picked to `integration/7.1.3` and `debug-int/7.1.3`.*

The patch does what it was written to do, and the proof is in the error code.
Before it, `.prepare` logged

```
aw8898 4-0034: iis clock not detected (-110), playing anyway
```

`-110` is `-ETIMEDOUT`: the poll ran its full second without the condition ever
becoming true — which is exactly what a loop spinning on one cached sample
looks like. On the first boot of r58 the same line reads

```
aw8898 4-0034: iis clock not detected (-5), playing anyway
```

`-5` is `-EIO`: `regmap_read_poll_timeout()` now performs a real bus read on
every iteration, and that read **fails**. The timing says the same thing
independently — the eleven lines this boot are spread over 24.81 s to 25.43 s,
a few tens of milliseconds apart, where a one-second timeout would have put
them a second apart.

So the PLL hypothesis is settled in a way that was not on the list of expected
answers. It was never "the PLL fails to lock"; the driver could not read the
register that would have told it either way. **What is actually wrong is one
layer lower: the amplifier does not answer on I²C at all.**

☠️ **And this cold boot had a dead amplifier from the start**, which the
2026-08-16 morning boot did not. `fp3-selftest --only speaker-amp` fails both
arms minutes after boot: the `RX Volume` write (255 → 254) is refused, and the
clock complaint is there. Yesterday's cold boot passed both. So "cold boot
heals it" is not reliable either — the state the phone comes up in varies, and
that variation is now the thing to chase.

What that makes the next question. Not the PLL, and not the poll: **why does a
register access to 0x34 return -EIO on a bus whose controller probed cleanly?**
The driver's own probe succeeded on this boot — there is no `Chip ID check
failed` line, so the very first `regmap_read` of `AW8898_ID` went through — and
the failures start only at 24.8 s, when DAPM first powers the widget. Between
those two points something makes the chip stop answering, and the candidates
worth separating are its supplies, its reset GPIO, and `SND_SOC_DAPM_POST_PMD`
having powered it down earlier in the boot than anyone assumed.

### Narrowed the same evening: it is dead before anything plays

Two more boots of r58, and they move the fault well away from the stream:

| boot | first `iis clock` line | amp answers? |
|---|---|---|
| 18:43 | 24.81 s (eleven of them) | no — both arms of `24-speaker-amp` fail |
| 18:52 | **none at all** until the check's own `aplay` | no — the `RX Volume` write fails **before** that `aplay` |

The second boot is the informative one. Nothing had played, the kernel had said
nothing about the amplifier, and the very first thing anyone asked of it — a
one-step `RX Volume` write — was refused. A raw I²C transaction to `0x34`,
independent of the driver and its cache, **NAKs**. So this is not the stream, not
DAPM's teardown of a stream, and not a regmap artefact: by the time userspace can
ask, the chip is not on the bus.

Yet the driver's own probe succeeded. There is no `Chip ID check failed` line on
either boot, which means the first `regmap_read` of `AW8898_ID` — issued straight
after `aw8898_reset()` toggles the reset GPIO — went through. The chip therefore
answers at probe and stops answering somewhere between probe and userspace, with
no audio anywhere in that window.

Checked and cleared as causes:

* **the supplies.** All three consumers are enabled: `4-0034-vdd` off `vph_pwr`,
  `4-0034-dvdd` and `4-0034-vddio` off `pm8953_l5` at 1.8 V.
* **the reset polarity**, which looked like a promising discrepancy and is not.
  The vendor tree declares `reset-gpio = <&tlmm 21 0>` — flags `0`, active-high —
  where ours declares `GPIO_ACTIVE_LOW`. But the vendor driver uses the legacy
  API and ignores the flag: `aw8898_hw_reset()` drives the line **raw low, then
  raw high**. Ours asks for logical 1 then 0 through `gpiod_`, and with
  `GPIO_ACTIVE_LOW` that is raw low then raw high — the same waveform. The two
  descriptions disagree and the two behaviours agree, which is the only thing
  that matters here.

**The hypothesis worth testing next**, and the one experiment that decides it:
`SND_SOC_DAPM_POST_PMD` calls `aw8898_set_power(aw8898, false)`, which writes
`SYSCTRL.PW = PDN`. DAPM powers widgets down when the card's widgets are first
brought up, not only at the end of a stream — so that write plausibly lands
during card registration, long before anything plays. If the chip stops
acknowledging its address in PDN, then the first power-down is permanent: every
later access fails, `aw8898_set_power(true)` included, because it is itself an
I²C write. That fits every observation on both boots.

☠️ The one thing it does not fit is the rebind, and that has to be explained
before the hypothesis is believed: unbinding and re-probing re-runs
`aw8898_reset()`, and a reset should bring any chip back — but it fails at
`Chip ID check failed, -EIO`. Either PDN survives the reset pulse, or the reset
line is not reaching the chip. Deciding between those two is what the experiment
has to do, so it needs to be run with the reset toggled by hand as well.

### The POST_PMD hypothesis is dead, and `aw8898_cfg.bin` is not on the phone

*Measured on the throwaway branch `wip/7.1.3/audio-debug` (`afad60700184`),
deployed as a module hot-swap over r58 and reverted afterwards.*

The experiment answered cleanly and in the negative:

```
[   15.909845] aw8898 4-0034: component_probe: live chip id read -> 0 (0x1702)
[   24.000970] aw8898 4-0034: iis clock not detected (-5), playing anyway
```

and `POST_PMD` was logged **zero** times on that boot. So the widget was never
powered down, and the chip still died — the power-down write is not what takes
it off the bus. The first line also does what it was added for: a
**cache-bypassed** read at 15.91 s returns the real chip ID, `0x1702`, so the
part is alive on the bus when the card binds the component, and dead eight
seconds later.

That narrows the window to what happens between card bind and the first stream,
and there is exactly one substantial thing in it — `SND_SOC_DAPM_PRE_PMU` calls
`aw8898_cold_start()`, which asks for the amplifier's configuration blob and,
on the callback, writes **arbitrary register addresses out of the file**:

```c
regmap_write(aw8898->regmap, addr, val);	/* addr comes from the blob */
```

☠️ **And the blob is not installed.** `/lib/firmware/aw8898_cfg.bin` does not
exist on this device. So `cfg_loaded` never becomes true, every widget power-up
re-issues the request, and — much more to the point — **the amplifier has never
been given its initialisation registers at all.** It is running on whatever the
part powers up with, which is a perfectly good explanation for an I²S interface
that never comes alive, and a candidate one for a chip that stops answering.

Two things follow, in this order, and neither is a kernel patch:

1. **Find out what the blob is and where it comes from.** The vendor tree
   (`hadk22/kernel/fairphone/sdm632`, `sound/soc/codecs/aw/aw8898.c`) loads the
   same file, so the vendor image should carry it — that is the thing to look
   for, along with its licence, before anything is copied anywhere.
2. **Only then decide what the driver should do without one.** Right now a
   missing file is silent past a single `dev_err` and the part is left
   uninitialised; whether that should be a probe failure, a warning, or a set of
   built-in defaults is a real question for the upstream series, not for us
   alone.

☠️ Note what this costs the earlier write-ups: "the amplifier stops answering
mid-session" was measured, and stays measured, but every explanation offered for
it so far was reasoning about a chip that had never been configured. Re-measure
the variability once the blob is in place; the boot-to-boot difference may
simply be a race with a firmware request that can never succeed.

### The blob was on the phone all along, and installing it changed nothing

Both halves of item 1 above are now answered, and the answer to the second half
made the first half cost nothing.

**Where it comes from.** `aw8898_cfg.bin` is a Fairphone stock vendor file. It
is in the extracted vendor tree at
`hadk22/vendor/fairphone/FP3/proprietary/vendor/firmware/aw8898_cfg.bin`, from a
`FP3-6.A.040.2-gms` stock build — and, decisively, it is **also on this phone's
own `vendor` partition, on both slots**, byte-identical:

```sh
mount -o ro /dev/disk/by-partlabel/vendor_a /mnt/vend
md5sum /mnt/vend/firmware/aw8898_cfg.bin	# bbcda305cedb3a26f5c29b48ae80b3ec
```

so the file never has to be redistributed to reach `/lib/firmware`: it is copied
from the device's own stock partition to the device's own rootfs.

☠️ **The licence question has a tempting wrong answer.** The AOSP build tree
carries a `.meta_lic` next to the blob reading
`license_kinds: "SPDX-license-identifier-Apache-2.0"`. That is soong's *default*
for a `raw` prebuilt with no licence of its own, not a grant from Awinic or
Fairphone — the same file names `build/soong/licenses/LICENSE` as its licence
text, which is the build system's, not the blob's. Treat it as proprietary
vendor content with no stated licence: fine to use on the device it shipped
with, not something to commit to a public repository.

**It is 96 bytes of register writes**, 24 entries of `(le16 addr, le16 val)`, and
the mainline driver's parser matches the vendor's byte-for-byte — vendor
`aw8898_container_update()` does `data[i+1]<<8 | data[i+0]` for the address and
the same for the value, which is exactly `struct { __le16 addr; __le16 val; }`.
The last two entries are `0x04 = 0x0044` (SYSCTRL) and `0x08 = 0x0ea0`
(PWMCTRL), i.e. a plausible real init tail.

**And with it installed, the amplifier still dies.** Measured on the boot after
installing it: the cached register dump shows `04: 0044` and `05: 0c08`, which
are the blob's own values, so the file loaded and the driver ran its writes;
every live (cache-bypassed) read still returns `XXXX`.

☠️ **The cached values are not evidence that the writes reached the chip.**
`_regmap_write()` updates the cache *before* it touches the bus and returns the
bus error afterwards, so a failed write leaves the cache looking exactly like a
successful one. Two instruments that share a layer are one instrument.

### The death window, measured to 220 ms

A boot-armed poller (`/usr/local/bin/aw-poll.sh`, a `Type=simple` unit ordered
`After=sysinit.target`) reads `AW8898_ID` through `cache_bypass` every 200 ms
from the moment the driver's regmap appears. One boot, no playback of ours:

```
regmap appeared at 15.12
15.23 00: 1702      <- alive
...                    (44 consecutive samples, 9 seconds)
24.19 00: 1702      <- last live sample
24.41 00: XXXX      <- gone
```

and the first `iis clock not detected (-5)` follows at 24.45. Filtering the
charger's own log spam away, **there is no other kernel event in the window** —
no regulator change, no SSR, no pinctrl message, nothing but the first audio
stream starting.

So the chip is alive for nine uninterrupted seconds and dies within ~220 ms of
the first stream. That also clears the poller itself of suspicion: 44 bypassed
reads in a row did no harm.

**Two hypotheses died cheaply on the way:**

- *The pinmux collides.* It does not. The amplifier's I²C is `gpio22`/`gpio23`
  (`i2c_6_default`), reset is `gpio21`, its IRQ `gpio20`, and QUIN MI2S is
  `gpio88`/`91`/`92`/`93`. No pin is in both groups.
- *A reset revives it.* It does not. A full unbind/rebind — which re-runs probe,
  including the reset-GPIO pulse — fails at the very first step:
  `Failed to read register AW8898_ID: -5`, `Chip ID check failed`,
  `probe with driver aw8898 failed with error -5`. Once it is gone it stays gone
  until a reboot.

Next instrument, because three indirect exclusions have not separated the cases:
a throwaway driver that does a cache-bypassed ID read at *every* step the stream
makes — `hw_params` around each of its two `I2SCTRL` read-modify-writes,
`.prepare` before the PLL poll, the DAPM power-up before and after
`aw8898_set_power()`, the config write before and after, and the mute — so the
death can be attributed to one register access instead of to "the stream".

### The death has nothing to do with audio, and the kernel never says a word

Every explanation offered above rested on the death coinciding with the first
audio stream. **It does not.** The control that settles it: boot with no audio
server at all (pulseaudio's autospawn off and its xdg autostart masked,
pipewire and wireplumber masked), and with `systemctl set-default
multi-user.target` so there is no graphical session either. On that boot there
is not a single `aw8898` line in `dmesg` — no stream was ever prepared — and the
amplifier still stops answering at 23.87 s.

☠️ The earlier reading was a coincidence of timing: userspace comes up at about
the same second on every boot, so "it dies when the first stream starts" and "it
dies about 25 s in" are indistinguishable until you remove the stream.

**What has been excluded, each by its own A/B boot** (all with the death still
occurring):

| suspect | how it was excluded |
|---|---|
| the audio stream | no audio server, no session, no `aw8898` log line — still dies |
| WLAN (`iris` shares `pm8953_l5`) | `blacklist wcn36xx qcom_wcnss_pil wcnss_ctrl` — still dies |
| our own `spkwatch` diagnostic | `systemctl disable --now spkwatch` — still dies |
| our own liveness poller | poller disabled entirely; a single first read at 60 s already reads `XXXX` |
| ModemManager bringing the modem up | `systemctl disable --now ModemManager` — still dies |
| the i2c controller runtime-suspending | `power/control = on` pinned from boot — still dies |
| the i2c pinmux going to its sleep state | `pin 22/23: device 7af6000.i2c function blsp_i2c6` while dead |
| the reset line being asserted | `gpio21: out high` (`GPIO_ACTIVE_LOW`, so de-asserted) while dead |
| the supplies dropping out | `vdd=1 vddio=1 dvdd=1` in the driver's own sample, taken *at* the transition |

**The instrument that settles the layer.** A driver-side `delayed_work` samples
`AW8898_ID` through `regcache_cache_bypass` every 250 ms and logs the moment the
error code changes, so the death lands on the kernel's own timeline next to
every other message:

```
[   17.047332] aw8898 4-0034: LIVE[cfg_write-exit]: err=0 id=0x1702
[   24.993011] aw8898 4-0034: WATCH: id read 0 -> -5 (id=0xffff0000) reset=0 vdd=1 vddio=1 dvdd=1
```

and **there is nothing else in `dmesg` between 23.5 s and 26.5 s** — not one
line, charger spam included.

**It is the chip, not the bus.** Probing the same adapter through `/dev/i2c-N`:
a nonexistent address (`0x20`, `0x35`) returns `EIO`, which is what this
controller reports for a NAK, so `EIO` from the amplifier means the part is not
acknowledging rather than that the bus is broken. A full `0x03`–`0x77` scan with
the chip dead answers **nothing at all**.

**The blob does load and every write succeeds.** With `aw8898_cfg.bin` in place
the log shows `EXP: loaded aw8898_cfg.bin - size: 96` and all 24 writes
returning `0`, ending `reg 0x0004 = 0x0044`, `reg 0x0008 = 0xa00e`. So the
amplifier *is* initialised now — the missing blob was a real defect, and fixing
it did not fix the silence.

**Death times measured so far** (uptime seconds, various boots and
configurations): 23.92, 24.41, 24.55, 24.99, 25.04, 25.25, 25.51 — and one
outlier at 34.16. Tightly clustered around 25 s and anchored to boot, not to any
event we have been able to name.

Open lead being tested next: the kernel's own late regulator cleanup
(`regulator_init_complete_work_function`, 30 s after `late_initcall_sync`) or
another boot-anchored timer turning off a rail the amplifier needs but our
device tree does not describe — which would explain a chip that is powered
according to the framework, out of reset, and electrically absent.

#### 2026-08-17: four arms, one oracle, and `sync_state()` ruled out

All of this was measured with a new instrument that talks to the chip **straight
on the i2c bus** (`/dev/i2c-N` with `I2C_SLAVE_FORCE`, bus resolved from the
`*-0034` device name because the adapter number moves between boots). That
matters: the driver's `regmap_config` caches and declares no `volatile_reg`, so
anything read through the driver can report a plausible value for a chip that is
not on the bus at all. The tool was first pointed at an already-dead chip and
returned 21 failures out of 21 reads — a verifier that has not been shown failing
proves nothing, so that came first.

It ran from a `Type=simple` unit ordered `After=sysinit.target`, because the
death is earlier than sshd and cannot be caught from the host. Both instruments
are in [`docs/audio/tools/`](audio/tools/): `awpoke.py` for one-shot reads and writes,
`awwatch.py` for the boot-window A/B (`control` / `pdn` / `vendor` / `cp` arms).

**The death is invariant.** Four boots, four arms:

| arm | what it wrote at ~15 s | last good read | died |
|---|---|---|---|
| control | nothing | 23.90 | 24.16 |
| pdn | `SYSCTRL = 0x0007` (as found) | 24.07 | 24.32 |
| vendor | `SYSCTRL = 0x0045` — accepted, read back | 24.12 | 24.37 |
| control, `multi-user.target`, no session | nothing | 24.32 | 24.58 |

So it is not the chip's register state, and it is not the graphical session or
the sound server: the last row had **no `aw8898` line in dmesg at all** and died
on schedule. ⚠️ In an earlier boot the driver's `iis clock not detected (-5)`
messages started at 24.46 s, a fifth of a second *after* the chip had already
stopped answering — those messages are a consequence of the session opening the
sink into a dead chip, not the cause. The window is ±0.3 s across every boot,
which is the signature of a kernel timer rather than of anything userspace does.

**`sync_state()` is ruled out.** The `syncstate-snap.sh` sampler shows **no
`state_synced` flag changing anywhere** — not across the death window, not across
the whole run (14.9 s → 84.5 s). Exactly one device is still unsynced,
`soc@0/1800000.clock-controller`, and it is still unsynced at the end, so its
callback has not run at all.

☠️ The first run of that sampler was worthless and looked clean: its three-level
glob under `/sys/devices/platform` reached **13 of the 39** `state_synced` files
and none of the i2c devices, so it could not have seen the amplifier's own
supplier sync even if that had been the cause. The script now walks the tree with
`find`; the verdict above is the run with 39/39 coverage.

**The Ubuntu Touch oracle, read the same night.** On the vendor 4.9 kernel the
amplifier sits at `6-0034` and **answers every register at 9 minutes of uptime**
— same silicon, so the death is ours, not a property of the part. Two things came
out of the comparison:

* **The vendor device tree gives the aw8898 no supply at all.** Its probe reports
  only `reset gpio provided ok` and `irq gpio provided ok`, and no regulator in
  `regulator_summary` lists it as a consumer. So the mainline `l5` choice is our
  invention, and the `l10` that drifts 2850→2800 mV is consumerless on the oracle
  too. Both directions of the earlier plan are answered: the rail we are looking
  for is not described on either side, which points at an always-on rail or an
  external switch rather than at a PMIC regulator the kernel manages.
* The vendor idles at `SYSCTRL = 0x0045` (charge pump active, I2S enabled) where
  we idle at `0x0007` (both powered down). Writing the vendor's value changed
  nothing — see the table — so this is a difference, not the lever.

Vendor register semantics confirmed from
`hadk22/kernel/fairphone/sdm632/sound/soc/codecs/aw/aw8898_reg.h`: `SYSCTRL`
bit 0 is `PW_PDN` (1 = powered down), which is the polarity our driver already
uses. The golden trace is `docs/audio/` material; the vendor blob stays out of
the repo.

What is left, in order: something un-logged in the kernel at ~24 s takes the
chip's power or reset away. The reset line and the pinmux were excluded earlier
with instruments that read through the driver's cache, so those exclusions are
worth re-running with the bus-direct tool before looking further.

## ~~The phone was stuck at a hang and needed a button press~~ — recovered 2026-08-17

**Resolved.** The way back in was not any of the host-side attempts below: it was
the **UBports recovery**, reached with a button press, whose adb shell can mount
the pmOS filesystems directly. `system_b` (`mmcblk0p31`) carries an embedded
msdos table — `/boot` at offset 1048576, root at 511705088 — so
`losetup -o <offset>` plus `mount` gives read-write access to `extlinux.conf`
without booting pmOS at all. That is worth remembering as the general recovery:
**anything on disk can be fixed from the recovery, no matter how badly the
default boot entry is broken.** The clean `append` line was restored from
`extlinux.conf.bak-aw`, `panic=10` was added to both labels (neither had it), and
`fp3-selftest --only boot-fallback` is green. Full battery afterwards: 29 ok,
1 failed, 3 skipped — the one failure being the open `24-speaker-amp` case.

☠️ The recovery reboot leaves **slot `a`** active (the Ubuntu Touch side), so
`fastboot set_active b` is needed before pmOS will boot again.

The original state, kept because the attempts below are the useful part:

**State, 2026-08-16 ~21:00.** The device does not boot and does not enumerate on
USB at all. The last good boot was 20:54:15; the reboot at 20:57:23 never came
back, and 25 minutes of polling saw nothing on `lsusb`.

**What did it.** I added `fw_devlink=off` to the kernel command line, in
`/boot/extlinux/extlinux.conf`, to test whether a `sync_state()` callback was
turning off a rail the amplifier needs. It hangs before the USB gadget comes up,
so there is no console, no ssh and no fastboot — and the parameter is on disk, so
every reboot repeats it. The watchdog does not save it either, which places the
hang before the watchdog driver probes.

☠️ **The rule this broke is already written down**: *a kernel experiment must
never block boot*. A command-line change is exactly that class of change, and I
made it with no armed fallback — on a device whose only two channels (ssh over
USB and ssh over WiFi) both need userspace to be running. The cost is not the
experiment, which was a fair one, but that it was staged in the one place that
cannot be undone from the outside.

**Recovery, needs a hand on the phone:**

1. Hold **power** for ~15 s to force it off.
2. Hold **volume up** while powering on to reach the lk2nd boot menu, and pick
   the second entry (`postmarketOS-fallback`) — its `append` line was never
   touched and still has the clean command line.

> ☠️ **Later correction (2026-08-23, measured by the user):** the button
> mapping recorded in step 2 is inverted for this device — **volume-UP + power
> reaches EDL, volume-DOWN + power starts fastboot**, and the lk2nd menu is not
> usable blind because the screen stays black. The reliable recovery on this
> phone is fastboot → `set_active a` (boot Ubuntu Touch) → mount `system_b`'s
> embedded `/boot` with `losetup -o 1048576 /dev/mmcblk0p31` → edit
> `extlinux.conf` → `set_active b`. See the ✅ RECOVERED block in `TODO.md`.
3. Once up, undo the change; the untouched original is already saved next to it:

```sh
sudo cp /boot/extlinux/extlinux.conf.bak-aw /boot/extlinux/extlinux.conf
grep append /boot/extlinux/extlinux.conf	# no fw_devlink=off, no regulator_ignore_unused
```

**What was tried from the host, 2026-08-16 23:00–00:00, and what it settled.**
The phone reached fastboot (ABL, `version-bootloader 6.A.039`, `unlocked: yes`,
`secure: no`), which made it worth asking whether the hang could be undone
without a hand on the phone at all. It cannot, and the attempts are worth
recording because each one looked promising:

| attempt | result |
|---|---|
| `fastboot flash boot_b <our boot image>`, then reboot | flash OKAY, phone returns to fastboot, `slot-retry-count:b` still **6** — never attempted, so the image is rejected by validation |
| same, with the boot header's `id` (SHA1) field filled in | same rejection; the empty `id` was not the difference |
| `fastboot boot` with the gzip `vmlinuz` + appended dtb | `FAILED (remote: 'dtb not found')` |
| `fastboot boot` with the raw `Image` + appended dtb | `FAILED (remote: 'unknown reason')` — so the appended dtb is only found on an uncompressed kernel |
| same, with the ramdisk moved to `0x82000000` (the 28 MB kernel at `0x80008000` overlapped `0x81000000`) | unchanged: `unknown reason` |
| **`fastboot boot lk2nd.img`** — the image that boots perfectly when flashed | `FAILED (remote: 'unknown reason')` |

The last row is the one that matters: **`fastboot boot` fails identically for a
known-good image**, so it is broken on this bootloader for every input, and the
whole dtb / `id` / load-address investigation above was chasing a message that
was never about the image. The lesson is now rule 22 in `fp3-kernel-test`, and
the procedure lives in [`../deploy/README.md`](deploy/README.md) under *If the
phone does not boot at all*. `lk2nd.img` was flashed back to `boot_b` afterwards,
so the normal boot chain is intact and the button press is all that is missing.

☠️ The fastboot USB link freezes if a command is interrupted (an outer `timeout`
firing mid-transfer is enough) and every later command then hangs; a
`USBDEVFS_RESET` on the device node clears it immediately.

**Also left on the device, all deliberate and all reversible from a shell:**

| change | undo |
|---|---|
| `graphical.target` → `multi-user.target` | `systemctl set-default graphical.target` |
| pulseaudio autospawn off, xdg autostart masked | `sed -i 's/^autospawn = no/; autospawn = yes/' /etc/pulse/client.conf`; `rm ~/.config/systemd/user/app-pulseaudio@autostart.service` |
| pipewire/wireplumber masked | `systemctl --user unmask pipewire.service pipewire.socket wireplumber.service` |
| WLAN blacklisted | `rm /etc/modprobe.d/zz-fp3-wlan-off.conf` |
| `spkwatch`, `ModemManager`, `aw-poll` disabled | `systemctl enable --now spkwatch ModemManager` |
| `regsnap.service` (per-second regulator snapshots) | `systemctl disable --now regsnap` |
| the instrumented `snd-soc-aw8898.ko` | `cp /root/aw8898.ko.r58 /lib/modules/$(uname -r)/kernel/sound/soc/codecs/snd-soc-aw8898.ko && depmod -a` |
| `/lib/firmware/aw8898_cfg.bin` | **keep it** — it is stock content from the phone's own vendor partition and it is what the driver has always been asking for |

The experiment kernel is preserved on the fork as `wip/7.1.3/audio-debug`, tagged
`archive/wip-7.1.3-audio-debug-watch`; nothing on any shipping branch changed.

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
## `apcs-cpu0-pll` fails to lock, and it took the phone down — ✅ CLOSED 2026-08-22

**Resolved by the v2 PLL fix (r65, `#66-fp3`).** Root cause measured: sugov
changes the rate while the owning cluster is in power collapse and the SPM gates
the PLL (A/B: power collapse off → 0 warnings). The v1 fix (per-CPU `dev_pm_qos`
from the clk notifier) deadlocked ABBA against the GPU-devfreq QoS notifier on
4/4 boots; the v2 uses a global `cpu_latency_qos` request (no notifier chain on
`cpu_latency_constraints`, so safe under `clk_prepare_lock`) plus an
`smp_call_function_any()` kick. Validation: 27 720 frequency transitions +
24 916 power-collapse entries under burst load, **0 failures** (baseline
predicted ~50), plus a 37-minute idle window at 0 (r64 predicted ~14). Full
post-mortem in [`docs/power/bringup/findings-log.md`](power/bringup/findings-log.md) (Part II, the former run-book)
(2026-08-22 entry). Not LKML-material: `apcs-msm8953.c` is
msm8953-mainline-only. The history below is kept as the record of the hunt.

`apcs-cpu0-pll failed to enable!` — `wait_for_pll()` returning `-ETIMEDOUT`
from `alpha_pll_huayra_set_rate()` under `sugov_work`, 266 times in one boot on
2026-08-15/16, ending in an unclean power cut with no shutdown sequence in the
journal. Evidence and the analysis are in
[`docs/power/bringup/findings-log.md`](power/bringup/findings-log.md) (Part II); the raw capture is
[`docs/power/bringup/captures/2026-08-16_apcs-cpu0-pll-lock-failures.txt`](power/bringup/captures/2026-08-16_apcs-cpu0-pll-lock-failures.txt).

Two reasons this outranks the power numbers it was found under. It makes the
device **unreliable** — an unclean cut can corrupt the rootfs and did once
already cost a boot to fsck elsewhere in this port. And `clk-alpha-pll.c` has
no retry on this path, so a transient lock failure is fatal to that frequency
transition rather than merely slow.

Not yet known: whether it is voltage-dependent (it started at the lowest
battery voltage of the session, but recurred while charging at 3.89 V), whether
it is specific to the little cluster, and whether it predates the current base.
The first test is a fixed cpufreq sweep at high and at low battery, counting
failures — not another power leg, which would only measure this.

Measured again 2026-08-16 on r56, and it narrows the question. 299 instances in
one 85-minute boot, the first nine seconds in, arriving every 10–40s.

☠️ An earlier version of this paragraph said it was **not load-driven**, on the
strength of a 60s-idle-vs-30s-burn comparison. Withdraw that: the counts came
from a `dmesg` that had already wrapped — noted as unreliable at the time and
used anyway. On the clean r57 boot the picture is different and not yet
explained: **zero** across the whole 27-check battery, which includes a 30s
eight-core burn, then **24 in three minutes** during the three acoustic audio
checks. Whatever drives it, it is not simply CPU load, and the audio path is
now the first place to look. The cluster still reaches every operating point — `policy0`'s
`time_in_state` shows residency at all seven, up to 1804800 — so each failure is
a rate change that is retried, not a clock left stuck, which is why nothing else
on the phone shows it. The battery was at 99–100% throughout, which weakens the
voltage hypothesis without disproving it (this was the terminal voltage, not the
rail the PLL sees).

It is also, as of today, visible: `10-health` greps for `WARNING:` and prints
this line with its count on every run, from `journalctl -k -b` rather than from
a ring buffer these same warnings had been evicting.


## ~~☠️ Deep sleep: `vlow` has never once been reached~~ — CLOSED 2026-08-24: `vlow` never occurs on this platform at all

Closed by the raw message-RAM read of the RPM's own `vlow`/`vmin` records on the
working UT oracle (`power/bringup/tools/rpmstats_raw.py`): across a 10-min window
in which the oracle demonstrably slept at full depth (APSS +34 603 collapses,
MPSS/PRONTO/LPASS XO +1 779/+4 997/+7 745), `vlow` count stayed 0 there too. The
mode never occurs on this device/firmware under ANY OS; the target was a phantom
and oracle-equivalence — the real criterion — was already met. The planned
`smd-rpm.c` s2idle-handshake work is cancelled (the RPM-observable handshake
exists and works on mainline; `msm_rpm_enter_sleep`'s SMD-RX-mask + flush are
AP-local and invisible to the RPM). Full account: findings-log 2026-08-24
"(continued)" entry. What replaces it in TODO: the modem lead.

Everything below is the section as it stood when closed:

## ☠️ Deep sleep: `vlow` has never once been reached

The single open item behind every idle-current number on this page, stated
separately because the section above is a status summary and this is a task.

★★★ **This is the project's top priority as of 2026-08-23**, and on that day the
AP-side gate stopped being unidentified. Full derivation and the next steps are
in [`STATUS.md`](STATUS.md) queue item 1; the short form:

★★★ **2026-08-24 — the regression-vs-SoC-limit question is ANSWERED: it is a
MAINLINE REGRESSION.** Booted the UT oracle (slot a, 4.9.218) and forced a real
downstream `mem` suspend: **APSS `xo_count` 0 → 2** across two confirmed suspends
(echo mem exit 0, 7 s + 12 s). The downstream AP votes its XO down in a genuine
suspend; mainline never does across a confirmed `rtcwake -m mem`. So pmOS
`vlow`=0 is a fixable gap in the mainline msm8953 suspend/RPM path (the AP's XO
vote), **not** an s2idle- or SoC-inherent limit — it sits alongside the LDO
sleep-vote gap below (the AP XO vote is one necessary condition, not the last
gate; `xo_sleep_off=1` already forces APSS XO and `vlow` is still 0). Forcing the
downstream to suspend took powering both ofono modems off (~5 wakeups/s from the
modem IPC router aborted every attempt) and disabling the `7000000.ssusb` wakeup
source (it stays active through a physical unplug — same dwc3 behaviour as pmOS).
Caveat: the mainline side has not yet been re-run with modems off. Capture:
`captures/2026-08-24_xo-across-suspend-ut-oracle-slotA.txt`; full trace in
findings-log 2026-08-24 (UT-oracle across-suspend).

★★★ **2026-08-24 — the AP XO vote is now LOCALIZED, and two tempting culprits are
ruled out by measurement.** From the mainline side (`qcom_rpm_master_stats`,
across a real `rtcwake -m mem` suspend):

- APSS **`XO shutdown count: 0`** (never), while `Shutdown count` = 39218 advances
  (cluster power-collapse works). Every other master drops XO: MPSS 5502, PRONTO
  19148, LPASS 48.
- **NOT cpuidle/PSCI/OSI.** dmesg's `psci: [Firmware Bug]: failed to set PC mode`
  is a red herring (an `EPROBE_DEFER` that recovered): the genpd `idle_states`
  usage counters show `system-pc` (0x42000353) entered **50933×** (2 in s2idle)
  and `cluster-pc` ~150k× each. The AP *does* reach system power collapse.
- **NOT the LDO regulators** (so the regulator-state-mem thread was never going to
  move `vlow`).
- **IS the AP-side RPM sleep-set XO/TCXO vote.** `clk_summary`: the root `xo`
  (held via `bi_tcxo`) is kept up by the two MMC controllers
  (`7824900`/`7864900.mmc`) and the codec ahbix (`c0f0000.codec`) on the AP side;
  the `qcom_rpm_smd_write` tracepoint confirms `sleep clk0/0 "Enab"=1` (CXO on in
  the sleep set). This explains *why APSS naturally never XO-shutdowns* and is
  upstream-correctness detail — but it is **necessary, not sufficient** for
  `vlow`: the prior `clk_smd_rpm.xo_sleep_off=1` lever already forces APSS into XO
  shutdown and `vlow` **still stayed 0** (queue item 1 in STATUS). So fixing the
  MMC/codec XO holders will make APSS XO-shutdown naturally, but will not by
  itself reach `vlow`. The open frontier (per STATUS) is the **USB controller**
  (`7000000.usb` stuck `control=on`/`pm_runtime_forbid`, never runtime-suspends —
  the `control=auto`+detach test is still not done), not the XO vote and not the
  LDOs (killed).
- Full chain + the disproven PSCI hypothesis:
  [`power/bringup/findings-log.md`](power/bringup/findings-log.md) and
  [`power/bringup/captures/2026-08-24_apss-xo-shutdown-count-zero-mainline.txt`](power/bringup/captures/2026-08-24_apss-xo-shutdown-count-zero-mainline.txt).

- The RPM's own entry threshold is **not** readable from any source we hold.
  `qcom_stats.c` (mainline) and the vendor 4.9 `rpm_stats.c` are both *readers*
  of an RPM-maintained counter — the vendor binding says so in as many words —
  and a word-boundary grep for `vlow|vmin` across the entire vendor tree returns
  no RPM hit at all. ☠️ It returns plenty of `VMIN` from `termbits.h` and `vmin`
  regulator properties from dtsi files; an unanchored grep here lies.
- What the AP *votes* is fully readable, and that is where the hole is. Four
  subsystems write `QCOM_SMD_RPM_SLEEP_STATE`: `clk-smd-rpm`, `rpmpd`,
  `icc-rpm`, `qcom_smd-regulator`. The first three vote sleep; the LDOs measured
  14 active / 0 sleep.
- ☠️ **The reason is a device-tree gap, not a driver gap.**
  `qcom_smd-regulator.c` already has `rpm_reg_write_sleep()` behind
  `.set_suspend_enable/disable/voltage` — **our** commit `0be43747a1d2`. Those
  ops are reached from `regulator/core.c:__suspend_set_state()`, which needs a
  `regulator_state` that only a DT `regulator-state-mem` child node can create
  (`of_regulator.c`, which also sets `constraints->initial_state =
  PM_SUSPEND_MEM` at line 327, making `regulator_register()` cast the sleep vote
  **at probe**). **No DT in the tree has that node** — not
  `sdm632-fairphone-fp3.dts:741`, not any of the ~616 qcom arm64 DTs. The ops
  have never been called.
- ☠️ **Two traps before anyone writes the DT.** (1) A `regulator-state-mem` node
  without `regulator-on-in-suspend` or `regulator-off-in-suspend` is silently
  ignored (`regulator_get_suspend_state_check()`); a suspend voltage alone only
  earns a `No configuration` warning. (2) The phone suspends via **s2idle**
  (`/sys/power/mem_sleep` = `[s2idle]`, no `deep`), and
  `regulator_get_suspend_state()` returns NULL for `PM_SUSPEND_TO_IDLE` — so the
  *runtime* `regulator_suspend()` path is dead here regardless. Only the
  probe-time `initial_state` path can work on this device.
- ☠️☠️ **DEPLOYED AS r74 AND IT DID NOT BOOT (now recovered to r73) — see the ✅ RECOVERED section at the top of
  this page.** `regulator-state-mem { regulator-on-in-suspend; }` went onto all
  20 rails (`wip/7.1.3/power` `e59893af`, cherry-picked to `integration/7.1.3`
  and `debug-int/7.1.3` `84241a07`, shipped as r74). The DTB compiles, the
  binding schema allows the node (`regulator.yaml`
  `^regulator-state-(standby|mem|disk)$`, inherited by
  `qcom,smd-rpm-regulator.yaml` through `$ref`), and 20 of 20 nodes are present
  in the deployed DTB. The phone then stopped booting, silently and before the
  watchdog probed.
  The likely mechanism, read from source: `regulator_register()` treats a failed
  `suspend_set_initial_state()` as fatal and `rpm_reg_probe()` returns out of
  its loop, so **one rejected or timed-out sleep vote unregisters every rail on
  the board**. Full derivation, recovery steps and the guardrail post-mortem are
  in the ✅ RECOVERED section.
- **Next (the phone is back on r73 now):** repeat with **one** rail, not twenty,
  and read the boot before adding a second. ☠️ Prove the votes were cast before
  believing a null result — the `qcom_rpm_smd_write` tracepoint must show
  sleep-context writes for `ldoa`/`smpa`. A property that parsed into nothing is
  indistinguishable from a lever that did not work, and the witness for
  probe-time votes is `tools/sleepset-witness.sh` on a boot armed with
  `trace_event=qcom_smd_rpm:qcom_rpm_smd_write trace_buf_size=4M`
  (☠️ never `tp_printk` — see that script's header for why it would boot-loop
  the phone).
- A second, lower-ranked candidate found the same day: the USB controller
  `7000000.usb` and its PHY `79000.phy` are the only 2 of 45 `soc@0` children
  with `power/control = on`, and neither has ever runtime-suspended
  (`runtime_suspended_time = 0`). That is dwc3's unconditional
  `pm_runtime_forbid()` at probe (`core.c:2321`, never followed by
  `pm_runtime_allow()` on the success path) — **not** the cable. ☠️ So unplugging
  the cable on its own tests nothing; the experiment is `control=auto` on both
  nodes **and then** detach, over the WiFi link (`fp3@192.168.x.x`, verified
  live 2026-08-23).

  ★ **Measured 2026-08-24 — and it walked straight into the trap above.** With
  the cable physically out I re-ran the XO-across-suspend snap: APSS XO count 0
  and `vlow` 0, **identical to cable-in**, so the *cable* is not the variable.
  But `7000000.usb`/`79000.phy` were `control=on` / `runtime_suspended_time=0`
  in both runs (dwc3 forbid), exactly as this bullet warns - the USB *controller*
  was never idled. So the cable-alone A/B rules the cable out, not the controller;
  the `control=auto`+detach experiment is still the one to run. Captures:
  `captures/2026-08-24_xo-across-suspend-pmos-r73-cable{in,out}.txt`.

**What is known.** The application processor collapses constantly and says so to
the RPM; the audio DSP can be made to collapse for the whole of every suspend; and
`vlow` and `vmin` still read `Count: 0`. So a master being down is **necessary and
not sufficient**, which is a measured correction to a claim this project carried
for several days.

**Measured 2026-08-22** (findings-log, `captures/2026-08-22_vlow-a1-systemd.txt`):
`rpm_master_stats` across three real 120 s s2idle windows names the blocker —
**the APSS has never once entered XO shutdown** (count 0 against ~50 000 power
collapses), while MPSS/PRONTO toggle XO freely and LPASS sleeps for good. The
standing sleep-set XO vote comes from the `bi_tcxo` holders in `clk_summary`
(both remoteprocs, both mmc hosts, the codec ahbix path) plus the 08-17 LDO
no-sleep-vote finding. And the modem's 36 % now has a rate: the modem smd-edge
fires ~once per 2 s inside a suspend window (+64/124 s), each wake echoed by
RPM request traffic (rpm edge +775) and 57–76 APSS collapses per window.

**Measured further, 2026-08-22 night** (findings-log entries of that evening,
captures `2026-08-22_vlow-xo-sleep-off.txt`, `_smd-channel-census.txt`,
`_send-census.txt`, `_wifi-ab-sends.txt`):

* **The XO lever works.** Booted with `clk_smd_rpm.xo_sleep_off=1` (the parked
  patch, `postmarketOS-xo` extlinux entry) the APSS enters XO shutdown ~0.7/s
  where it had never once — and `vlow` is *still* 0. So of the two named
  blockers only the LDO sleep votes remain.
* **The LDO driver side exists now**: `regulator: qcom_smd: cast sleep-set
  votes for suspend states` on `wip/7.1.3/power` (`5fe5dba6`, all three
  layers). No-op until a board opts in via `regulator-state-mem`; the opt-in
  plan (start `smpa/3`, never `ldoa/7`/`ldoa/8`) is in
  `power/bringup/leads/rpm-sleep-set.md`.
* **The window traffic has names.** kprobe census: `rpm_requests` ~670 events
  per 120 s window — our own interconnect/clk votes, cast per wakeup
  (`qcom_icc_rpm_set_bus_rate`; a governor A/B *refuted* the cpufreq-vote
  theory) — against IPCRTR 35 (signal-level pokes, ~zero qrtr payload) and
  `WLAN_CTRL` 32 (wcn36xx). **`ip link set wlan0 down` takes WLAN_CTRL to
  zero and the vote churn down a third** — a real, unpriced lever.
* ☠️ **Call-wake and staying asleep are mutually exclusive today**: with the
  modem edge armed (the r66 wake fix + the arm-at-boot unit) the signal ring
  re-wakes the phone within seconds of every suspend — measured as the
  99-suspend check failing armed and passing 3/3 disarmed. Quieting that ring
  gates both automatic sleep and leaving call-wake armed.

**Measured at dawn, 2026-08-23** (findings-log; captures
`2026-08-23_vlow-both-sets.txt`, `_rail-census-both-sets.txt`,
`_vlow-sleep-init.txt`, `_xo-simultaneity.txt`, `_icc-summary.txt`,
`_oracle-vlow-control.txt`): **the whole AP-side sleep-set family is closed,
three measured negatives deep.** A `both_sets=1` knob (r68) mirrors every
regulator request into the sleep set — the vendor shape, all 23 downstream
rails are `qcom,set = <3>` and none turn off in sleep, which killed the
off-in-suspend idea; the census under it shows every PMIC rail voted, leaving
only interconnect resources — and those turned out to be the GPU's
ACTIVE-tagged config path (sleep-0 by design, just never *written* because
`qcom_icc_rpm_set` elides no-change writes). An `icc_smd_rpm.sleep_init=1`
knob (r69) writes the explicit sleep zeros at probe. **All three knobs
together: vlow still 0** — across windows in which the APSS held one
continuous 121 s XO-shutdown with every other master cycling inside it, so
simultaneity is not the gap either. The TZ (all-zero master stats) is
**acquitted**: the oracle shows the same zeros. And the decisive control is
still unrun: **with a USB cable in, the oracle cannot sleep at all**
(`7000000.ssusb` wakeup source held; `rtcwake` fails on UT), so whether the
working system ever reaches vlow is itself unmeasured — the night's negatives
may describe both slots equally.

**What to do next, in order:**

1. **The oracle control with USB physically detached** (one session, WiFi
   links both slots): does UT ever reach vlow while actually sleeping? This
   decides whether vlow is a real target or a re-framing — everything below
   is ordered by its answer. Same detached-cable session also reruns the
   rail census (the three USB-PHY rails stay confounded until then;
   USBIN-suspend does not help — it cuts charge current, not the data link).
2. ~~**Decode the vlow `Client Votes` mask**~~ — **done by subtraction on
   2026-08-23, no RPM firmware needed** (findings-log). Take one master away
   at a time and watch which bit moves: **bit 0 ↔ APSS, bit 1 ↔ MPSS,
   bit 2 ↔ PRONTO, bit 4 ↔ LPASS**, and the four bytes are the same field
   sampled four times, not four clients. ☠️ **Bit 3 has never once been set**
   — not under any knob, not on the oracle. ☠️ **Named the same day, and it
   is not an outside client:** the RPM message RAM gives each master a 4 KB
   slot (`0x150`, `0x1150`, `0x2150`, `0x3150`, `0x4150` in `msm8953.dtsi`),
   so the master index is `offset >> 12` — APSS 0, MPSS 1, PRONTO 2, **TZ 3**,
   LPASS 4, which is exactly where the four measured bits fall. **Bit 3 is the
   TZ**, silent for the same reason its stats block is all zeros: it does not
   participate. The earlier "vote from outside the five masters" reading is
   retracted; stop looking for a sixth client. ★★★ **The last follow-up — read
   the mask immediately after a suspend window, from the `postmarketOS-xo`
   entry — is done, 2026-08-23, and it named the blocker.** Six real 30 s
   windows (`/sys/power/suspend_stats/success` 6 → 12, APSS XO shutdown
   +1710, so the windows suspended and the APSS collapsed inside them):
   `vlow`/`vmin` `Count` **0 in all 58 samples**, and the master stats show
   **LPASS `Shutdown count` frozen at 65 with `Last shutdown @` decoding to
   46.3 s of uptime** (19.2 MHz ticks). APSS/MPSS/PRONTO cycle normally.
   Bit 4 was set in exactly 1 of 58 mask samples — the same fact seen by the
   other instrument, since bit 4 is LPASS. **The ADSP slept 65 times in the
   first ~46 s of the boot and has not slept since**, and an aggregate
   low-power set cannot be entered while a master has not voted itself down.
   Instrument `docs/power/bringup/tools/votes-post-resume.sh`, capture
   `captures/2026-08-23_votes-post-resume-xo.txt`, write-up in
   `leads/rpm-sleep-set.md`.
   ☠️ **Corrections, same evening, both in `leads/rpm-sleep-set.md`:** the
   freeze is at **~34 s of Linux uptime**, not 46 — the RPM's 19.2 MHz counter
   runs from SoC reset and leads `/proc/uptime` by the bootloader's ~13 s.
   The sensor stack was the obvious suspect (`snsregd` starts at 33.6 s, SMGR
   runs on the ADSP) and is **acquitted**: modules unloaded and both services
   stopped, LPASS flat at 37 for 60 s while APSS did +1960; the `+2` at the
   moment of teardown says the ADSP can still shut down and that the pin
   re-establishes within five seconds.
   ☠️☠️☠️ **RETRACTED the same night, in full: the ADSP was never pinned.**
   A flat `Shutdown count` means "asleep and staying down" just as readily as
   "held awake"; `Last XO shutdown enter` vs `exit` and `Active cores bitmask`
   are what separate them, and every capture above shows `enter > exit` with
   `cores 0x0` — asleep. Re-measured on a clean r73 boot: LPASS reads
   `ASLEEP cores=0x0` from ~34 s to the end of the trace. The LPASS question was
   already closed on 2026-08-21 (two root causes, both fixed, shipped in r63),
   and this evening re-walked it only because the closure lived in a working
   note the resume path never read. The sensor bisect and the ADSP-offline
   control answered a question that did not exist.
   ☠️☠️ **And the ADSP is NOT the `vlow` gate** — which was also already known: With the ADSP
   `remoteproc` stopped by name, a 30 s suspend window leaves `vlow`/`vmin`
   `Count` at 0, identical to the control with it running. "One master is not
   voting" was a mechanism that explained the symptom, not evidence that it
   caused it. Two investigations now, not one: the `vlow` gate and the ADSP.
   ★ **Updated 2026-08-23: the `vlow` gate is no longer "unidentified" on the
   AP side** — the regulator sleep-set votes are never cast because no DT
   describes a suspend state (top of this section). The never-sleeping ADSP
   remains a separate anomaly whose cost in mA is unmeasured.
3. **Price the WiFi lever** (slope leg, wlan0 down vs up: WLAN_CTRL 32→0 and
   a third of the vote churn) and decide the suspend policy. ☠️ **The mask
   decode found the other side of this trade**: with `wlan0` down, PRONTO's
   XO shutdown count stops advancing at all and its mask bit sits pinned —
   the co-processor parks holding the XO instead of cycling it. Price the
   whole leg in mA, not the churn. WiFi is also
   the USB-independent rescue link.
4. ~~**Name and quiet the modem edge's signal ring**~~ (~one poke per 2 s,
   payload-free) — **not ours to quiet, measured 2026-08-23.** Stopping
   `ModemManager` and `rmtfs` leaves the rate unchanged (24 / 33 / 20 / 31
   pokes per 60 s across the A/B), so the modem produces it on its own and no
   AP-side policy reaches it. What is left is the modem firmware or the SMD
   channel state machine, neither reachable from a device patch. **So the
   call-wake trade has to be resolved elsewhere**: hold an inhibitor while
   ringing, or arm the edge only when a long sleep is not wanted. That
   decision, not more measurement, is what gates automatic sleep.
5. **The three experiment knobs stay default-off** (`clk_smd_rpm.
   xo_sleep_off`, `qcom_smd_regulator.both_sets`, `icc_smd_rpm.sleep_init`,
   all in r69); design their upstream forms only after a measured positive.
   ☠️ **`both_sets` is now understood to be the wrong shape, which is part of
   why it measured nothing.** It mirrors each *active*-set request verbatim into
   the sleep set, i.e. it votes every rail **on** in sleep — the opposite of
   what a sleep vote should say. The correct mechanism is the DT
   `regulator-state-mem` path at the top of this section, which lets each rail
   state its own suspend enable/voltage. Do not resurrect `both_sets` as the
   upstream form.
6. **Release the internal digital codec's LPASS clocks** — ☠️ **half of this is
   already done and the entry was stale until 2026-08-23.** In the tree the
   package builds, `mclk` is requested per stream (`.startup`/`.shutdown`, with
   a comment naming the ADSP); the upstream base has no such code, so that half
   is ours. What is still held for the life of the boot is **`ahbix-clk` alone**,
   enabled in `msm8916_wcd_digital_probe()` and dropped only in `remove()`.
   ☠️ It cannot simply be moved per-stream the way `mclk` was: it is the AHB
   interface clock behind the codec's MMIO regmap, so every register access
   outside a stream — DAPM widgets, mixer controls — needs it. The honest fix is
   runtime PM around register access, which is a real piece of work, not a
   one-liner. On this board the codec is not in the audio path, and the leg
   prices the whole mechanism at ~4 %, so this stays correctness-and-upstream
   work rather than a power fix. Detail in the audio section above.

☠️ **Do not restart any of this by building a kernel.** Nothing here is blocked on
code that has not been written; it is blocked on not knowing which vote is left.

---

## ~~Does the sleeping ADSP cost current, and is `lpass-never-sleeps` worth fixing?~~ — CLOSED 2026-08-25: it costs NEGATIVE current

Carried since 2026-08-19 as the last live piece of the LPASS thread. The
observation behind it is true and is not withdrawn: the audio DSP does not
power-collapse in normal operation, and
[`power/bringup/leads/lpass-never-sleeps.md`](power/bringup/leads/lpass-never-sleeps.md)
names the holder (an upstream `msm8916-wcd-digital-codec` clock, not our UCM
verb — see the first section of this file). What was still open was the only
question that decides whether it belongs on the power track at all: **what does
it cost?**

**Measured 2026-08-25, A/B/A′ on the same protocol, panel proven dark:**

| leg | floor (p10) |
|---|---|
| A — ADSP running as normal | **52.9 mA** |
| B — ADSP stopped | **56.3 mA** |
| A′ — control, back to normal | **54.6 mA** |

**Stopping the ADSP makes the phone draw *more*, by ~2 mA.** Read the A→A′ drift
(52.9 → 54.6) as the instrument's own spread at this resolution, which puts B
outside it in the wrong direction. Whatever the ADSP costs by staying up, the
system pays more for it being down — most plausibly because work it was doing
falls back to the application processor, though nothing here measures that and it
is not claimed.

**So `lpass-never-sleeps` is a true observation worth no milliamps**, and it is
closed as a *power* item. It stays open as a correctness/upstream question if
anyone wants it, at its own page.

☠️ **The A′ leg is the whole reason this is a result.** Without it, A→B alone
reads as "+3.4 mA, stopping the ADSP is bad" with a confidence the data does not
support; with it, the honest statement is "+2 mA against a ±1.7 mA drift". The
same day produced two other candidate effects that turned out to be pure drift.
A two-leg comparison on this instrument is not a comparison.

☠️ **This is also the seventh of seven exclusions** on the continuous-draw hunt
(userspace, the CPUs, wakeup blockers, the modem, the debug UART and clocks, the
rails, the ADSP) — seven exclusions, zero findings, ~38 mA still unaccounted for.
Note what they share: **every one of them counts events.** The open item is in
[`TODO.md`](TODO.md) under "Where the hunt actually stands".

---

## ~~An incoming call cannot wake the phone from s2idle~~ — FIXED (r66, 2026-08-22)

Measured 2026-08-14 (the reason automatic sleep went off): across an 8 min sleep
a call reached the modem, the AP never woke, and the queued event replayed on
the button wake. Root cause: `qcom_smd_parse_edge()` requested the edge IRQ with
no wake registration at all, so `suspend_device_irqs()` masked it; the one knob
that existed (smp2p, with its *"to not miss phone calls"* comment) was measured
useless — the call travels the SMD data edge, not smp2p.

**The fix shipped in r66** (`wip/7.1.3/power` `8c9b2568`, on all three layers):
the smp2p pattern mirrored into `qcom_smd_parse_edge()` — every rpmsg edge is
`device_set_wakeup_capable()` + `dev_pm_set_wake_irq()`, disabled by default,
armable per edge from sysfs. Verified 2026-08-22 on the device, three ways:

* **differential:** disarmed windows sleep to the alarm (30 s→32, 60 s→62);
  with the modem edge armed the same windows end on modem traffic
  (120 s→65 s, 180 s→64 s, 180 s→4 s);
* **live call:** armed + 300 s window, an incoming call woke the phone 15 s in
  (modem smd-edge +35 IRQs, `suspend_stats/success` advanced) and it rang;
* **no storm:** arming does not produce an immediate wake loop, and the default
  stays off so nothing changes for a board that does not opt in.

☠️ **The r66 patch had a teardown bug, fixed 2026-08-23 (`d0e738c107e3`, all
three layers).** Stopping a remoteproc whose edge was **armed** oopsed on a NULL
klist: an armed edge owns a wakeup-class child device, and
`qcom_smd_unregister_edge()`'s child walk unregisters every child as if it were
an smd channel, so the wakeup device was torn down twice. Disarmed edges were
never affected. The fix drops the wakeup source before the walk; the LKML draft
is regenerated as one patch carrying both hunks. **Deployed as r70 and verified
on the device the same day**: with the edge armed, stopping the modem and then
the ADSP remoteproc each returns 0, leaves the node `offline`, restarts on a
`start` write, and the boot ends with zero `Unable to handle kernel` lines —
the two edges that oopsed on r69. ☠️ Address a remoteproc by platform address
or `name`, not by index: the numbering moves between boots (the ADSP was
`remoteproc1` on one boot, `remoteproc2` on the next).

☠️ Attribution counters are blind here: the plain `enable_irq_wake` path bumps
neither the device's `wakeup_count` nor `/sys/power/pm_wakeup_irq` in s2idle —
the differential is the instrument, not the counter. The arm knob is
`.../4080000.remoteproc/remoteproc/remoteproc0/remoteproc0:smd-edge/power/wakeup`.

Upstream: the series is staged in `lkml-drafts/smd-wake-v1/` (Assisted-by
trailer, checkpatch/get_maintainer steps in its NOTES.md); sending is in the
user's hands.

**Still open before automatic sleep returns:** (1) a persistent boot-time arm
for the modem edge (udev rule or oneshot — the knob resets to `disabled` per
boot by design); (2) the ringing inhibitor — even with the AP awake, something
must hold suspend off while the dialer rings, untested because automatic sleep
is currently off.

**Open question, not decided:** this belongs to no branch category. It is not
FP3-specific — `qcom_smd.c` is upstream and every SMD-era Qualcomm SoC is
affected, which with the smp2p precedent makes it unusually defensible on the
LKML. Functionally it is the call path, so `voice` is the closest fit.

☠️ **SSH does not wake the phone either**, despite `wcn36xx_rx` being wake-armed
— it times out with `No route to host`. Useful, because a logger left running
under `systemd-run --collect` cannot be contaminated by the observer polling it;
and a warning for anything that assumes the device is reachable while asleep.
**★ Closed 2026-08-25 with the end-to-end proof the r66/r70 work had never
had.** Everything above measures the *wake*; what was never once observed was
the whole chain, from a call placed on another continent to a phone that
actually rings. One controlled suspend with a 420 s RTC backstop:

* `PM: suspend entry (s2idle)`, then **the phone woke 113.6 s in** — not at the
  backstop, so the RTC did not do it;
* `bl_power` 4 → 0;
* journal, `18:06:14 PM: suspend exit` → `18:06:15 [modem0/call0] call state
  changed: unknown -> ringing-in (incoming-new)` → `18:07:16 terminated`.

**Resume-to-ring: one second. Ringing: 61 seconds.** Chain: paging →
`remoteproc1:smd-edge` armed wakeup source → resume → ModemManager →
`fp3-voiced`.

☠️☠️ **Both instruments chosen for this test returned EMPTY on a call that
worked**, and if the dialling time had not been known independently it would
have been written up as a clean failure:

* `/sys/class/wakeup/*` read **+0 everywhere**. It does not attribute an s2idle
  wake at all — `wakeup_count` advances only on `pm_wakeup_event()`, and the
  plain `enable_irq_wake` path never calls it. The instrument that does work is
  the **`/proc/interrupts` diff**.
* `mmcli --voice-list-calls` answered *"No calls were found"* — read one second
  before the call object existed.

**Two instruments agreeing on nothing is not evidence of nothing.** What proved
it was the journal, which nobody had chosen in advance.
[`power/bringup/tools/call-wake-test.sh`](power/bringup/tools/call-wake-test.sh)
now carries both fixes: the interrupt diff, and a re-read of the call list after
a settle.

☠️ **What is NOT closed by this, and has its own section in
[`TODO.md`](TODO.md):** the arm knob resets to `disabled` on every boot and
nothing arms it. This proof armed it by hand. Automatic sleep stays off until a
boot-time arm exists.

---

## ✅ RECOVERED — r74 does not boot; recovered via r73, phone since moved to r76 (2026-08-23 23:22)

☠️ **This heading said "back on r73, phone is up" until 2026-08-25 evening.** That
was the state on 2026-08-23; the phone has run **r76** (`debug-int/7.1.3`
`5aafd59e`, `#77-fp3`) since the morning of 2026-08-25, and the boot default is a
frozen r76 snapshot. The recovery *route* below is what this section is for and
it is unchanged — the revision numbers in it are historical.

The device booted again on the r73 kernel and DTB and answered on both SSH
links. r74 is still on `/boot` untouched for later diagnosis; the boot default
was moved off it. What follows is kept because the *cause* is not yet fixed —
only the boot was recovered.

**How it was recovered (the route that worked, in order):**

1. The phone was in **stock ABL fastboot** (`fastboot devices` →
   `A209H47E0202`, `version-bootloader 6.A.039`, unlocked, slot `b`). ☠️ A
   prior `fastboot getvar` had been interrupted by an outer `timeout`, which
   froze the link exactly as `docs/deploy/README.md` warns; a `USBDEVFS_RESET`
   on the device node (`ioctl 'U'<<8|20`) cleared it in one shot.
2. `fastboot set_active a` → `fastboot reboot`. Slot `a` is the **Ubuntu Touch**
   side and it boots on its own; adb came up at ~60 s as user `phablet`
   (`sudo` password `<pw>`; `adb root` is refused, plain sudo is the way).
3. From UT, mounted pmOS's embedded `/boot` off `system_b` (`mmcblk0p31`):
   `losetup -o 1048576 <loop> /dev/mmcblk0p31` then `mount <loop> /tmp/pmboot`.
   This is read-write; the msdos `/boot` is at offset 1048576.
4. Edited `extlinux.conf`: `default postmarketOS-sleepset` → `default
   postmarketOS-prev` (r73's `/boot/vmlinuz-r73` + `/boot/sdm632-fairphone-fp3.dtb-r73`,
   the exact config that had run the previous hour). Backed the broken file up
   as `extlinux.conf.pre-r73revert`. `sync`, `umount`, `losetup -d`.
5. `adb ... sudo reboot bootloader` → `fastboot set_active b` → `fastboot
   reboot`. pmOS came up on r73 in ~15 s; `02-boot-fallback` passes (default
   `postmarketOS-prev`, watchdog active, 4/4 entries carry `panic=`), and the
   running tree has **zero** `regulator-state-mem` nodes — proof it is r73, not
   the broken r74.

☠️ **Button-mapping correction, measured by the user (the earlier note here was
inverted).** On this phone **volume-UP + power reaches EDL** (`05c6:900e`
QUSB__BULK) and **volume-DOWN + power starts fastboot**. The lk2nd graphical
boot menu is **not usable blind**: the screen stays black in these modes, so
picking a menu entry by sight is not an option — recovery goes through fastboot
+ the UT-slot route above, not through the on-screen menu. The prior claim that
volume-down reached EDL and volume-up reached the lk2nd menu was wrong.

☠️ **EDL was never needed and should not be reached for.** Only one DTB was ever
proven unbootable; three intact alternatives sat on `/boot` the whole time, and
the slot-swap-to-UT route edits the boot config with ordinary tools. A firehose
flash is a far bigger operation than this fault ever justified.

**What broke.** The `regulator-state-mem` device-tree change (r74,
`debug-int/7.1.3` `84241a07`) was deployed and the phone rebooted at 22:45:10.
It never came back on USB or WiFi. The host log shows the `cdc_ncm` disconnect
and **no re-enumeration for fifteen minutes** — and that absence is the
informative part: `panic=10` is on all four entries and the debug layer starts
the watchdog at probe, so a *later* hang would have produced a reboot **cycle**.
There was no cycle, so the kernel stopped **before the watchdog device probed**.

**Why, read from source after the fact — a hypothesis, not a measurement:**

- `suspend_set_initial_state()` runs inside `regulator_register()`
  (`regulator/core.c:1497`), and on this SoC the RPM rails register very early.
  The change makes it issue 20 extra `qcom_rpm_smd_write()` calls into the RPM
  **sleep** set right there.
- `qcom_rpm_smd_write()` (`soc/qcom/smd-rpm.c:139`) waits on the RPM ack with
  `RPM_REQUEST_TIMEOUT = 5 * HZ` and returns `-ETIMEDOUT`, or the RPM's own
  `ack_status`.
- ☠️ **`regulator_register()` treats that as fatal** — `if (ret < 0) { rdev_err;
  return ret; }` — and `rpm_reg_probe()` returns straight out of its
  `for_each_available_child_of_node_scoped` loop. So **one rejected or
  timed-out sleep vote leaves every rail on the board unregistered**, not just
  its own. No regulators means no storage, no USB and no display: exactly the
  silent early stop that was observed. 20 rails × 5 s is also up to 100 s of
  blocked probe before that.
- ☠️ A NULL `smd_vreg_rpm` was checked and **ruled out**: it is assigned before
  the registration loop (`qcom_smd-regulator.c:1530`).

**What this changes about the plan.** The next attempt starts from **one** rail
and reads the boot before adding a second. Twenty at once was the mistake, and
the `regulator_register()` all-or-nothing behaviour is a genuine upstream
robustness point worth writing up separately.

☠️ **The isolation guardrail was followed in letter and missed in substance.**
"Put anything risky on the non-default label" was obeyed by giving the *tracing
arguments* their own label — but the tracing arguments were never the risk. The
**device tree** was, and both r74 labels point at the same
`/boot/sdm632-fairphone-fp3.dtb`. A second arm that differs only in a kernel
flag is not an isolated arm; it is the same arm twice. Isolating a change means
isolating **the file that changed**.

☠️ Second cost, exactly as `docs/deploy/README.md` warns: `apk add` ran
`boot-deploy`, which **rewrote `extlinux.conf` from scratch**, dropping the
fallback label, `panic=10` and the menu timeout. It was rebuilt by hand with
four labels and `02-boot-fallback` confirmed them (4 of 4 entries carry
`panic=`) *after* the install and *before* the reboot — which is why three
working alternatives exist to boot into. The pre-install file is on the device
as `/boot/extlinux/extlinux.conf.pre-r74`.

**Nothing is stranded.** `wip/7.1.3/power` `e59893af`, `integration/7.1.3`
`4cf51780`, `debug-int/7.1.3` `84241a07`, all pushed to `fork`; the package is
at `/mnt/1TB/pmos/work/packages/edge/aarch64/linux-fp3-7.1.3-r74.apk`.

**★★ 2026-08-24 — cause found, and reverted.** A one-rail bisection probe
answered the open question. Rebuilt the DTB with `regulator-state-mem
{ regulator-on-in-suspend; }` on **only `pm8953_s3`**, deployed DTB-only, and it
**boots** (~16 s), **casts the sleep vote** (`sleep smpa/3 swen=1 @ t=0.276084`
on the `qcom_rpm_smd_write` tracepoint — measured, not assumed) and **suspends**
(`success` 0 → 1). So `regulator-state-mem` is fully usable; the all-20 no-boot
is the `regulator_register()` all-or-nothing behaviour tripping on **one
specific rail** whose sleep vote the RPM rejects/times out — exactly the
hypothesis above, now confirmed from the working side. Details:
[`power/bringup/findings-log.md`](power/bringup/findings-log.md) (2026-08-24
one-rail entry).

☠️ **But on-in-suspend saves nothing** — the rail stays on, only the vote is made
to exist; no bisected subset of it would lower draw. A real win needs
`off-in-suspend`/lower `suspend-microvolt` on genuinely-unused rails, and is gated
behind the AP-XO regression anyway. So the all-20 commit is **reverted** off all
three branches (a no-benefit change must not ship; a no-boot one must not be the
pinned commit). The one-rail DTB stays on the device
(`/boot/sdm632-fairphone-fp3.dtb-1rail-s3`) for later per-rail bisection if the
`off-in-suspend` direction is picked up. `84241a07` remains reachable in history
(revert-on-top, not a rewrite), so the old package tarball still resolves.

---

# From the `autonomy.cjs` run plan (2026-08-31 … 2026-09-03)

A 2026-09-03-i átállás előtt a soron következő munkát egy hook saját
állapotfájlja tartotta (`autonomy.cjs`), nem ez a repó. Az átállásakor a **20
nyitott** tétel a [`TODO.md`](TODO.md) `FP3-QUEUE` szakaszába került; ez a
szakasz a **lezárt 104** tétel, szó szerint, ahogy a hook tartotta őket.

☠️ **Miért van itt.** A leállításkor azt írtam, hogy „semmi nem veszett el, a
state-fájl mindent megtart" — ez a state-fájlra igaz volt, a **repóra nem**:
ez a 104 tétel sehol nem volt megtalálható a `docs/` alatt (104-ből 2 volt
szövegre kikereshető), és a leállítás ráadásul a `STATUS.md` resume-blokkját
is felülírta a *„No autonomous run is active."* sorral. Egy állapot, ami csak
egy nem verziókövetett fájlban él, nincs meg — ugyanaz a lecke, mint amit a
[`gates.md`](gates.md) a verziókövetetlen kapukról ír.

The item numbers are the originals so that references resolve. `[x]` = done,
`[-]` = dropped.

## ☠️ This block stays in Hungarian, and it is an ARCHIVE, not a source

The repository is otherwise English (`docs/` pages, capture READMEs, leads). This
one section is kept in the language it was written in, because it is a verbatim
archive of working notes rather than a page anybody reads to learn what the
device does. **New entries here are written in English.**

That is only defensible because the substance is elsewhere, which was checked
rather than assumed, 2026-09-03:

| check | result |
|---|---|
| closed items with a resolving witness | **86 / 86 done items** (a capture directory, a commit, or a declared `unverifiable:`) |
| items with no witness | 18 — **exactly the dropped ones**, which by definition produced no result |
| measured numbers in the notes | 150 |
| …that also appear elsewhere under `docs/` | **138 (92 %)** |
| …that appear nowhere else | 12, each inspected by hand |

The twelve were all leg-context or validation values whose *finding* is recorded
elsewhere — the QMI census's 50.9 % duty, the RAT ladder's 49.8 %, the XO
series' 50.6 %, and so on — with their capture directory intact. Two were worth
naming:

- ☠️ **The contaminated IMS-off window** (item 56: MPSS 0 wakeups in 600 s,
  `exit>enter` ⇒ awake throughout, the modem continuously awake for >766 s,
  because the DIAG log mask is modem-side state that outlives the capture
  process). Recorded in
  [`power/bringup/leads/ims-missing-ap-half.md`](power/bringup/leads/ims-missing-ap-half.md):
  *"The one window taken with IMS off is unusable."*
- ☠️ **A 1 ms discrepancy nobody had noticed**: the fourth reachability call is
  **325 ms** in the ringlog's own replay (machine-derived) and **326 ms** in the
  hand analysis quoted in `STATUS.md`, while the note claims the two are
  "exactly the same numbers". It changes no conclusion — the mean is 385 ± 92 ms
  — but it is left standing here rather than silently reconciled, because
  picking one without the journal would be a guess.

The OCV acceptance threshold (`< 0.2 mV/min over the last five minutes`) appears
only here among the pages — it lives where it is enforced, in `night-run.sh`.

- [x] **1.** ★★★★★ A CENSUS EREDMENYENEK ROGZITESE: capture + a 'terse buys no residency' verdikt VISSZAVONASA a leads/modemmanager-suspend-modes.md-ben
      - tanú: `capture:docs/power/bringup/captures/2026-08-31_modem-night`
      - capture megirva (dcb3e9a) es a lead verdiktje visszavonva a helyen

- [x] **2.** ★ mA-ATVALTAS: a 86 kor v_uV oszlopa -> meredekseg -> mA a 2026-08-28_discharge-to-shutdown referencia-gorbevel. ☠️ A capacity oszlop hasznalhatatlan (fagyott integrator). Adapter kell a sleep-night-fit.py formatumara
      - tanú: `commit:57541d4`
      - 86 +/- 4 mA (43 kor, 91,7% alvas, stabil minden vagasnal). A ket ALVO pontbol: meredekseg 133 (az ebren-illesztett 135-hoz kepest 1,5%-on belul), tengelymetszet 41,4 mA (nem 54,9). A tengelymetszet UGYANAZ a szam, mint a reggeli 'gazdatlan ~41 mA'.

- [x] **3.** ☠️ MUSZER-HIANY: a 43 rtcwake kornek NINCS QMI-adata, mert az 'rtcwake -m mem' a /sys/power/state-be ir es NEM futtatja a systemd system-sleep hookjait, tehat a FP3_FREEZE/THAW markerek nem sultek el. A census fele vak. Javitani kell (sajat marker az rtcwake ag koré) vagy kimondani a lefedettseget
      - tanú: `commit:7f56463`
      - LEZARVA: a javitas telepitve ES az azonossag igazolva (host=eszkoz sha 251a5e7a2dda510d), mindket suspend-uton talal ablakot, a sajat tracepoint zaja kiszurve. ☠️ Ket sajat hiba derult ki menet kozben: a 'pkill -f wake-qmi.sh' mintaja a SAJAT parancssorara is illeszkedett es megolte a shelljet mielott az install lefutott (ezert maradt ketszer a regi verzio az eszkozon), es a machine_suspend ablak a sajat timekeeping_freeze parjat szamolta csomagnak. Az eszkoz most tiszta: 0 maradek folyamat, ures kprobe_events, MM active + registered.

- [x] **4.** ★ A MODELL ELLENORZESE: mA = 54,9 + 135 x duty AZ EBREN-ABLAKOKRA lett illesztve. Ez a futas az elso, ahol magas modem-duty (33,6%) EGYUTT all egy 93%-ban alvo AP-vel. Ha az aram nem a josolt ~100 mA, a modell alvo telefonra NEM ervenyes - es akkor a D-palya erteke sokkal kisebb, mint hittuk
      - tanú: `commit:57541d4`
      - A MODELL ATVISZ, csak a tengelymetszet mas: a 135-os egyutthato reprodukalodik alvo telefonon is (133), de a tengelymetszet 54,9 helyett 41,4. VISSZAVONVA az egesz napon at ismetelt allitasom, hogy a D-palya csak paritast vehet: az orakulum 6,1%-os dutyjan a szamitott ertek 49,5 mA, azaz A CEL, kizarolag a modem-palyarol.

- [-] **5.** ★ USB-link bearazasa - az egyetlen megmaradt nev a ~41 mA-re (ejszaka-hosszu, felhasznaloi dontes a telefonrol)
      - az USB-link bearazasa - ejszaka-hosszu, es most a fenti kontroll fontosabb

- [x] **6.** Ismert-pozitiv a <wrn> agra: a mai 'a modem nem utasitja el' negativum csak annyit er, amennyire igazolt, hogy a figyelmeztetes tudna is elsulni
      - tanú: `capture:docs/power/bringup/captures/2026-08-31_wrn-known-positive`
      - MEGVAN: a patch altal hozzaadott <wrn> sor elsult a NORMAL patchelt buildben (ed056596), sajat szovegevel es a hibauzenettel: 'couldn't unregister serving system indications: Cannot write message: Error sending data: Broken pipe; the modem may keep sending them'. ⇒ a mai negativum MERES, nem csend. ☠️ Amit NEM mutat: hogy kifejezetten egy MODEM-OLDALI elutasitas is ezt valtja ki - a latott hiba egy reteggel lejjebb volt (transzport). Az injektalt build nem lett kiprobalva es torolve lett az eszkozrol.

- [x] **7.** ★★★★★ A KONTROLL, ami a ket-pontos vonalat vezerelte kiserlette teszi: UGYANEZ a 8 oras census, de ModemManager LEALLITVA. Ugyanaz a WiFi-down, kabel-out, ugyanaz a valtakozas. Harmadik pont ~5% dutynal, ahol CSAK a daemon ter el. ☠️ Elore rogzitve: ha ~48 mA jon ki, a 133-as meredekseg es a 41,4-es tengelymetszet MEGERSODIK es a D-palya onmagaban eleri a celt; ha erdemben mas, a ket-pontos vonal ket KONFIGURACION at volt huzva es a kovetkeztetes megdol
      - tanú: `capture:docs/power/bringup/captures/2026-09-01_modem-night-control`
      - A 8 oras mereserek le kell futnia: ciklus vege 05:32, utolso kor ~05:42. A telefon nem elerheto (nincs kabel, nincs WiFi) es NEM IS SZABAD megerinteni - minden ssh-belepes ebreszti az AP-t es elrontja a kort, amibe beleesik. A WiFi magatol visszajon ~05:35-re, figyelo (bg task) jelez

- [x] **8.** ★★★★★ A 48 mA-es PADLO nem reprodukalodik kabel nelkul: ugyanaz a daemon-allapot KET fogyasztoval kevesebb (nincs WiFi, nincs kabel) 100 mA-t mer. Mindket kulonbseg rossz iranyba mutat ⇒ nem a terhelesi oldal. Gyanu: a sleep-night.sh a padlot BEDUGOTT kabellel es input_suspend bittel meri, es hogy a VBUS ilyenkor visz-e a rendszersinbol, azt itt SOHA nem mertuk. Kiserlet: EGY ORA - ket leg egymas utan, kabel-be/input_suspend majd kabel-ki, azonos dutyn
      - tanú: `capture:docs/power/bringup/captures/2026-09-01_modem-night-control`
      - MEGOLDVA MASKENT, forrasbol: a VBUS-hipotezis HALOTT (a sleep-night.sh input_suspend ciklusa no-op - a fajl nem letezik -, es az igazi vagas a qcom_smbx.c smb_set_property-jeben USBIN_SUSPEND_BIT-et allit ⇒ a rendszer az akkurol megy). A valodi hiba PROVENANCIA: a 48 mA a 08-30-i 58 kores futasbol jon, aminek a dutyjat SOHA nem mertek, az 5,0% pedig egy 08-31-i EGYETLEN ablakbol, ami aramot nem mert. Ket kulon futas ket kulon napon, egy kozos kapuval ('MM leallitva') osszeragasztva

- [x] **9.** ★★★★★ WIFI-UP KAR (kabel ki, MM leallitva, 2 ora): a 2026-08-31-i EGYETLEN 5%-os ablak ket dologban tert el minden ejszakatol - WiFi FENT es kabel BENT. Ez a ketto kozul a WiFit valasztja szet. ☠️ ELORE ROGZITVE: ha az MPSS ~5%-ra esik, a WiFi-fent (vagy hogy a modem nem az egyetlen halozati ut) az ELSO megtalalt D-palya kar; ha ~34-36% marad, a WiFi nem az, es a kulonbseg a kabel vagy az n=1
      - tanú: `capture:docs/power/bringup/captures/2026-09-01_wifi-up-arm`
      - A 2 oras ablaknak le kell futnia (~08:08, dead-man 08:27). A telefon elerheto WiFin, de megerinteni TILOS - egy ping is ebreszti az AP-t es elrontja a kort. Tiszta idozito figyel 08:12-re

- [x] **10.** Ha a WiFi-kar nem magyaraz: KABEL-BE kar (modem-night.sh 2 600 15 stopped up in) - ez reprodukalja pontosan a 2026-08-31-i 5%-os ablak konfiguraciojat, n>1-gyel. Kabel kell hozza
      - tanú: `capture:docs/power/bringup/captures/2026-09-01_cable-in-arm`
      - A 2 oras kabel-be ablaknak le kell futnia (~10:26)

- [x] **11.** ★★★★★ REBOOT-TESZT: a duty EGY BOOTON BELUL ugrott 5% -> 34% (uptime 16 h vs 22+ h) es 28 ora ota ott all minden konfiguracioban. Parositott par: UGYANAZ a beallitas (kabel be + bemenet elvagva, WiFi fent, 12 ablak 44 h uptime-nal), csak az uptime ter el. ☠️ ELORE ROGZITVE: ~5% friss booton ⇒ a duty PER-BOOT allapot ami romlik, es az 5% parancsra eloallithato; ~36% ⇒ nem az uptime, es a 08-31 reggeli epizod magyarazatlan marad. ☠️ A rebootot a classifier letiltotta - FELHASZNALOI JOVAHAGYAS kell
      - tanú: `capture:docs/power/bringup/captures/2026-09-01_modem-core-cycle`
      - A letra-ablaknak le kell futnia: korai ellenorzopont 13:05, teljes futas ~15:10. ☠️ WiFi fent, egy ping is ebreszti az AP-t

- [x] **12.** ★★★★★ MODEM-MAG CIKLUS (reboot nelkul): disable -> power-state-low -> on -> enable, a modem visszaall registered/LTE/attached-re (a B-leg allapota). Ugyanaz a kar mint a kabel-be (kabel be + bemenet elvagva, WiFi fent, MM leallitva), 1 ora. ☠️ ELORE ROGZITVE: ~5% ⇒ az allapot MODEM-BELSO es reboot NELKUL reszetelheto (van kerulout!); ~36% ⇒ nem a modem-mag allapota, es a reboot-teszt tovabbra is kell
      - tanú: `capture:docs/power/bringup/captures/2026-09-01_modem-core-cycle`
      - Az 1 oras ablaknak le kell futnia: inditva 10:36:33, utolso kor ~11:52, dead-man 12:06. ☠️ WiFi fent, pingelni TILOS; tiszta idozito 11:56-ra

- [x] **13.** ★★★★★ AZ ATMENET ELKAPASA (a 'mitol' kerdes): egyik mai kar sem mondja meg, mi emeli a dutyt 5%->36%-ra - csak azt, hol lakik az allapot. DUTY-LETRA az uptime menten: reboot utan 10-15 percenkent egy 600 s-os ablak, amig a lepcso be nem kovetkezik. Ez adja a MIKOR-t, es a lepcso alakja (ugras vs lassu emelkedes) a MIT-et. A tools/duty-vs-uptime.sh pont ezt kerdezi es hasznalatlanul all a repoban
      - tanú: `capture:docs/power/bringup/captures/2026-09-01_modem-core-cycle`
      - LEZARVA MASKENT: a letra nem talalt lepcsot, mert nem volt mit talalnia - a duty MAR AZ ELSO ablakban 34,7% volt, 6 perccel a boot utan. A 'MIKOR' kerdes ezzel targytalan; a keresés atkerult a 15/16. tetelre (adat-context)

- [x] **14.** ☠️ NAPLO-BISZEKCIO: 2026-08-31 06:12 (meg 5%) es 11:48 (mar 33,6%) kozott 5,6 ora telt el, amiben merések, MM-ujrainditasok es a patchelt MM telepitese tortent. A journal az eszkozon van; vegignezni, mi tortent a lepcso elott. Az elso dolog a futas utan, mert ssh kell hozza
      - tanú: `capture:docs/power/bringup/captures/2026-09-01_duty-step-journal`
      - ☠️ A naplo PERZISZTENS (/var/log/journal), a -1 boot lefedi 08-30 14:00 - 09-01 11:56-ot ⇒ a rebootom NEM semmisitette meg a bizonyitekot. A reggel rogzitett kockazat nem valosult meg, de a proceduralis tanulsag all

- [x] **15.** ★★★★★ PERZISZTENS ALLAPOT: ez az egyetlen kategoria, ami tulel daemont, WiFit, kabelt, modem-power-cyclet, rebootot ES napszakot. Ket alcsoport, es szetvalaszthatok: (a) MODEM NV / carrier config - amit 08-31 reggel valami beleirt; (b) a HALOZAT allapota erre az IMSI-re. Szetvalasztas: detach+attach (a halozati oldalt ujraalkuja), illetve a modem NV/carrier-config olvasasa qmiclivel es osszevetes azzal, amit a leads/modem-carrier-config.md mar tud
      - tanú: `capture:docs/power/bringup/captures/2026-09-01_both-slots`
      - MINDKET ALCSOPORT KIZARVA. (a) modem NV / carrier config: szerkezetileg - a PDC/NV a modem sajat taroloja, UGYANAZ mindket sloton, egy slot-valtas nem valtoztatja; es leolvasva is generikus (ROW_Commercial aktiv). (b) a halozat allapota erre az IMSI-re: a ket-slot futas kizarja - az orakulum UGYANAZOKON a cellakon 6,9%-ot ad, ahol mi 34-50%-ot. ⇒ A 30 pontos kulonbseg STACK-kulonbseg, es az alakja: azonos ebredes-utem, HETSZER hosszabb ebredesek

- [x] **16.** ★★★★★ ADAT-CONTEXT KAR: huzz fel egy bearert (mmcli --simple-connect), igazold hogy a rmnet interfesz UP es van cime, majd merd a dutyt ugyanazzal a karral. ☠️ ELORE ROGZITVE: ~5-8% ⇒ MEGVAN a D-palya kar, es a magyarazat az, hogy a modem context nelkul nem kap/nem hasznal mely DRX-et; ~34% ⇒ az adat-context sem az, es a 08-31 reggeli epizod tovabbra is magyarazatlan. ☠️ Ellenorizni kell, hogy a bearer VEGIG fent marad-e a meres alatt - egy kozben leeso context ket regimet atlagolna
      - tanú: `capture:docs/power/bringup/captures/2026-09-01_bearer-arm`
      - 48,8% MPSS (n=6, teljes 601 s alvas) az elore rogzitett 5-8% helyett - a bearer NEM kar, hanem KOLTSEG. Ket tovabbi jel: a LPASS XO-off 617-626 s/601 s ablakrol 17-20 s-re esik (az ADSP vegig ebren), es minden handshake NELKULI rtcwake kor 1-216 s utan meghal 141:smd-edge-en, mikozben mind a 6 logind kor vegigalussza a 600 s-ot. A bearer vegig fent maradt (attempts=1). Fut az A' kontroll (bearer lebontva, minden mas azonos)

- [-] **17.** ★ MM-BINARIS A/B: /usr/sbin/ModemManager.pkg.bak egy mv-re van. Csomagolt binaris visszaallitasa + ujraindites, majd ugyanaz a duty-meres. ☠️ ELORE ROGZITVE: ~5% ⇒ az uj build a kulonbseg; ~34% ⇒ nem a binaris. ☠️ Es a 08-29-i 48,9-52,7% MAR a csomagolt binarissal keszult, tehat az onmagaban nem magyarazza a harom regimet
      - REVIEW (Fable, 2026-09-01): eldobva - a 08-29-i 48,9-52,7% MAR a csomagolt binarissal keszult, tehat a bináris onmagaban nem magyarazza a regimeket; a varhato informacio ~0

- [x] **18.** ☠️ A 2026-09-01_duty-step-journal capture RAW resze hianyzik: a 186 soros ablak az eszkozon van /tmp/win.txt-ben, a masolas a meres miatt maradt el. Lehuzni es bemasolni
      - tanú: `docs/power/bringup/captures/2026-09-01_duty-step-journal/raw/journal-window-2026-08-31_06-00_11-08.txt`
      - 186 sor bemasolva, a README Raw szekcioja ratesz

- [x] **20.** ★ AZ IPA-LEAD KOZVETLEN OLVASASA, amit a 09-01-i zaras meg ad hozzatartozik: lsmod | grep ipa ; qrtr-lookup (van-e mar kliens a 49-en) ; dmesg | grep -iE 'ipa|init_driver' (nincs-e 60 s timeout). Olcso, egy ssh - de CSAK meres kozott
      - tanú: `docs/power/bringup/captures/2026-09-01_radio-context-and-ipa/raw/pmos-reads-2026-09-01_1607.txt`
      - ★ AZ IPA-HANDSHAKE KESZ: ipa2_lite betoltve, es a 49-es szolgaltatasnak MOST VAN KLIENSE - ket sor a qrtr-lookupban: '49 1 2 0 22' (modem-oldali server) es '49 1 1 1 16387' (node 1 = a mi oldalunk). Nincs INIT_DRIVER timeout a dmesgben. A 09-01-i kozvetett zaras KOZVETLENUL igazolva

- [x] **21.** ☠️ AZ UJ modem-night.sh (sav-oszlop) TELEPITESE az eszkozre - CSAK a 19. meres utan, mert a futo szkript feluliras kozben megsérulhet. Utana a 15. tetel elso olcso lepese: sav+csatorna beolvasasa MOST, es osszevetes azzal, amin a 08-31-i 5%-os epizod ment (ha megallapithato)
      - tanú: `docs/power/bringup/tools/band-ladder.sh`
      - Telepitve es hash-igazolva az eszkozon: modem-night.sh (sav/cella/TAC/RSRP oszlop), modem-window.sh (ketoldali radio+carrier-config blokk), radio-context.sh, es az UJ band-ladder.sh. Mind a 4 md5 egyezik a hosttal

- [x] **22.** ★★ AZ ADSP-MECHANIZMUS: mi tartja ebren a q6-ot futo ModemManagerrel? Olcso olvasas egy booton belul, daemon le/fel: /sys/kernel/debug/asoc, apr/q6 kliensek, ill. a qrtr port-lista. Ha egy nyitott APR/q6 session a valasz, az korrektsegi hiba is lehet
      - tanú: `docs/power/bringup/captures/2026-09-01_radio-context-and-ipa/raw/adsp-ab-awake-1738.txt`
      - ☠️ NEGATIV, ES PONTOSIT: EBREN a daemon NEM szamit - mind a HAROM leg (A futo / B leallitva / A' futo, 90 s-onkent, kapuzva) LPASS XO-off 0,0 s es NULLA shutdown. Az ADSP ebren soha nem alszik, daemonnal vagy nelkule. ⇒ a mai '121 kores' lelet ERVENYES marad, de SZUKEBB, mint ahogy kimondtam: a daemon hatasa CSAK ALVASON AT letezik. Nem egy allandoan nyitott q6-session a magyarazat - valami a SUSPEND-uthoz kotott. ☠️ A qrtr node-1 lista mindharom labban 5 elem: a MM kliens, nem szerver, ez a muszer NEM kulonboztet

- [x] **23.** ★★★★★ ORAKULUM-UJRAMERES MA, SLOT-VALTASSAL - a review legnagyobb lelete: a 6,1% egy NAPOKKAL EZELOTTI szam, es az egesz 'perzisztens allapot' vadaszat arra epul, hogy ma is igaz. Ugyanazon a delelotton mindket slot, AZONOS muszerkeszlet: XO-duty + ebredes-hossz, sav/cella/RSRP, PDC aktiv config, system-selection-preference, IMS-reg, CS+PS attach. ☠️ ELORE ROGZITVE: orakulum ma is ~6% ugyanazon a cellan ⇒ valodi stack/NV-diff es a diff ott olvashato ahol allunk; orakulum ma ~30+% ⇒ A REFERENCIA ELAVULT, a perzisztens-allapot vadaszat LEALL, es a kerdes az lesz, melyik halozati feltetel adja az olcso regime-et es kerhet-e ilyet a UE. ☠️ FELHASZNALOI JOVAHAGYAS kell (slot-valtas)
      - tanú: `capture:docs/power/bringup/captures/2026-09-01_both-slots`
      - ★★★★★ A REFERENCIA EL: az orakulum MA 6,9% (a 08-28-i 6,1% reprodukalodik), ugyanazzal a muszerrel, 27 percen belul a pmOS 37,4%-a utan. ⇒ a stack-kulonbseg VALODI, nem elavult szam. ☠️ ES A SAV NEM MAGYARAZZA: az orakulum ablaka ATFOGJA MINDKET cellat (1470722 az olcso eutran-20, 1470762 a draga eutran-1) es 6,9%-ot ad mindkettovel; a sav 17 pontot er a MI stackunkon BELUL, a 30 pontos stack-kulonbsegbol semmit

- [x] **24.** ★★★★ SAV-LOCK LETRA: --nas-set-system-selection-preference sav-lockkal egy-egy ablak eutran-1 / -3 / -20-on. Ez az EGYETLEN ismert, KIKENYSZERITHETO nagy hatas (13,6 pp meres a repoban), es az eutran-20 (800 MHz) SOHA nem lett merve. Olcso, reboot-mentes. ☠️ Restore 'any'-vel, nem a kiirt listaval
      - tanú: `capture:docs/power/bringup/captures/2026-09-01_band-ladder`
      - ★★★★★ A SAV 17 PONTOT ER: eutran-1 48,8% es 51,6% (A-A' zarojel tart), eutran-3 31,8%, eutran-20 34,1% - egy booton belul, 4x600 s, minden leg a kert savon regisztralt. Reprodukalja a repo korabbi 50,0 vs 36,4-et mas napon, mas cellan. ★★ Es az ARAM ugyanezt mondja erosebben: 147 mA (eutran-1 atlag) vs 93 mA (eutran-20) = 54 mA, tobb mint amennyit a duty-modell josol (21 mA) ⇒ a draga sav tobbe kerul a duty-reszenel. ☠️ Az ebredes UTEME lapos (35,5-36,6/s) - megint a HOSSZ valtozik. ☠️ A sav egyik savon SEM megy 5% koze ⇒ a 08-31-i epizodot NEM magyarazza

- [x] **25.** ★★★ A 15. TETEL KONKRET MUSZEREI (egy ssh-menetben, mindket sloton ha mar slot-valtas van): PDC aktiv carrier-config, system-selection-preference (ha GSM/WCDMA benne van, a UE IRAT-t mer minden DRX-ciklusban = ebredes-hossz!), IMS-reg allapot (a modem vegtelen IMS-PDN retry-ba ragadhat - carrier-config vezerli, tehat pont a 'mindent tulel' profil), EF_FPLMN a SIM-rol (--uim-read-transparent)
      - tanú: `docs/power/bringup/captures/2026-09-01_radio-context-and-ipa/raw/pmos-nv-ims-fplmn-1730.txt`
      - Mind a negy muszer leolvasva. PDC: 25 tarolt software-config, AKTIV a 'ROW_Commercial' (v0x7010804) - generikus Rest-Of-World profil, NEM operator-specifikus; platform-config 'SR_DSDS-LA-7+7_mode-SDM632' INAKTIV. IMS: mindharom szolgaltatas ELUTASIT (imsa/ims: InvalidOperation, imsp: Internal) ⇒ pmOS-en nincs IMS-regisztracio. EF_FPLMN: EGY tiltott PLMN, 216-30 (Yettel HU) - nem a mi operatorunk (216-70), a tobbi ures. System-selection-preference mar a 16:07-es olvasasban

- [x] **26.** ★★ AZ EBREDES-UTEM AZ ORAKULUMON: a 2,4/s XO-elhagyas RAT-fuggetlen nalunk; ha az orakulum is 2,4/s-sel ebred csak rovidebben, a mechanizmus AZONOS es a kerdes tisztan 'mitol hosszu az ebredes'; ha ritkabban, akkor eDRX/hosszabb paging-ciklust alkudik ki ⇒ config-diff. A 23. tetel meresevel egy menetben
      - tanú: `capture:docs/power/bringup/captures/2026-09-01_both-slots`
      - ★★ AZ EBREDES-UTEM KERESZT-STACK MERVE: az orakulum TOBBSZOR ebred (3,14/s vs 2,38/s), megis 5x olcsobb ⇒ a kulonbseg TELJES EGESZEBEN az ebredes HOSSZA: 22 ms/ebredes az orakulumon, 157 ms nalunk, HETSZERES. Ez a problema legelesebb megfogalmazasa eddig

- [-] **27.** ★ BEARAZATLAN ANOMALIA (lead): mm=stopped mellett az ADSP VEGIGALSZIK, megis +14 mA a rendszer ⇒ valami mas, MM-hianyhoz kotott fogyaszto megeszi az ADSP-megtakaritast is. Ennek meg neve sincs. Ez arazza be a 22. tetelt is: mennyit er mA-ban a LPASS ebren-lete?
      - DOBVA (Fable #15): az uj celfuggveny mellett nem termel dontest. Ami emiatt kimondatlan marad: 'tudjuk, mi a +14 mA mm=stopped alatt'. A padlo-bontas a KOVETKEZO kar kerdese, nem a lezarase.

- [-] **28.** ★ A PADLO NEM ELENGEDVE, csak elhalasztva: a sajat modell szerint a TELJES siker (6,1% duty) = 41,4 + 133x0,061 = 49-50 mA, PONT a celon, NULLA tartalekkal. Az UT ~30 mA-es padloja szerint ott is van ~10 mA. A duty-front lezarasa utan a padlo a kovetkezo front
      - DOBVA (Fable #15): kimondatlan marad, hogy 'mi eszi a ~40 mA-es padlot'. A tengelymetszet-modell amugy is nyugdijas - a B-allapotot MAR KOZVETLENUL merjuk, nem duty=0-ra extrapolalva.

- [x] **29.** ★★★★★ ☠️ A BEARER-LELET UJRA VESZELYBEN: a 09-01-i +15 pp (33,4-36,8% -> 48,8%) EPP AKKORA, mint a repo sajat sav-hatasa (eutran-3 36,4% -> eutran-1 50,0%), es a bearer-futas savja NINCS ROGZITVE. Ha a letra ma reprodukalja a sav-hatast, a bearer-magyarazatot vissza kell vonni es a merest a savra kontrollalva megismetelni
      - tanú: `capture:docs/power/bringup/captures/2026-09-01_band-ladder`
      - A bearer-lelet MEGDOLT: a 48,8% PONTOSAN az eutran-1 szama, es minden mas leg 31,8-34,1%. A bearer-futas savja nincs rogzitve ⇒ a kar megkulonboztethetetlen egy sav-valtastol. Meg kell ismetelni SAV-LOCKKAL mindket labon

- [x] **32.** ★★★★★ A UTODJA A 15-nek: MIT KER AZ AP A MODEMTOL? A kulonbseg csak a futasideju QMI-forgalomban lehet. Ket resz: (a) a MI oldalunk teljes QMI-kerés-halmaza egy nyugodt percben (mar van muszer: wake-qmi.sh tracepointjai); (b) a vendor oldal - az UT-n a QMI a smdcntl-en megy, a qrtr-tracing NEM latja, tehat vagy diag, vagy a vendor forras olvasasa (hadk22/kernel/fairphone/sdm632 + a rild/qmuxd). ☠️ Elore rogzitve: ha talalunk egy periodikus kerest, ami minden paging-ciklus utan fenntartja a modemet, az a 157 ms magyarazata
      - tanú: `capture:docs/power/bringup/captures/2026-09-01_qmi-census-awake`
      - ★★★★★ AZ AP NINCS BENNE AZ EBREDESEKBEN. 300 s a draga allapotban (eutran-1, cella 1470762, MPSS 50,9%): a modem->AP QRTR-forgalom OSSZESEN 14 uzenet (0,047/s), MIND ugyanaz - NAS msg 81 'Indication Signal Info', kb. 21 masodpercenkent -, az AP->modem irany 4 (0,013/s). Kozben a modem ~770-szer ebredt. ⇒ az ebredesek legfeljebb 2,3%-ahoz tartozik BARMILYEN AP-modem uzenet. ★ Es az rmtfs (pid 779, FUT) 300 s alatt 0,00 s CPU-t hasznalt ⇒ a modem EFS-forgalma NEM megy, tehat a Fable-fele rmtfs-jelolt is halott. ☠️ AMIT NEM ZAR KI: a nem-QMI AP-interakciot (RPM sleep-set szavazatok, interconnect/busz, smp2p handshake) es barmit a modemen BELUL. A szonda a qrtr_endpoint_post-on ul: ami nem a QRTR-en megy, azt nem latja

- [-] **33.** ★★ A PONTOSITOTT ADSP-KERDES: mi tortenik az ADSP-vel a SUSPEND alatt, ha a ModemManager fut? A kulonbseg csak ott letezik. Jelolt: a daemon suspend-handshake-je (terse) valamit felebreszt vagy nyitva hagy a freeze pillanataban. Muszer: LPASS-szamlalo a suspend ket oldalan, MM futo/leallitott karral, UGYANABBAN a bootban - ez mar a modem-night.sh formatuma, csak 2x2 kor kell hozza
      - DOBVA (Fable #15): kimondatlan marad az ADSP-suspend attribucio. Diagnozis dontes nelkul - es 45 percet kert egy olyan telefontol, aminek a teszt-ideje mostantol koltseg.

- [x] **34.** ★★★★★ RAT-LISTA (IRAT) LETRA - a review jelolteje, es a legjobb magyarazat-jelolt a HETSZERES ebredes-hosszra: semmi, amit az AP pollozik, nem fut 2,4 Hz-en, tehat a tobblet-ido a modem MUNKAJA paging-alkalmankent, es a mi mode preference-unk MINDEN RAT-ot felsorol (cdma-1x, cdma-1xevdo, gsm, umts, lte, td-scdma). Ez AP-oldali futasideju allapot - a daemon irja -, tehat pont olyan, amit egy slot-valtas eloallithat. Letra: lte / gsm|umts|lte / lte-ismetles, 600 s-onkent. ☠️ ELORE ROGZITVE: ha az lte-only erdemben alacsonyabb dutyt ad, MEGVAN a mechanizmus; ha nem, az IRAT kiesik. ☠️ Az lte-only alatt CSFB-hivas nem jon at (nincs IMS) - meresre jo, szallithato defaultnak nem
      - tanú: `capture:docs/power/bringup/captures/2026-09-01_mode-ladder`
      - ★★★★★ A RAT-LISTA KIESIK. A SAV-ILLESZTETT par eutran-1/cella 1470762-n: 'gsm|umts|lte' 49,8% / 142 mA, 'lte'-only 49,5% / 145 mA - AZONOS. Es a sav-letra UGYANEZEN a savon a TELJES 'mergezett' listaval (cdma-1x, cdma-1xevdo, gsm, umts, lte, td-scdma) 48,8 es 51,6%-ot adott. NEGY kulonbozo mode preference ugyanazon a savon: 48,8 / 51,6 / 49,8 / 49,5 - mind a ~3 pontos ismetelhetosegen belul. ⇒ sem az IRAT-meres, sem a fantom-RAT-ok (CDMA/TD-SCDMA acquisition-scan) nem magyarazzak a hetszeres ebredes-hosszt. ☠️ Az 1. lab (lte, eutran-3, 38,4%) NEM osszevetheto a 2.-kal: a sav kozben elmozdult - epp az a kovarians, ami a masodik visszavonasomat okozta

- [x] **35.** ★★ ALLANDO GYAKORLAT (felhasznaloi keres 2026-09-01): IDONKENT KONZULTALJ FABLE-LEL (Agent, model=fable), ne csak kulon kerésre. Termeszetes ellenorzopontok: amikor egy meres eredmenye atrendezi a tervet, amikor visszavonok valamit, es MIELOTT egy draga (ejszaka-hosszu vagy slot-valtasos) meresbe kezdek. ☠️ A subagent FRISS kontextussal indul - a promptba bele kell tenni a celt, a mert tenyeket szamokkal, a visszavont allitasokat es a konkret kerdest. ☠️ A valasz nem automatikusan igaz: merd, ne vedd at
      - tanú: `/home/fp3/.claude/projects/-mnt-1TB-Fp3-Sailfish/memory/feedback_consult_fable.md`
      - Beepitve: memoria-bejegyzes + MEMORY.md sor, es a review #2 EL IS INDULT a mai leletekre (sav-letra, orakulum-ujrameres, ket visszavonas, MM CHANGE_DURATION_PERMANENT). Ot kerdes: mi a kovetkezo mechanizmus-jelolt ha az IRAT kiesik; mit lehet a MEGLEVO adatbol kiolvasni uj meres nelkul; eletkepes-e a 'ki bootolt utoljara' NV-nyom a 34 perces 5%-os epizodra; van-e meg nem mert kovarians; mit ne csinaljak

- [x] **36.** ★ A Fable-konzultacio gepesitese: autonomy.cjs 'consulted' verb + Stop-kapu (6 eredmeny vagy 4 ora), a SendMessage-forma ugyanannak az agentnek
      - tanú: `commit:817cffc`
      - kapu 4 agon vegigmerve: tuzel / NEM tuzel ismetlesre / NEM tuzel consulted utan / ujra tuzel 6 eredmennyel, mar a SendMessage-formaval

- [x] **37.** ★★★ 1 Hz XO-idosor MINDEN labban (MPSS delta(xo-off)/s): elkuloniti a 'sima 157 ms/ebredes' es a 'masodperces burst-ok' esetet - ez donti el, hogy per-paging munka vagy acquisition-scan; ES visszamenoleg allapot-atmenet-detektorra valtja minden labunkat
      - tanú: `capture:docs/power/bringup/captures/2026-09-01_xo-series`
      - ★★★★ A BURST-HIPOTEZIS KIESIK, de nem a CV-bol. A javitott 600 s (eutran-1, cella 1470762): duty 50,6% - PONTOSAN a sav-letra eutran-1 erteke (48,8/51,6/49,8/49,5), tehat a muszer keresztvalidalt. 1543 ebredes 600 s alatt (2,57/s), 304 s ebren => 197 ms/ebredes, egyezik a 157 ms nagysagrenddel. A CV 0,40 a kuszobeim kozott van (UNDECIDED - kimondva, nem elkenve), DE a SZERKEZET dont: leghosszabb telitett futam 2 s, run mass 0,09, es NULLA csendes masodperc - a legcsendesebb masodperc is 170 ms ebrenletet visz, 581-bol csak 64 van 250 ms alatt. Tobbmasodperces acquisition-scan tehat NINCS. ☠️ 1 Hz felbontas: ez csak a ~1-2 s-nal hosszabb burstot zarja ki, a masodpercen BELULI szerkezetrol semmit nem mond

- [-] **38.** ★★ NO-OP PREFERENCE-IRAS KONTROLL: a jelenlegi teljes pref visszairasa, 600 s elotte/utana. Ha egy pusztan formalis NAS-iras atbillenti draga->olcso, akkor MINDEN letra-eredmeny latszat
      - Fable #4 alapjan lefokozva: negy egymas utani NAS-iras mar mind a draga allapotban landolt, tehat az informacio nagy resze megvan; a maradek egy jovobeli letra INGYEN labjakent jon, nem kulon 20 perces sessionkent

- [-] **39.** ★★ ORAKULUM-PREF KIOLVASAS: kozvetlenul egy UT-session utan pmOS boot MM-maszkolva, '--nas-get-system-selection-preference' BARMILYEN iras elott. Ha az orakulum UGYANAZZAL a mergezett listaval olcso, a phantom-RAT hipotezis halott
      - DOBVA (Fable #15): SEMMI nem veszik el - a tetel sajat jegyzete szerint az indoka mar halott (a fantom-RAT hipotezist a mode-letra kozvetlenul megmerte). Az ondeklaraltan halott tetel maradjon halott.

- [x] **40.** Kovarians-bovites: pref-visszaolvasas lab elejen ES vegen; cella/sav/RSRP KOZBEN is (nem csak a vegeken); journal/MM-esemeny szelet a lab ablakara; CS-domain regisztracios allapot
      - tanú: `commit:535d4d3`
      - leg-covariates.sh: egysoros kovarians (state, CS, PS, mode-pref, sav, csatorna, cella, TAC, RSRP, RSRQ, SNR), --watch modban 60 s-onkent; mindket letra most MENET KOZBEN is mintaz, plusz labankent 1 Hz XO-idosor. ☠️ A mintavetel ebreszti a modemet - ezert MINDEN labban azonos intervallum, es alvo censusban tilos. Telepites a futo meres utan

- [x] **42.** ★★★★★ RRC-ALLAPOT: a draga = RRC_CONNECTED cDRX-szel, az olcso = RRC_IDLE camped? Ez a tankonyvi mechanizmus pont erre a mikroszerkezetre (kevesebb de hosszu ebredes, ~200 ms, nulla csendes masodperc), bistabil egy booton belul, kozombos a mode-preference-re ES a cpuidle-re, alig kell hozza QMI. ☠️ MA ESTE MERVE: rmnet_ipa0 DOWN, rx=0 tx=0, default route WiFin ⇒ uplink adat-forgalom NINCS, megis draga allapot vagyunk - ez az uplink-valtozatot gyengiti, de az RRC-t magat nem donti el. Muszer: TX-in-traffic mintavetel, es ha kell diag
      - tanú: `capture:docs/power/bringup/captures/2026-09-02_diag-ota-pmos`
      - ★★★★★ MEGVALASZOLVA, es igen: a draga allapot RRC_CONNECTED. Nem kovetkeztetve, hanem az OTA-logbol: 391 RRC-uzenet 120 s alatt, es 22 teljes PDN-fel/le ciklus, mindegyik RRC-kapcsolatot igenyel. Az aritmetika zarja: 3,14/s = 1/320 ms = a paging DRX ciklus (orakulum ES a mi olcso allapotunk = IDLE camped, 16-22 ms/ebredes); 2,47/s @ 142-197 ms = connected-mode DRX. A 'kevesebb de hosszabb ebredes' rejtelye ezzel megszunt: a wake-ek a kapcsolat haztartasa

- [x] **43.** ★★★ RSRP-KAR ATTENUACIOVAL (Fable #5 c): eutran-1 lockolva, az RSRP-t FIZIKAILAG rontani (folia/femdoboz) lepcsokben, 600 s/lepcso, a kovarians-mintavevo igazolja hogy a cella NEM valtozott. Igy a sav/cella-konfund konstrukciobol ki van vagva. ☠️ -110 RSRP folott maradni, kulonben reselection/RLF es a lab ervenytelen
      - tanú: `commit:9a62d4a`
      - A 08-31 elotti journal VEGLEGESEN ELVESZETT - nem vacuum miatt: / 85%-on, journald SystemKeepFree=15% (~360 MB) > a szabad 331 MB => folyamatosan vagja a tortenetet (--list-boots: EGYETLEN boot, legregebbi sor ma 17:10). Amit meg lehetett menteni: az olcso ablak 16 h uptime-on futott ES a B-labban MM FUTOTT 4,9%-nal => az olcso allapot nem 'a daemon ki volt kapcsolva'

- [x] **44.** ☠️ AUDIT: a STATUS.md/terv tobbi LPASS- es APSS-allitasat is at kell nezni ugyanezzel a disambiguacios szaballyal (enter vs exit, cores, fagyott count). Ma HAROM helyen bizonyult invertaltnak ugyanaz az olvasat (adsp-ab.sh legjei, xo-series.sh elso futasa, es a both-slots LPASS-sora). Ahol 'X% ebren' all NULLA shutdown mellett, ott a szam ertelmetlen amig a statikus mezoket meg nem neztem
      - tanú: `docs/STATUS.md`
      - AUDIT KESZ a STATUS.md ket kezzel irt tablajara. (1) A 2026-09-01 both-slots sora JAVITVA a nyers adatbol: pmOS LPASS 0 ebredes / vegig alva, orakulum 8512 ebredes (14,19/s, 2,2 ms) = 3,0% ebren - az irany forditott volt. (2) A 2026-08-24-es harom-ablakos tabla LPASS-sora MEGJELOLVE ismeretlennek: ugyanazzal az invertalt szaballyal keszult, de a nyers statikus mezoit nem neztem meg, ezert NEM allitok helyette korrigalt szamot - csak azt, hogy nem hihetunk neki. ☠️ A leads/lpass-mclk-gate-state.md es rpm-sleep-set.md NEM erintett: azok a 'cores=0x1' mezot hasznaljak, ami epp a megkulonbozteto

- [x] **45.** 44 STRUKTURALIS: EGY kanonikus RPM-master-stats olvaso (nojon bele a tools/rpmstats_raw.py), minden eszkoz azt hivja; + selftest ami grepeli a tools/-t awk/grep-re ami rpm_master_stats-ot erint a kanonikus olvason KIVUL. Indok: negy azonos csaladu muszer-hiba (tick, INT_MAX-clamp, hianyzo strtonum, '@' vs ':') mind magabiztos ROSSZ szamot nyomtatott
      - tanú: `commit:f76fbe4`
      - ★★★ KANONIKUS RPM-OLVASO KESZ es VALIDALVA: tools/rpm_master_stats.py mindket formatumot olvassa (mainline decimalis '@'/':' + downstream hex), es SOHA nem ad dutyt nulla deltara - a statikus mezokkel dont (enter>exit => lent), kulonben UNDECIDABLE. Harom archiv capture-on reprodukalja a kezzel levezetett szamokat: olcso 5,1%/3,14/16,2ms, draga 35,8%/2,46/145,5ms, orakulum 6,3%/3,15/20,0ms + LPASS 2,9%/13,71/2,1ms. --tagged mod a modem-window.sh BEFORE/AFTER fajljaira

- [x] **46.** 45 STRUKTURALIS: golden-file ontesztek a fp3-selftest batteriaba - egy OLCSO, egy DRAGA es egy INVERZIOS-CSAPDA capture rogzitve, a kanonikus olvasonak mindharomra a lejegyzett valaszt kell adnia. Egy parser-regresszio igy nem egy ejszakaba kerul, hanem egy teszt-futasba
      - tanú: `commit:f76fbe4`
      - ★★ GOLDEN-FILE ONTESZT KESZ: selftest-rpm-readers.sh - 7 golden eset + az inverzios csapda MINDKET iranyban EGY osszevetesben (pmOS LPASS alszik / orakulum LPASS 2,9% ebren - ez a par jelent meg forditva) + 'nincs masodik olvaso' or, a 29 meglevo direkt parser befagyasztva (a lista csak csokkenhet). ☠️ MINDKET ort MEGMUTATTAM MUKODES KOZBEN: guard 2b telepitett hamis parsert, guard 1c rossz ablakhosszt. ☠️ Host-oldali teszt, NEM a device-batteriaban: a golden capture-ok a repoban vannak

- [x] **47.** 46 PRONTO passzazsr: minden jovobeli negy-master ablakban rogzitsd a TRANSZPORTOT (ssh-ut, wlan0 oper/carrier, rfkill) es nezd az elore lejegyzett josolatot: ha MPSS olcsoba megy, a PRONTO ~17-19%-ra es ~20 ms-ra ter vissza. Onallo ablakot NE kolts ra
      - tanú: `capture:docs/power/bringup/captures/2026-09-02_ims-ladder`
      - NEGATIV, INGYEN: a PRONTO 24,9/25,5/25,7% es 27,9/28,9/29,1 ms maradt, mikozben az MPSS 40 pp-t mozgott => a 'ha az MPSS olcsoba megy, a PRONTO ~17-19%-ra ter vissza' josolat MEGDOLT; a WiFi-mag dutyjat a sajat transzportja szabja meg, nem a modem allapota

- [x] **48.** 47 IMS-olvasas libqmi-vel: ~30 soros program ami EGY qrtr-kliensen bindol (IMSA Bind) majd ugyanazon a kliensen kerdez (Get Registration Status). A qmicli-vel nem megy: a qrtr CID nem eli tul a processzt, es a qmicli nem enged ket IMSA-akciot egy futasban
      - tanú: `capture:docs/power/bringup/captures/2026-09-02_diag-ota-pmos`
      - TARGYTALAN A BINDOLT IMS-OLVASAS NELKUL IS: a diag OTA-log kozvetlenul megmutatja, hogy a modem IMS-PDN-t ker (APN 'ims') 8,4 masodpercenkent - ez tobb, mint amit az imsa-regisztracios statusz adott volna. Az ims-state.py megmarad altalanos bindolt-QMI muszernek

- [x] **49.** 48 JOURNAL MINT EROFORRAS: a / 85%-on all, a journald SystemKeepFree=15% (~360 MB) > a szabad 331 MB, ezert FOLYAMATOSAN vagja a tortenetet - a 08-31 elotti journal EMIATT veszett el, nem vacuum miatt. Vagy szabaditsd fel a helyet 15% fole, vagy minden journal-bizonyitekot MEG AZNAP ments a repoba, a kerdesnel szelesebb ablakkal
      - tanú: `commit:41ff051`
      - ☠️ A SAJAT MAGYARAZATOM DOLT MEG: nem a SystemKeepFree 15%-a vagta a journalt, hanem OT sajat drop-in cap (20/30/32/30 MB) negy kulonbozo napról; a systemd nevsorban merge-el es az UTOLSO nyer, tehat a julius 13-i cap.conf dontott, mert a 'c' a '0' utan van. A journald maga mondta ki: 'max 30M'. Az en 10- prefixu fajlom SOHA nem ervenyesult volna - csak azert bukott ki, mert a merge-listaban ket sorral lejjebb ott allt a 30M. Atnevezve zz-fp3-retention.conf-ra, igazolva: 'max 96M, 74.4M free'. Semmi nem lett torolve. TANULSAG: kerdezd meg a komponenst, milyen limitet tart be - ne vezesd le a dokumentalt defaultbol

- [x] **51.** ★★ RPM SLEEP-SET (a masodik forras-lead): a vendor kulon szavaz az active es a sleep setre (rpm-smd.c + az egesz msm_bus stack); a mainline smd-rpm.c ISMERI a fogalmat (a request active/sleep state flageket visz), de hogy a mi drivereink toltik-e valaha a sleep setet, az kulon kerdes. Alacsonyabb prior egy PER-EBREDESES 125 ms-os koltsegre, ezert a masodik
      - tanú: `docs/power/bringup/leads/rpm-sleep-set.md`
      - FORRASBOL MEGVALASZOLVA es SZUKITVE: a 'mainline nem tolti a sleep setet' allitas CSAK a regulatorokra igaz. A clk-smd-rpm.c FELTETEL NELKUL ir mindket allapotba (234/243, 261/275, 445/453), az icc-rpm.c kulon aggregal active_rate-et es sleep_rate-et es mindkettot kiirja, es az msm8953 interconnect provider LETEZIK, be van kapcsolva (CONFIG_INTERCONNECT_QCOM_MSM8953=y) es a DT-ben 34 hivatkozas van ra. A regulator-lyuk ket lezarasa MAR ELERHETO es mindketto default OFF: a sajat both_sets=1 modul-parameterunk, es a per-rail regulator-state-mem DT-node (grep: EGY SINCS). ☠️ ES NEM EZ A MODEM-LEAD: az RPM sleep set az AP power-collapse-akor lep eletbe, a 30 pontos res viszont EBREN mert 600 s-os ablakokban van - ott mindket rendszer az active setet hasznalja. A lead ertekes marad a vlow/suspend fronton, de ide nem tartozik

- [x] **52.** ★★★★★ A MODEM FELIRATKOZASI MASZKJA - a firmware-oldal MERHETO flashelés nelkul: a notify_other_smsm() csak azokra a bitekre ebreszti a modemet, amikre a modem FELIRATKOZOTT, es a feliratkozasok ugyanabban a megosztott memoriaban vannak (SMEM_SMSM_CPU_INTR_MASK), amit a mainline smsm.c mar mapel. Olvasd ki a MODEM maszkjat az APPS bejegyzesre, es nezd a 12. bitet: BEALLITVA => a firmware kerte hogy szoljanak, a patch merese ERTELMES; NULLA => a bit nem is tudja ebreszteni, es az 50. tetel HALOTT egyetlen ablak elkoltese nelkul. Kell hozza egy olvaso (debugfs a debug-retegben, vagy /dev/mem + SMEM-tabla bejaras, mint a rpmstats_raw.py). ☠️ EZT AZ A/B ELE kell tenni
      - tanú: `capture:docs/power/bringup/captures/2026-09-01_smsm-subscription-mask`
      - ★★★★★ MERVE, 30 masodperc alatt, ABLAK NELKUL - es MEGBUKTATJA a sajat leademet a modemre. A MODEM maszkja az APPS bejegyzes felett 0x00800000 = CSAK a 23. bit; a 12-re NEM iratkozott fel => a bit nem tudja ebreszteni es nem valtoztathat az ebredesenkenti munkajan. Az APPS allapotvektor 0x00000600, a 12. bit tenyleg NULLA - a forras-olvasat ezen fele helyes volt. ★ ES UGYANAZ A TABLA ATADJA A BITET AZ IGAZI GAZDAJANAK: a Q6/ADSP maszkja 0x00001000, azaz PONTOSAN es KIZAROLAG a 12. bit. Ez fuggetlen transzporton ugyanoda fut ki, mint a 08-31-i smp2p-sleepstate-missing lead (remote-pid 2 = ADSP). A ket commit es az r80 csomag NEM veszett karba: ugyanaz a patch, mas elore rogzitett olvasat - most a LPASS-szamlalot nezi suspenden at (33. tetel), nem az MPSS dutyt

- [x] **56.** ★★★★★ AZ INTERVENCIO (elore rogzitve a capture-ben): allitsd meg az IMS-PDN hurkot es merd a dutyt. 1. kar: az AP FOGJA a PDN-t (mmcli --simple-connect apn=ims) - FUT; 2. kar ha ez nem eleg: az ims-profilok letiltasa/torlese. ELORE ROGZITVE: a duty ~5-6% fele esik ES az ebredes-utem 3,14/s-re ugrik => MEGNEVEZVE ES MEGERSITVE; valtozatlan duty => a hurok utas, a capture oksagi allitasa hamis
      - tanú: `capture:docs/power/bringup/captures/2026-09-02_diag-ota-pmos`
      - ☠️ AZ IMS-OFF DUTY-ABLAK KONTAMINALT: MPSS 0 ebredes 600 s alatt (exit>enter => VEGIG EBREN, nem alvas). A modem >766 s ota egyfolytaban ebren. Ket vilag: (a) az IMS-off tette ilyenne, (b) a DIAG LOG MASK modem-oldali allapot, ami TULELI a capture-processzt - nincs fogyaszto, de a modem tovabb general logot. A (b) a valoszinubb es MERHETO: remoteproc-restart torli. ☠️ Emellett a sav KOZBEN elmozdult (BEFORE eutran-20/1470722, AFTER eutran-1/1470762) - pont az a kovarians, ami mar ketszer megbuktatott. A meresi allitas VISSZATARTVA

- [x] **57.** ★★★★★ SAV-PINELT IMS A/B/A' LETRA (ims-ab.sh 600, futASBAN, inditva 00:35, ~01:15): modem-restart (torli a diag-maszkokat ES megvalaszolja a perzisztenciat) -> eutran-1 pin -> A=IMS on, B=IMS off, A'=IMS on, mind 600 s. ELORE ROGZITVE: B >=10 pp-vel olcsobb A es A' atlaganal => a hurok OKSAGI; A≈B≈A' => a hurok utas es a capture oksagi allitasat vissza kell vonni; A'≠A => drift-terhelt letra, semmit nem mond. ☠️ Fable #12: a letranak NINCS mechanizmus-tanuja, csak dutyje - a lab-parositast utolag diag-gal kell igazolni
      - tanú: `capture:docs/power/bringup/captures/2026-09-02_ims-ladder`
      - ★★★★★ AZ ELORE ROGZITETT JOSLAT KETSZERESEN BEJOTT: A=44,5% / B(IMS off)=4,8% / A'=46,8%, mind eutran-1/cella 1470762/RSRP -93 dBm, egy booton belul, labankent visszaolvasott IMS-vektorral. B a 45,7%-os A/A' atlagtol 40,9 pp-vel lejjebb (a kuszob 10 volt), A' 2,3 pp-re A-tol => nincs drift. A MASODIK, FUGGETLEN alairas az ebredes-utem: 3,13/s = 1/320 ms = a paging DRX, 15,4 ms/ebredes => RRC_IDLE camped, azaz az ORAKULUM ujjlenyomata (6,9%/3,15/20 ms) a MI stackunkon, kicsit olcsobban. ☠️ Az IMS-iras TULELI a modem-firmware-restartot (restart utan minden kapcsolo False volt barmilyen iras elott) => a megosztott-NV figyelmeztetes az orakulum-slotra MEGEROSITVE, nem torolve

- [-] **58.** ★★★★★ SAV-PINELT IMS A/B/A' LETRA (ims-ab.sh 600, FUT, inditva 00:35, ~01:15-re kesz): modem-restart (torli a diag-maszkokat ES megvalaszolja a perzisztenciat) -> eutran-1 pin -> A=IMS on, B=IMS off, A'=IMS on, mind 600 s. ELORE ROGZITVE: B >=10 pp-vel olcsobb A es A' atlaganal => a hurok OKSAGI; A~B~A' => a hurok utas es a capture oksagi allitasat vissza kell vonni; A' erdemben mas mint A => drift-terhelt letra. ☠️ Fable #12: a letranak NINCS mechanizmus-tanuja, csak dutyje; a lab-parositast utolag kell igazolni
      - duplikatum: az 57. ugyanez

- [x] **59.** ★★ IMS-KAPCSOLOK TELJES VEKTORANAK ROGZITESE a letra utan (Fable #12 d): a beavatkozas elotti read CSAK NEGY kapcsolot jegyzett fel (voice/video/SMS/UT), a tobbi (VoWiFi, USSD, presence, RCS, XDM, autoconfig) SOHA nem lett leirva ⇒ a visszaallitas azokra csak best-effort. Uj baseline read-back mentese fajlba, es a both-slots figyelmeztetes torlese VAGY megerositese aszerint, hogy az iras tulelte-e a modem-restartot
      - tanú: `capture:docs/power/bringup/captures/2026-09-02_ims-ladder`
      - A TELJES VEKTOR ROGZITVE labankent (raw/log.txt): A/A' = voice/VoWiFi/video/SMS/UT True, USSD False; B = mind False. A restore visszaolvasva. ☠️ A both-slots figyelmeztetes MEGEROSITVE (nem torolve): az iras tulelte a firmware-restartot. ☠️ Uj apro anomalia: az USSD akkor is False-t olvas, amikor True-t irtunk - harmadik kapcsolo, aminek a settere es gettere nem felel meg egymasnak; rogzitve, nem magyarazva

- [x] **60.** ★★★★★ ELERHETOSEG-TESZT IMS=off MELLETT - a cel masik fele ('UT reagalasi parameterei mellett'), es a szallithatosag KAPUJA: (a) bejovo hivas CSENG-e es felveheto-e, (b) bejovo SMS megerkezik-e, (c) kimeno hivas. A modem 'registered' es CS-attached IMS nelkul is, es ezen az eszkozon a hivas amugy is CSFB - de ez KOVETKEZTETES, nem meres. ☠️ Amig ez nincs meg, az IMS-off NEM szallithato default, barmit mond a duty
      - tanú: `capture:docs/power/bringup/captures/2026-09-02_reachability-ims-off`
      - LEZARVA A BEJOVO IRANYRA: csenges (503 ms) + felvett hivas (329 ms, 57 s aktiv, hang mindket iranyban) + bejovo SMS (~5 s, SGs-visszaeses). Hatra: kimeno irany, reboot-ateles, korona-teszt

- [x] **61.** ★★★★★ A mA-FRONT: kozvetlen arammeres a MOST MAR PARANCSRA ELOALLITHATO olcso allapotban (IMS off, ~4,8% duty) - KABEL KI, AP alszik, ugyanaz a sleep-night/modem-night kar, mint amivel a 86 mA es a 41,4 mA-es tengelymetszet keszult. ☠️ A letra HAROM labja kabelen, ebren allo AP-vel futott, tehat a feszultsegoszlopa semmit nem ar; a modell 48 mA-t josol, de >=15 mA strukturalis maradekkal. EZ zarja be vagy nyitja ki az 50 mA-es celt
      - tanú: `capture:docs/power/bringup/captures/2026-09-02_ims-ma`
      - ★★★★ A CENZUS LEFUTOTT (02:21-04:02, akkun, AP rtcwake-kel alva). Draga (IMS on): MPSS 45,6% - REPRODUKALJA a letra 44,5/46,8%-at, azaz a ket muszer ugyanazt meri. Olcso (IMS off): a MPSS XO-off ideje MEGHALADJA az ablakot (2861 s a 2700 s-ban) => a modem gyakorlatilag VEGIG aludt; a letra 4,8%-a AP-ebren szam volt, alva meg az a maradek is eltunik. Aram: -142 mV/h vs -12,3 mV/h, a 08-28-i referencia helyi meredeksegevel ~200 vs ~40 mA. ☠️ A mA NEM bizonyitek: a draga lab masodpercekkel a tolto elvagasa utan indult 4,32 V-rol (felszini toltes relaxacioja, tehat a 200 felfele torzit), az olcso lab az ADC felbontasi kuszoben ul (5-bol 2 kor NULLA vagy EMELKEDO feszultseg), es a sav csak a labak VEGEN volt mintavetelezve. ☠️ Muszer-hiba: a current_now EL ezen az eszkozon (275,9->272,4->266,6 mA mintavetelezve utana), es a referenciafajlnak, amire az elemzes tamaszkodik, VAN cur_uA oszlopa - alvo telefont nem ar be, de a sampler-be be kellett volna tenni

- [-] **62.** ★★★ SZALLITHATO FORMA: idempotens boot-idejű systemd oneshot az fp3-pmaports-ban, ami minden IMS-kapcsolot kiir ES visszaolvas. ☠️ Az iras modem-perzisztens (tulelte a firmware-restartot), tehat a szolgaltatas nem a perzisztenciahoz kell, hanem BIZTOSITEKNAK egy NV-reset/masik stack utanra - es hogy a beallitas LATHATO es verziozott legyen, ne egy egyszeri kezi QMI-iras
      - a 74. valtja fel: nem egyszeri boot-oneshot, hanem konvergens reconciler visszaolvasassal es datalt naplozassal

- [x] **65.** ★★★★ TISZTA mA-SZAM (a 61. ujramerese, Fable #13 a szerint): sav PINELVE es MENET KOZBEN mintavetelezve; a pakk hagyva LESZALLNI a 4,3 V-os lapos tetorol az elso lab elott; A/B/A' alak, hogy a draga kar ismetlese bezarolja a driftet; es current_now mintavetel MINDEN ebredeskor a feszultseg mellett. ☠️ Ez az egyetlen nyitott dolog a <=50 mA cel es a bizonyitek kozott - a mostani ~40 mA konzisztens a cellal, de nem bizonyitek
      - tanú: `capture:docs/power/bringup/captures/2026-09-02_ims-ma2`
      - a tiszta mA-cenzus vegigfutasara (04:10 -> ~06:07); a telefon 600 s-os rtcwake ciklusokban alszik, ssh-val nem elerheto. Monitor b7j8nnmhx

- [-] **66.** ★★★★ AZ ARAM-FRONT EJSZAKA-HOSSZU FORMAJA: a 86 +/- 4 mA-es szam, amiben a projekt bizik, EGY 8 ORAS 86 KORES futasbol jott - a 30 perces labak 3 mintat adnak, ami nem meres. Kell egy ejszakanyi futas allapotonkent (vagy egy ejszaka, a karokat egymasba szove), IMS on / IMS off. ☠️ Es a mintavetel elott FIX letelepedesi keslelteltes kell ebredes utan, kulonben a voltage_now az IR-esest meri: az A lab 4,071 V-on vegzodott es a B 4,172 V-on kezdodott, 100 mV ugras ket egymast koveto olvasas kozott
      - a 67. valtja fel: a Fable #14 szerint a fix kesleltetes NEM a megoldas - 'ne ebredeskor merj toltottseget', hanem pihentetett vegpontokbol

- [-] **67.** ★★★★★ AZ ARAM-CENZUS PIHENTETETT-VEGPONTOS FORMAJA (Fable #14 a, a 66. helyebe): egy ejszaka, NEM szove es NEM ket ejszaka. (1) elotte a pakkot levinni 75-85%-ra (a 100%-os lapos teton a feszultseg-muszer vak); (2) rest(30p) -> OCV0 -> A-blokk (IMS on) 3-3,5 o -> rest(30p) -> OCV1 -> B-blokk (IMS off) 3-3,5 o -> rest(30p) -> OCV2; (3) a mA a VEGPONTOKBOL: az OCV-parok a 08-28-i gorben SoC-va kepezve adjak a dmAh/dt-t - 3,5 o x 50-150 mA = 175-500 mAh = a pakk 6-16%-a; (4) a rest alatt a modem a MERENDO allapotaban marad, a rest vegen 60 minta 1 Hz-cel, p90 az OCV-kozelites (a raid-burstok kozotti burkolo), mellette current_now a V = OCV - I*R illeszteshez. ☠️ Ez KONSTRUKCIOBOL keruli meg az IR-esest es a relaxaciot, nem kesleltetessel
      - targytalan: a QG-akkumulatoros rovid cenzus (78.) egy oraban megadta, amiert ez az ejszakai OCV-letra letezett volna - a muszer, amit meg akart kerulni, LATJA az alvo telefont

- [-] **68.** ★★★★ REBOOT-ATELES + KIMENO IRANY (a 60. maradeka, beallitas-valtoztatas NELKUL): reboot, majd (a) csengesi-teszt ujra - az IMS-iras modem-perzisztens, tehat a bootolt telefonnak is csengenie kell; (b) kimeno hivas; (c) kimeno SMS. ☠️ A reboot elott ELLENORIZNI, hogy a USB-input-suspend bit NINCS beallitva (a PMIC-ben el es tulel egy meleg rebootot)
      - DOBVA MINT ONALLO TETEL, ketfele bontva (Fable #15): (a) a REBOOT-ATELEST a ma esti 3 boot + a reconciler-naploja bizonyitja - kulon meres nem kell; (b) a KIMENO IRANY viszont a lezaro allitas resze es NULLA meresunk van ra (a 14/14 mind BEJOVO) - egy MO-hivas CSFB-n perc-munka, beolvasztva a 109. triazs vegere, amikor a telefon ugyis ebren van.

- [x] **69.** ★★★★★ A DUTY NEM ELEGSEGES STATISZTIKA - a focim ujraszamolasa: az 58 mA-es nyereseg egy MAS SAVON kalibralt modell kiertekelese azon a savon (eutran-1), ahol a modell a legrosszabbul josol (+41 mA reziduál, szemben az eutran-20 +6-javal). A jelentesben az 58 mA NEM konzervativ becsles es NEM meres. Teendo: a STATUS.md/capture-ok minden helyen, ahol az 58 mA vagy a 47,3 mA szerepel, kapjon egy sort errol; es a modellt vagy dobjuk ki, vagy illesszuk ujra SAV-PARAMETERREL. ☠️ A provenancia ellenorizve: a 147/93 a current_now medianjaibol jott (nem a bukott feszultseg-modszerbol), DE EBREN mert aram egy ALVASRA illesztett meredekseg ellen - a kvalitativ allitas all, a '367 mA/duty' szam nem idezheto
      - tanú: `docs/power/bringup/leads/duty-is-not-sufficient.md`

- [x] **70.** ★★★★★ ELERHETOSEG N=1 -> N=20+: a paging SZTOCHASZTIKUS, es most egy hivas + egy SMS all mogotte. Kell egy automatizalt ejszakai sorozat: 20+ bejovo hivas kezbesitesi idovel (csenges-kesleltetes eloszlas), alvo AP-vel, akkun, a szallithato konfiguraciobol. ☠️ Ez ugyanaz a lecke, mint a hangszoro-saga: egy boot allapotat ne mondjam ki a telefon tulajdonsagakent. Kell hozza egy masodik keszulek vagy egy hivas-generator
      - tanú: `unverifiable:a-naplo-a-telefonon-marad-/var/log/fp3-reach-call2/journal.txt`
      - N=1 -> N=4, nem 20 (a felhasznalo lezarta: 'nem hivok tobbet'). MIND A NEGY hivas megcsorrent IMS=off mellett, eszkozoldali kesleltetes 520/339/355/326 ms = 385 +- 92 ms, es a tegnapi 329 ms ebben a savban van. A ~6 s tarcsazas->visszacsenges es a +1-2 s a HALOZATE (alerting/CSFB), nem a konfiguracioe. ☠️ SAJAT HIBA: a rogzitot RuntimeMaxSec=1800-zal inditottam, ezert 08:57-kor leallt, es a 9 ora utani hivasok NINCSENEK rogzitve - a mero elettartama rovidebb volt, mint a meres. A 20+ mintas eloszlas tovabbra sincs meg; az a 63. tetelen marad, hivas-generatorral.

- [x] **71.** ★★★★ QG NYERS REGISZTEREK: a charge_now befagyasa a DRIVER allapota - a PMI632 QG sajat coulomb-akkumulatora ettol meg szamolhat. Regmap/debugfs-dump ket idopontban; a vendor 4.9 forras a lemezen (hadk22/kernel/fairphone/sdm632) dokumentalja a regisztereket. Ha el, ez az EGYETLEN igazi coulomb-szamlalo az eszkozon es minden feszultseg-akrobatikat kivalt. ~fel nap ellenorizni
      - tanú: `docs/power/bringup/leads/qg-accumulator-current.md`

- [-] **73.** ★★★ A 41,4 mA-es TENGELYMETSZET FELBONTASA ABLACIOVAL (nem regresszioval - a metszet a duty=0-ra valo extrapolacio mellékterméke, nem meres): letra a bevalt cenzus-muszerrel - (1) modem KI (radio ki vagy remoteproc stop; ilyenkor 1800 s teljes alvas van merve) => a nem-modem padlo; (2) +WiFi ki; (3) +USB FIZIKAILAG kihuzva (a VBUS-jelenlet PHY-t tarthat ebren); (4) a tobbi RPM-master ugyanabbol a debugfs-bol (APSS, ADSP - a szenzorok az ADSP-n futnak). ☠️ A duty=0 extrapolacio a modem duty-fuggetlen reszet (VDD_CX-padlo, memoria-retencio) hamisan a 'nem modem' fiokba teszi
      - DOBVA - ☠️ EZT FABLE NEM NEVEZTE MEG, en terjesztettem ki ra a 28. indoklasat, es ezt lathatova teszem, hogy visszavonhato legyen: a 73. UGYANANNAK a 41,4 mA-es tengelymetszetnek a felbontasa, amirol Fable a 28-nal kimondta, hogy a MODELL NYUGDIJAS - a B-allapotot mar kozvetlenul merjuk, nem duty=0-ra extrapolaljuk. Egy tetel, ami egy visszavont modell mellektermeket bontja fel, nem termel dontest. Ha megis kell, ujranyithato.

- [x] **74.** ★★★★★ KONVERGENS IMS-RECONCILER (a 62. helyebe, Fable 5.1 (f)): NEM egyszeri boot-iras es NEM finomabb sorrendezes, hanem szolgaltatas + ~5 perces timer, ami (1) olvassa a TELJES vektort, (2) kapcsolonkent ir ES visszaolvas, (3) backoffal ujraprobal amig a visszaolvasas nem egyezik - a sikertelen irast EREDMENY alapjan eszlelve, nem feltetelezve -, (4) minden eltrest DATALTAN a journalba naplóz. ☠️ Az After=ModemManager.service nem eleg: a demon 'elindult' es 'a modemet inicializalta' ket kulon pillanat (a MM aszinkron probe-ol, a modem-objektum 10-30 s-cel kesobb jon). ★ A naplo INGYEN adja az idosort ahhoz, hogy MIKOR es milyen gyakran all vissza
      - tanú: `userspace-power/fp3-ims-reconcile.py`
      - MEGEPITVE, TELEPITVE es MINDKET AGA MEGMUTATVA az eszkozon (563c935): fp3-ims-reconcile.py + .service + .timer az userspace-power/-ben. 1. futas a boot utani (IMS=on) allapotbol: '☠️ want=off but sms,ut,video,voice disagree' majd '☠️ HAD DRIFTED, corrected on attempt 2' visszaolvasott bizonyitekkal; 2. futas: 'already want=off, nothing to do'. A timer aktiv (OnBootSec=90s, OnUnitActiveSec=5min). Minden eltres datalva a journalba => INGYEN idosor ahhoz, hogy mikor es milyen gyakran all vissza. ☠️ A boot-utat MEG NEM validaltam - ahhoz reboot kell

- [x] **76.** ★★★★ KET CHECK A SELFTEST-BATTERIABA (Fable 5.1 (f)): (1) KONFIGURACIO-SZINTU - az IMS-vektor visszaolvasasa es osszevetese a kivanttal; determinisztikus es halozat-fuggetlen, de csak azt bizonyitja, amit a modem MOND. (2) VISELKEDES-SZINTU - 3-5 perces MPSS-duty-ablak kuszobbel (duty < 10% ES ebredes-utem ~3,1/s = a paging-DRX ujjlenyomat); a kuszob a mert sav-szoras (olcso 4,4-6,9%, draga 31-52%) koze lojve, es a check NAPLOZZA a savot/cellat, hogy egy FAIL savvaltaskent is olvashato legyen; a nulla-delta-ketertelmuseget statikus mezokkel dontse el. ☠️ A ketto egyutt zarja a kort: az 1. jelez ha valami visszairta a konfiguraciot, a 2. akkor is bukik, ha a konfiguracio 'jo' de a viselkedes megis draga
      - tanú: `commit:049864a`
      - Mindket IMS-check MINDKET aga megmutatva az eszkozon. 56: IMS=off PASS (rc=0), IMS=on FAIL (rc=1) a pontos uzenettel; a demonstracio TALALT egy valodi hibat magaban a checkben (enabled != active: kezzel leallitott timer tovabbra is enabled) - javitva, mindkettot kerdezi. 57: azonos savon es cellan (eutran-3/1470732, a sav mint konfundalo kizarva) 37,1 % / 2,41 ebr/s -> FAIL, es 5,0 % / 3,13 ebr/s -> PASS. Kozben a reconciler elesben elkapta a demo sajat driftjet, visszaolvasassal. Bizonyitek: docs/power/bringup/captures/2026-09-02_check-demos/

- [x] **77.** ★★★★ PROTOKOLL-SZABALY MINDEN JOVOBELI MERESRE: a blokk elejen ES vegen olvasd vissza az IMS-vektort (es tedd bele a capture-be). Egy varatlan revert a blokk kozepen pontosan az a nema allapotvaltas, ami a hangszoro-sagaban 16 napig lathatatlan maradt - es most mar TUDJUK, hogy a vektor vissza TUD allni magatol. Beepitendo az ims-ma2.sh/ims-ab.sh labaiba es a tervezett OCV-letraba
      - tanú: `commit:3798c8c`
      - A blokk-vegi IMS-visszaolvasas beepitve az ims-ab.sh es ims-ma2.sh labfuggvenyebe (az ims-ma3.sh mar vitte). Plusz ket dolog, ami menet kozben bukott ki ugyanabbol a mintabol - a lecke a headerben, a kod meg a regit csinalja: az ims-ma3.sh ALARM defaultja MEG MINDIG 60 volt kozvetlenul a sajat, hosszan indokolt '90 legyen' bekezdese alatt (javitva 90-re), es a kapu-komment 3,35*alarm-ot mondott a lab sajat median alvasa helyett (javitva).

- [x] **78.** ★★★★★ ROVID-INTERVALLUMU ARAM-CENZUS a QG-akkumulatorral (a 67. OCV-letra ELE): mivel az akkumulator ablaka ~76 s es AT AZ ALVASON fut, a helyes kar NEM 600 s-os rtcwake, hanem ~60-90 s-os - akkor az akkumulator ablaka az alvas NAGY RESZET fedi, es minden ebredes egy hardverben atlagolt aramszamot ad. A/B/A' sav-pinelve, labankent tobb tucat minta a 3 helyett. ☠️ ELOBB EZ, es csak ha ez nem eleg, akkor az ejszakai OCV-letra - a 67. azert letezett, hogy megkeruljon egy muszert, ami nem latja az alvo telefont; ez a muszer latja
      - tanú: `capture:docs/power/bringup/captures/2026-09-02_ims-ma3`
      - a cenzus vegigfutasara (06:55 -> ~08:15; dead-man 08:30). A telefon 60 s-os ciklusokban alszik, ssh-val gyakorlatilag elerhetetlen. Monitor bvify7yql

- [x] **80.** ★★ A QG MINTAVETELI RATA MERESE ALVAS KOZBEN: a ~3,35/s EBREN lett merve. Ket olvasas egy 76 s-nal rovidebb alvas ele/moge, (cnt2-cnt1) mod 256 osztva az eltelt idovel. Ha alvasban lassabb, a ~76 s-os ablak-becsles ES a szennyezes-valoszinuseg is modosul - tehat a 78. elemzesenek kapuja (cnt >= 201) is. Olcso, egyszeri
      - tanú: `docs/power/bringup/captures/2026-09-02_ims-ma3`
      - a telefonra - egy percnyi meres, de a 78. cenzus alatt tilos hozzanyulni

- [x] **83.** ★★★★★ A JELENTES MEGFOGALMAZASA RENDSZER-SZINTURE (Fable 5.1 a): a 40,1 vs 91-99 mA kontraszt NEM 'a modem-duty ara', hanem 'az IMS-hurok rendszer-szinten X mA-t er, aminek resze az AP elvesztett alvasa'. A kontrafaktualis (IMS on, de az AP atalussza) csak SMD-ablacioval merheto, es azt a 08-26-os sajat leletunk blokkolja: nem-wake IRQ ezen a platformon megszakitja az s2idle-t => a lefegyverzett lab egy harmadik, egyik kerdesre sem valaszolo allapotot ad. A dontes-relevans szam ugyis a rendszer-szintu. Atirni minden helyen, ahol a szam megjelenik.
      - tanú: `commit:ee3724e`
      - A jelentes megfogalmazasa rendszer-szintu: a 51-59 mA-es res modem-duty PLUSZ az AP elvesztett alvasa, es kulon szekcio mondja ki, miert nem merheto a kontrafaktualis (a 08-26-os s2idle-abort lelet), es hogy ez nem engedmeny (a cel a falnal van kimondva).

- [x] **84.** ★★★★★ A 40,1 mA HIBASAVJA ES A SONT NELKULI OFFSET-KORLAT (Fable 5.1 b): (1) szamold ki a 22 megtartott ablak szorasat/sqrt(22)-t es MONDD KI a statisztikai savot - a sav nelkuli 40,1 ugyanaz a hiba lenne, mint az 58 mA-es focim volt; (2) az A vs A' 91,0 vs 98,8 = 7,8 mA szoras AZONOS konfiguracion, tehat a draga allapot savja +-4-5 mA, ezt is ki kell mondani; (3) TILOS a visszavont feszultseg-lejtos ~40 mA-t alatamasztaskent idezni. Az offset-korlat levezetese: eps a QG-be kozvetlenul megy (mert=I+eps), a feszultseg-gorbes utba csak a kapacitas-skalan at (2185 mAh ~110 mA-s integralasbol) => ott I*(eps/110), 40 mA-nel 0,36*eps; ha a ketto delta-n belul egyezik, |eps| <= 1,6*delta. Egy 2-3 mA-es egyezes +-3-5 mA-re korlatozza az offsetet SONT NELKUL.
      - tanú: `commit:ee3724e`
      - Hibasav kimondva mindharom labra + a retracted feszultseg-lejtos tanu ELTAVOLITVA a jelentesbol + az offset-korlat levezetese (|eps| <= 1,6*delta) beirva. Plusz tools/ma3-fit.py: a kapu eddig CSAK a sessionben elt. ☠️ Es a szkript irasa kozben derult ki, hogy a kapu skalaja a LAB SAJAT ALVASA, nem az ebreszto - '3,35 x alarm'-kent olvasva az A lab 39 szennyezett mintat tart meg 7 helyett es 91,0 helyett 84,2 mA-t ad.

- [x] **86.** ★★★★★ A HIVHATOSAG-ALLITAS KETTEVAGASA ES A 0,473 KIMONDASA (Fable #6 a): a jelentes NEM mondhatja, hogy 'a cel teljesult' a hivhatosag oldalan. Ket kulon allitas: (1) 'a hivas-ut MUKODIK IMS=off mellett' - ez N=4-gyel lezarhato, funkcionalis bizonyitek, 385 +- 92 ms; (2) 'a kezbesitesi RATA nem romlott' - NINCS merve: negy sikerbol a 95%-os egyoldali also korlat p >= 0,05^(1/4) = 0,473, azaz a 4/4 azzal is konzisztens, hogy minden masodik hivas elveszik. Ezt a szamot KI KELL IRNI az N=4 melle. p>=0,95-hoz 59, p>=0,99-hez 299 egymas utani siker kell. ☠️ Es a '~6 s a halozate' ATTRIBUCIO MERES NELKUL - hipotezisnek cimkezni.
      - tanú: `commit:ce236f6`
      - A 0,473-as also korlat kiirva a hivhatosag-capture-be, es a ket allitas szetvalasztva: a hivas-UT mukodik (funkcionalis bizonyitek, N=4 eleg hozza), a kezbesitesi RATA nincs merve. Tabla is: p>=0,86-hoz 20, p>=0,95-hoz 59, p>=0,99-hez 299 egymas utani siker. A '~6 s a halozate' hipotezisnek cimkezve. Plusz a rogzito-lejarat (RuntimeMaxSec=1800 egy 9 oras ablakra) beirva mint a 'muszer rovidebb, mint a meres' osztaly MASODIK esete.

- [x] **87.** ★★★★ A HIBASAVOK ATIRASA (Fable #6 b): a bootstrap n=7-nel a sajat farkat becsli => az A/A' labakra t-alapu sav (df=6, t=2,447 * s/sqrt(7)) VAGY 'n=7, terjedelem X-Y, indikativ'. ES mindket sav felirata 'labon beluli; boot-kozti ismeretlen' - a domináns ismeretlen a boot-kozti variancia, amit egyetlen lab bootstrapje ELVILEG nem lathat. A ma esti 3 lab utan a boot-kozti szoras a HAROM LAB-ATLAG szorasabol jon, nem az osszeontott ablakokebol.
      - tanú: `commit:ce236f6`
      - ma3-fit.py: n<15-nel t-alapu sav (df szerinti tabla), n<3-nal csak terjedelem; a metodus kiirva minden sorban. Az A/A' savja +-8,4-rol +-12,2 / +-43,3-ra nott = a bootstrap HAMIS PRECIZIOT mutatott. Minden sav felirata 'within-leg; boot-to-boot unknown', es a szkript kiirja, hogy tobb boot utan a savot a LAB-ATLAGOK szorasabol kell venni, nem az osszeontott ablakokbol.

- [x] **88.** ★★★★ A MERES-WRAPPER KOVETELJEN TERVEZETT IDOTARTAMOT (Fable #6 d): utasitsa el az inditast, ha a sajat RuntimeMaxSec-je / log-rotacioja / ablaka ROVIDEBB, mint a tervezett meres. ☠️ Ez a hibaosztaly EGY KORON BELUL KETSZER fordult elo: a hivas-rogzito RuntimeMaxSec=1800 volt egy 9 oras ablakra, es korabban a QG 76 s-os ablaka egy 60 s-os alvasra. Harmadszorra ne emberi figyelmen muljon.
      - tanú: `commit:b88d3f4`
      - A wrapper kiolvassa a RuntimeMaxSec-et az inditasbol es ELUTASIT, ha rovidebb az ETA-nal; cap nelkul figyelmeztet (nincs, ami megallitsa, ha beragad). Mindket ag megmutatva. ☠️ ES A KAPU KIPROBALASA TALALT EGY ROSSZABBAT MELLETTE: a 'foglalt-e a telefon' ellenorzes MINDEN fp3-* unitra illeszkedett, koztuk az ALLANDO szolgaltatasokra (fp3-voiced, fp3-ims-reconcile, fp3-usbnet-watchdog) - vagyis MINDEN inditast elutasitott volna, es a telefont vedo kapu lett volna az elso, amit barki kikapcsol. Most csak a wrapper sajat, timestampes tranziens unitjaira illeszkedik. Olvasassal nem jott volna elo, csak eles eszkozon.

- [x] **89.** ★★★★ SZABALY: PUBLIKALT SZAM CSAK REPO-BELI SZKRIPTBOL (Fable #6): a jelentes tablait a szkript GENERALJA, ne kezzel masoljam at - akkor a kovetkezo elteres FUTASI HIBAKENT bukik ki, nem hatodik koros nyomozaskent. Ugyanez a csalad: az ALARM=60 alapertek es az indoklasa ket helyen elt; az alapertek oda kerul, ahol az indoklas van.
      - tanú: `commit:ce236f6`
      - ma3-fit.py --md generalja a jelentes tablajat, a README pedig ezt hasznalja (a szoveg is kimondja, hogy generalt, nem atmasolt). Az ALARM=60 parja mar a 3798c8c-ben javitva: az alapertek most ott van, ahol az indoklasa.

- [x] **90.** ★★★★★ ALLANDO HIVAS-NAPLOZO A TELEFONRA (a 63. gepi fele): systemd service + timer NELKUL, sima always-restart unit, ami a journalbol kigyujti a 'ringing-in (incoming-new)' es a 'Setting ring state' parokat egy /var/log/fp3/ringlog.tsv-be (idobelyeg, eszkozoldali kesleltetes ms, sav, cella, uptime, es hogy alvasbol ebredt-e). ☠️ NEM RuntimeMaxSec-kel - ez pont az a hibaosztaly, ami ma ketszer utott. Enabled, hogy reboot utan is menjen. Igy a felhasznalonak CSAK hivnia kell, jelentenie semmit.
      - tanú: `commit:7c67bc1`
      - fp3-ringlog telepitve, enabled es aktiv az eszkozon; Restart=always, SEMMI idokorlat. IGAZOLVA a mai negy VALODI hivason (--stdin ujrajatszas): 520/339/355/325 ms, azaz pontosan a kezi elemzes szamai. Ket hiba jott elo kozben: a /dev/stdout nem seekable (a header-ellenorzes elszallt), es az elso verzio a FELDOLGOZAS idejet belyegezte a sorokra a HIVAS ideje helyett - ezt csak az ujrajatszas mutatja meg, eles futasban sosem latszott volna.

- [x] **91.** ★★★★★ 20 PERCES MINIATUR FOPROBA A TELJES EJSZAKAI LANCBOL, lefekves elott (Fable #7 d): 1 reboot -> reconciler-konvergencia naplobol -> radio-ki rest + OCV -> 10 perces B-lab 90 s-os ebresztovel -> ma3-fit --md, VEGIG a wrapperen at. ☠️ Az ejszakai futas egylovetu es felugyeletlen, es szinte minden alkatresze MA keszult - a foglaltsag-ellenorzesrol is MA derult ki, hogy mindent blokkolt volna, es CSAK eles proban jott elo. Egy egyejszakas ablaknal a foproba nem ovatossag, hanem a meres resze.
      - tanú: `capture:docs/power/bringup/captures/2026-09-02_night-rehearsal`
      - A FOPROBA LEFUTOTT ES NEGY HIBAT TALALT, mind nema lett volna. A mechanika hibatlan: rest+OCV -> reboot -> lab -> rest+OCV vegigment, az allapotgep a reboot utan magatol folytatta (step 0 -> step 1), es a service LETILTOTTA ONMAGAT - ez volt a legnagyobb kockazat. ☠️ (1) A LAB A DRAGA ALLAPOTOT MERTE, miközben olcsonak hitte magat: 6 percen at voice=True/SMS=True/UT=True, mert a konvergencia-ellenorzes a journalban a 'fp3-ims-reconcile:' sztringre illesztett, es az illeszkedett a unit SAJAT LEIRASARA ('Finished Hold the modem's IMS service switches off'), amit a systemd akkor is kiir, ha a reconciler nem ert el semmit. Javitva: a VEKTORT olvassa, ujraprobal, es FELADJA a labat, ha 4 percen belul nem megy off. (2) Az OCV a TOLTON keszult (4,413 V 'Charging' = a tolto lebegtetesi feszultsege, nem a pakke) - most a toltot is lekapcsolja es ELLENORZI, hogy Discharging. (3) A sav es a cella URESEN maradt (az sed elhagyta a zaro aposztrofot) - a sav itt ~17 pp dutyt es ~54 mA-t er, sav nelkul a lab osszehasonlithatatlan; javitva, es a lab VEGEN is rogziti. (4) Az OCV meg EMELKEDETT 3 perc pihenő utan es ezt nem mondta meg - most kiirja a driftet. Mind a negy ugyanaz az osztaly, mint a nap korabbi kettoje, es MINDEGYIK csak eles proban jott elo.

- [x] **92.** ★★★★★ A BECSLO JAVITASA a ma3-fit.py-ben (Fable #7, ONCAFOLAT): se bootstrap, se sulyozatlan t-sav - a helyes a SULYOZOTT atlag SULYOZOTT varianciaja, Var(mu)=sum(w^2*(x-mu)^2)/(sum w)^2, w=cnt, MINDKET ut helyere. Plusz: az A' lab 11 ablakabol s=64,5 mA jon ki => 1-2 ablak valoszinuleg 200 mA folott - SZEMMEL megnezni, mielott statisztika lesz belole. Utana a jelentes MINDEN szamat regeneralni (a '51-59 mA' focim elavult: a becsuletes alak 91,0-40,1 = 50,9, +-12,2).
      - tanú: `commit:baa9493`
      - Becslo kicserelve a sulyozott atlag SULYOZOTT varianciajara (w=cnt), mindket korabbi ut helyere. ☠️ ES A KIUGROK KIIRASA EGY LYUKAT TALALT A SAJAT KAPUMBAN: az A' labban egy ablak cnt=1-gyel (EGYETLEN akkumulator-tick, nulla atlagolas) 303,7 mA-t adott, es egyedul o csinalta a lab szorasanak nagy reszet. A kapunak volt PLAFONJA (a lab alvasanal hosszabb ablak szennyezett), de PADLOJA NEM. Uj kapu: 20 <= cnt < 3,35 x a lab sajat median alvasa. A B-lab focime VALTOZATLAN (40,1 +- 1,1, 21/30) - a kovetkeztetest hordozo szam nem fuggott a rossz resztol. A jelentes regeneralva: az '51-59 mA' focim elavult volt, a becsuletes alak 50,2 +- 12,3 (A) es 57,5 +- 10,3 (A').

- [x] **93.** ★★★★★ A RINGLOG MONOTON IDOT ES BOOT-ID-T IS NAPLOZZON (Fable #7 b, ii): a KIMARADT hivas definicio szerint NEM hagy nyomot, tehat a kezbesitest a MENETREND es a naplo KULONBSEGE adja - ehhez megbizhato idobelyeg kell, DE ezen az eszkozon az RTC 1970-rol indul es NTP-ig hamis. Plusz kereszt-annotacio: a sajat kiserleteim (reboot/cenzus) alatt erkezo slot NE szamitson kezbesitesi hibanak.
      - tanú: `commit:baa9493`
      - A ringlog monoton idot es boot-id-t is naploz (az RTC 1970-rol indul NTP-ig, a kimaradt hivas pedig definicio szerint nem hagy nyomot => a slot-illesztes hamis idon szetesne). Plusz beirva, hogy ujrajatszasnal a sav/cella oszlop ERTELMETLEN: a negy reggeli hivas eutran-20-kent jott vissza, holott eutran-1-en tortent - az ujrajatszas CSAK az idozites-kinyerest validalja.

- [x] **94.** ★★★★ NAPI EGY REGGELI HIVAS az elso interakcio ELOTT (Fable #7 b): a nappali orankenti census minden hivassal UJRAINDITJA a tetlenseg orajat, tehat az '1 oras idle'-t surun mintavetelezi es a '8 orasat SOHA' - pedig a veszelyes sarok epp az. Napi egy reggeli hivas nulla tulajdonosi teherrel adja az ejszakai 7-9 oras sarkot, KULON sorozatkent.
      - tanú: `unverifiable:a-63.-tetel-human-protokolljaba-epult`
      - A reggeli hivas beepult a 63. tetel ember-protokolljaba masodik lepeskent, sajat indoklassal (az orankenti hivas ujrainditja a tetlenseg orajat => a 8 oras sarkot SOHA nem mintavetelezi). Kulon sorozatkent szamolodik.

- [-] **95.** ★★★ A DIAG-LETRA a nema folyamra (Fable #7 a), NEM invaziv sorrendben: (1) kotelezoen valaszolo keres (Version 0x00 / build-ID 0x7C) - valasz jon => RX+TX el, akkor 0x73 GET-tel olvasd VISSZA a log-maszkot; valasz NEM jon => a TX-ut halott (ehhez passzol, hogy a nyitasi burst atjott: RX el, TX nem) => dmesg glink/rpmsg, flow-control kredit; (2) fuser/lsof a diag-eszkozon - maradt-e nyitva korabbi kliens; (3) close/reopen; (4) DIAG mode-reset 0x29 (a diag-taskot inditja, NEM a modemet); (5) remoteproc-restart CSAK legvegul, a hivas-census szunetében. ☠️ A maszk-iras ACK-ja fuggetlen a maszk TARTALMATOL, tehat a kontroll +0-ja mar kizarta a maszk-hipotezist.
      - DOBVA MINT ONALLO TETEL, de NEM nulla (Fable #15): a maradeka egy 2 PERCES SZONDA a reggeli triazsban - kotelezoen valaszolo keres (Version) + maszk-visszaolvasas. Indok: a ma esti 3 reboot a modemet HAROMSZOR ujrainditotta, tehat a nema DIAG-folyam valoszinuleg magatol felebredt. Beolvasztva a 109. triazs-listajaba.

- [x] **96.** ★★★★ A FOPROBA MEGISMETLESE A NEGY JAVITAS UTAN, indulas elott (a foproba maga is uj kod most): ugyanaz a miniatur alak, de a varakozas MOST: a lab IMS=off-fal fut (a vektor visszaolvasva mindket vegen), az OCV Discharging statusszal keszul, a sav/cella KITOLTVE latszik, es a drift ki van irva. ☠️ A javitas maga is olyan kod, ami ma keszult - a foproba javitasa nem foproba.
      - tanú: `capture:docs/power/bringup/captures/2026-09-02_night-rehearsal`
      - MIND AZ OT ELORE KIMONDOTT ELVARAS TELJESULT, es a vektor-kapu ELESBEN ELSULT ('vector NOT off yet - starting the reconciler' -> 'vector verified off') - pontosan az az allapot, ami az elso foprobat tonkretette, csak most a MERES ELOTT derult ki. ☠️ Ket UJ hiba: (1) a SAV ELMOZDULT a lab kozepen (eutran-3 -> eutran-1 hat perc alatt) - a sav ~17 pp dutyt es ~54 mA-t er, harom lab harom booton CSAK a bootban kulonbozhet; a labak mostantol sav-pinelve futnak es a lab kiabal, ha megis elmozdul. Ezt az a mezo talalta meg, amit az ELSO foproba mutatott hianyzonak. (2) ☠️☠️ A MERES A SAJAT ELLENORZESEMTOL romlott el: a lab median alvasa 9 s lett a 90 s-os ebreszto ellen (28 minta 4 helyett, a kapu 1-et tartott meg), mert 11:49-kor a lab KOZEPEN ssh-ztam es pingeltem a telefont. Egy ssh-bejelentkezes AP-ebresztes - ugyanez a csapda aznap reggel irasban ment a tulajdonosnak. A kapu skalaja a lab SAJAT alvasa, ezert REJTETTE EL: a zavart lab igy is adott egy szamot (45,1 mA). Javitva: a fit kimondja, ha a median alvas az ebreszto 60%-a alatt van.

- [x] **97.** ★★★★★ ☠️ SZABALY MAGAMRA: MERES KOZBEN NEM NYULOK A TELEFONHOZ. Egy ssh-bejelentkezes AP-ebresztes; a masodik foproba labjat a sajat 'megnezem, mi van' ssh-m rontotta el (median alvas 9 s a 90 helyett). MA MASODSZOR: reggel a hivas-teszt kozben pollozott ssh-kkal ugyanezt csinaltam. A vedelem KETRETEGU legyen: (1) a fit kimondja, ha a lab zavart volt (KESZ), es (2) a meres alatt a valaszom a felhasznalonak 'a telefon mer, X-kor nezem meg' - nem egy gyors ssh. Ha a valaszhoz eszkoz-adat kell, az VARJON a meres vegeig.
      - tanú: `commit:3553f8c`
      - A szabaly GEPI FELE megepitve: a fp3-measure kiirja, mit inditott es mikorra var (~/.claude/.state/fp3-measuring.json), es a PreToolUse-kapu ELUTASIT minden ssh/scp/ping-et a telefonra, amig a meres tart - a valasz ilyenkor 'a telefon mer, HH:MM-kor nezem meg'. FP3_TOUCH_ANYWAY=1 felulirja, de override-kent naplozodik, tehat a gates megmutatja, ha a menekulout lett az ut. Mindket aga megmutatva (deny + atengedes).

- [x] **98.** ★★★★★ ☠️ HIBA-POLITIKA A FELUGYELETLEN EJSZAKARA (Fable #8 a4): most nincs kimondva, mit tesz a szkript hajnali 3-kor. Dontes: egy elbukott vektor-kapu vagy sav-veszteseg a LABAT dobja (jelolve, hogy miert) es MEGY TOVABB a kovetkezo bootra - NEM oli meg az ejszakat. Ket lab jobb, mint nulla. A give_up CSAK arra maradjon, ami a telefont veszelyezteti (allapot-fajl serules, MAXSTEP). Felugyeletlen futasnal a hiba-politika ugyanolyan alkatresz, mint a meres.
      - tanú: `commit:4bacd55`
      - A hiba-politika BEEPITVE: elbukott vektor-kapu => a labat dobja (dropped.txt), megy a kovetkezo bootra, es az utolso lab utan is lezarja az ejszakat rendesen (zaro OCV + onletiltas). A give_up csak allapot-fajl serulesre es MAXSTEP-re marad.

- [x] **99.** ★★★★★ LOGIN/UNIT-AUDIT A LABAK ALATT (Fable #8 e): a median-alvas detektor STATISZTIKAI es ALLAPOTFUGGO (a B-labon megy, az A-labon vak), es csak azt mondja, HOGY zavar volt. Kell melle: a lab rogzitse a journal 'Accepted publickey' sorait ES a lab alatt indult unitokat; barmelyik nem-ures => 'disturbed' cimke AZ OKAVAL. Allapot-fuggetlen, es a MI TORTENT-et mondja.
      - tanú: `commit:4bacd55`
      - Hiba-politika kimondva es beepitve: elbukott vektor-kapu => a LABAT dobja (dropped.txt-be jegyezve) es megy a kovetkezo bootra; a give_up csak arra marad, ami a telefont veszelyezteti.

- [x] **100.** ★★★★ OCV ELFOGADASI KRITERIUM (Fable #8 d): az OCV ne EGY pont legyen, hanem 10 perces sorozat a rest vegen, es a szkript fogadja el, ha az utolso 5 perc meredeksege < 0,2 mV/perc. Igy a 'meg emelkedett' nem utolagos megfigyeles, hanem beepitett kriterium. A maradek ~1-2 mV vegpontonkent ~0,4-1,0 mA jarulek a delta-hoz => az |eps|<=1,6*delta kap egy ~1 mA-es padlot.
      - tanú: `commit:4bacd55`
      - Login/unit-audit a labban: minden ssh-login es minden inditott unit rogzitve; barmelyik nem-ures => 'INTERFERED WITH' cimke az okaval. VISSZAMENOLEG IGAZOLVA a mai zavart labon: 'Accepted publickey = 1' pontosan abban az ablakban.

- [x] **101.** ★★★★ MONOTON IDO + BOOT-ID AZ EJSZAKAI NAPLO MINDEN SORABA (Fable #8 a2): az RTC 1970-rol indul, minden reboot utan NTP-ig hamis a falioora - a ringlognal mar megvan, de a night-run naploja csak faliorat ir, es a HAROM BOOT labai igy nem illesztheto. Plusz: systemd StartLimitBurst + journald rate-limit ellenorzese indulas elott (20 percben nem tuzel, 3 boot alatt igen).
      - tanú: `commit:4bacd55`
      - OCV: 10 perces sorozat, es az utolso 5 perc meredeksege < 0,2 mV/perc az ELFOGADASI kriterium; kulonben 'NOT RESTED - suspect' cimke.

- [x] **102.** ★★★ A ZAVART-LAB DETEKTOR ALLAPOT-FUGGOVE TETELE (Fable #8 b): a 0,6-os kuszob levezetve helyes IMS=off labra (zavartalan arany ~0,97; a median csak 46 AP-ebresztes/ora folott torik le), DE egy A-lab (IMS=on) median alvasa MAGATOL 0,2 - ott a detektor MINDIG tuzelne. A hajnali A-kontrollra kikapcsolni vagy kulon kuszobot adni.
      - tanú: `commit:901601c`
      - Allapot-fuggo kuszob, DE nem heurisztikaval: a --state kapcsoloval KIMONDVA, alapertelmezetten 'cheap' (a default hibamodja hamis riasztas legyen, ne elmulasztott). ☠️ Az ELSO probalkozasom az alvas-aranybol KOVETKEZTETTE ki az allapotot - es ezzel pont azt a esetet mentette fel, amiert a detektor letezik: a drága lab es a ZAVART OLCSO lab ARANYBAN MEGKULONBOZTETHETETLEN (mindketto 0,1-0,2), tehat a sajat mai zavart labam azonnal 'normalisnak' minosult. A merendo mennyisegbol kovetkeztetni az allapotra korkoros. Harom agon megmutatva.

- [x] **103.** ★★★★★ ☠️☠️ AZ AUDIT ALLOWLISTJE (Fable #9 a1) - INDULAS ELOTT KOTELEZO: a reconciler-timer 5 percenkent unitot indit => 75 perces lab alatt ~15-szor, tehat a mostani 'minden inditott unit => INTERFERED' logika MINDEN labat zavartnak minositene es reggel csupa-piros ejszakam lenne ERVENYES adatokkal. Ugyanaz az osztaly, mint a wrapper fp3-* mintaja. A vart periodikus unitok (fp3-ims-reconcile, fp3-ringlog, fp3-usbnet-watchdog) allowlistre; minden mas jelezzen.
      - tanú: `commit:4356abc`
      - Az allowlist beepitve az ims-ma3-leg.sh-ba: fp3-ims-reconcile|fp3-ringlog|fp3-usbnet-watchdog|systemd-tmpfiles|logrotate|apk- kiszurve, minden mas jelez.

- [x] **104.** ★★★★★ A BEJOVO HIVAS MINT ZAVARO (Fable #9 a2): a login-audit ssh-t es unitot lat, egy hajnali hivast EGYIKET SEM - pedig AP-ebresztes es percekre szettori a labat. A ringlog mar fut: a lab vesse ossze a sajat ablakat a /var/log/fp3/ringlog.tsv bejegyzeseivel, es a hivast tartalmazo lab kapjon 'disturbed (call)' cimket.
      - tanú: `commit:4356abc`
      - Az audit allowlistje kesz (fp3-ims-reconcile, fp3-ringlog, fp3-usbnet-watchdog, tmpfiles, logrotate, apk) - e nelkul MINDEN lab 'INTERFERED' lett volna, mert a reconciler 75 perc alatt ~15-szor indit unitot.

- [x] **105.** ★★★★★ ☠️ A cnt-KAPU FELSO SKALAJA DEKLARALT LEGYEN (Fable #9 c1): maig 'a lab sajat median alvasa' - ugyanaz az onreferencia, amit a --state-tel mar kivettem az arany-detektorbol. Zavart labon a median rovidul, a kapu EGYUTT CSUSZIK vele, es pont a zavart ablakokra lesz engedekeny: a mai 45,1 mA igy szuletett. Cheap labon a skala 3,35 x EBRESZTO legyen; expensive labon maradhat a mert median (ott nincs mit vedeni).
      - tanú: `commit:4356abc`
      - A lab osszeveti a sajat ablakat a ringlog.tsv-vel es 'disturbed (call)' cimket ad, ha hivas erkezett - a login/unit-audit ezt nem latna.

- [x] **106.** ★★★★ VISELKEDESI TANU A KONFIG MELLE (Fable #9 c2): a reconciler ugyanazokon a QMI-gettereken ellenoriz, amelyeken egyszer mar megbuktam (setter<->getter nem-megfeleles) - ha egy getter rossz kapcsolot olvas, a konfig-check orokre zolden hazudik. A fit vesse ossze a lab MPSS-dutyjat a deklaralt allapot vart savjaval (cheap: 4-7%, expensive: 31-52%) es kiabaljon, ha konfig-ok mellett draga a duty.
      - tanú: `commit:6ff709d`
      - Viselkedesi tanu kesz: a fit a lab MPSS XO-total-duration-jebol szamol dutyt es osszeveti a DEKLARALT allapot vart savjaval (cheap 0-12%, expensive 25-60%). A meglevo cenzuson 46,1/2,8/47,1% - egyezik a jelentes 46,8/4,5/47,7-evel, ezert hallgat. MEGMUTATVA BUKNI is: az olcso labat draganak deklaralva kiabal. ☠️ Az elso valtozatom a 'Last XO shutdown enter/exit' parbol talalt ki kepletet - ket EL-idobelyeg, ami semmit nem mond a halmozott idorol - es 100%-ot adott egy labra, ami bizonyithatoan aludt. Egy szarmaztatott mennyiseg, amit senki nem ellenorzott ismert eseten, egy tipp szazalekjellel.

- [x] **107.** ★★★★ AZ ELSO REST ADAPTIV (Fable #9 b): az elfogadasi kriteriumot (utolso 5 perc < 0,2 mV/perc) VEZERLOKENT hasznalni, ne cimkekent - az elso rest tartson addig, amig at nem megy, 90 perces felso korlattal. A toltes utani relaxacio lassabb es mas elojelu, mint a kisutes utani; a zaro OCV-nel a 30 perc jo.
      - tanú: `commit:6ff709d`
      - Az elso rest ADAPTIV: addig pihen, amig a feszultseg meg nem all (2 perces ablakban <1 mV), 90 perces plafonnal; a plafon eleresekor 'suspect' cimke. A zaro OCV marad 30 perc, mert kisutesbol jon.

- [-] **108.** teszt-tetel, mindjart eldobom
      - teszt-tetel volt, csak az id-kiirast mutatta meg

- [x] **109.** ★★★★ A REGGELI TRIAZS LEFUTTATASA az ejszakara (night-triage.sh, mar telepitve): 1. interferencia-audit, 2. vektor-kapuk + dobott labak, 3. sav-naplo, 4. OCV-vegpontok leulepedese, 5. a szamok, 6. boot-kozti szoras a LAB-ATLAGOKBOL. Ervenyesseg eloszor - egy zavart lab szama akkor sem hihetobb, ha szep.
      - tanú: `docs/power/bringup/captures/2026-09-02_night-replication/triage-output.txt`
      - A triazs LEFUTOTT 03:15-kor, automatikusan, es ERVENYESSEG-ELSO sorrendben mukodott: az audit dobta az egyetlen labat, a vektor-kapuk zoldek, a sav mindket vegen eutran-1/1470762 (nem mozdult), es kimondta, hogy 1 hasznalhato lab -> nincs boot-kozti szoras. A DIAG-szonda es a kimeno hivas NEM futott le - azok a bovitesek a repo-oldali szkriptben vannak, az eszkozre a triazs ELOTT telepitett verzio ment. ☠️ Ez maga egy lelet: a telepites es a triazs egy menetben van, tehat a friss bovites CSAK a kovetkezo ejszakan lesz benne.

- [x] **110.** ★★★★ AZ imsd-UT ATSOROLASA: eddig 'kulon projekt, kulon dontessel' cimkevel feküdt, mint kivancsisag. A CSFB-fuggoseg miatt ez a TARTALEK TERV: ha a halozat lekapcsolja a 2G-t, a valasztas nem 'IMS ki vagy be', hanem 'VoLTE vagy semmi', es akkor nem a 8,4 s-os hurok kikapcsolasa a kerdes, hanem hogy MIERT bontja a modem a bearert (a 64. tetel, amit most a nema DIAG-folyam blokkol). Nem kell most megepiteni - de a jelentesnek meg kell neveznie, es a 64. tetel ertekét ez emeli.
      - tanú: `commit:9ed8a7b`
      - Az imsd-lead atirva: a ket irany NEM valasztas, mert kulonbozo alapon allnak - az 'IMS ki' CSAK addig mukodik, amig a halozat ad CS-tartomanyt (ma merve), es a 3G mar elment. Ha a 2G koveti, az az ag nem lassabb lesz, hanem megszunik hivast kezbesiteni, es marad a masik. Tehat az imsd a TARTALEK TERV, es a blokkolo kerdese nem 'hogyan allitsuk le a hurkot', hanem 'MIERT bontja a modem a bearert' - amit most a nema DIAG-folyam allja utjat. Ez a kerdes ARAT valtoztat, nem surgosseget.

- [-] **111.** ★★★★ SAROK-MINTA EGY MERES NELKULI EJSZAKA UTAN: a 8-9 oras tetlenseg utani paging az EGYETLEN meg nem mintavetelezett eset, es a replikacios ejszaka NEM adja (3 boot, 90 s-os ebresztok, ket rádió-ki rest). A kovetkezo olyan ejszaka utan, amikor semmit nem merek: reggel, az elso erintes elott, egy hivas. Kulon sorozatkent szamolodik.
      - DOBVA MINT TETEL (Fable #15): a lezaras utan ez nem tetel, hanem ALAPALLAPOT - minden meres-mentes ejszaka ingyen sarok-minta, es a 0,807-es also korlat magatol kuszik felfele. A protokoll a 63. tetelben all a felhasznalonal.

- [x] **113.** ★★★★ A JELENTES FUGGOSEGI SZAKASZA (Fable #10): soronkent a szolgaltatas, a ra epulo allitas, es az OBSERVABLE ami jelzi ha megvaltozott. A cel nem lablegyzet, hanem muszerrel orzott allitas
      - tanú: `commit:2588374`
      - 7 sor: CS-domain (a teherhordo - a ringlog band-oszlopa mar tanu), IMS-provisioning (pcscf-scan.py), keszulek-policy (nyitva, 112.), DRX (halozati parameter, a check PASS-savja rajta ul), MM/libqmi, modem-firmware, SIM - az utolso harom eddig TANU NELKUL allt, most a lab-fejlec logolja. A leg-szkript CSAK a repoban valtozott; az ejszakai futas a /usr/local/bin masolatokbol megy, deploy a triazs utan.

- [-] **114.** x
      - elgepeles

- [x] **115.** ★★★ AZ ATTRIBUCIO A CIMKET VALTOZTATJA, A SORSOT SOHA (Fable #14): lab-ablakban nem-allowlistelt AP-ebresztes => a lab KIESIK a fo aggregatumbol, akarmilyen jol ertett az oka. A fokonyv szerepe a JOVO javitasa (a forras megszuntetese) es a lab-dobas vs ejszaka-dobas megkulonboztetese, NEM a megtartas. ☠️ Tukor-hibamod: 'nincs fokonyv-sor => tiszta' - a foonyv csak ssh-t lat; a negy tanu (foonyv, ringlog, unit-audit, median-alvas detektor) VAGY-kapcsolatban marad, tiszta lab az, amelyiknel MIND hallgat. A statisztikai detektort NE nyugdijazd: o az egyetlen, ami az okokat nem ismero zavarra is erzekeny
      - tanú: `commit:40ac94f`
      - A szabaly GEPI: a fit osszegyujti a lab sajat audit-sorait (ssh/hivas/unit), VAGY-oljta a statisztikai medián-alvás detektorral, es a labat KIVESZI a res-bol - nem figyelmeztetes egy szam mellett, amit aztan felhasznal (a probafutas 45,1 mA-e igy jelent meg). ☠️ A leg_audit ELSO valtozata ugyanabba a csapdaba lepett, amiert a leg_state ma reggel javult: a kozos naplobol az A lab sorat MINDEN labra alkalmazta -> harom labbol harmat elmarasztalt egyetlen belepesre. Elkapva a repo sajat cenzusan, mielott ejszakat ert volna. Most 'LEG X' fejlecekre szukitve; fejlec nelkuli tobb-labas fajl SZANDEKOSAN mindet elmarasztalja. Ket agban demonstralva: csak az A-ban belepes -> csak az A esik ki, es CSAK az o gap-sora tunik el.

- [x] **117.** ★★ AZ imsd RAFORDITAS-BECSLESE OFFLINE (Fable #14): a flamingradian/imsd forrasanak elolvasasa + a QMI-szolgaltatas-lista osszevetese a sajat firmware-unkkel. A becsles (hetek vs napok) MAGA IS KAPU, es a gepen elvegezheto, amig a telefon alszik. ☠️ Es egy atarazas: a nema DIAG-folyam javitasa TOVABB OLCSOSODOTT - a 'miert bont 30 ms utan' fo terhet (vart-e a halozat egyaltalan IMS-t adni) a PCO-fejtes levette; ami maradt, az az imsd-epites UTANI hibakereseshez kell, elotte nem dontes-releváns
      - tanú: `docs/power/bringup/leads/imsd-cost-estimate.md`
      - NAPOK, nem hetek - de nem ma. ☠️ Ket ellentetes iranyu korrekcio: (1) az imsd-ben NINCS KOD, csak doksi (1105 sor IMS-QUALCOMM.md, utolso commit 2024-01-30, 17 uzenetbol 6 'Service: ???') => iras, nem portolas; (2) DE a libqmi 1.39.1 mar NEGY IMS-szolgaltatast visz (IMS/IMSA/IMSDCM/IMSP), es az IMSDCM ket uzenete a 'PDP Activate/Deactivate Request' = PONT a keresett hianyzo AP-fel. Ami hianyzik: POLITIKA, nem protokoll. A hat ismeretlenbol ketto azonositva (0x0034=IMSA Get Bind, 0x0033=IMSA Bind - SZERKEZETI egyezes: szomszedos ID, setter/getter, illeszkedo payload-alak, jo sorrend), egy nyitva (0x0023: link-local IPv6 stringkent, libqmi-ben nincs). Ket kapu elotte, egyik sem kodolasi: a keszulek-policy (116.) es a telefon libqmi-verzioja (a lab-fejlec mar logolja).

- [-] **119.** x
      - elgepeles

- [x] **120.** ★★★★★ MIERT NEM ALUDT AZ AP a 09-02-i lab1-ben? 11 s median alvas a 90 s-os ebreszto ellen, MIKOZBEN a 09-02 reggeli cenzus B-laba 62 s-ot aludt UGYANAZON a konfiguracion. Ket gyanusitott a naplobol: (a) NetworkManager Script Dispatcher indult a labba - miert, es mi valtotta ki (a sav-pineles mmcli-hivasa? a bemenet-felfuggesztes network-change-kent?); (b) a lab kozvetlenul boot+50 s utan indult, a reconciler konvergalasa utan - lehet, hogy a boot utani ~perceк meg nem nyugodt allapot. ☠️ EZ KAPUZZA a kovetkezo ejszakat: ujabb ejszaka egy ismert, diagnozalatlan ebresztoforrasra pazarlas
      - tanú: `commit:7b97791`
      - MEGVAN, es EGYIK tippem sem volt jo: a wlan0 DHCP-ujraprobalkozasi hurka. NM 197 IPv4 + 196 IPv6 tranzakcio a 77 perces labban (~23 s-enkent), 'no lease'; a REGGELI cenzus bootjaban NULLA => tiszta kontroll mar a lemezen levo adatbol. Az en ket tippem (sav-pineles mmcli-hivasa, boot-tranziens) es Fable tippje (sav-valtas -> modem re-regisztracios vihar) MIND rossz volt. Fix: a lab idejere 'nmcli device set wlan0 managed no' - ez NEM eli tul a rebootot, tehat egy osszeomlas sem hagyhatja a telefont WiFi-mento-ut nelkul.

- [x] **121.** ★★★★★ GYORSITOTT TELJES-SZEKVENCIA FOPROBA AZ ESZKOZON (Fable #17 d): alarm=10 s, leg=3 perc, rest=5 perc, BOOTS=3, HAROM VALODI reboot, ~30 perc. ☠️ Indok: a lepes-hiba a SZEKVENCIABAN volt, es ket LAB-foproba nem fogta; az offline szekvencia-teszt (6d22b85) az aritmetikat zarja, de a reboot-interakciokat nem. Ez a kapu az ejszaka elott. Zold felteteI: 3 lab lefut, 1 COMPLETE, mindket OCV 'rested' (alvo rest!), es a labakban nincs wlan0 DHCP-esemeny
      - tanú: `commit:0b311ba`
      - ★ A FOPROBA ATMENT a szerkezeti tesztjen: 3 lab, 3 KULON booton (05:07/05:12/05:17, harom boot-id), EGY 'NIGHT COMPLETE' 05:31-kor, service letiltva - a lepes-aritmetika javitasa VALODI rebootokon is all, es pont ezert kellett, mert ket LAB-foproba nem fogta meg a SZEKVENCIA hibajat. ☠️ De mindket OCV-vegpont ures meredekseget irt ('slope:  mV/min NOT RESTED'), es EZ HAROM DIAGNOZISBA kerult: (1) here-doc - 'megcafolva' egy teszttel, ami valtozoba tette az awk-programot, tehat MAST tesztelt; (2) a ^ operator - a HOST busyboxa nem tud matekot, a TELEFONE tud (sqrt(4)=2); (3) a valodi ok: a telepitett blokkot VALTOZATLANUL futtatva a telefonon azonnal reprodukalodik - 'awk: Unexpected end of string', mert a nem-idezojeles here-doc kifejti a torzset. A set -- forma -4.01/1-et ad ugyanazon az adaton, ELLENORIZVE a telefonon. ☠️ Plusz ket sajat hiba menet kozben: a visszavont ^-allitas javitasakor APOSZTROFOKAT irtam az egyszeres idezojeles awk-programba (busybox ash: 'bad for loop variable'); mindket szkript most sh -n ES busybox ash -n tiszta.

- [x] **122.** ★★★★ AZ ALVO REST VALIDALASA egy 15 perces NAPPALI resttel (Fable #17 c): a javitas utan a slope-nak ~0,1 mV/perc kore kell esnie a korabbi -0,78...-0,91 helyett, ES a journalnak suspend-belepeseket kell mutatnia a rest alatt (eddig NULLA volt). ☠️ A suspend-szamlalo a kozvetlen tanu; a gorbe-meredeksegbol szamolt aram ezen a szakaszon 8x-os savban szor, tehat NEM alkalmas dontesre
      - tanú: `capture:docs/power/bringup/captures/2026-09-03_sleeping-rest`
      - ★ AZ ALVO REST MUKODIK: 15 suspend (tegnap 0), es a feszultseg le is ul - az utolso 3 percben 4,264/4,263/4,264/4,264 V = ±1 mV. ☠️ DE a verdikt PIROS lett, es a hiba a MUSZERBEN volt: a meredekseg az utolso 6 pont ELSO es UTOLSO ertekebol szamolt (ketmintas kulonbseg, nem meredekseg), es egy terhelesi letores ket mintat 30 es 90 mV-tal lehuzott, egyiket az ablak elejere. Ugyanazon az adaton: regi 5,42 mV/perc NOT RESTED, uj (MAD-szures + illesztes) 0,10 mV/perc RESTED, '2 minta eldobva'. Javitva a night-run.sh-ban (88b3df5), es ha 4-nel kevesebb minta marad, a verdikt 'ZAVART rest', nem 'nem ult le'. ☠️ Plusz ablak-hossz lecke: 8 mintara -2,73 mV/perc, mert az ablak visszanyul a letores ELOTTI szintre - a hosszabb ablak nem robusztusabb, hanem MAS kerdesre valaszol.

- [x] **123.** ★★★ A JELENTES-OLDAL (docs/power/README.md) FRISSITESE a 09-02-i eredmenyekre: a fejlec 08-28-i allapotot hirdetett (IMS, 40,3 mA, 14/14, CSFB egyike sem volt benne). Plusz ket korrekcio: a 'nekunk nincs coulomb-szamlalonk' driver-korlat volt, nem hardveres; es az 'arithmetic' blokk meg mindig aktualis allapotkent volt cimkezve, a duty-modell figyelmeztetese nelkul
      - tanú: `commit:df1a619`
      - MEGVAN (df1a619). A 09-02-i szakasz a 'Where the numbers stand' ELEJERE kerult (mechanizmus 8,3-8,7 s / 30 ms / nincs ESM-ok; harom duty-letra; az AP-alvas tablaja; az akkumulator-aram tablaja 40,3 +- 1,3-mal), es a harom kapu (boot-kozti szoras, kalibracios offset, CSFB) A SZAMMAL EGYUTT utazik. A 08-28-i blokk lefokozva 'igy lett lokalizalva a front'-ra. Ket korrekcio: (a) 'nekunk nincs coulomb-szamlalonk' DRIVER-korlat volt, nem hardveres - a szamlalo a PMIC-ben van, alvason at szamol (3,39/s vs 3,35/s); a 'ez a legertekesebb hatralevo muszer-munka' mondat kicserelve arra, amiva valt; (b) az 'arithmetic' blokk mar nem 'current state', es megkapta a duty-nem-elegseges figyelmeztetest (+41 mA reziduál eutran-1-en, +6 eutran-20-on). A nyitott-kerdes tabla elso sora MEGVALASZOLVA; helyette a ket replikacio-fuggo hezag + CSFB + a ket imsd-kapu + a mintavetelezetlen 8 oras sarok. ☠️ A 113. 'Fuggosegek szakasza' MAR KESZ VOLT (2588374) - a 112. 'I DO MEANWHILE' sora elavult, es majdnem masodszor irtam meg ugyanazt; egy elavult terv-jegyzet ugyanugy hamis instrukcio, mint egy elavult banner.

---

# Closed from the queue

Tasks closed out of the `FP3-QUEUE` section of [`TODO.md`](TODO.md),
newest last, moved by `queue.cjs done`. The item number is the original
so that `after:` and `continues:` references still resolve.

- [x] **127.** Turn the hooks back on  — closed 2026-09-03 09:31
      why: ☠️ ALL seven hook registrations were removed on 2026-09-03 09:12 at the user's request. Restore with `node plugins/fp3/hooks/hooks-toggle.cjs on` (edits ONLY the hooks key; the old `cp settings.json.hooks-all-on-… settings.json` recipe would also have removed the kernel-review plugin installed since). Three consequences while they are off: measurement-watch no longer stops an unattended measurement being started with no watcher; precompact-status no longer writes a state snapshot before a compaction; risky-target no longer warns before a command touches boot config. ☠️ measurement-watch was ALSO dead while 'on' until 2026-09-03 (a syntax slip crashed it on exactly its positive path) — fixed

- [x] **128.** Cut upstreaming/wcd9335-audio from wip/7.1.3/audio with b4 prep on sound/for-next; tag submit/7.1.3/audio archive/submit-7.1.3-audio-final  — closed 2026-09-03 09:41
      lane: upstreaming
      why: first series branch of the new namespace
      STATUS.md row wcd9335-audio moves preparing → rebased when the trial rebase records its base-commit

- [x] **129.** Archive the other six submit/7.1.3/* branches and cut their upstreaming/<series> successors (i2c-qup-pinctrl, psci-cpuidle-fixes, smb5-charger, imx363-camera, qmi-encdec-fix)  — closed 2026-09-03 09:57
      lane: upstreaming
      after: 128
      why: STATUS.md names the target series per legacy branch
      every archive tag before any delete

- [x] **131.** Track D-1 (patchwork 875540) and D-2 (Otto's q6afe series) with the kernel-review plugin: /track the cover message-ids, record them on STATUS.md  — closed 2026-09-03 10:03
      lane: upstreaming
      why: the dependency list has patchwork ids but no lore message-ids yet

- [x] **134.** Add D-3 (Yassine Oudjana's QRTR + Sensor Manager IIO series, v2 2025-07-10, changes-requested) to the dependency list on docs/upstreaming/STATUS.md  — closed 2026-09-03 17:34
      why: docs/upstreaming/bringup/README.md 8b names it as a dependency of qmi-encdec-fix and of everything sensor-shaped, but STATUS.md's D- list stops at D-2
      the ledger says STATUS.md is the live record, so the record must carry it
      lane: upstreaming

- [x] **136.** B1: rebuild the IMX363 import commit on wip/7.1.3/camera so it adds ONLY the IMX363 hunks — today it deletes VIDEO_OV2732 and VIDEO_T4KA3 from Kconfig+Makefile and strips select V4L2_CCI_I2C from OG01A1B/OV9282 (30 deletions in a commit that certifies byte-identical import); then regenerate upstreaming/imx363-camera  — closed 2026-09-03 19:41
      why: docs/upstreaming/review-2026-09-03-wip-and-series.md B1 — a maintainer applying patch 1 would see four unrelated drivers regress under a message that says nothing changed. wip cda174905a83, series 7b5eb48928cd. Nothing from this series moves before this
      lane: upstreaming

- [x] **139.** B4+B5: adapt smb5-charger to devm_thermal_of_cooling_device_register(dev, u32 cdev_id, ...) on wip/7.1.3/charger and record the failed next-20260902 build in its Test block; re-cut i2c-qup-pinctrl on the current i2c-host tip (qup_i2c_enable_clocks now returns an error) with Fixes: from blame  — closed 2026-09-03 20:33
      why: review B4/B5 — the series does not build on the tree it targets and the record says rebased
      the cooling patch is silently missing from upstreaming-int
      the i2c series and the integration carry different resolutions
      lane: upstreaming

- [x] **141.** Re-triage the power category: the left-out table calls sendable fixes 'not upstream-shaped' — pinctrl-msm8953 wakeirq map, irq-qcom-mpm wakeup timer/accessor/cap, qcom_smd wake irq + double teardown, qcom_smd-regulator set_suspend ops (minus both_sets), smsm proc-awake (+ a binding that does not exist yet), msm8953.dtsi MPM/rpm-stats/domain-idle-states, msm8916-wcd-digital mclk, slimbus disable_stream; plus camss RDI stride, leds-qcom-flash PMI632, ak7375 PM rework from camera  — closed 2026-09-03 20:41
      why: review section 4 — each patches a file in Linus' tree with a measurement behind it and is blocked by none of D-1/D-2/D-3
      the experiments (xo_sleep_off, sleep_init, sleep_bw_off, both_sets) stay behind
      lane: upstreaming

- [x] **143.** Take Bert Karwatzki's lc898217 two-supply fix (vaf + vio; the actuator's i2c times out with only one because the sensor rail is already down at probe) as HIS patch onto wip/7.1.3/camera, update the onnn,lc898217xc binding, drop the dev_info leftover; his device has this actuator at 0x72 with the IMX363 at 0x10  — closed 2026-09-03 20:44
      why: mail 2026-09-03 — the actuator the review called untested hardware is now tested, by him, on the original camera module
      his authorship and Signed-off-by, our follow-up if any
      lane: upstreaming

- [x] **144.** Two rear-camera modules, two DTS: Bert's FP3 has IMX363@0x10 + LC898217@0x72, ours IMX363@0x1a + AK7374@0x0c; decide sdm632-fairphone-fp3.dtsi common + per-module dts (his proposal) before fp3-dts is cut, and ask the qcom DT maintainers on the cover letter how they want an undetectable module variant described  — closed 2026-09-03 20:46
      why: mail 2026-09-03 — the board DTS as written describes one of two shipped modules and disables the camera on the other
      the eeprom@50 must stay on both
      lane: upstreaming

- [x] **145.** Draft the reply to Bert (the person sends it): thank + ask for a formal Tested-by on wcd9335-audio naming the commit set he ran (5bc4d5ebb7c0 = integration/7.1.3 of 2026-08-30, Debian trixie userspace, call audio works); our measured QRTR port data for his wakeup filter (39 voice, 40 NAS, 52 DSD; IMS off 48 -> 4.4 % duty; radio off = 1802 s sleep, so the noise is the network's); the touch regression acknowledged; his lc898217 patch taken with his authorship  — closed 2026-09-03 20:46
      why: a second tester on a second device is the strongest thing the cover letter can carry, and every word of the reply must be the person's
      lane: upstreaming

- [x] **146.** B7 host-only half: on wip/7.1.3/camera fold the leftover C++ comments out of imx363.c (//0c40, // analog cropping, //subsampling, // digital cropping) into the cleanup patch, and replace '// NOT SURE HOW TO FIND THIS VALUE' on the 636 MHz link frequency with a comment that says what it is - a reverse-engineered value from the Pixel 3a downstream logs, carried into the binding's link-frequencies - then regenerate upstreaming/imx363-camera; no behaviour change, no build needed  — closed 2026-09-03 20:48
      why: review B7 — a maintainer reads the file, not the tree
      these lines survived the 'remove the commented-out code' patch and one of them contradicts any claim of measured values. The vdig hardcode and the FP3-named delays stay in 140 because moving them changes what the sensor does at power-up
      lane: upstreaming

- [x] **147.** Cut the four host-only power driver series from the 2026-09-03 plan (STATUS 'Planned series'): qcom-mpm-wakeup-timer (3 wip commits → 1, on tip/irq/core), pinctrl-msm8953-mpm (pinctrl/for-next), qcom-smd-wake (fold d0e738c107e3 into 8c9b25687119, rpmsg), smsm-proc-awake (write qcom,smsm.yaml binding first, qcom for-next); b4 prep each, checkpatch --strict, section in STATUS  — closed 2026-09-03 20:56
      lane: upstreaming
      why: review §4 — each patches a torvalds file with a measurement behind it and no D- dependency

- [x] **148.** Cut the ASoC/slimbus/media/LEDs series from the 2026-09-03 plan: wcd-digital-mclk (sound/for-next), ngd-disable-stream (squash c44534943e82), camss-rdi-stride (media/next, name the libcamera half), qcom-flash-pmi632 (binding then driver+Kconfig folded), ak7375-pm (AK7374 id alone; PM rework to final shape; Fixes: only where blame on master supports it); b4 prep each, checkpatch --strict, section in STATUS  — closed 2026-09-03 21:03
      lane: upstreaming
      why: same re-triage, second half; all host-only

- [x] **150.** Implement the #144 decision on wip/7.1.3/camera: move the rear-camera nodes out of sdm632-fairphone-fp3.dts into sdm632-fairphone-fp3-rear-camera-ak7374.dtso, add -rear-camera-lc898217.dtso from Bert's node set (IMX363@0x10, LC898217@0x72 with vaf+vio), compose both in arch/arm64/boot/dts/qcom/Makefile like sm8550-hdk-rear-camera-card; dtbs_check both composed dtbs on the host; then the phone lane must switch the flashed dtb to the -ak7374 composite (add a phone task when done)  — closed 2026-09-03 21:07
      lane: upstreaming
      keeps the in-tree dtb name valid
      why: #150 landed the overlay split on all three branches; a build that keeps the old dtb name silently loses the camera

- [x] **153.** qcom-smd-wake cover letter: Link: Caleb Connolly's 2023 glink thread (20230117142414.983946-1-caleb.connolly@linaro.org) and MM work item 694, CC Caleb + Bert; state it is the SMD counterpart, answer Bjorn's EPOLLWAKEUP question the way Caleb did (arming is policy, sysfs per edge), and say why no port filter in the kernel (port 52 = WMS on Bert's firmware, DSD on ours - per-firmware numbers); generated-content.rst disclosure  — closed 2026-09-03 21:31
      lane: upstreaming
      why: D-4 prior art found 2026-09-03; a maintainer who saw Caleb's patch will ask how this relates

- [x] **155.** Assisted-by model correction on the eight series cut 2026-09-03 (all but qcom-smd-wake): for each patch take the model from its wip commit's Co-authored-by (git log on wip/7.1.3/{power,camera}) and set Assisted-by: Claude:<that model id>, adding claude-fable-5-1 as a second trailer where 5.1 reshaped the patch; force-with-lease after tagging; STATUS Done line per series  — closed 2026-09-03 21:33
      lane: upstreaming
      why: skill rule: name the model that did the work; #147/#148 wrote fable-5-1 on all, but the code was written 2026-08 by Fable 5 (and earlier models on camera)

- [x] **155.** Rebase upstreaming/imx363-camera onto media next 274af88c8aca (it sits on v7.3-rc1, 16 commits behind the base camss-rdi-stride and ak7375-pm use); tag the old tip, force-with-lease, checkpatch, STATUS base line + Done  — closed 2026-09-04 05:49
      lane: upstreaming
      why: one media tree, three series on two different bases is a question a maintainer will ask; found by the 2026-09-04 review

- [x] **156.** #142: separate the idle length from the periodic wakeup — hold the probe idle fixed at 15 s and vary ONLY whether fp3-usbnet-watchdog.timer runs, interleaved arms, ~500 probes each (~2 h per arm)  — closed 2026-09-04 21:37
      continues: 142
      lane: phone
      why: RUNNING as fp3-142-wd since 21:25, ~4.2 h, finishes ~01:45. Holds the idle fixed at 15 s and varies ONLY whether fp3-usbnet-watchdog.timer runs; 10 interleaved blocks of 50 probes, screen off, driver unbound ONCE at the start (re-unbinding between blocks would re-arm the fault and measure the artifact instead of the question), arming probe discarded. ☠️ PREDICTION RECORDED BEFORE THE RUN, in the script: both arms empty. In every screen-off run so far the fault fired once, on the first transaction after the arming event, and never again - 0 in 26158 subsequent probes across three runs with the watchdog ticking throughout (~80 ticks). If the WD-ON arm DOES produce stalls, the root-cause account written for 155 is wrong and this run is what says so. Original framing partly superseded by 155: the cause is now measured (the panel is the only voter on pm8953_l6 and drops it with the display), so this arm no longer decides the mechanism - it tests whether anything RE-ARMS the fault without an unbind. Script: captures/2026-09-04_142-touch-after-resume/142-wd.sh
      until: 01:45

- [x] **85.** Replication across 3 boots + OCV-vs-QG  — closed 2026-09-05 01:17
      until: 19:00
      why: RAN AND COMPLETED 2026-09-03 23:17 -> 2026-09-04 01:15, started by fp3-night-start.timer which then self-disabled by design. Raw data on the device at /var/log/fp3/night/: leg1, leg2, leg3 (each log.txt + mpss-B.txt + samples-B.txt), ocv.txt, run.log, ending "=== NIGHT COMPLETE ===". ☠️ THE OCV HALF IS SELF-FLAGGED SUSPECT and #118 must weigh it: run.log records "rest end hit its 30 min ceiling without settling - this endpoint is suspect", one outlier sample dropped after a load spike landed in the rest window, and "OCV end slope over the last 5 min: -0.83 mV/min - NOT RESTED". The three replication legs are complete; the calibration-offset endpoint is the doubtful part. Closed on the queue semantics that done means the task WORK is finished (run the replication), not that the result was good - which is the judgment #118 exists to make, and which was deadlocked while #118 sat behind 85. ☠️ Nobody closed this for two days because a device-side timer ran it with no session in the loop.
      lane: phone

- [x] **118.** Evaluate the night's balance against the pre-registered bands  — closed 2026-09-05 01:22
      after: 85
      why: EVALUATED 2026-09-05. The 09-03 night FAILED its own gates and produced nothing usable: all three legs dropped for a median sleep of 13/18/9 s against a 90 s alarm, so the boot-to-boot spread the night was run for does not exist (means 0.0 0.0 0.0); both OCV endpoints hit their ceilings unrested (-2.02 and -0.83 mV/min), so there is no calibration bound either. Interference gates were CLEAN - zero ssh logins, zero unexpected units, zero incoming calls, vector verified off, eutran-1/1470762 throughout - so nothing external did this. ☠️ The 09-02 night failed identically (both ceilings, a leg at median sleep 11 s), so it is the measurement as designed, not luck. ☠️ Do NOT read the legs 47.9/47.7/45.7 mA agreeing within 2.2 mA as the band: they describe an AP waking every 9-18 s, so the tightness is of the WAKE pattern, not of a sleeping floor. Blocker for a third attempt is an instrument gap, not another night: neither run recorded what woke the AP. Capture: captures/2026-09-05_118-night-triage/README.md; findings-log 2026-09-05; power/README.md open-question row updated.
      continues: 85

- [x] **130.** Measure the AFE api_version this ADSP reports (q6core svc info) — the one number the q6afe clock-set redesign turns on  — closed 2026-09-05 01:34
      lane: phone
      after: 85
      why: MEASURED 2026-09-05: AFE service api_version = 2, api_branch_version = 0, query successful (ret=0, so the zeros are real values and not a lookup miss). Read with a kretprobe on q6core_get_svc_api_info using entry-argument access at return, triggered by an APR-bus unbind/rebind of aprsvc:service:4:4 so q6afe_probe runs again — no rebuild and no flash, because nothing in the tree prints it and /proc/kcore does not exist on this kernel. ☠️ THE FIRST READ WAS ONE STRUCT FIELD OUT and would have been reported as api_version = 0: struct q6core_svc_api_info is service_id, api_version, api_branch_version, so +0 was the field the function never writes. Both 0 and 2 are plausible, so nothing about the wrong number looked wrong — caught by reading q6core.h. The corrected read carries two self-checks. ☠️ THE METHOD COSTS A REBOOT: the rebind wedges the AFE ports (fail to start AFE port 7f, ASoC error -110 on QUIN_MI2S_RX), a second rebind did not clear it, and audio only came back after a reboot — verified afterwards with a silent aplay reaching state: RUNNING and 0 errors. If the number is wanted again, fold a one-line dev_info into q6afe_probe on the next flash. What it does NOT decide: which branch 2 selects, because the dispatch is Otto Pflüger D-2 patch 3/4 which is not in mainline and our tree branches on ainfo nowhere. Docs: audio/bringup/captures/2026-09-05_130-afe-api-version/README.md, audio/README.md, upstreaming/README.md
      a device read, not an argument

- [x] **159.** Close the loop for device-run measurements: make a scripted run on the phone update the queue when it finishes, so the dispatcher can hand out what was waiting on it  — closed 2026-09-05 01:47
      lane: any
      why: ☠️ MEASURED COST, 2026-09-05. #85 was started by a device-side timer (fp3-night-start.timer), ran to completion 2026-09-03 23:17 -> 09-04 01:15, and then sat unclosed for TWO DAYS with NINE tasks blocked behind it — because no session was in the loop and the queue only reads markers, it never infers from the device. Worse, it was a deadlock rather than mere lag: #118, the task that judges whether the night is good enough, carried after: 85, so the evaluation that would justify closing 85 was itself blocked behind 85. Design constraints the fix has to respect, all learned tonight: (1) the run must NOT close its own task on the "unit exited" signal alone — the 09-03 night exited cleanly and produced nothing usable, every leg dropped, so completion is not success
      (2) the evaluator is a separate task and must become dispatchable the moment the run FINISHES, not when someone judges it — i.e. the run should satisfy the dependency, not the verdict
      (3) whatever the phone writes has to survive the reboots the measurement itself performs (#85 reboots three times), so a /run marker is wrong and it has to land somewhere durable or be pushed to the host
      (4) a bare exit code is not enough — the triage output carries the invalidating information and should travel with the completion. Candidate shapes to weigh, not a decision: a completion sentinel file the run writes and queue.cjs check notices
      the run calling queue.cjs on the host over the link
      or a host-side watcher like measurement-watch that learns about timer-started runs it never saw launched. ☠️ The third is the real gap: measurement-watch only knows about runs a session started with systemd-run, which is exactly why a timer-started one is invisible to it.

- [x] **160.** Put the DEV SIM in the daily factory-Android handset and call it — one variable, the card  — closed 2026-09-05 03:22
      lane: phone
      when: whenever the operator swaps the card
      they-do: Move the dev FP3 card into the daily Android handset and place/receive a call, reading Settings -> About phone -> SIM status -> "Mobile network type" (it updates live; the status bar does NOT show it during a call). ☠️ NOW THE DECISIVE TEST, AND WELL CONTROLLED: measured 2026-09-05, that handset's SIM2 shows 4G idle and switches to GSM on a call, while its other SIM is known to hold 4G through a call - same handset, same Android, same modem. So the variable is the card's VoLTE provisioning, not the device. GSM for the dev card there = the dev subscription has no VoLTE and NO software work on pmOS or UT can change it; 4G there = the stack is the difference after all and the 09-05 oracle conclusion must be narrowed. One word is the answer
      why: ☠️ Decides whether ANY software work on our side can give this phone a 4G call. Measured 2026-09-05 04:34 on the UT oracle — same device, same IMEI, same card, full vendor IMS stack — the incoming call ran on EDGE from 04:34:21 to 04:34:33 and returned to LTE one second after teardown. So IMS registration does not imply VoLTE here, and imsd would give pmOS only what UT already has. The remaining variable is the subscription: the daily handset carries two vodafone HU SIMs whose CSFB behaviour differs by TARIFF (private keeps 4G, corporate falls back), and the dev phone carries a THIRD card never characterised on its own. Falls back there too => the card is the variable and neither imsd nor a factory Android on the dev phone changes anything. Rings on 4G there => the certified stack gets what the vendor IMS on UT does not, and the software side is worth reopening. Evidence: captures/2026-09-05_ut-call-rat/README.md and, stronger, captures/2026-09-05_ut-call-rat-newsim/README.md — a second card, two calls, the RAT dropping to EDGE 2-3 s BEFORE the call is signalled, a 21 s answered call spent entirely on EDGE, and IpMultimediaSystem.Registered=true + VoiceCapable=true in every sample. ☠️ The first capture's ims= column is of unknown provenance (its sampler was not kept) and proves nothing either way; the second one asks the modem directly

- [x] **161.** Re-run #160 with the Android's own VoLTE switch ON - the first answer was a device setting --lane phone --they-do On the daily Android, the per-SIM "4G hívás" (VoLTE) switch is OFF BY DEFAULT and it was off for the slot holding the dev card - which is why that test showed GSM and why its conclusion was retracted. Switch it ON for that slot, enable mobile data for that SIM too (so a second unknown is not introduced), then call the handset and read Settings -> About phone -> SIM status -> "Mobile network type" DURING the call. Stays 4G => the subscription HAS VoLTE, the earlier closure was wrong in both directions, and the software side reopens. Drops to GSM with the switch on => the subscription is the variable after all, and no software work on our side can help. ☠️ Do not conclude from a device whose own switch state has not been read --why The 2026-09-05 closure of the imsd lead rested entirely on this measurement and has been retracted; both leads/ pages are reopened. Evidence and the retraction: captures/2026-09-05_ut-call-rat-newsim/README.md  — closed 2026-09-05 04:14

- [x] **162.** Re-run #160 with the Android's own VoLTE switch ON - the first answer was a device setting  — closed 2026-09-05 04:23
      lane: phone
      when: as soon as the switch is on
      they-do: On the daily Android the per-SIM "4G hívás" (VoLTE) switch is OFF BY DEFAULT, and it was off for the slot holding the dev card - which is why that test showed GSM and why its conclusion was retracted. Turn ON all three for that slot: (1) "4G hívás" / VoLTE, (2) mobile data for that SIM, (3) "adathasználat hívások közben" - on a dual-SIM handset only one SIM is the data SIM, and the other needs this to raise its own PDN, which is what IMS registration runs on. Then call the handset and read Settings -> About phone -> SIM status -> "Mobile network type" DURING the call. Stays 4G => the subscription HAS VoLTE, the earlier closure was wrong, and the software side reopens. Drops to GSM with all three on => the subscription is the variable after all and no software work on our side can help. ☠️ Do not conclude from a device whose own switch states have not been read
      why: the 2026-09-05 closure of the imsd lead rested entirely on the retracted measurement and both leads/ pages are reopened. Evidence and retraction: captures/2026-09-05_ut-call-rat-newsim/README.md

- [x] **164.** Read the IMS registration fields the ofono plugin throws away - pAssociatedUris says whether IMS really registered  — closed 2026-09-05 05:13
      lane: phone
      why: ☠️ PARTLY ANSWERED ALREADY, from captures we had - do not start from scratch. Correction to this task's first version: the plugin does NOT only read state, it already DBG-prints three of the five fields, and those lines are in captures/2026-09-05_ut-call-rat/calls-journal.txt: 'ims:imsradio0: QtiRadioRegInfo state:N radiotech:N error_code:N'. Decoded (QTI_RADIO_REG_STATE: REGISTERED=0, NOT_REGISTERED=1, REGISTERING=2, INVALID=3 - the enum inverts the naive reading): at ofono start the slot goes UNKNOWN -> NOT_REGISTERED(radiotech 21, err 0) -> REGISTERING(radiotech 15) -> REGISTERED(radiotech 15) in two seconds, no error. So IpMultimediaSystem.Registered=true is genuine (binder_ims_reg.c: registered = state == BINDER_EXT_IMS_STATE_REGISTERED) and the registration really completes. WHAT IS STILL MISSING and is the whole point: pAssociatedUris and error_message are in QtiRadioRegInfo but not in the DBG line. pAssociatedUris is the P-Associated-URI from the SIP REGISTER 200 OK - populated means the device registered with the OPERATOR'S IMS core rather than merely reaching a modem-internal state, and that is what separates 'the subscription has no VoLTE' from 'the stack does not finish IMS voice'. Route chosen by the operator: patch the DBG in qti_ims_reg_status_changed / qti_ims_reg_status_response to print info->uri and info->error_message, rebuild the standalone .so (source: gitlab.com/ubports/development/core/hybris-support/ofono-binder-plugin-ext-qti, ~4700 lines). Second open item: radiotech 15 vs 21 cannot be decoded from the plugin source - the enum lives in the vendor HIDL; the libraries are on the device at /vendor/lib64/vendor.qti.hardware.radio.ims@1.{3,4,5,6}.so

- [x] **163.** Put the dev card - now proven VoLTE-capable - back in the FP3 and call it  — closed 2026-09-05 05:19
      lane: phone
      when: after the card is swapped back
      they-do: Move the dev card from the daily Android back into the FP3, then call the FP3 and let it ring. Nothing to read on the phone - this window instruments it over ssh and reads the RAT, the IMS state and the call state at 1 Hz, so just say when the card is in and when you are about to call
      why: ☠️ THE DECISIVE TEST OF THE WHOLE THREAD, and the one comparison nobody has made. Measured 2026-09-05: this card holds 4G through a call in a stock Android, and the FP3 lands on EDGE - but with a DIFFERENT card, so the two say nothing about each other. Same card, two devices, is the only pairing that separates device from subscription. Still EDGE on the FP3 => the device or the stack is the variable and the software side is worth real work, with operator IMEI/TAC whitelisting as the next gate to check. 4G on the FP3 => the CSFB we have been chasing was the other card all along

- [x] **165.** Is the modem on a generic carrier config? Query the active MBN, on both slots  — closed 2026-09-05 05:31
      lane: phone
      why: ☠️ The strongest device-side candidate for the VoLTE gap now that #163 has shown the device is the variable. On Qualcomm the carrier MBN is largely what enables VoLTE: IMS still registers under a generic config, which is exactly the measured symptom - registration succeeds and the operator returns a P-Associated-URI, yet the network CS-pages. captures/2026-08-29_pdc-configs/pmos-software.txt shows 25 configs with ROW_Commercial ACTIVE and Global-VoLTE-Vodafone among the inactive ones
      the vendor store on the device has generic/eu/vodafone/volte/{cz,germany,global,ie,italy,netherla,portugal,safrica,spain,turkey,uk} - no hungary - plus dt/commerci/hungary. One HU is the former Vodafone Hungary, MCC 216 MNC 070. WHAT TO DO: (1) re-run the PDC config query on pmOS to confirm ROW_Commercial is still active today, (2) find out what UT has active - there is no qmicli or pdc on UT and no QMI char device since Halium reaches the modem over binder, so this needs either a tool or an inference from the Android pdc service, (3) only then consider selecting a VoLTE config. ☠️ Do not skip to (3): changing the active MBN is a modem-config change, and two things are unverified - whether Global-VoLTE-Vodafone's carrier policy even matches MCC 216 MNC 070 after the One rebrand, and whether the MBN is the gate at all, since operator IMEI/TAC gating produces the same symptom. Evidence: captures/2026-09-05_163-same-card-two-devices/README.md
