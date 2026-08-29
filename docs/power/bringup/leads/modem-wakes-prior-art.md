# What is already known elsewhere about a modem that will not let the AP sleep

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed every claim it rests on. Web sources
> are cited; anything checked against this device says so explicitly.

Searched 2026-08-29, after the four legs in
[`../findings-log.md`](../findings-log.md) showed that every suspend on this phone
dies on the modem's SMD edge with ModemManager running and none of them without it.
Three findings, one of them dead on arrival — which is the point of looking.

## 1. ☠️ The closest prior art is a *clock* bug, and it does not apply here

`remoteproc: qcom: q6v5-pil: fix modem hang on SDM845 after axis2 clk unvote`
(Sibi Sankar, upstream `7cbb540a3a68`, in 4.18.10) describes exactly the failure
mode this project is chasing, in the same subsystem:

> When the clock is turned ON after Q6 is brought out of reset and later turned
> off, it results in modem hang. When Q6 attempts a power collapse, the internal
> handshaking to check if AXIS2 is idle never goes through since it is turned off,
> preventing the RSC from getting triggered and leaving the modem in a funky state.

A clock the *application processor* manages can block the *modem's* internal
power-collapse handshake, so the modem never collapses and burns current with
nothing to show for it. That is a very good description of a modem awake 34.8 % of
the time.

**It is not our bug.** Checked against the device rather than assumed: mainline's
`msm8953_mss` in `drivers/remoteproc/qcom_q6v5_mss.c` holds

```
proxy_clk_names  = { "xo" }
active_clk_names = { "iface", "bus", "mem" }
```

and the vendor 4.9 device tree on this disk (`msm8953.dtsi:1940`) asks for exactly
the same set:

```
qcom,proxy-clock-names  = "xo";
qcom,active-clock-names = "iface_clk", "bus_clk", "mem_clk";
```

Identical lists, so there is no clock we hold that the vendor releases, or the
reverse. **Cost of excluding it: one grep.** Worth recording precisely because the
mechanism is so plausible that it would otherwise come back.

## 2. ★ ModemManager registers exactly the indications the measurement points at

The QMI plugin registers **NAS Serving System events** and **Signal Info**
indications when the modem is enabled — that is what
`mm-broadband-modem-qmi.c` sends `NAS Register Indications` for, and libqmi
documents both `nas_serving_system` and `nas_signal_info` as indication types the
modem then emits unsolicited.

That is the right shape for what was measured here: the traffic is **unsolicited,
from the modem**, needs no running code on our side once registered, and stops the
moment the daemon's qrtr socket goes away — which is exactly the A/B/C/D result
(started → 22 / 16 s, stopped → 602 s).

☠️ And it says why `mmcli --signal-setup` is not the knob: that governs the
*extended* signal API, and on this device it already reads `refresh rate: 0
seconds` while the wakes continue. The registrations that matter are made
unconditionally at enable time.

## 3. ★★ The kernel side says there is no "just ignore it" fix

From `Documentation/power/suspend-and-interrupts.rst`: `IRQF_NO_SUSPEND`
interrupts "will bring CPUs out of idle while in that state, but they will not
cause the IRQ subsystem to trigger a system wakeup", and system wakeup interrupts
"will trigger wakeup from suspend-to-idle in analogy with what they do in the full
system suspend case".

The modem edge is neither: `qcom_smd_parse_edge()` requests it with plain
`IRQF_TRIGGER_RISING` and marks it a *wake* IRQ that is left **disabled by
default** — and on this device `remoteproc0:smd-edge` indeed reads
`power/wakeup = disabled`. So it is an ordinary device IRQ, masked by
`suspend_device_irqs()`, and an interrupt that arrives while device IRQs are
suspended is treated by the IRQ core as a system wakeup — which is what
`/sys/power/pm_wakeup_irq` reporting `141` on 5 of 5 rounds *is*.

**That behaviour is by design and should not be patched around**: the kernel
cannot know that a masked interrupt is uninteresting. Which settles the direction —
**the fix is not to generate the interrupt**, i.e. it lives in what the modem is
asked to report, not in how the AP handles being told.

## Where this leaves the next step

Not "make the wake cheaper" but "stop subscribing to what we do not need while the
screen is off". That is a ModemManager question — and, since a phone still has to
receive calls and SMS, a question about *which* indications, not about all of them.

Sources: the SDM845 clock patch (LKML, 2018) · ModemManager QMI plugin and libqmi
NAS indication reference · `Documentation/power/suspend-and-interrupts.rst`.
