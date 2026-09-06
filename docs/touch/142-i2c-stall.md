# The touchscreen freezes for 15 seconds (#142)

> ⚠️ **AI-assisted.** The measurements on this page were run by Claude (Opus 5)
> under the direction of Lajosházi, László Gergely, who reviewed them. Every
> number states the conditions it was taken under; where a claim is an inference
> rather than an observation it says so.

Reported upstream by Bert Karwatzki against msm8953-mainline commit
`0314fee3ce35` (msm8953.dtsi, `system-pc` `arm,psci-suspend-param`
0x41000353 -> 0x42000353): the hx83112b touchscreen stops responding after
resume. Independently observed on this device by the operator.

**Status (2026-09-06): the duration is explained, the trigger conditions are
measured, and there are now TWO distinct hangs, told apart by the bus lines** -
see section 10. The operator-visible one has been caught in the act with its own
signature. The msm8953.dtsi idle-state patch remains on HOLD.

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

**Gate 1 - idle before the transaction, >= ~10 s. SUPERSEDED**, see the end of
this section: the trigger is not idle at all. The table is kept because it is
what the day measured, and because the shape it shows - the fault clustering at
the slow end - is real and is explained by each slow run carrying its own arming
event:

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

☠️☠️ **And gate 1 is confounded, which is worse than thin.** `fp3-usbnet-watchdog`
fires every 30 s on this phone by design (`OnUnitActiveSec=30s`), so the chance
that a periodic system wakeup falls inside an idle window of length T is
`min(T/30, 1)` - a quantity that moves with T exactly as the arms above do:

```
idle      0.02 s   0.5 s   2 s    3 s    15 s   45 s
P(tick)     0.1 %   1.7 %  6.7 %  10 %    50 %  100 %
observed    0 %     0 %    0 %    0 %   0.56 %  33 %
```

Fitting "a tick is required" on the 15 s arm gives 1.12 % per tick, and that
model then predicts every other arm's null with probability 67-96 %. It fits as
well as the idle-length model, because **in this design the two are the same
variable**. So "the fault needs a long idle" and "the fault needs an intervening
system wakeup" are not distinguished by anything measured here - and the second
is the more interesting reading, since a wakeup is what produces a cluster
idle-exit, which is what `arm,psci-suspend-param` governs.

**Both candidates are now dead.** That run happened (2026-09-04 21:25-23:32,
[`ANSWER-nothing-re-arms-it.md`](../power/bringup/captures/2026-09-04_142-touch-after-resume/ANSWER-nothing-re-arms-it.md)): idle held
at 15 s, only the watchdog varied, ten interleaved blocks, screen off.

```
WD-ON  0 / 250      WD-OFF  0 / 250      arming probe (discarded): 15.0759 s
```

At the 1.7 %/probe measured in this exact regime earlier the same day, 500
probes expect 8.3 stalls; none appeared, P = 0.02 %. So it does not choose
between the two readings of gate 1 - it **dissolves both**. Every one of those
500 probes had a 15 s idle, half of them with the watchdog ticking, and none
stalled.

What separates a stalling probe from a clean one is being the **first
transaction after an arming event**: the panel releasing pm8953_l6 (see 6), or
an unbind. The arming probe of that very run hung for 15.08 s one minute before
500 probes in identical conditions hung for none. Pooled across every screen-off
run of the day, after the arming probe: **0 stalls in 26 658 probes**.

☠️ The run was half the size asked for - 250 per arm, not 500 - and 0 against 0
could not have ranked the arms at any size. The conclusion rests on the pooled
null, not on the comparison.

Gate 2 is **not** affected: its arms used an identical 12 s idle and were
interleaved, so any periodic activity reached both equally. That is what the
interleaving bought.

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

☠️ It is also aimed off-target. **Nothing on this phone asks for a suspend** -
`sleep-inactive-ac-type='nothing'`, `IdleAction=ignore`, documented since
2026-08-30 in
[`leads/opportunistic-sleep-missing.md`](../power/bringup/leads/opportunistic-sleep-missing.md).
Measured 2026-09-04: 130 suspends in the 23:00 hour while the overnight run was
cycling them, then **zero between 02:00 and 11:00**. So the 50 forced rtcwake
cycles tested a state the phone does not enter on its own, and the 187-suspend
boot that did reproduce was itself full of measurement-driven suspends. Whatever
gate 3 is about, it is not about suspends that happen in ordinary use.

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

☠️ **This is no longer an inference. Measured 2026-09-04 21:00**, from the
kernel's own regulator framework, screen toggled and nothing else changed:

```
screen ON    l6 use=1   its one consumer 1a94000.dsi.0-iovcc  use=1
screen OFF   l6 use=0   its one consumer 1a94000.dsi.0-iovcc  use=0
l10          use=0 in both states - no consumer at all, ever
```

`pm8953_l6` has **exactly one** consumer, the panel's iovcc, and it drops its
vote when the display is powered down. And the reason our DTS looks correct is
that it *is* correct against the bindings: `himax,hx83112b` appears in mainline
twice for one piece of silicon - a panel binding that **requires**
`iovcc-supply`, and `trivial-touch.yaml` for the touch half, which
(`unevaluatedProperties: false`) cannot carry a supply at all. The touch
controller therefore runs on a vote it does not hold and cannot see released.

That closes the chain: screen off -> panel releases l6 -> nothing votes -> the
touch controller's I/O rail goes -> the next transfer takes the bus and both
lines stay low -> the 14.98 s timeout -> -110. It is also why the screen A/B
separated so cleanly: 5/5 against 0/5 is what a rail with one voter looks like.
Full capture: [`ROOTCAUSE-the-panel-owns-the-rail.md`](../power/bringup/captures/2026-09-04_142-touch-after-resume/ROOTCAUSE-the-panel-owns-the-rail.md).

**Fixed** on `wip/7.1.3/touch` (a new category - there was none for touch),
cherry-picked to `integration/7.1.3` and `debug-int/7.1.3` and pushed:

```
a316c7edd163  dt-bindings: input: himax,hx83112b: give the touch half its own binding
71e8b167175c  Input: himax_hx83112b - hold the rails the touch half runs on
18483b7410a7  arm64: dts: qcom: sdm632-fairphone-fp3: give the touchscreen its supplies
```

The binding had to move out of `trivial-touch.yaml` before the DTS could legally
carry the property, so it is three patches to three trees rather than one.

☠️ **The fix is argued, not demonstrated.** The confirming run is
[`142-trigger.sh`](../power/bringup/captures/2026-09-04_142-touch-after-resume/142-trigger.sh) on a kernel carrying it, and the
pre-registered rule is that screen-off must go from 5/5 to 0/5 over five
interleaved rounds. That needs a flash, which is gated on the dtb switch in
queue item #151. Until that run happens, this page states a measured mechanism
and an unproven cure.

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
* ~~Whether the missing supplies are the cause~~ - answered at the rail level
  (§6): l6 has one consumer and it releases the rail with the display. What is
  **not** answered is whether restoring the vote removes the fault on the device,
  which is the confirming run §6 describes.
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

## 9. The fix is on the device, and what that does and does not prove

2026-09-05, `linux-fp3-7.1.3-r81` (`3f843d0534e3`). Full write-up and raw
output: [`../power/bringup/captures/2026-09-05_155-supplies-on-device/`](../power/bringup/captures/2026-09-05_155-supplies-on-device/).

Measured with the driver **bound**, against the pre-fix reading of 2026-09-04:

| | pre-fix | r81 |
|---|---|---|
| screen ON, `l6` use | 1 (panel only) | **2** (panel + `3-0048-iovcc`) |
| screen OFF, `l6` use | **0** | **1** (`3-0048-iovcc` holds it) |
| `l10` use | 0, no consumer | **1** (`3-0048-vdda`) |

So the chain in section 7 is cut at its first link: the touch controller's I/O
rail no longer goes unvoted when the display powers down.

☠️ **`142-trigger.sh` was NOT re-run, deliberately.** It unbinds the driver, and
unbind releases the supplies the fix takes — measured: `l6` 2 → 1, `l10` 1 → 0.
On a fixed kernel it therefore reproduces the *pre-fix* rail state, so a stall
there would say nothing. The step #155 named is not a valid test of #155.

**Still outstanding:** the operator-visible fault (`Failed to read input event:
-110` during ordinary bound use). Its rate is per vulnerable moment and the
measured gaps run to 726 s, so only a real session — ~36 min of use with pauses,
as `tests/checks/59-touch-i2c-stall-test.sh` argues — can speak to it. That
check reports it on every later selftest run and distinguishes "no stalls" from
"nobody touched the screen".


---

## 10. 2026-09-06: the operator's fault caught in the act, and it is not the one the reproducer makes

Everything above rests on the unbind reproducer. On 2026-09-06 the fault the
operator actually hits was captured with the driver **bound**, in ordinary use,
by diagnostics added to `i2c-qup` in r84. It is a different mechanism.

### The capture

```
06:36:55  i2c_qup 78b7000.i2c: transfer to 0x48 timed out, bus active,
                               master is us, SDA 1 SCL 0 (I2C_STATUS 0x0411a700)
06:36:55  i2c_qup 78b7000.i2c: bus still held after 10 bus-clear attempts:
                               clear not accepted, bus still active,
                               (I2C_STATUS 0x04006300, BUS_CLR 0x1)
```

### Two hangs, one duration

| | unbind reproducer (2026-09-04) | the operator's fault (2026-09-06) |
|---|---|---|
| address | 0x50, an address with no device | **0x48, the touch controller itself** |
| driver | unbound | **bound, real use** |
| screen | off | **on** |
| bus lines | `SDA 0 SCL 0` | **`SDA 1 SCL 0`** |
| reading | an unpowered part clamping both lines through its ESD path | **a powered slave stretching the clock** - SDA is free, SCL is held |

☠️ **So the rail explanation in sections 6-9 does not cover the operator's
fault.** It explains the reproducer, and the supply fix cut that chain at its
first link; but a chip that is stretching SCL is powered and alive. Both produce
`-ETIMEDOUT`, which is why one duration hid two mechanisms for two days.

### Why the bus-clear did not help, and it is not what was assumed

r84 added the QUP hardware bus-clear and it failed 3/3 against the reproducer.
That was read as "clocking cannot persuade a dead chip", which is true there. The
r85 diagnostic shows it is **not** what happens in the operator's fault:
`BUS_CLR 0x1` reads back **still set** after all ten attempts - *the block never
accepted the command*. With a transfer wedged, flushing and forcing `RUN` is not
enough; the core has to be reset to idle and brought back up first, which is what
the vendor driver does before every clear. Fixed in `af2628ca18d2`, unmeasured at
the time of writing.

### What the retry did, and did not do

`himax_hx83112b` logged **nothing** during this event: one of its three attempts
succeeded, so the panel never wedged. But the tap was still lost - the input log
shows `PRESS #7` held for **9 ms** where its neighbours held 89-119 ms.

**The retry protects the panel, not the touch.** That is exactly the operator's
symptom since r83: occasional missing digits, no freeze. A PIN digit not taken
after unlocking, and digits missing in the calculator.

### The other fault the same week: a storm that killed the interrupt

2026-09-05 21:26, on r84: 85 905 failed `-EIO` reads in eleven seconds (~7800/s),
then `irq 127: nobody cared` and `Disabling IRQ #127` - a dead panel until the
driver was rebound. Cause: `himax_irq_handler` returned `IRQ_NONE` on a failed
read, so a level-triggered line that re-asserts immediately counted every pass as
unhandled. Fixed in `c59812386d99` (r85).

☠️ **r82 had the same bug and never tripped it**, because printing every failure
over `console=ttyMSM0,115200` paced the loop: 72 chars/line at 11 520 chars/s
gives **160 lines/s theoretical against 156 measured**. The serial console was
an accidental brake, and `dev_err_ratelimited` removed it. The rate limit did not
create the bug; it released the rate that trips it. **Removing an accidental
throttle exposes whatever it was hiding, and that has to be looked for
deliberately.**

### Eliminated on 2026-09-06: the bus is healthy right after resume

The operator's trigger is a power-button lock/unlock, so the bus was probed
immediately after the screen returns, fully automatically, at 0, 1, 3 and 10 s:

```
after resume: 0 / 8 probes stalled      control: 0 / 8
```

all sub-millisecond. ☠️ `0/8` bounds the rate only at ~31 % by the rule of three,
and the probe measures the **bus**, not touch *sensing* - a controller that is
alive but not reporting would leave the bus spotless. Both limits stated because
neither is obvious from the table.

### The instruments this took, and what each cannot see

| instrument | sees | blind to |
|---|---|---|
| `fp3-touch-gaps` v4/v5 (`captures/2026-09-06_r85-call-plus-tapping/`) | frame gaps >=100 ms, every `BTN_TOUCH`, and interrupts-without-frames | anything above the input layer |
| `fp3-resume-probe.sh` | i2c health at chosen delays after resume, no human needed | touch sensing; it probes an empty address |
| `fp3-resume-taps.sh` | lost taps after resume, with an interleaved control | needs a finger; the phone buzzes to time it |
| `142-trigger.sh` | the unpowered-clamp hang | the supply fix (it unbinds, dropping the votes) and the bound-driver fault |

☠️ **A uinput injector is not on this list and must not be.** It delivers events
straight into the input layer, bypassing the controller and the bus - the things
under test - so it would pass unconditionally. The stimulus cannot be automated;
only the verification can, and now is.

☠️ **And an instrument can break another one.** The automated resume probe
unbinds the driver, which destroys the input node, which kills `fp3-touch-gaps`;
systemd restarted it **12 times** between 06:31 and 06:34 and its counters reset
each time. Stop the logger, or skip the unbind, before running the probe.

## 11. r86: reset the core before asking it to clear the bus — deployed, not yet measured

The four-line trail (`fp3-kernel-test` reporting rule 6) for this release. The
fourth line is deliberately empty; see below.

- **Symptom.** A tap is swallowed with no `himax` log line at all, because a
  retry absorbed it — the fault is a powered controller stretching the clock
  (`SDA 1 SCL 0`), not the unpowered clamp the reproducer makes.
- **How to provoke.** Ordinary use. It has never been produced on demand: the
  06:36:55 capture of 2026-09-06 caught it during a real PIN entry, and the
  automated resume probe went 0/8 because it probes an empty address, which a
  healthy chip answers instantly.
- **The change.** `i2c: qup: reset the core before asking it to clear the bus`
  (`wip/7.1.3/touch` `af2628ca18d2` ≡ `debug-int/7.1.3` `585a3423b76f`, same
  patch-id). r84's bus-clear was not ineffective but **refused**:
  `QUP_I2C_MASTER_BUS_CLR` still read back `0x1` after ten attempts, i.e. the
  hardware never accepted the command. The vendor driver resets the core first,
  so this does the same — `QUP_SW_RESET`, poll `QUP_RESET_STATE`, restore the
  cached `QUP_CONFIG` and `QUP_I2C_MASTER_GEN`, back to `QUP_RUN_STATE`,
  rewrite `QUP_I2C_CLK_CTL`, and only then write the clear.
- **The measured effect.** **The clear is now accepted, first try.** Caught in
  ordinary use at 09:00:23 on 2026-09-06, one hour after deploying r86, when the
  operator took the phone off the charger and the lock screen missed three
  presses:

  ```
  09:00:23.817467  transfer to 0x48 timed out, bus active, master is us,
                   SDA 1 SCL 0 (I2C_STATUS 0x0411a700)
  09:00:23.819568  bus cleared after 1 attempt(s)
  ```

  The status word is **identical** to the 06:36:55 fault on r85, so this is the
  same mechanism, not a different one that happens to recover. On r84/r85 it
  produced `clear not accepted` after ten attempts; on r86 it clears 2.1 ms
  later, on the first. Counters for the whole boot: `bus still held` 0,
  `clear not accepted` 0, `Failed to read input event` 0, `Disabling IRQ` 0.

  ☠️ **And the tap was still lost.** Recovery is not prevention: the transfer
  still timed out first, and that timeout is 2.03 s (21.786 resume → 23.817
  timeout), which during PIN entry swallows several taps. r86 closes the
  cascade, not the fault — exactly the distinction the operator drew when
  rejecting "the stall is shorter" as a fix.

☠️ **The success criterion is a log line, not a fault count.** If the clear now
takes effect, `bus still held … clear not accepted` must be replaced by
`bus cleared after N attempt(s)`. A run with no faults at all proves nothing
about this change — it only means nobody touched the phone.

That message is a `dev_dbg`, so it needs dynamic debug on, and the control file
is reset by every boot. From r86 the unit `fp3-i2c-qup-dyndbg.service`
(`After=multi-user.target`, per brick-safety rule 14) re-enables it — verify
with `systemctl is-active fp3-i2c-qup-dyndbg` and
`sudo grep -c 'i2c-qup.c.*=p' /sys/kernel/debug/dynamic_debug/control`, which
should read 5.


## 12. Where the fault comes from: the pinctrl fix for a different bus

The 09:00 capture carries more than the success criterion. The three lines
before it say when the fault happens:

```
09:00:21.766407  78b7000.i2c: pm_runtime: suspending...
09:00:21.786452  78b7000.i2c: pm_runtime: resuming...      <- 20 ms later
09:00:23.817467  78b7000.i2c: transfer to 0x48 timed out
```

**The transfer that hangs is the first one after a runtime-PM resume.** That
makes it a consequence of something the resume path does, and the resume path
on this driver was changed by us:

`1380c70af7b3 "i2c: qup: select the sleep/default pinctrl states across runtime
PM"` selects the sleep state on runtime suspend and the default state on resume.
It was written for a **different bus**: on i2c-3 (`7af6000`, the `aw8898`
speaker amp) the ADSP resets the BLSP6 pads behind Linux's back, and cycling
through the sleep state is what makes the resume-side select rewrite them.

On the touch bus the same cycling has a cost, and the DT says what it is:

```
i2c_3_default:  pins gpio10, gpio11   function = "blsp_i2c3"   bias-disable
i2c_3_sleep:    pins gpio10, gpio11   function = "gpio"        bias-disable
```

Every runtime suspend takes SDA and SCL **out of the I2C function to plain GPIO
with no pull**, and resume puts them back. Before that commit the driver never
touched pinctrl, so this sleep state was dead configuration; the commit is what
made it run. A controller left mid-byte by a pad transition then holds SCL low —
which is precisely the `SDA 1 SCL 0` signature, and precisely what a bus-clear
is for.

**Why it hits touch and not the amp** is asymmetric access, not the pins: the
driver writes to the amp when it chooses, while the touch controller raises an
asynchronous interrupt, so a read can begin at any instant — including one that
lands on a resume.

☠️ **This is a hypothesis with a mechanism, not a conclusion.** It explains why
the fault needs a finger, why the unbind reproducer never made it, and why it
appeared in ordinary use rather than under load — but nothing here has been
measured against a control yet.

### The experiment now running

One change, no flash, revertible, and it leaves the amp's fix untouched:

```sh
echo on > /sys/bus/platform/devices/78b7000.i2c/power/control   # touch bus only
```

Runtime PM off on the touch bus stops the suspend/resume cycling, so the pins
never leave `blsp_i2c3`. Armed 2026-09-06 09:05:05; the baseline for that boot
is in `/var/log/fp3-touch/r86-experiment.log` (1 timeout, 1 clear, 72 touch
interrupts — a thin before-window, and it is worth saying so). It reverts on
reboot, or with `echo auto`.

If the timeouts stop over a comparable window of use, the resume path is
implicated and the fix belongs in the driver or the DT: give this bus a sleep
state that keeps the I2C function, or restrict the pinctrl cycling to the bus
that needs it. If they continue, the resume is a coincidence of timing and this
section is wrong.

☠️ **What this experiment cannot separate**: runtime PM off stops the pinctrl
cycling *and* the clock gating. It tests whether the resume path is involved at
all, not which half of it. That is the next question, not this one.
