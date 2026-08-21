# The "amp death": ADSP resets the I2C6 pads — root cause and fix

> ⚠️ **AI-generated.** This page — and the code, device tree and tooling it
> describes — was written by Claude (Fable 5) working under the direction of
> Lajosházi, László Gergely, who reviewed every change and made or reviewed
> every measurement it rests on.

**Status (2026-08-21): root-caused and fixed in `linux-fp3` r64.**

## The symptom

On every boot, ~24 s in (24.16–24.58 s measured over four differently-configured
boots), the AW8898 speaker amplifier at `i2c-6` address 0x34 stopped
acknowledging — every register read returned `EIO`, including reads of
non-existent addresses on the same bus, and only a reboot brought it back.
Weeks of investigation treated this as the chip dying (see
`../..//docs/audio/` history and the `24-speaker-amp` selftest check).

## The measurement that broke it open

An ftrace trap armed from early boot (`awdeath-trap.py` +
`awdeath-trap.service`: `regulator:*`, `gpio:*`, `clk:clk_disable*`,
`qcom_smd_rpm:*`, `workqueue:workqueue_execute_start`, with a 0.1 s bus-direct
poll and an immediate buffer dump at the first NAK) showed:

- in the death window (24.05–24.25 s) the kernel touches **no** regulator, no
  gpio, no relevant clock — only GPU DVFS and cgroup cleanup noise;
- the before/after `/sys/kernel/debug/gpio` snapshots show **gpio22/23 — the
  BLSP6 I2C pads the amp sits on — flipped from `func3` (blsp_i2c6) to the TLMM
  power-on default** `0x201` (GPIO function, output low, pull-down), while
  `pinmux-pins` still reported them owned by `7af6000.i2c` in function
  `blsp_i2c6`.

Writing the two TLMM cfg registers back by hand
(`pmem.py 0x1016000 0x0C; pmem.py 0x1017000 0x0C`) revived the "dead" chip
instantly: 21/21 register reads OK, chip ID 0x1702. **The chip never died; the
bus pads were taken away.** With the pads muxed off the QUP, the controller
sees the lines idle and every address — real or not — NAKs, which is exactly
the signature that had been read as a dead chip.

## The actor: the ADSP

- restarting the **modem** (`remoteproc0`) with a pad watcher running: nothing;
- restarting the **ADSP** (`remoteproc2`): ~1.7 s after the start completes,
  gpio22/23 are reset to `0x201` again, and gpio14/15 (downstream the sensor
  I2C) are actively muxed to `func3` in the same event — this is the ADSP
  sensor stack's pad init (watched at 0.05 s resolution with `padwatch.py`).

On a cold boot the death lands at modem-up (16.4 s) + ~7.8 s: the ADSP sensor
init waits for the modem, which is why the timing was boot-anchored and
independent of session, playback and chip register state.

Why the vendor kernel (and the Ubuntu Touch oracle) never showed this: the
downstream `i2c-msm-v2` driver re-selects its active pinctrl state around
**every** transfer, so the first transaction after the trample silently heals
the pads. Mainline `i2c-qup` never touches pinctrl at all — the `i2c_6_sleep`
state declared in `msm8953.dtsi` was dead configuration.

## The fix (r64)

`i2c: qup: select the sleep/default pinctrl states across runtime PM`
(`wip/7.1.3/audio` 490c046b339e, cherry-picked to `integration/7.1.3` and
`debug-int/7.1.3`): select the sleep state on runtime suspend and the default
state on runtime resume. Cycling through the sleep state is essential — the
pinctrl core short-circuits a same-state select, so without the toggle the
resume-side select would be a no-op and the pads would stay lost.

With the 1 s autosuspend delay of `i2c-qup`, any transfer after the trample
runtime-resumes the controller and rewrites the pad registers first.

## Instruments (all bus-direct or register-direct)

| tool | what it does |
|---|---|
| `tools/awpoke.py` / `tools/awwatch.py` | amp register access bypassing the driver's cached regmap |
| `awdeath-trap.py` (+ systemd unit) | early-boot ftrace trap with liveness poll and dump-at-death |
| `pmem.py` | 32-bit MMIO read/write via `/dev/mem` (TLMM cfg) |
| `padwatch.py` | polls TLMM cfg of the pads of interest, logs every transition |

## Upstream status

Our first instinct — submit the i2c-qup change and/or the SLIMbus
`disable_stream` work — hit prior art on patchwork (searched by file name, as
the `/msm8953-mainline-pr` skill requires):

- `[v2] slimbus: qcom-ngd-ctrl: Implement disable_stream callback`, Viken
  Dadhaniya (Qualcomm), 2026-08-10, state `new`
  (msgid `20260810-slim-disable-stream-support-v2-1-c2e8fcc3c99d@oss.qualcomm.com`).
  This is the same fix our r63 carries (independent implementations of the same
  downstream message). **Do not send a competing patch** — the useful
  contribution is a tested-on-hardware reply on that thread with our
  measurements (LPASS XO-shutdown released in ~15 s after a capture session).
- The i2c-qup pinctrl patch has no counterpart found on patchwork
  (`q=i2c-qup pinctrl`, checked 2026-08-21); it remains a candidate for an
  LKML submission with the FP3 measurement as evidence.

## Transferable lessons

- **The pinctrl framework's state is bookkeeping, not hardware.** A
  co-processor can rewrite the TLMM behind Linux's back; only
  `/sys/kernel/debug/gpio` (which reads registers) or `/dev/mem` tell the
  truth, and `pinmux-pins` will happily claim a function the pad no longer has.
- "Every address NAKs, even non-existent ones" proves the *controller* works,
  not that the *pads* are connected — a bus with its pads muxed away produces
  exactly the dead-chip signature.
- An invariant boot-anchored timing (±0.3 s) need not be a kernel timer; here
  it was a co-processor init chain (modem-up + fixed delta).
