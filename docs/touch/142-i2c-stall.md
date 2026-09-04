# The touchscreen freezes for 15 seconds (#142)

> ⚠️ **AI-assisted.** The measurements on this page were run by Claude (Opus 5)
> under the direction of Lajosházi, László Gergely, who reviewed them. Every
> number states the conditions it was taken under; where a claim is an inference
> rather than an observation it says so.

Reported upstream by Bert Karwatzki against msm8953-mainline commit
`0314fee3ce35` (msm8953.dtsi, `system-pc` `arm,psci-suspend-param`
0x41000353 -> 0x42000353): the hx83112b touchscreen stops responding after
resume. Independently observed on this device by the operator.

**Status: the duration is fully explained, the trigger conditions are measured,
the cause of the hang is not known.** The msm8953.dtsi idle-state patch is on
HOLD until it is.

---

## 1. The symptom, verbatim

```
Himax-hx83112b-TS 2-0048: Failed to read input event: -110      (ETIMEDOUT)
Himax-hx83112b-TS 2-0048: Failed to read input event: -6        (ENXIO)
```

What the user sees: the panel is dead for ~15 s, then works again. Typically
the first touch after waking the screen. `himax_handle_input()` logs the error
and drops the event, `himax_irq_handler()` returns `IRQ_NONE`, and **the driver
retries nowhere**, so the touch is simply lost.

Counting instrument: `dmesg | grep -c 'Failed to read input event: -110'`, against
the touch interrupt count in `/proc/interrupts` (row `msmgpio 65 ... hx83112b`).

## 2. Closed: why it is 15 seconds

Not a property of the fault. [`drivers/i2c/busses/i2c-qup.c`](https://github.com/llg179org/linux/blob/debug-int/7.1.3/drivers/i2c/busses/i2c-qup.c) computes the
transfer timeout **once, at probe**, from the largest transfer the controller
could ever perform, and then applies it to every transfer:

```c
#define TOUT_MIN 2                            /* seconds */
#define MX_DMA_TX_RX_LEN  (2 * SZ_64K)        /* 131072 bytes */
one_bit_t  = (USEC_PER_SEC / clk_freq) + 1;
one_byte_t = one_bit_t * 9;
qup->xfer_timeout = TOUT_MIN * HZ + usecs_to_jiffies(MX_DMA_TX_RX_LEN * one_byte_t);
```

The DT declares no `clock-frequency`, so the driver defaults to 100 kHz:

    2 s + 131072 x 99 us = 14.976 s

Measured stalls: 14.99-15.17 s. That is the constant, not the fault.

☠️ **The 15 s is therefore not a fingerprint.** Every hang on this bus lasts
exactly this long whatever causes it, so "same 15 s" is not evidence that two
events share a mechanism. That mistake cost most of a day (2026-09-04).

A 4-byte read from the touch controller inherits a timeout sized for 128 KB.
That is what turns a momentary bus problem into a 15-second dead screen, and it
is a defect in its own right - see §7.

## 3. Reproducing it

[`142-trigger.sh`](../power/bringup/captures/2026-09-04_142-touch-after-resume/142-trigger.sh)

Unbind the touch driver, issue one i2c transaction to an address with no device
on it, and time it. Interleaved arms, five each (2026-09-04, `debug-int/7.1.3`,
kernel `#80-fp3`, commit `5aafd59e553a`):

```
round 1 OFF  15.0704 s errno 110  STALL      round 1 ON  0.0006 s errno 6  ok
round 2 OFF  15.0692 s errno 110  STALL      round 2 ON  0.0004 s errno 6  ok
round 3 OFF  15.0899 s errno 110  STALL      round 3 ON  0.0003 s errno 6  ok
round 4 OFF  15.0465 s errno 110  STALL      round 4 ON  0.0006 s errno 6  ok
round 5 OFF  15.1061 s errno 110  STALL      round 5 ON  0.0006 s errno 6  ok

screen OFF 5/5      screen ON 0/5      (7/7 vs 0/7 including reruns; p ~ 0.004)
```

☠️ **This is not the operator's fault, and must not be quoted as if it were.**
The operator's fault happens with the driver **bound**; this reproducer requires
it unbound, which never happens in normal use. The first transaction after an
unbind with the screen off has now stalled **7 times out of 7**, so anything
measured across an unbind must discard trial 0 or it will count that instead. What it establishes is narrower:
the touch chip *can* hold the bus for the full timeout, and whether it does is
gated by the screen, deterministically.

☠️ The rebind must be done with the **screen on**. With the screen off the Himax
probe returns -5 and the phone is left with no touchscreen until rebooted; that
cost five reboots in one afternoon before the ordering was fixed.

## 4. The gates, with their strength

Three conditions are measured. They are not equally well established, and the
difference matters more than the list does.

**Gate 1 - idle before the transaction, >= ~10 s.** Strong, but carried entirely
by the null in the fast range:

```
idle before probe   probes  stalls          idle    probes  stalls
      0.02 s (44/s)  52688       0          10-60 s     20       1
      0.5  s          1392       0          15 s        60       1
      2    s           300       0          15 s        59       0
      3    s            40       0          45 s         3       1

pooled:  >= 10 s   3 / 142  = 2.11 %        <= 3 s   0 / 54420
if the fast range had the slow rate: 1150 stalls expected, 0 observed
rule of three on the fast range: < 0.0055 %  ->  >= 383x separation
```

☠️ The separation is real, but there are only **three events** above the
threshold. "The threshold lies between 3 s and 10 s" is an inference from four
small runs; "below 3 s the fault effectively does not occur" is the measured
part.

**Gate 2 - screen off.** Strong and clean: 5/5 against 0/5 at an **identical**
12 s idle, interleaved arms, one variable.

**Gate 3 - not a fresh boot.** Weak; three observations, one of them decisive
only if the other two hold:

| capture | suspends this boot | result |
|---|---|---|
| [`armB-clean-boot-trial2.txt`](../power/bringup/captures/2026-09-04_142-touch-after-resume/armB-clean-boot-trial2.txt) | 1 | a real suspend/resume on the suspect psci value, ~513 post-resume touch interrupts, **no -110** |
| 16:54 boot, 2026-09-04 | 0 | **0 stalls in 59 probes** at 15 s idle, screen off |
| [`armB-first-touch-after-resume.txt`](../power/bringup/captures/2026-09-04_142-touch-after-resume/armB-first-touch-after-resume.txt) | 187 | one -110, on the **first touch after a resume** |

Gate 3 also explains an otherwise puzzling afternoon: the phone was rebooted
five times, so every later run ran on a young boot.

☠️ **The one test aimed at gate 3 was underpowered and settles nothing.** On the
16:54 boot, paired - same boot, same script, the suspend count the only thing
changed between the arms:

```
 0 suspends  ->  0 stalls / 59 probes at 15 s idle, screen off
50 suspends  ->  0 stalls / 59 probes            (suspend_stats/success 0 -> 50)
```

The design is right and the result is worth nothing on its own: at the 1.7 %
per probe measured in this exact regime at 14:29, one arm of 59 probes expects
**1.0** stalls, so seeing none has probability 37 %; both arms pooled, 14 %. It
could not reliably detect the *baseline*, let alone a change in it. Bounding the
rate below the reference at 95 % needs ~180 probes per arm, which is **0.8 h per
arm** at 15 s spacing.

What it does rule out is a *deterministic* effect: 50 suspends do not switch the
fault on the way the screen does (5/5). The 187-suspend observation stands
unexplained, and gate 3 stays the weak leg.

## 5. Eliminated by measurement

Everything Linux can see is **identical** between a stalling and a
non-stalling run. This is the part of the page most worth reading before
proposing a mechanism.

| candidate | instrument | result |
|---|---|---|
| a shared regulator dropping | `/sys/kernel/debug/regulator/regulator_summary`, screen on vs off | `l6` unchanged, `normal 1800mV` in both |
| i2c controller runtime PM | `78b7000.i2c/power/runtime_status` | `suspended` in **both** arms before the probe |
| pinctrl sleep/default state | `pinctrl/1000000.pinctrl/pinmux-pins`, pins 10/11 | identical: `gpio` while suspended, `blsp_i2c3` after; the in-tree pinctrl fix is working |
| touchscreen reset GPIO | same file, pin 64 | `GPIO ...:592` -> `UNCLAIMED` on unbind, identically in both arms |
| system suspend (Bert's suspect) | stalls observed with **no suspend at all** | `0314fee3ce35` is not the cause of the stall as such |
| audio disturbed by the same stall | ALSA `tstamp` across a 15 s stall | 15.09 s of audio over 15 s of wall clock; unaffected |
| correlation with other subsystems | kernel log +/- 20 s, charger, usbnet-watchdog, ModemManager, phoc | nothing; phoc excluded only by an activity-matched control |

The difference reaches the chip through the display module, where there is no
instrument from the AP side.

## 5a. What the controller sees during the hang

Read from the QUP registers and the two i2c pads while a transfer was hung
(2026-09-04 19:13, full capture and its limits in
[`REGISTERS-both-lines-low.md`](../power/bringup/captures/2026-09-04_142-touch-after-resume/REGISTERS-both-lines-low.md)):

```
--- HEALTHY (screen on, driver bound)
pad gate (bus idle, must be 1/1): gpio10=1 gpio11=1
[  0.001] STATE=0x01c OPER=0x0000c0[OUT_FULL,NO_INPUT] I2C_STATUS=0x0c000000[-]
          gpio10=1 gpio11=1                                    probe 0.0003 s, errno 6

--- HUNG (screen off, driver unbound)
pad gate (bus idle, must be 1/1): gpio10=1 gpio11=1    <- one second before the probe
[  0.001] STATE=0x01d OPER=0x000010[OUT_NOT_EMPTY]
          I2C_STATUS=0x00138700[BUS_ACTIVE,BUS_MASTER] gpio10=0 gpio11=0
[ 15.007] STATE=0x01c OPER=0x0000c0[OUT_FULL,NO_INPUT] gpio10=0 gpio11=0
samples: 6197                                          probe 15.0057 s, errno 110
```

Five things, and together they narrow the mechanism a long way:

1. **The controller starts.** `BUS_ACTIVE` and `BUS_MASTER` are set and
   `QUP_STATE` 0x01d is `QUP_RUN_STATE` + `VALID`, against 0x01c
   (`QUP_RESET_STATE`) at rest.
2. **Both wires are held low for the entire 15 s** - and were **high one second
   earlier** in identical conditions, which the pad gate recorded. Starting the
   transfer pulls them down and they do not come back.
3. **Nothing moves.** 6197 samples, two distinct states: hung, then post-timeout.
   The sampler prints only on change.
4. **No error, anywhere.** `QUP_ERROR_FLAGS` is 0 and the `I2C_STATUS` error mask
   is clear: no NACK, no over- or under-run. From the controller's side nothing
   went wrong - nothing happened.
5. **A byte is stuck in the output FIFO** (`QUP_OPERATIONAL` = `OUT_NOT_EMPTY`).

Master in RUN state, bus owned, data queued, no error, both wires grounded,
static for fifteen seconds: a bus held down by something other than this
controller. That is what an unpowered or unresponsive slave clamping the lines
looks like, which is why §6's missing supplies matter.

☠️ Limits: which pin is SDA and which is SCL was not verified (it does not matter
here - both are low), and bits 10, 15, 16, 17 and 20 of `0x00138700` are
undecoded because neither driver names them.

## 6. The oracle: what the vendor kernel does differently

Ubuntu Touch runs the same silicon and does not have this symptom. Every
downstream line below was read from
[`ubports/.../android_kernel_fairphone_sdm632`](https://gitlab.com/ubports/porting/community-ports/android10/fairphone/android_kernel_fairphone_sdm632),
branch `ubuntutouch`, commit `6d508b494756`, and the links are pinned to that
commit so the line numbers stay true. It stacks **three** independent
mitigations; mainline has one of them.

**Retry, in the touch driver.**
[`hxchipset83112b/himax_platform.c`](https://gitlab.com/ubports/porting/community-ports/android10/fairphone/android_kernel_fairphone_sdm632/-/blob/6d508b49475678dbafcd106504c65ff2b8e7dc4f/drivers/input/touchscreen/hxchipset83112b/himax_platform.c)
wraps every read and every write in `for (retry = 0; retry < toRetry; retry++)`
with `HIMAX_REG_RETRY_TIMES = 5`
([`himax_ic.h:20`](https://gitlab.com/ubports/porting/community-ports/android10/fairphone/android_kernel_fairphone_sdm632/-/blob/6d508b49475678dbafcd106504c65ff2b8e7dc4f/drivers/input/touchscreen/hxchipset83112b/himax_ic.h#L20)). Mainline
[`himax_hx83112b.c`](https://github.com/llg179org/linux/blob/debug-int/7.1.3/drivers/input/touchscreen/himax_hx83112b.c) retries
nowhere.

**Timeout proportional to the transfer.**
[`i2c-msm-v2.c:i2c_msm_xfer_calc_timeout()`](https://gitlab.com/ubports/porting/community-ports/android10/fairphone/android_kernel_fairphone_sdm632/-/blob/6d508b49475678dbafcd106504c65ff2b8e7dc4f/drivers/i2c/busses/i2c-msm-v2.c#L2055)
sizes it per transfer from the actual byte count; constants from
[`include/linux/i2c/i2c-msm-v2.h:202-203`](https://gitlab.com/ubports/porting/community-ports/android10/fairphone/android_kernel_fairphone_sdm632/-/blob/6d508b49475678dbafcd106504c65ff2b8e7dc4f/include/linux/i2c/i2c-msm-v2.h#L202-203) (`SAFETY_COEF` 10, `MIN_USEC` 500000):

| transfer | downstream | mainline i2c-qup |
|---|---|---|
| 4-byte himax read | **0.504 s** | 14.976 s |
| 8-byte read | 0.507 s | 14.976 s |
| 128 KB maximum | 118.5 s | 14.976 s |

Note the shape: downstream is *more* generous for a huge transfer and far
stricter for a small one. It is not more cautious, it is **proportional**.

**Pinctrl re-selected around every transfer**
([`i2c-msm-v2.c:2244`](https://gitlab.com/ubports/porting/community-ports/android10/fairphone/android_kernel_fairphone_sdm632/-/blob/6d508b49475678dbafcd106504c65ff2b8e7dc4f/drivers/i2c/busses/i2c-msm-v2.c#L2244) and
[`:2289`](https://gitlab.com/ubports/porting/community-ports/android10/fairphone/android_kernel_fairphone_sdm632/-/blob/6d508b49475678dbafcd106504c65ff2b8e7dc4f/drivers/i2c/busses/i2c-msm-v2.c#L2289)).
Mainline did not do this until our own
`i2c: qup: select the sleep/default pinctrl states across runtime PM`, which is
in the running kernel (`1380c70af7b3` on `debug-int/7.1.3`) and measured working
in §5.

**And the device tree declares supplies that ours does not.** The FP3 board file
downstream is
[`arch/arm64/boot/dts/qcom/sdm450-pmi632.dtsi`](https://gitlab.com/ubports/porting/community-ports/android10/fairphone/android_kernel_fairphone_sdm632/-/blob/6d508b49475678dbafcd106504c65ff2b8e7dc4f/arch/arm64/boot/dts/qcom/sdm450-pmi632.dtsi)
(identified by
`himax,hxcommon` at `reg = <0x48>` with `display-coords = <0 1080 0 2160>`,
matching our `touchscreen-size-x/y`):

```
vendor sdm450-pmi632.dtsi            mainline sdm632-fairphone-fp3.dts
  compatible = "himax,hxcommon"        compatible = "himax,hx83112b"
  reg = <0x48>                         reg = <0x48>
  vcc_i2c-supply = <&pm8953_l6>        (absent)
  vdd-ana-supply = <&pm8953_l10>       (absent)
```

Our `touchscreen@48` declares **no supply at all**, and the driver requests no
regulator. `pm8953_l6` is the same rail our *panel* node takes `iovcc` from, so
the touch chip's i2c-pad supply is held only by the panel driver, and its analog
supply `l10` by nobody - it reads `idle 2800mV`, with no consumer voting for it.

☠️ **This is the strongest root-cause candidate on the page and it is still an
inference**, not a measurement: the two missing supplies have not been added and
the fault has not been shown to disappear when they are.

## 7. Proposed fixes

Two changes, to two different trees, **neither of which requires knowing why the
bus hangs**. Together they remove the user-visible symptom.

**`i2c: qup`: size the transfer timeout from the transfer.** A 4-byte read
should not inherit a timeout computed for 128 KB. The downstream driver on this
same hardware is the evidence that proportional is the correct behaviour here.
This does not fix the hang; it turns a 15-second dead screen into a fraction of
a second. Goes to the i2c tree, on its own.

**`Input: himax_hx83112b`: retry the transfer.** Precedent on this very phone:
[`media: i2c: ak7375: retry the first transfer of a resume`](https://github.com/llg179org/linux/commit/1a5f4a9461d2) - *"the first
transfer after the supplies come up can time out ... the resume returns -110"* -
same signature, different controller, already diagnosed and fixed here by
retrying. Goes to the input tree.

**Separately, and needing measurement first:** add `vcc_i2c` and `vdd-ana` to
`touchscreen@48` and have the driver enable them, mirroring the vendor DT. Do
not send this until §6's inference is turned into a measurement.

## 8. Still unknown

* **What holds the lines down.** §5a settles that the controller starts and that
  both wires are grounded for the whole timeout, which eliminates "the controller
  never starts" and points at the slave. What it does not identify is the
  mechanism on the chip side - an unpowered input clamping through its protection
  diodes, a reset asserted mid-transfer, or the chip deliberately stretching
  forever. Separating those needs either the missing supplies added (below) or a
  scope.
* **Whether the missing supplies are the cause** (§6).
* **Whether `0314fee3ce35` makes it worse.** It is not the cause - stalls occur
  with no suspend at all - but whether the deeper `system-pc` state raises the
  rate has not been measured. That is what the HOLD is for.
* **Whether the reproducer in §3 and the operator's fault are the same
  mechanism.** They share a duration, and §2 says why that is worth nothing.

## Evidence

Raw logs, scripts and the day's dated notes:
[`captures/2026-09-04_142-touch-after-resume/`](../power/bringup/captures/2026-09-04_142-touch-after-resume/), in particular
[`TRIGGER-screen-gates-it.md`](../power/bringup/captures/2026-09-04_142-touch-after-resume/TRIGGER-screen-gates-it.md) (the screen A/B
and the retractions), [`MECHANISM-qup-timeout.md`](../power/bringup/captures/2026-09-04_142-touch-after-resume/MECHANISM-qup-timeout.md),
[`FINDING-not-suspend.md`](../power/bringup/captures/2026-09-04_142-touch-after-resume/FINDING-not-suspend.md),
[`ANSWER-audio-is-unaffected.md`](../power/bringup/captures/2026-09-04_142-touch-after-resume/ANSWER-audio-is-unaffected.md),
[`CORRELATION-nothing-found.md`](../power/bringup/captures/2026-09-04_142-touch-after-resume/CORRELATION-nothing-found.md).

☠️ Three conclusions were reached and retracted during that day, and they are
kept because they say which reasoning to distrust: *"the fault needs a long
idle"* (refuted by the operator tapping continuously), *"the fault scales with
transactions"* (wrong denominator - it was fitted on interrupt counts mislabelled
as transactions, and off by 4x besides), and *"the unused-address probe is not a
valid instrument"* (it is; it had been moved out of its working idle range).
